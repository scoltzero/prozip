import Darwin
import Foundation
import XCTest
import ProZipCore
import ProZipEngines
import ProZipShared

final class CoreEngineAuditFixesTests: XCTestCase {
    private func makeTempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("prozip-core-audit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    func testTarCreateStripsHostPathsAndPreservesEntryModificationDates() async throws {
        let root = try makeTempDirectory()
        let fm = FileManager.default
        let dirA = root.appendingPathComponent("hostDirA", isDirectory: true)
        let dirB = root.appendingPathComponent("hostDirB/nested", isDirectory: true)
        try fm.createDirectory(at: dirA, withIntermediateDirectories: true)
        try fm.createDirectory(at: dirB, withIntermediateDirectories: true)

        let dashFile = dirA.appendingPathComponent("-dash.txt")
        try Data("dash".utf8).write(to: dashFile)

        let reportFile = dirB.appendingPathComponent("report.txt")
        try Data("payload-123".utf8).write(to: reportFile)

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let historicalDate = try XCTUnwrap(
            cal.date(from: DateComponents(year: 2023, month: 5, day: 20, hour: 12, minute: 0, second: 0))
        )
        try fm.setAttributes([.modificationDate: historicalDate], ofItemAtPath: reportFile.path)

        let linkFile = dirB.appendingPathComponent("link.txt")
        try fm.createSymbolicLink(atPath: linkFile.path, withDestinationPath: "./report.txt")

        let tarURL = root.appendingPathComponent("clean.tar.gz")
        let engine = LibarchiveEngine()
        try await engine.create(
            sources: [dashFile, dirB],
            at: tarURL,
            profile: CreationProfile(purpose: .general, format: .tarGz, preserveMacMetadata: false),
            password: nil,
            progress: { _ in }
        )

        let entries = try await engine.list(tarURL, password: nil, progress: { _ in })
        let byPath = Dictionary(uniqueKeysWithValues: entries.map { ($0.path, $0) })

        XCTAssertEqual(
            Set(entries.map(\.path)),
            ["-dash.txt", "nested", "nested/report.txt", "nested/link.txt"]
        )
        XCTAssertFalse(entries.contains { $0.path.contains("hostDir") || $0.path.contains("Users") })
        XCTAssertEqual(byPath["nested/link.txt"]?.symlinkTarget, "./report.txt")

        let parsedReportDate = try XCTUnwrap(byPath["nested/report.txt"]?.modifiedAt)
        XCTAssertEqual(cal.component(.year, from: parsedReportDate), 2023)
        XCTAssertEqual(cal.component(.month, from: parsedReportDate), 5)
        XCTAssertEqual(cal.component(.day, from: parsedReportDate), 20)

        // Verify HH:MM year rollover when listing spans across New Year
        let janRef = try XCTUnwrap(
            cal.date(from: DateComponents(year: 2027, month: 1, day: 10, hour: 9, minute: 0, second: 0))
        )
        let rolloverEntries = LibarchiveEngine.parseBsdtarListing(
            "-rw-r--r--  0 user staff      12 Nov 11 00:31 recent.txt",
            referenceDate: janRef
        )
        let rolloverDate = try XCTUnwrap(rolloverEntries.first?.modifiedAt)
        XCTAssertEqual(cal.component(.year, from: rolloverDate), 2026)
        XCTAssertEqual(cal.component(.month, from: rolloverDate), 11)
        XCTAssertEqual(cal.component(.day, from: rolloverDate), 11)
        XCTAssertEqual(cal.component(.hour, from: rolloverDate), 0)
        XCTAssertEqual(cal.component(.minute, from: rolloverDate), 31)
    }

    func testTemporaryRegistryReportsRecursiveBytesAndSkipsOpenPreviewFiles() async throws {
        let root = try makeTempDirectory()
        let fm = FileManager.default
        let registry = try ManagedTemporaryArtifactRegistry(fileURL: root.appendingPathComponent("registry.sqlite"))

        let idleDir = try await registry.createManagedTemporaryDirectory(purpose: "quicklook")
        addTeardownBlock { try? FileManager.default.removeItem(at: idleDir) }
        let idleSub = idleDir.appendingPathComponent("sub", isDirectory: true)
        try fm.createDirectory(at: idleSub, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 2048).write(to: idleSub.appendingPathComponent("a.bin"))
        try Data(repeating: 0x42, count: 1024).write(to: idleDir.appendingPathComponent("b.bin"))

        let activeDir = try await registry.createManagedTemporaryDirectory(purpose: "quicklook")
        addTeardownBlock { try? FileManager.default.removeItem(at: activeDir) }
        let activeFile = activeDir.appendingPathComponent("preview.bin")
        try Data(repeating: 0x43, count: 4096).write(to: activeFile)
        let openReader = try FileHandle(forReadingFrom: activeFile)
        defer { try? openReader.close() }

        // Explicit in-flight extraction staging in currentPID must not be treated as idle cleanable temp
        let inFlightDir = root.appendingPathComponent("inflight-extract", isDirectory: true)
        try fm.createDirectory(at: inFlightDir, withIntermediateDirectories: true)
        try Data(repeating: 0x44, count: 8192).write(to: inFlightDir.appendingPathComponent("part.bin"))
        _ = try await registry.registerArtifact(at: inFlightDir, purpose: .streamExtraction, sessionID: "extract-tx")

        let cleanableWhileOpen = await registry.totalCleanableBytes()
        XCTAssertEqual(cleanableWhileOpen, 3072)

        let freedWhileOpen = try await registry.cleanAllTemporaryFiles()
        XCTAssertEqual(freedWhileOpen, 3072)
        XCTAssertFalse(fm.fileExists(atPath: idleDir.path))
        XCTAssertTrue(fm.fileExists(atPath: activeFile.path), "Open preview file must not be removed mid-read")
        XCTAssertTrue(fm.fileExists(atPath: inFlightDir.path), "Active transactional staging must remain untouched")

        try openReader.close()

        let cleanableAfterClose = await registry.totalCleanableBytes()
        XCTAssertEqual(cleanableAfterClose, 4096)

        let freedAfterClose = try await registry.cleanAllTemporaryFiles()
        XCTAssertEqual(freedAfterClose, 4096)
        XCTAssertFalse(fm.fileExists(atPath: activeDir.path))
        let remaining = await registry.totalCleanableBytes()
        XCTAssertEqual(remaining, 0)
    }

    func testExtractionPlanValidatorCachesAncestorsAndRejectsSymlinkSubdirectory() throws {
        let root = try makeTempDirectory()
        let fm = FileManager.default
        let dest = root.appendingPathComponent("output", isDirectory: true)
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)

        let entries = (0..<300).map { idx in
            ArchiveEntry(path: "folder-\(idx % 12)/sub/item-\(idx).txt", type: .file, uncompressedSize: 16)
        }
        let plan = try ArchiveExtractionPolicy.buildPlan(
            entries: entries,
            archiveURL: root.appendingPathComponent("sample.zip"),
            destinationURL: dest,
            options: ExtractionOptions(stripSingleRootFolderIfMatching: false)
        )
        XCTAssertEqual(plan.itemsToExtract.count, 300)

        let outside = root.appendingPathComponent("outside", isDirectory: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        try fm.createSymbolicLink(
            atPath: dest.appendingPathComponent("folder-3").path,
            withDestinationPath: outside.path
        )

        XCTAssertThrowsError(
            try ArchiveExtractionPolicy.buildPlan(
                entries: entries,
                archiveURL: root.appendingPathComponent("sample.zip"),
                destinationURL: dest,
                options: ExtractionOptions(stripSingleRootFolderIfMatching: false)
            )
        ) { error in
            guard case .destinationIsSymlink = error as? ProZipError else {
                return XCTFail("Expected destinationIsSymlink, got \(error)")
            }
        }
    }

    func testDiskImageInspectSignatureHandlesUnsignedAndAdHocBundles() async throws {
        let root = try makeTempDirectory()
        let fm = FileManager.default
        let appURL = root.appendingPathComponent("Sample.app", isDirectory: true)
        let macosURL = appURL.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try fm.createDirectory(at: macosURL, withIntermediateDirectories: true)

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleExecutable</key>
            <string>Sample</string>
            <key>CFBundleIdentifier</key>
            <string>org.prozip.test.sample</string>
        </dict>
        </plist>
        """
        try Data(plist.utf8).write(to: appURL.appendingPathComponent("Contents/Info.plist"))
        let execURL = macosURL.appendingPathComponent("Sample")
        try fm.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: execURL)
        // Strip existing signature on copied binary so unsigned path is tested first
        _ = try? await ProcessCancellationController.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/codesign"),
            arguments: ["--remove-signature", execURL.path]
        )

        let unsignedStatus = await DiskImageEngine.inspectSignature(of: appURL)
        XCTAssertEqual(unsignedStatus, .unsigned)

        let signRes = try await ProcessCancellationController.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/codesign"),
            arguments: ["--force", "--sign", "-", appURL.path]
        )
        XCTAssertEqual(signRes.exitCode, 0)

        let adHocStatus = await DiskImageEngine.inspectSignature(of: appURL)
        XCTAssertEqual(adHocStatus, .adHocSigned)

        XCTAssertEqual(AllowedOpenFormat.exact32.count, 32)
        XCTAssertEqual(AllowedOpenFormat.defaultAllowedIDs.count, 32)
    }
}
