import XCTest
import SwiftUI
import AppKit
import Foundation
import SQLite3
@testable import ProZipShared
@testable import ProZipCore
@testable import ProZipEngines
@testable import ProZipUI

@MainActor
final class ProZipAcceptanceTests: XCTestCase {

    // MARK: - Binary ZIP Helpers for GBK / Raw Construction

    private func makeRawGBKZip(fileNameGBK: Data, content: Data) -> Data {
        var data = Data()
        let crc = NativeZipEngine().computeCRC32(for: content)
        let localOffset = UInt32(data.count)

        // 1. Local File Header (0x04034B50)
        data.append(contentsOf: [0x50, 0x4B, 0x03, 0x04])
        data.append(UInt16(20).littleEndianBytes) // version needed: 2.0
        data.append(UInt16(0).littleEndianBytes)  // flags: GP Bit 11 = 0 (Not UTF-8)
        data.append(UInt16(0).littleEndianBytes)  // method: Store (0)
        data.append(UInt16(0x4B3A).littleEndianBytes) // mod time
        data.append(UInt16(0x546B).littleEndianBytes) // mod date
        data.append(UInt32(crc).littleEndianBytes)
        data.append(UInt32(content.count).littleEndianBytes)
        data.append(UInt32(content.count).littleEndianBytes)
        data.append(UInt16(fileNameGBK.count).littleEndianBytes)
        data.append(UInt16(0).littleEndianBytes) // extra field length
        data.append(fileNameGBK)
        data.append(content)

        let cdOffset = UInt32(data.count)

        // 2. Central Directory Header (0x02014B50)
        data.append(contentsOf: [0x50, 0x4B, 0x01, 0x02])
        data.append(UInt16(0x0314).littleEndianBytes) // version made by: UNIX 2.0
        data.append(UInt16(20).littleEndianBytes)     // version needed: 2.0
        data.append(UInt16(0).littleEndianBytes)      // flags: GP Bit 11 = 0
        data.append(UInt16(0).littleEndianBytes)      // method: Store (0)
        data.append(UInt16(0x4B3A).littleEndianBytes) // mod time
        data.append(UInt16(0x546B).littleEndianBytes) // mod date
        data.append(UInt32(crc).littleEndianBytes)
        data.append(UInt32(content.count).littleEndianBytes)
        data.append(UInt32(content.count).littleEndianBytes)
        data.append(UInt16(fileNameGBK.count).littleEndianBytes)
        data.append(UInt16(0).littleEndianBytes) // extra field length
        data.append(UInt16(0).littleEndianBytes) // comment length
        data.append(UInt16(0).littleEndianBytes) // disk number start
        data.append(UInt16(0).littleEndianBytes) // internal attributes
        data.append(UInt32(0o100644 << 16).littleEndianBytes) // external attributes: regular file 0644
        data.append(UInt32(localOffset).littleEndianBytes)
        data.append(fileNameGBK)

        let cdSize = UInt32(data.count) - cdOffset

        // 3. End of Central Directory Record (0x06054B50)
        data.append(contentsOf: [0x50, 0x4B, 0x05, 0x06])
        data.append(UInt16(0).littleEndianBytes) // disk number
        data.append(UInt16(0).littleEndianBytes) // disk where CD starts
        data.append(UInt16(1).littleEndianBytes) // entries on this disk
        data.append(UInt16(1).littleEndianBytes) // total entries
        data.append(UInt32(cdSize).littleEndianBytes)
        data.append(UInt32(cdOffset).littleEndianBytes)
        data.append(UInt16(0).littleEndianBytes) // comment length

        return data
    }

    // MARK: - Group A: Browse & Index Acceptance Tests

    /// A1: Directory first, case-insensitive sort, and real directories overriding virtual directories
    func testA1_DirectoryFirstAndCaseInsensitiveSort() async throws {
        let index = try EntryIndex.inMemory()

        let entries = [
            ArchiveEntry(path: "readme.txt", type: .file, uncompressedSize: 10, modifiedAt: Date()),
            ArchiveEntry(path: "Alpha.txt", type: .file, uncompressedSize: 20, modifiedAt: Date()),
            ArchiveEntry(path: "sub/file.txt", type: .file, uncompressedSize: 30, modifiedAt: Date()),
            ArchiveEntry(path: "Beta", type: .directory, uncompressedSize: 0, modifiedAt: Date())
        ]

        try await index.rebuild(with: entries)
        let rootItems = try await index.listDirectory(parentPath: "")

        XCTAssertEqual(rootItems.count, 4)

        // 1. Directories appear first: "Beta" and "sub"
        XCTAssertTrue(rootItems[0].isDirectory)
        XCTAssertTrue(rootItems[1].isDirectory)
        XCTAssertEqual(rootItems[0].name, "Beta")
        XCTAssertEqual(rootItems[1].name, "sub")

        // 2. Files appear next in case-insensitive order: "Alpha.txt", "readme.txt"
        XCTAssertFalse(rootItems[2].isDirectory)
        XCTAssertFalse(rootItems[3].isDirectory)
        XCTAssertEqual(rootItems[2].name, "Alpha.txt")
        XCTAssertEqual(rootItems[3].name, "readme.txt")

        // 3. Real directory overrides virtual directory (excluded.is_virtual = 0)
        let entriesWithRealSub = [
            ArchiveEntry(path: "sub/file.txt", type: .file, uncompressedSize: 30, modifiedAt: Date()),
            ArchiveEntry(path: "sub", type: .directory, uncompressedSize: 0, modifiedAt: Date())
        ]
        let index2 = try EntryIndex.inMemory()
        try await index2.rebuild(with: entriesWithRealSub)
        let subItems = try await index2.listDirectory(parentPath: "")
        XCTAssertEqual(subItems.count, 1)
        XCTAssertEqual(subItems[0].name, "sub")
        XCTAssertTrue(subItems[0].isDirectory)
    }

    /// A2: UTF-8 Chinese names in ZIP archive probe & listing
    func testA2_UTF8ChineseNamesInZip() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("prozip_a2_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let subDir = tempDir.appendingPathComponent("中文目录")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        let testFile = subDir.appendingPathComponent("测试文件.txt")
        try "中文 UTF-8 内容".write(to: testFile, atomically: true, encoding: .utf8)

        let zipURL = tempDir.appendingPathComponent("utf8_chinese.zip")
        let engine = NativeZipEngine()

        try await engine.create(
            sources: [subDir],
            at: zipURL,
            profile: CreationProfile(purpose: .general, format: .zip),
            password: nil,
            progress: { _ in }
        )

        let desc = try await engine.probe(zipURL)
        XCTAssertFalse(desc.hasNonUTF8Encoding)
        XCTAssertTrue(desc.editingEligibility.allowed)

        let entries = try await engine.list(zipURL, password: nil, progress: { _ in })
        let paths = entries.map { $0.path }
        XCTAssertTrue(paths.contains(where: { $0.contains("中文目录") }))
        XCTAssertTrue(paths.contains(where: { $0.contains("测试文件.txt") }))
    }

    /// A3 & E7: GBK ZIP displays Chinese names properly, marks non-UTF8 encoding, and rejects editing
    func testA3_And_E7_GBKZipDisplayAndRejectEdit() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("prozip_a3_e7_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Encode "中文名称.txt" in GB18030 / GBK
        let cfEncoding = CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        guard let gbkBytes = "中文名称.txt".data(using: String.Encoding(rawValue: nsEncoding)) else {
            XCTFail("Failed to encode string in GB18030")
            return
        }

        let content = "GBK Payload".data(using: .utf8)!
        let rawZip = makeRawGBKZip(fileNameGBK: gbkBytes, content: content)

        let zipURL = tempDir.appendingPathComponent("gbk_archive.zip")
        try rawZip.write(to: zipURL)

        let engine = NativeZipEngine()
        let desc = try await engine.probe(zipURL)

        // 1. Detected non-UTF8 encoding
        XCTAssertTrue(desc.hasNonUTF8Encoding)
        XCTAssertEqual(desc.detectedEncodingName, "GBK")

        // 2. Correctly decoded Chinese filename
        let entries = try await engine.list(zipURL, password: nil, progress: { _ in })
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.name, "中文名称.txt")

        // 3. Editing eligibility rejected with informative reason
        XCTAssertFalse(desc.editingEligibility.allowed)
        XCTAssertNotNil(desc.editingEligibility.reason)
        XCTAssertTrue(desc.editingEligibility.reason?.contains("GBK") == true)

        // 4. Applying mutations is rejected by the engine
        let outURL = tempDir.appendingPathComponent("gbk_modified.zip")
        do {
            try await engine.applyMutations(
                [.deleteEntry(archivePath: "中文名称.txt")],
                to: zipURL,
                outputURL: outURL,
                profile: CreationProfile(purpose: .general, format: .zip),
                password: nil,
                progress: { _ in }
            )
            XCTFail("Expected editing GBK archive to be rejected")
        } catch {
            guard case .editingNotSupported = (error as? ProZipError) else {
                XCTFail("Expected editingNotSupported, got \(error)")
                return
            }
        }
    }

    /// A5: Corrupted or truncated ZIP archive is rejected with ProZipError.corruptedArchive
    func testA5_CorruptedTruncatedZipRejected() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("prozip_a5_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let corruptedURL = tempDir.appendingPathComponent("truncated.zip")
        try Data([0x50, 0x4B, 0x03, 0x04, 0x14, 0x00, 0x00]).write(to: corruptedURL)

        let engine = NativeZipEngine()
        do {
            _ = try await engine.probe(corruptedURL)
            XCTFail("Expected probe to fail on truncated archive")
        } catch {
            guard case .corruptedArchive = (error as? ProZipError) else {
                XCTFail("Expected corruptedArchive error, got \(error)")
                return
            }
        }
    }

    func testA6_Zip64OutOfRangeOffsetIsRejected() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("prozip_zip64_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var zip = Data()
        zip.append(UInt32(0x06064B50).littleEndianBytes)
        zip.append(UInt64(44).littleEndianBytes)
        zip.append(UInt16(45).littleEndianBytes)
        zip.append(UInt16(45).littleEndianBytes)
        zip.append(UInt32(0).littleEndianBytes)
        zip.append(UInt32(0).littleEndianBytes)
        zip.append(UInt64(1).littleEndianBytes)
        zip.append(UInt64(1).littleEndianBytes)
        zip.append(UInt64(0).littleEndianBytes)
        zip.append(UInt64.max.littleEndianBytes)
        zip.append(UInt32(0x07064B50).littleEndianBytes)
        zip.append(UInt32(0).littleEndianBytes)
        zip.append(UInt64(0).littleEndianBytes)
        zip.append(UInt32(1).littleEndianBytes)
        zip.append(UInt32(0x06054B50).littleEndianBytes)
        zip.append(UInt16(0).littleEndianBytes)
        zip.append(UInt16(0).littleEndianBytes)
        zip.append(UInt16.max.littleEndianBytes)
        zip.append(UInt16.max.littleEndianBytes)
        zip.append(UInt32.max.littleEndianBytes)
        zip.append(UInt32.max.littleEndianBytes)
        zip.append(UInt16(0).littleEndianBytes)
        let archive = root.appendingPathComponent("invalid.zip")
        try zip.write(to: archive)
        do {
            _ = try await NativeZipEngine().probe(archive)
            XCTFail("Out-of-range ZIP64 offset must fail without integer conversion traps")
        } catch {
            guard case .corruptedArchive = error as? ProZipError else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    /// A7 & A8: Directory entry, breadcrumb trail, and navigation stack (back, forward, up)
    func testA7_And_A8_EnterDirectoryAndNavigationStack() async throws {
        let session = ArchiveBrowsingSession()
        let entries = [
            ArchiveEntry(path: "folderA/file1.txt", type: .file, uncompressedSize: 10, modifiedAt: Date()),
            ArchiveEntry(path: "folderA/folderB/file2.txt", type: .file, uncompressedSize: 20, modifiedAt: Date()),
            ArchiveEntry(path: "root.txt", type: .file, uncompressedSize: 5, modifiedAt: Date())
        ]

        try await session.index.rebuild(with: entries)
        await session.refreshDisplayedEntries()

        // Root state
        XCTAssertEqual(session.currentDirectoryPath, "")
        XCTAssertFalse(session.canGoBack)
        XCTAssertFalse(session.canGoForward)
        XCTAssertFalse(session.canGoUp)
        XCTAssertEqual(session.breadcrumbs.count, 1)

        // Enter folderA
        await session.enterDirectory("folderA")
        XCTAssertEqual(session.currentDirectoryPath, "folderA")
        XCTAssertTrue(session.canGoBack)
        XCTAssertTrue(session.canGoUp)
        XCTAssertEqual(session.breadcrumbs.count, 2)
        XCTAssertEqual(session.breadcrumbs[1].title, "folderA")
        XCTAssertEqual(session.breadcrumbs[1].path, "folderA")

        // Enter folderA/folderB
        await session.enterDirectory("folderA/folderB")
        XCTAssertEqual(session.currentDirectoryPath, "folderA/folderB")
        XCTAssertEqual(session.breadcrumbs.count, 3)

        // Go Up to parent folderA
        await session.goUp()
        XCTAssertEqual(session.currentDirectoryPath, "folderA")

        // Go Back to folderA/folderB
        await session.goBack()
        XCTAssertEqual(session.currentDirectoryPath, "folderA/folderB")

        // Go Forward to folderA
        await session.goForward()
        XCTAssertEqual(session.currentDirectoryPath, "folderA")
    }

    /// A9: Auxiliary file filtering (__MACOSX, ._*, .DS_Store, Thumbs.db vs .gitignore, .env)
    func testA9_AuxiliaryFileFiltering() async throws {
        // 1. Model detection contract
        XCTAssertTrue(ArchiveEntry.detectAuxiliary(path: "__MACOSX/._sample.pdf"))
        XCTAssertTrue(ArchiveEntry.detectAuxiliary(path: "._data.dat"))
        XCTAssertTrue(ArchiveEntry.detectAuxiliary(path: ".DS_Store"))
        XCTAssertTrue(ArchiveEntry.detectAuxiliary(path: "sub/Thumbs.db"))
        XCTAssertFalse(ArchiveEntry.detectAuxiliary(path: ".gitignore"))
        XCTAssertFalse(ArchiveEntry.detectAuxiliary(path: ".env"))
        XCTAssertFalse(ArchiveEntry.detectAuxiliary(path: ".editorconfig"))

        // 2. EntryIndex query filtering
        let index = try EntryIndex.inMemory()
        let mixed = [
            ArchiveEntry(path: "report.pdf", type: .file, uncompressedSize: 100, modifiedAt: Date()),
            ArchiveEntry(path: "Thumbs.db", type: .file, uncompressedSize: 50, modifiedAt: Date()),
            ArchiveEntry(path: ".env", type: .file, uncompressedSize: 20, modifiedAt: Date()),
            ArchiveEntry(path: "__MACOSX/._report.pdf", type: .file, uncompressedSize: 30, modifiedAt: Date())
        ]

        try await index.rebuild(with: mixed)

        let hiddenList = try await index.listDirectory(parentPath: "", includeAuxiliary: false)
        let hiddenNames = hiddenList.map { $0.name }
        XCTAssertTrue(hiddenNames.contains("report.pdf"))
        XCTAssertTrue(hiddenNames.contains(".env"))
        XCTAssertFalse(hiddenNames.contains("Thumbs.db"))
        XCTAssertFalse(hiddenNames.contains("__MACOSX"))

        let visibleList = try await index.listDirectory(parentPath: "", includeAuxiliary: true)
        let visibleNames = visibleList.map { $0.name }
        XCTAssertTrue(visibleNames.contains("Thumbs.db"))
    }

    /// A11: IndexPhase capability gates and preliminary prompt
    func testA11_IndexPhaseCapabilityGates() {
        let preliminary = IndexPhase.preliminary(loadedCount: 50)
        XCTAssertTrue(preliminary.canBrowse)
        XCTAssertTrue(preliminary.canExtractAll)
        XCTAssertFalse(preliminary.canSearch)
        XCTAssertFalse(preliminary.canPreview)
        XCTAssertFalse(preliminary.canDragOut)
        XCTAssertFalse(preliminary.canExtractSelected)
        XCTAssertFalse(preliminary.canEdit)

        let reason = preliminary.disabledReason(for: "执行搜索")
        XCTAssertEqual(reason, "请等待文件列表读取完成，再执行搜索。")

        let ready = IndexPhase.ready(totalCount: 50)
        XCTAssertTrue(ready.canBrowse)
        XCTAssertTrue(ready.canExtractAll)
        XCTAssertTrue(ready.canSearch)
        XCTAssertTrue(ready.canPreview)
        XCTAssertTrue(ready.canDragOut)
        XCTAssertTrue(ready.canExtractSelected)
        XCTAssertTrue(ready.canEdit)
        XCTAssertNil(ready.disabledReason(for: "执行搜索"))
    }

    /// A12: Search with wildcard escaping (% and _ treated as literal characters)
    func testA12_SearchWithWildcardEscaping() async throws {
        let index = try EntryIndex.inMemory()
        let entries = [
            ArchiveEntry(path: "100%_done.txt", type: .file, uncompressedSize: 10, modifiedAt: Date()),
            ArchiveEntry(path: "1000done.txt", type: .file, uncompressedSize: 10, modifiedAt: Date()),
            ArchiveEntry(path: "a_b.txt", type: .file, uncompressedSize: 10, modifiedAt: Date()),
            ArchiveEntry(path: "axb.txt", type: .file, uncompressedSize: 10, modifiedAt: Date())
        ]

        try await index.rebuild(with: entries)

        // Searching for "100%" must only match "100%_done.txt"
        let percentMatches = try await index.search(keyword: "100%")
        XCTAssertEqual(percentMatches.count, 1)
        XCTAssertEqual(percentMatches.first?.path, "100%_done.txt")

        // Searching for "a_b" must only match "a_b.txt"
        let underscoreMatches = try await index.search(keyword: "a_b")
        XCTAssertEqual(underscoreMatches.count, 1)
        XCTAssertEqual(underscoreMatches.first?.path, "a_b.txt")
    }

    // MARK: - Group B: Extraction & Security Acceptance Tests

    /// B1 & B2: Extraction planning and single-root folder deduplication
    func testB1_And_B2_ExtractAllAndSingleRootDeduplication() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("prozip_b1_b2_\(UUID().uuidString)")
        let destURL = tempDir.appendingPathComponent("sample")
        try FileManager.default.createDirectory(at: destURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let entries = [
            ArchiveEntry(path: "sample/readme.txt", type: .file, uncompressedSize: 10, modifiedAt: Date()),
            ArchiveEntry(path: "sample/src/app.swift", type: .file, uncompressedSize: 20, modifiedAt: Date())
        ]

        let options = ExtractionOptions(
            conflictResolution: .replace,
            stripSingleRootFolderIfMatching: true
        )

        let plan = try ArchiveExtractionPolicy.buildPlan(
            entries: entries,
            archiveURL: tempDir.appendingPathComponent("sample.zip"),
            destinationURL: destURL,
            options: options
        )

        XCTAssertEqual(plan.itemsToExtract.count, 2)
        // Stripped single root folder avoids sample/sample/
        XCTAssertEqual(plan.itemsToExtract[0].relativeOutputPath, "readme.txt")
        XCTAssertEqual(plan.itemsToExtract[0].destinationURL.path, destURL.appendingPathComponent("readme.txt").path)
        XCTAssertEqual(plan.itemsToExtract[1].relativeOutputPath, "src/app.swift")
        XCTAssertEqual(plan.itemsToExtract[1].destinationURL.path, destURL.appendingPathComponent("src/app.swift").path)
    }

    /// B3: Path traversal paths rejected with ProZipError.unsafePath
    func testB3_PathTraversalRejected() {
        XCTAssertThrowsError(try ArchiveExtractionPolicy.validateRelativeArchivePath("../../evil.txt")) { error in
            XCTAssertEqual(error as? ProZipError, ProZipError.unsafePath("../../evil.txt"))
        }
        XCTAssertThrowsError(try ArchiveExtractionPolicy.validateRelativeArchivePath("foo/../../evil.txt")) { error in
            XCTAssertEqual(error as? ProZipError, ProZipError.unsafePath("foo/../../evil.txt"))
        }
    }

    /// B4: Absolute paths rejected with ProZipError.unsafePath
    func testB4_AbsolutePathRejected() {
        XCTAssertThrowsError(try ArchiveExtractionPolicy.validateRelativeArchivePath("/tmp/evil.txt")) { error in
            XCTAssertEqual(error as? ProZipError, ProZipError.unsafePath("/tmp/evil.txt"))
        }
        XCTAssertThrowsError(try ArchiveExtractionPolicy.validateRelativeArchivePath("C:\\Windows\\evil.txt")) { error in
            XCTAssertEqual(error as? ProZipError, ProZipError.unsafePath("C:\\Windows\\evil.txt"))
        }
    }

    /// B5 & B6: Symlink target bounds validation (external rejected, internal allowed)
    func testB5_And_B6_SymlinkOutOfBoundsRejectedAndInternalAllowed() {
        let extractionRoot = URL(fileURLWithPath: "/tmp/prozip_test/dest")
        let linkURL = extractionRoot.appendingPathComponent("links/test_link")

        // Symlink pointing to /etc/passwd rejected
        XCTAssertThrowsError(try ArchiveExtractionPolicy.validateSymlinkTarget(
            linkDestinationURL: linkURL,
            targetPath: "/etc/passwd",
            extractionRootURL: extractionRoot
        )) { error in
            XCTAssertEqual(error as? ProZipError, ProZipError.symlinkOutOfBounds("/etc/passwd"))
        }

        // Symlink pointing to ../../outside rejected
        XCTAssertThrowsError(try ArchiveExtractionPolicy.validateSymlinkTarget(
            linkDestinationURL: linkURL,
            targetPath: "../../outside",
            extractionRootURL: extractionRoot
        )) { error in
            XCTAssertEqual(error as? ProZipError, ProZipError.symlinkOutOfBounds("../../outside"))
        }

        // Symlink pointing within root directory allowed
        XCTAssertNoThrow(try ArchiveExtractionPolicy.validateSymlinkTarget(
            linkDestinationURL: linkURL,
            targetPath: "./readme.txt",
            extractionRootURL: extractionRoot
        ))
        XCTAssertNoThrow(try ArchiveExtractionPolicy.validateSymlinkTarget(
            linkDestinationURL: linkURL,
            targetPath: "../root_file.txt",
            extractionRootURL: extractionRoot
        ))
    }

    /// B8 & B9: Conflict resolution (replace, keepBoth, skip) and structure conflict detection
    func testB8_And_B9_ConflictResolutionAndStructureConflict() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("prozip_b8_b9_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let existingFile = tempDir.appendingPathComponent("existing.txt")
        try "Disk content".write(to: existingFile, atomically: true, encoding: .utf8)

        let archiveURL = tempDir.appendingPathComponent("archive.zip")
        let fileEntry = ArchiveEntry(path: "existing.txt", type: .file, uncompressedSize: 20, modifiedAt: Date())

        // 1. Conflict: replace
        let replaceOpt = ExtractionOptions(conflictResolution: .replace)
        let replacePlan = try ArchiveExtractionPolicy.buildPlan(entries: [fileEntry], archiveURL: archiveURL, destinationURL: tempDir, options: replaceOpt)
        XCTAssertEqual(replacePlan.itemsToExtract.count, 1)
        XCTAssertEqual(replacePlan.itemsToExtract.first?.conflictAction, ConflictResolution.replace)
        XCTAssertEqual(replacePlan.itemsToExtract.first?.destinationURL.path, existingFile.path)

        // 2. Conflict: skip
        let skipOpt = ExtractionOptions(conflictResolution: .skip)
        let skipPlan = try ArchiveExtractionPolicy.buildPlan(entries: [fileEntry], archiveURL: archiveURL, destinationURL: tempDir, options: skipOpt)
        XCTAssertEqual(skipPlan.itemsToExtract.count, 0)
        XCTAssertEqual(skipPlan.skippedEntries.count, 1)

        // 3. Conflict: keepBoth -> renames to "existing (2).txt"
        let keepBothOpt = ExtractionOptions(conflictResolution: .keepBoth)
        let keepBothPlan = try ArchiveExtractionPolicy.buildPlan(entries: [fileEntry], archiveURL: archiveURL, destinationURL: tempDir, options: keepBothOpt)
        XCTAssertEqual(keepBothPlan.itemsToExtract.count, 1)
        XCTAssertEqual(keepBothPlan.itemsToExtract.first?.destinationURL.lastPathComponent, "existing (2).txt")

        // 4. Structure conflict: Disk has directory "conflict_dir", archive entry is FILE "conflict_dir"
        let conflictDirOnDisk = tempDir.appendingPathComponent("conflict_dir")
        try FileManager.default.createDirectory(at: conflictDirOnDisk, withIntermediateDirectories: true)
        let conflictFileEntry = ArchiveEntry(path: "conflict_dir", type: .file, uncompressedSize: 10, modifiedAt: Date())
        XCTAssertThrowsError(try ArchiveExtractionPolicy.buildPlan(entries: [conflictFileEntry], archiveURL: archiveURL, destinationURL: tempDir, options: replaceOpt)) { error in
            guard case .structureConflict = (error as? ProZipError) else {
                XCTFail("Expected structureConflict, got \(error)")
                return
            }
        }
    }

    func testB10_ExtractMergesExistingDirectoriesAcrossEngines() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("prozip_merge_\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let source = root.appendingPathComponent("payload")
        let nested = source.appendingPathComponent("nested")
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("new content".utf8).write(to: nested.appendingPathComponent("new.txt"))
        try Data("replacement".utf8).write(to: nested.appendingPathComponent("replace.txt"))
        let archive = root.appendingPathComponent("archive.zip")
        try await NativeZipEngine().create(sources: [source], at: archive,
            profile: CreationProfile(purpose: .general, format: .zip), password: nil, progress: { _ in })

        var engines: [any ArchiveEngine] = [NativeZipEngine(), LibarchiveEngine()]
        if SevenZipEngine.resolveBinaryURL() != nil { engines.append(SevenZipEngine()) }
        for (index, engine) in engines.enumerated() {
            let destination = root.appendingPathComponent("output-\(index)")
            let existing = destination.appendingPathComponent("payload/nested")
            try fm.createDirectory(at: existing, withIntermediateDirectories: true)
            try Data("user file".utf8).write(to: existing.appendingPathComponent("keep.txt"))
            try Data("old content".utf8).write(to: existing.appendingPathComponent("replace.txt"))
            let entries = try await engine.list(archive, password: nil, progress: { _ in })
            let report = try await engine.extract(entries, from: archive, to: destination, password: nil,
                options: ExtractionOptions(conflictResolution: .replace, stripSingleRootFolderIfMatching: false),
                progress: { _ in })

            XCTAssertEqual(try String(contentsOf: existing.appendingPathComponent("keep.txt")), "user file", engine.engineName)
            XCTAssertEqual(try String(contentsOf: existing.appendingPathComponent("new.txt")), "new content", engine.engineName)
            XCTAssertEqual(try String(contentsOf: existing.appendingPathComponent("replace.txt")), "replacement", engine.engineName)
            XCTAssertTrue(report.extractedURLs.contains { $0.lastPathComponent == "new.txt" }, engine.engineName)
        }
    }

    func testB11_RejectsExistingSymlinkInOutputDirectory() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("prozip_output_link_\(UUID().uuidString)")
        let destination = root.appendingPathComponent("destination")
        let outside = root.appendingPathComponent("outside")
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try fm.createSymbolicLink(at: destination.appendingPathComponent("nested"), withDestinationURL: outside)

        for entry in [
            ArchiveEntry(path: "nested/file.txt", type: .file, uncompressedSize: 1, modifiedAt: Date()),
            ArchiveEntry(path: "nested", type: .directory, uncompressedSize: 0, modifiedAt: Date())
        ] {
            XCTAssertThrowsError(try ArchiveExtractionPolicy.buildPlan(entries: [entry],
                archiveURL: root.appendingPathComponent("archive.zip"), destinationURL: destination,
                options: ExtractionOptions(stripSingleRootFolderIfMatching: false))) { error in
                    guard case .destinationIsSymlink = error as? ProZipError else {
                        return XCTFail("Expected destinationIsSymlink, got \(error)")
                    }
                }
        }
    }

    func testB12_SingleFileMatchingDestinationIsNotStripped() throws {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let entry = ArchiveEntry(path: destination.lastPathComponent, type: .file, uncompressedSize: 1, modifiedAt: Date())
        let plan = try ArchiveExtractionPolicy.buildPlan(entries: [entry],
            archiveURL: destination.appendingPathExtension("zip"), destinationURL: destination,
            options: ExtractionOptions(stripSingleRootFolderIfMatching: true))
        XCTAssertEqual(plan.itemsToExtract.map(\.relativeOutputPath), [entry.path])
    }

    func testB13_DirectoryAncestorsConflictWithFiles() throws {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let entries = [
            ArchiveEntry(path: "folder/subfolder", type: .directory, uncompressedSize: 0, modifiedAt: Date()),
            ArchiveEntry(path: "folder", type: .file, uncompressedSize: 1, modifiedAt: Date())
        ]
        XCTAssertThrowsError(try ArchiveExtractionPolicy.buildPlan(entries: entries,
            archiveURL: destination.appendingPathExtension("zip"), destinationURL: destination,
            options: ExtractionOptions(stripSingleRootFolderIfMatching: false)))
    }

    func testB14_ZipPreservesRelativeSymlinkTarget() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("prozip_relative_link_\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let source = root.appendingPathComponent("source")
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("target".utf8).write(to: source.appendingPathComponent("target.txt"))
        try fm.createSymbolicLink(atPath: source.appendingPathComponent("link.txt").path, withDestinationPath: "target.txt")
        let archive = root.appendingPathComponent("links.zip")
        let engine = NativeZipEngine()
        try await engine.create(sources: [source], at: archive,
            profile: CreationProfile(purpose: .general, format: .zip), password: nil, progress: { _ in })
        let entries = try await engine.list(archive, password: nil, progress: { _ in })
        let destination = root.appendingPathComponent("output")
        _ = try await engine.extract(entries, from: archive, to: destination, password: nil,
            options: ExtractionOptions(stripSingleRootFolderIfMatching: false), progress: { _ in })
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: destination.appendingPathComponent("source/link.txt").path), "target.txt")
    }

    func testB15_BsdtarListingSkipsDatesAndSummary() {
        let listing = """
        drwxr-xr-x  0 user staff       0 Nov 11 00:31 payload/
        -rw-r--r--  0 user staff      12 Nov 11  2025 payload/file with spaces.txt
        lrwxr-xr-x  0 user staff       0 Nov 11 00:31 payload/link -> file with spaces.txt
        Archive Format: POSIX ustar format,  Compression: none
        """
        let entries = LibarchiveEngine.parseBsdtarListing(listing)
        XCTAssertEqual(entries.map(\.path), ["payload", "payload/file with spaces.txt", "payload/link"])
        XCTAssertEqual(entries[1].uncompressedSize, 12)
        XCTAssertEqual(entries[2].symlinkTarget, "file with spaces.txt")
    }

    func testB16_ZipCreatesDirectoryAndDanglingSymlinksWithoutFollowingThem() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("prozip_link_sources_\(UUID().uuidString)")
        try fm.createDirectory(at: root.appendingPathComponent("source"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try Data("must not follow".utf8).write(to: root.appendingPathComponent("source/payload.txt"))
        let directoryLink = root.appendingPathComponent("directory-link")
        let danglingLink = root.appendingPathComponent("dangling-link")
        try fm.createSymbolicLink(atPath: directoryLink.path, withDestinationPath: "source")
        try fm.createSymbolicLink(atPath: danglingLink.path, withDestinationPath: "missing.txt")
        let archive = root.appendingPathComponent("links.zip")
        let engine = NativeZipEngine()
        try await engine.create(sources: [directoryLink, danglingLink], at: archive,
            profile: CreationProfile(purpose: .general, format: .zip), password: nil, progress: { _ in })
        let entries = try await engine.list(archive, password: nil, progress: { _ in })
        XCTAssertEqual(Set(entries.map(\.path)), ["directory-link", "dangling-link"])
        XCTAssertTrue(entries.allSatisfy { $0.type == .symlink })
    }

    func testH1_CancellingChildProcessThrowsCancellation() async throws {
        let task = Task {
            try await ProcessCancellationController.run(executableURL: URL(fileURLWithPath: "/bin/sleep"), arguments: ["5"])
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled child process must not report success")
        } catch is CancellationError {
        }
    }

    func testH2_CancelledPublicationPreservesOriginal() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("prozip_cancel_publish_\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let registry = try ManagedTemporaryArtifactRegistry(fileURL: root.appendingPathComponent("registry.sqlite"))
        let target = root.appendingPathComponent("archive.zip")
        try Data("original".utf8).write(to: target)
        let task = Task {
            try await registry.publishAtomically(targetURL: target, writer: { partial in
                try Data("new content".utf8).write(to: partial)
                withUnsafeCurrentTask { $0?.cancel() }
            }, verifier: { _ in })
        }
        do {
            _ = try await task.value
            XCTFail("Cancelled writer must not publish its result")
        } catch is CancellationError {
        }
        XCTAssertEqual(try String(contentsOf: target), "original")
        XCTAssertFalse(try fm.contentsOfDirectory(atPath: root.path).contains { $0.contains(".prozip-partial-") })
    }

    func testH3_ChildProcessOutputBudgetIncludesFinalBytes() async throws {
        do {
            _ = try await ProcessCancellationController.run(executableURL: URL(fileURLWithPath: "/usr/bin/head"),
                arguments: ["-c", String(ProcessCancellationController.maxSingleLineBytes + 1), "/dev/zero"])
            XCTFail("Output above the single-line limit must fail")
        } catch {
            guard case .outputExceedsBudget = error as? ProZipError else {
                return XCTFail("Expected outputExceedsBudget, got \(error)")
            }
        }
    }

    func testH4_LargeBinaryMemberStreamsBypassDiagnosticLineLimit() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("prozip_binary_stream_\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let source = root.appendingPathComponent("binary.dat")
        let content = Data(repeating: 0xCE, count: ProcessCancellationController.maxSingleLineBytes + 65_536)
        try content.write(to: source)
        var engines: [(any ArchiveEngine, ArchiveFormat)] = [(LibarchiveEngine(), .gzip)]
        if SevenZipEngine.resolveBinaryURL() != nil { engines.append((SevenZipEngine(), .sevenZip)) }
        for (index, item) in engines.enumerated() {
            let (engine, format) = item
            let archive = root.appendingPathComponent("binary.\(format == .gzip ? "gz" : "7z")")
            try await engine.create(sources: [source], at: archive,
                profile: CreationProfile(purpose: .general, format: format), password: nil, progress: { _ in })
            let entries = try await engine.list(archive, password: nil, progress: { _ in })
            let member = try XCTUnwrap(entries.first { !$0.isDirectory })
            var bytes = 0
            for try await chunk in try await engine.openMember(member, in: archive, password: nil, range: nil) {
                XCTAssertLessThanOrEqual(chunk.count, 65_536)
                XCTAssertTrue(chunk.allSatisfy { $0 == 0xCE })
                bytes += chunk.count
            }
            XCTAssertEqual(bytes, content.count, engine.engineName)
            var rangeData = Data()
            for try await chunk in try await engine.openMember(member, in: archive, password: nil, range: 65_530..<65_550) {
                rangeData.append(chunk)
            }
            XCTAssertEqual(rangeData, Data(repeating: 0xCE, count: 20))
            let output = root.appendingPathComponent("output-\(index)")
            let report = try await engine.extract(entries, from: archive, to: output, password: nil,
                options: ExtractionOptions(stripSingleRootFolderIfMatching: false), progress: { _ in })
            XCTAssertEqual(try Data(contentsOf: XCTUnwrap(report.extractedURLs.first)), content, engine.engineName)
        }
        let activeReads = await MemberReadBudgetLimiter.shared.currentActiveReads
        XCTAssertEqual(activeReads, 0)
    }

    func testH5_NativeZipRejectsOversizedSourceBeforeReadingPayload() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("prozip_memory_budget_\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let source = root.appendingPathComponent("sparse.bin")
        fm.createFile(atPath: source.path, contents: nil)
        let file = try FileHandle(forWritingTo: source)
        try file.truncate(atOffset: UInt64(ProcessCancellationController.maxBinaryOutputBytes + 1))
        try file.close()
        let archive = root.appendingPathComponent("archive.zip")
        do {
            try await NativeZipEngine().create(sources: [source], at: archive,
                profile: CreationProfile(purpose: .general, format: .zip), password: nil, progress: { _ in })
            XCTFail("Large input must use the streaming engine")
        } catch {
            guard case .outputExceedsBudget = error as? ProZipError else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertFalse(fm.fileExists(atPath: archive.path))
    }

    func testH6_InflateRejectsPayloadLargerThanDeclaredSize() throws {
        let content = Data(repeating: 0x42, count: 65_536)
        let compressed = try NativeZipEngine.deflateRaw(data: content, level: 6)
        XCTAssertThrowsError(try NativeZipEngine.inflateRaw(data: compressed, expectedSize: 1))
        XCTAssertEqual(try NativeZipEngine.inflateRaw(data: compressed, expectedSize: Int64(content.count)), content)
    }

    // MARK: - Group C: Creation & Transactions Acceptance Tests

    /// C1 & C2: CompressionBodyProbe selects Store (0) for incompressible and Deflate (8) for compressible
    func testC1_And_C2_StoreAndDeflateProbe() {
        // High-entropy random payload (incompressible under Deflate)
        let incompressible = Data((0..<16384).map { _ in UInt8.random(in: 0...255) })

        // Highly compressible payload
        let compressible = Data(repeating: 0x42, count: 65536)

        // Incompressible switches to Store (false)
        let shouldDeflateIncompressible = CompressionBodyProbe.shouldUseDeflate(for: incompressible, strength: .balanced)
        XCTAssertFalse(shouldDeflateIncompressible)

        // Compressible uses Deflate (true)
        let shouldDeflateCompressible = CompressionBodyProbe.shouldUseDeflate(for: compressible, strength: .balanced)
        XCTAssertTrue(shouldDeflateCompressible)

        // Strength .store always forces Store
        XCTAssertFalse(CompressionBodyProbe.shouldUseDeflate(for: compressible, strength: .store))
    }

    /// C3: CreationManifest and post-write structural verification
    func testC3_ManifestAndPostWriteVerification() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("prozip_c3_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceFile = tempDir.appendingPathComponent("test.txt")
        let content = "Verification manifest payload"
        try content.write(to: sourceFile, atomically: true, encoding: .utf8)
        let zipURL = tempDir.appendingPathComponent("verified.zip")

        let engine = NativeZipEngine()
        try await engine.create(
            sources: [sourceFile],
            at: zipURL,
            profile: CreationProfile(purpose: .general, format: .zip),
            password: nil,
            progress: { _ in }
        )

        let contentData = Data(content.utf8)
        let crc = engine.computeCRC32(for: contentData)

        // Valid manifest passes post-write verification
        let validManifest = CreationManifest(items: [
            CreationManifestItem(path: "test.txt", type: .file, compressionMethod: 0, uncompressedSize: Int64(contentData.count), crc32: crc)
        ])
        XCTAssertNoThrow(try NativeZipEngine.verifyArchive(at: zipURL, against: validManifest))

        // Tampered manifest with extra entry fails verification
        let tamperedManifest = CreationManifest(items: [
            CreationManifestItem(path: "test.txt", type: .file, compressionMethod: 0, uncompressedSize: Int64(contentData.count), crc32: crc),
            CreationManifestItem(path: "tampered.txt", type: .file, compressionMethod: 0, uncompressedSize: 10, crc32: 0)
        ])
        XCTAssertThrowsError(try NativeZipEngine.verifyArchive(at: zipURL, against: tamperedManifest)) { error in
            guard case .verificationFailed = (error as? ProZipError) else {
                XCTFail("Expected verificationFailed, got \(error)")
                return
            }
        }
    }

    /// C4 & C7: ManagedTemporaryArtifactRegistry atomic publication, rollback, identity guard, and crash recovery
    func testC4_And_C7_AtomicPublicationAndCrashRollback() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("prozip_c4_c7_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dbURL = tempDir.appendingPathComponent("artifacts.sqlite")
        let registry = try ManagedTemporaryArtifactRegistry(fileURL: dbURL)
        let targetURL = tempDir.appendingPathComponent("target.zip")
        try "Original Stable Content".write(to: targetURL, atomically: true, encoding: .utf8)

        // 1. Rollback on verification failure
        do {
            _ = try await registry.publishAtomically(
                targetURL: targetURL,
                allowOverwrite: true,
                writer: { partial in
                    try "Corrupted Unverified Content".write(to: partial, atomically: true, encoding: .utf8)
                },
                verifier: { _ in
                    throw ProZipError.verificationFailed("Simulated verification error")
                }
            )
            XCTFail("Expected publishAtomically to throw")
        } catch {
            // Target file remains untouched with original content
            let targetContent = try String(contentsOf: targetURL, encoding: .utf8)
            XCTAssertEqual(targetContent, "Original Stable Content")
            // Partial artifacts are safely rolled back
            let leftoverPartials = (try? FileManager.default.contentsOfDirectory(atPath: tempDir.path))?.filter { $0.contains(".prozip-partial-") } ?? []
            XCTAssertTrue(leftoverPartials.isEmpty)
        }

        // 2. Identity Guard (device/inode mismatch)
        let guardedFile = tempDir.appendingPathComponent("guard.tmp")
        try "Guarded content".write(to: guardedFile, atomically: true, encoding: .utf8)
        let artID = try await registry.registerArtifact(at: guardedFile, purpose: .archiveCreation, sessionID: "s1")
        try await registry.updateArtifactIdentity(artifactID: artID, at: guardedFile)

        // Tamper with file identity by replacing it with a new file
        try FileManager.default.removeItem(at: guardedFile)
        try "Substituted file with new inode".write(to: guardedFile, atomically: true, encoding: .utf8)

        do {
            try await registry.safelyRemoveArtifact(artifactID: artID)
            XCTFail("Expected artifactIdentityMismatch")
        } catch {
            guard case .artifactIdentityMismatch = (error as? ProZipError) else {
                XCTFail("Expected artifactIdentityMismatch, got \(error)")
                return
            }
        }

        // 3. Crash recovery rolls back unfinished publication from crashed process
        let crashTarget = tempDir.appendingPathComponent("crash_target.zip")
        try "Target before crash".write(to: crashTarget, atomically: true, encoding: .utf8)

        let crashPartial = tempDir.appendingPathComponent("crash_partial.tmp")
        try "Partial written before crash".write(to: crashPartial, atomically: true, encoding: .utf8)

        let crashBackup = tempDir.appendingPathComponent("crash_backup.tmp")
        try "Target before crash".write(to: crashBackup, atomically: true, encoding: .utf8)

        let crashArtID = try await registry.registerArtifact(at: crashPartial, purpose: .archiveCreation, sessionID: "crashed_session")
        try await registry.updateArtifactIdentity(artifactID: crashArtID, at: crashPartial)

        let plan = PublicationPlan(targetPath: crashTarget.path, partialPath: crashPartial.path, backupPath: crashBackup.path, artifactID: crashArtID)
        let planData = try JSONEncoder().encode(plan)

        let insertPubSQL = """
        INSERT INTO archive_publications (
            transaction_id, session_id, process_id, ownership_token,
            state, parent_path, plan, reserved_at, updated_at
        ) VALUES ('crash_tx', 'crashed_session', 999999, 'token', 'prepared', ?, ?, 0, 0);
        """
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        var dbHandle: OpaquePointer?
        if sqlite3_open(dbURL.path, &dbHandle) == SQLITE_OK {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(dbHandle, insertPubSQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, tempDir.path, -1, transient)
                planData.withUnsafeBytes { raw in
                    _ = sqlite3_bind_blob(stmt, 2, raw.baseAddress, Int32(raw.count), transient)
                }
                let stepRes = sqlite3_step(stmt)
                XCTAssertEqual(stepRes, SQLITE_DONE)
                sqlite3_finalize(stmt)
            }
            sqlite3_close(dbHandle)
        }

        let recovery = try await registry.performStartupRecovery()
        XCTAssertGreaterThanOrEqual(recovery.cleanedArtifactsCount, 1)
        XCTAssertGreaterThanOrEqual(recovery.rolledBackCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: crashPartial.path))
    }

    /// C13: ZIP password with non-ASCII characters is rejected with prompt to use 7Z
    func testC13_ZipNonASCIIPasswordRejected() {
        let zipProfile = CreationProfile(
            purpose: .general,
            format: .zip,
            password: "密码123"
        )
        XCTAssertThrowsError(try zipProfile.validate()) { error in
            guard case .invalidCreationProfile(let message) = (error as? ProZipError) else {
                XCTFail("Expected invalidCreationProfile, got \(error)")
                return
            }
            XCTAssertEqual(message, "为保证跨平台可解压，创建 ZIP 时密码仅支持 ASCII。中文密码请使用 7Z")
        }

        // 7Z supports Unicode passwords
        let sevenZipProfile = CreationProfile(
            purpose: .general,
            format: .sevenZip,
            password: "密码123"
        )
        XCTAssertNoThrow(try sevenZipProfile.validate())
    }

    /// C14: Windows name repair repairs reserved and illegal names without touching source files
    func testC14_WindowsNameRepair() throws {
        XCTAssertEqual(WindowsNameRepairPolicy.repairComponent("CON.txt"), "_CON.txt")
        XCTAssertEqual(WindowsNameRepairPolicy.repairComponent("a:b*c?.txt"), "a_b_c_.txt")
        XCTAssertEqual(WindowsNameRepairPolicy.repairComponent("trailing... "), "trailing")
        XCTAssertEqual(WindowsNameRepairPolicy.repairPath("nested:folder/PRN.dat"), "nested_folder/_PRN.dat")

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("prozip_c14_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceFile = tempDir.appendingPathComponent("CON.txt")
        try "Original Source".write(to: sourceFile, atomically: true, encoding: .utf8)

        let issues = WindowsNameRepairPolicy.scan(paths: ["CON.txt", "a:b*c?.txt"])
        XCTAssertEqual(issues.count, 2)

        // Verify source file on disk is untouched
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceFile.path))
        XCTAssertEqual(try String(contentsOf: sourceFile, encoding: .utf8), "Original Source")
    }

    // MARK: - Group D: Passwords & PasswordBook Acceptance Tests

    /// D1 & D2: Traditional encrypted ZIP (ZipCrypto) correct password extracts, wrong password throws ProZipError.wrongPassword
    func testD1_And_D2_EncryptedZipCorrectAndWrongPassword() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("prozip_d1_d2_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let file = tempDir.appendingPathComponent("secret.txt")
        try "Top Secret 007".write(to: file, atomically: true, encoding: .utf8)

        let zipURL = tempDir.appendingPathComponent("encrypted.zip")
        let engine = NativeZipEngine()

        try await engine.create(
            sources: [file],
            at: zipURL,
            profile: CreationProfile(purpose: .general, format: .zip, password: "secret123"),
            password: "secret123",
            progress: { _ in }
        )

        let desc = try await engine.probe(zipURL)
        XCTAssertTrue(desc.isEncrypted)

        let extractDir = tempDir.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

        let entries = try await engine.list(zipURL, password: "secret123", progress: { _ in })
        XCTAssertEqual(entries.count, 1)

        // 1. Wrong password throws ProZipError.wrongPassword
        do {
            _ = try await engine.extract(
                entries,
                from: zipURL,
                to: extractDir,
                password: "badPassword",
                options: ExtractionOptions(),
                progress: { _ in }
            )
            XCTFail("Expected extraction with wrong password to throw")
        } catch {
            guard case .wrongPassword = (error as? ProZipError) else {
                XCTFail("Expected wrongPassword error, got \(error)")
                return
            }
        }

        // 2. Right password extracts cleanly
        let report = try await engine.extract(
            entries,
            from: zipURL,
            to: extractDir,
            password: "secret123",
            options: ExtractionOptions(),
            progress: { _ in }
        )
        XCTAssertEqual(report.extractedCount, 1)
        let extractedContent = try String(contentsOf: extractDir.appendingPathComponent("secret.txt"), encoding: .utf8)
        XCTAssertEqual(extractedContent, "Top Secret 007")
    }

    /// D6 & D7: PasswordBook AES-GCM encryption, master password locking, rejecting wrong master password
    func testD6_And_D7_PasswordBookEncryptionAndMasterPassword() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("prozip_d6_d7_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dbFile = tempDir.appendingPathComponent("vault.dat")
        let book = PasswordBook(storageURL: dbFile, keyStore: TestPasswordBookKeyStore())

        _ = book.addEntry(title: "Test Archive", password: "vaultKey42")
        XCTAssertEqual(book.entries.count, 1)

        book.setMasterPassword("masterSecret")
        book.lock()
        XCTAssertTrue(book.isLocked)
        XCTAssertTrue(book.entries.isEmpty)

        // Wrong master password rejected
        let wrongUnlock = book.unlock(withMasterPassword: "wrongPassword")
        XCTAssertFalse(wrongUnlock)
        XCTAssertTrue(book.isLocked)
        XCTAssertTrue(book.entries.isEmpty)

        // Right master password unlocks
        let correctUnlock = book.unlock(withMasterPassword: "masterSecret")
        XCTAssertTrue(correctUnlock)
        XCTAssertFalse(book.isLocked)
        XCTAssertEqual(book.entries.count, 1)
        XCTAssertEqual(book.entries.first?.password, "vaultKey42")
    }

    /// D8: Password never exposed in process argv command line arguments
    func testD8_PasswordNeverInProcessArguments() {
        let argsWithPassword = SevenZipEngine.buildCommandArguments(
            subcommand: "x",
            archivePath: "/tmp/archive.7z",
            extraArgs: ["-o/tmp/dest"],
            hasPassword: true
        )
        for arg in argsWithPassword {
            XCTAssertFalse(arg.hasPrefix("-p"), "Argv must never contain -p flag when hasPassword is true: \(arg)")
        }

        let argsWithoutPassword = SevenZipEngine.buildCommandArguments(
            subcommand: "x",
            archivePath: "/tmp/archive.7z",
            extraArgs: ["-o/tmp/dest"],
            hasPassword: false
        )
        XCTAssertTrue(argsWithoutPassword.contains("-p__ARCZIP_NO_PASSWORD__"))
    }

    // MARK: - Group E: Editing & Save Acceptance Tests

    /// E1 to E4: Draft mutations, Undo/Redo stack, and NativeZipEngine.applyMutations (add, delete, rename)
    func testE1_To_E4_AddDeleteRenameAndUndoRedo() async throws {
        // Part 1: ArchiveBrowsingSession Undo/Redo stack
        let session = ArchiveBrowsingSession()
        let dummy = URL(fileURLWithPath: "/tmp/dummy.txt")
        try? "dummy".write(to: dummy, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: dummy) }

        XCTAssertFalse(session.hasUnsavedChanges)
        XCTAssertFalse(session.canUndo)
        XCTAssertFalse(session.canRedo)

        session.addDraftMutation(.addFile(sourceURL: dummy, archivePath: "new.txt"))
        XCTAssertTrue(session.hasUnsavedChanges)
        XCTAssertTrue(session.canUndo)
        XCTAssertFalse(session.canRedo)

        session.addDraftMutation(.deleteEntry(archivePath: "old.txt"))
        XCTAssertEqual(session.pendingMutations.count, 2)

        await session.undo()
        XCTAssertEqual(session.pendingMutations.count, 1)
        XCTAssertTrue(session.canRedo)

        await session.redo()
        XCTAssertEqual(session.pendingMutations.count, 2)
        XCTAssertFalse(session.canRedo)

        // Part 2: NativeZipEngine.applyMutations
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("prozip_e1_e4_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let f1 = tempDir.appendingPathComponent("initial.txt")
        let f2 = tempDir.appendingPathComponent("toDelete.txt")
        try "Content Initial".write(to: f1, atomically: true, encoding: .utf8)
        try "Content Delete".write(to: f2, atomically: true, encoding: .utf8)

        let initialZip = tempDir.appendingPathComponent("initial.zip")
        let engine = NativeZipEngine()

        try await engine.create(
            sources: [f1, f2],
            at: initialZip,
            profile: CreationProfile(purpose: .general, format: .zip),
            password: nil,
            progress: { _ in }
        )

        let newFileOnDisk = tempDir.appendingPathComponent("addedOnDisk.txt")
        try "Brand New File".write(to: newFileOnDisk, atomically: true, encoding: .utf8)

        let updatedZip = tempDir.appendingPathComponent("updated.zip")
        let mutations: [ArchiveMutation] = [
            .addFile(sourceURL: newFileOnDisk, archivePath: "added.txt"),
            .deleteEntry(archivePath: "toDelete.txt"),
            .renameEntry(oldArchivePath: "initial.txt", newArchivePath: "renamed.txt")
        ]

        try await engine.applyMutations(
            mutations,
            to: initialZip,
            outputURL: updatedZip,
            profile: CreationProfile(purpose: .general, format: .zip),
            password: nil,
            progress: { _ in }
        )

        let entries = try await engine.list(updatedZip, password: nil, progress: { _ in })
        let paths = entries.map { $0.path }

        XCTAssertTrue(paths.contains("added.txt"))
        XCTAssertTrue(paths.contains("renamed.txt"))
        XCTAssertFalse(paths.contains("toDelete.txt"))
        XCTAssertFalse(paths.contains("initial.txt"))
    }

    // MARK: - Additional Matrix Tests (C8, C9, C10, E5, F4, Flow & System Integration)

    /// C8 & D3/D4: 7Z Creation, Listing, and Extraction via SevenZipEngine
    func testC8_SevenZipCreationAndExtraction() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("prozip_c8_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let srcFile = tempDir.appendingPathComponent("hello7z.txt")
        try "Hello 7-Zip Open Source ProZip!".write(to: srcFile, atomically: true, encoding: .utf8)

        let archive7z = tempDir.appendingPathComponent("test.7z")
        let engine = SevenZipEngine()
        let profile = CreationProfile(purpose: .windows, format: .sevenZip, strength: .balanced)

        try await engine.create(
            sources: [srcFile],
            at: archive7z,
            profile: profile,
            password: nil,
            progress: { _ in }
        )

        let entries = try await engine.list(archive7z, password: nil, progress: { _ in })
        XCTAssertTrue(entries.contains { $0.name == "hello7z.txt" })

        let outDir = tempDir.appendingPathComponent("extracted")
        let report = try await engine.extract(
            entries,
            from: archive7z,
            to: outDir,
            password: nil,
            options: ExtractionOptions(stripSingleRootFolderIfMatching: false),
            progress: { _ in }
        )
        XCTAssertGreaterThanOrEqual(report.extractedCount, 1)
    }

    /// C9: TAR Creation/Extraction and Single-Stream (.gz) Virtual File via LibarchiveEngine
    func testC9_TarAndSingleStreamVirtualFile() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("prozip_c9_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let srcFile = tempDir.appendingPathComponent("unix_note.txt")
        try "TAR bundle test".write(to: srcFile, atomically: true, encoding: .utf8)

        let tarURL = tempDir.appendingPathComponent("bundle.tar")
        let engine = LibarchiveEngine()
        let profile = CreationProfile(purpose: .unix, format: .tar, strength: .store)

        // Verify TAR locks strength adjustment
        XCTAssertFalse(profile.canAdjustStrength)

        try await engine.create(
            sources: [srcFile],
            at: tarURL,
            profile: profile,
            password: nil,
            progress: { _ in }
        )

        let tarEntries = try await engine.list(tarURL, password: nil, progress: { _ in })
        XCTAssertTrue(tarEntries.contains { $0.name == "unix_note.txt" })

        // Single-stream .gz virtual file check
        let gzURL = tempDir.appendingPathComponent("document.txt.gz")
        let gzProfile = CreationProfile(purpose: .general, format: .gzip, strength: .balanced)
        try await engine.create(
            sources: [srcFile],
            at: gzURL,
            profile: gzProfile,
            password: nil,
            progress: { _ in }
        )

        let gzEntries = try await engine.list(gzURL, password: nil, progress: { _ in })
        XCTAssertEqual(gzEntries.count, 1)
        XCTAssertEqual(gzEntries.first?.name, "document.txt")
    }

    /// C10 & C11: Split Volume Creation and Family Resolution (.001 .. .003)
    func testC10_SplitVolumeCreationAndFamilyResolution() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("prozip_c10_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let srcFile = tempDir.appendingPathComponent("payload.bin")
        let payload = Data((0..<12000).map { UInt8($0 & 0xFF) })
        try payload.write(to: srcFile)

        let targetZip = tempDir.appendingPathComponent("split_test.zip")
        let profile = CreationProfile(
            purpose: .general,
            format: .zip,
            strength: .store,
            split: .byCount(3)
        )

        try await NativeZipEngine().create(
            sources: [srcFile],
            at: targetZip,
            profile: profile,
            password: nil,
            progress: { _ in }
        )

        let part1 = tempDir.appendingPathComponent("split_test.zip.001")
        let part2 = tempDir.appendingPathComponent("split_test.zip.002")
        let part3 = tempDir.appendingPathComponent("split_test.zip.003")

        XCTAssertTrue(FileManager.default.fileExists(atPath: part1.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: part2.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: part3.path))

        // Resolving from part 2 should automatically point to primaryVolumeURL = part 1
        let family = SplitVolumeFamily.resolve(for: part2)
        XCTAssertTrue(family.isSplit)
        XCTAssertTrue(family.isComplete)
        XCTAssertFalse(family.hasEmptyVolume)
        XCTAssertEqual(family.primaryVolumeURL.lastPathComponent, "split_test.zip.001")
        XCTAssertEqual(family.volumeURLs.count, 3)
    }

    /// E5: Concurrent modification detection on source archive before saving
    func testE6_SevenZipMutationsPreserveRequestedArchivePaths() async throws {
        guard SevenZipEngine.resolveBinaryURL() != nil else { throw XCTSkip("7-Zip unavailable") }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("prozip_7z_edit_\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let original = root.appendingPathComponent("original.txt")
        let replacement = root.appendingPathComponent("replacement-source.txt")
        let addition = root.appendingPathComponent("addition-source.txt")
        try Data("original".utf8).write(to: original)
        try Data("replacement".utf8).write(to: replacement)
        try Data("addition".utf8).write(to: addition)
        let archive = root.appendingPathComponent("edited.7z")
        let engine = SevenZipEngine()
        let profile = CreationProfile(purpose: .general, format: .sevenZip)
        try await engine.create(sources: [original], at: archive, profile: profile, password: nil, progress: { _ in })
        try await engine.applyMutations([
            .replaceEntry(archivePath: "original.txt", replacementSourceURL: replacement),
            .addFile(sourceURL: addition, archivePath: "nested/added.txt")
        ], to: archive, outputURL: archive, profile: profile, password: nil, progress: { _ in })
        let entries = try await engine.list(archive, password: nil, progress: { _ in })
        XCTAssertEqual(Set(entries.filter { !$0.isDirectory }.map(\.path)), ["original.txt", "nested/added.txt"])
        for (path, expected) in [("original.txt", "replacement"), ("nested/added.txt", "addition")] {
            guard let entry = entries.first(where: { $0.path == path }) else {
                XCTFail("Missing \(path)")
                continue
            }
            var contents = Data()
            for try await chunk in try await engine.openMember(entry, in: archive, password: nil, range: nil) {
                contents.append(chunk)
            }
            XCTAssertEqual(String(decoding: contents, as: UTF8.self), expected)
        }

        let savedArchive = try Data(contentsOf: archive)
        do {
            try await engine.applyMutations([.addFile(sourceURL: addition, archivePath: "../../escape.txt")],
                to: archive, outputURL: archive, profile: profile, password: nil, progress: { _ in })
            XCTFail("Unsafe archive path must be rejected")
        } catch {
            XCTAssertEqual(try Data(contentsOf: archive), savedArchive)
        }
    }

    func testE5_SourceArchiveConcurrentModificationDetection() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("prozip_e5_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let archiveFile = tempDir.appendingPathComponent("concurrent.zip")
        try Data("initial-bytes".utf8).write(to: archiveFile)

        let session = ArchiveBrowsingSession(
            url: archiveFile,
            descriptor: ArchiveDescriptor(url: archiveFile, format: .zip)
        )
        session.captureSourceStat()
        XCTAssertFalse(session.hasSourceArchiveChangedOnDisk())

        // Simulate external modification changing size/mtime
        try Data("modified-bytes-longer".utf8).write(to: archiveFile)
        XCTAssertTrue(session.hasSourceArchiveChangedOnDisk())
    }

    /// F4: 14-Stage Application Installation Pipeline verification (doc/08 section 5)
    func testF4_14StageApplicationInstallationPipeline() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("prozip_f4_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create a synthetic valid .app bundle
        let appBundle = tempDir.appendingPathComponent("DemoApp.app")
        let contentsDir = appBundle.appendingPathComponent("Contents")
        let macosDir = contentsDir.appendingPathComponent("MacOS")
        try FileManager.default.createDirectory(at: macosDir, withIntermediateDirectories: true)

        let infoPlist: [String: Any] = [
            "CFBundleExecutable": "DemoApp",
            "CFBundleIdentifier": "org.prozip.DemoApp",
            "CFBundleName": "DemoApp",
            "CFBundleVersion": "1.0"
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: infoPlist, format: .xml, options: 0)
        try plistData.write(to: contentsDir.appendingPathComponent("Info.plist"))

        let execURL = macosDir.appendingPathComponent("DemoApp")
        try "#!/bin/sh\necho DemoApp\n".write(to: execURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: execURL.path)

        let installDest = tempDir.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: installDest, withIntermediateDirectories: true)

        final class StageBox: @unchecked Sendable {
            let lock = NSLock()
            var stages: [ApplicationInstallStage] = []
            func append(_ s: ApplicationInstallStage) {
                lock.lock()
                stages.append(s)
                lock.unlock()
            }
        }
        let stageBox = StageBox()

        let installedURL = try await DiskImageEngine().installApplication(
            from: appBundle,
            to: installDest,
            quickInstallRemoveQuarantine: true,
            allowReplace: true,
            stageObserver: { stage in
                stageBox.append(stage)
            }
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: installedURL.path))
        XCTAssertEqual(stageBox.stages.count, 14)
        XCTAssertEqual(stageBox.stages, ApplicationInstallStage.allCases)
    }

    /// Flow: Verify 32 Allowed Open Formats and 8-Step Flow Action Router (doc/09 sections 2-4)
    func testG_FlowActionRoutingAnd32AllowedFormats() {
        // Exact 32 allowed formats
        XCTAssertEqual(AllowedOpenFormat.exact32.count, 32)
        XCTAssertEqual(AllowedOpenFormat.defaultAllowedIDs.count, 32)
        XCTAssertEqual(FlowActionID.allCases.count, 13)

        let zipDesc = ArchiveDescriptor(url: URL(fileURLWithPath: "/tmp/a.zip"), format: .zip)
        let dmgDesc = ArchiveDescriptor(url: URL(fileURLWithPath: "/tmp/a.dmg"), format: .dmg)
        let allowed = AllowedOpenFormat.defaultAllowedIDs

        // 1. No selection -> nil (Flow Bar hides context action and shows default Extract All)
        XCTAssertNil(
            FlowActionRouter.recommendAction(for: [], in: zipDesc, allowedFormats: allowed)
        )

        // 2. Multiple selection -> Extract Selection
        let f1 = ArchiveEntry(path: "a.pdf", type: .file)
        let f2 = ArchiveEntry(path: "b.png", type: .file)
        XCTAssertEqual(
            FlowActionRouter.recommendAction(for: [f1, f2], in: zipDesc, allowedFormats: allowed)?.actionID,
            .extractSelection
        )

        // 3. Directory selected -> Extract Directory
        let dirEntry = ArchiveEntry(path: "docs", type: .directory)
        XCTAssertEqual(
            FlowActionRouter.recommendAction(for: [dirEntry], in: zipDesc, allowedFormats: allowed)?.actionID,
            .extractDirectory
        )

        // 4. .app in DMG vs .app in ZIP
        let appEntry = ArchiveEntry(path: "MyApp.app", type: .directory)
        XCTAssertEqual(
            FlowActionRouter.recommendAction(for: [appEntry], in: dmgDesc, allowedFormats: allowed)?.actionID,
            .openDiskImageApplication
        )
        XCTAssertEqual(
            FlowActionRouter.recommendAction(for: [appEntry], in: zipDesc, allowedFormats: allowed)?.actionID,
            .installApplication
        )

        // 5. Font selected -> Install Font
        let fontEntry = ArchiveEntry(path: "Inter-Bold.ttf", type: .file)
        XCTAssertEqual(
            FlowActionRouter.recommendAction(for: [fontEntry], in: zipDesc, allowedFormats: allowed)?.actionID,
            .installFont
        )

        // 6. .pkg selected -> Install Package
        let pkgEntry = ArchiveEntry(path: "Installer.pkg", type: .file)
        XCTAssertEqual(
            FlowActionRouter.recommendAction(for: [pkgEntry], in: zipDesc, allowedFormats: allowed)?.actionID,
            .installPackage
        )

        // 7. Whitelisted regular file -> Open File
        XCTAssertEqual(
            FlowActionRouter.recommendAction(for: [f1], in: zipDesc, allowedFormats: allowed)?.actionID,
            .openFile
        )

        // 8. Unknown extension -> Unavailable
        let binEntry = ArchiveEntry(path: "firmware.bin", type: .file)
        XCTAssertEqual(
            FlowActionRouter.recommendAction(for: [binEntry], in: zipDesc, allowedFormats: allowed)?.actionID,
            .unavailable
        )
    }

    /// UI Visual Verification: Renders Workspace, Mini, Settings, and Creation Dialog views
    func testUI_RenderScreenshotsOfAllPrimaryViews() async throws {
        let appVM = ProZipAppViewModel.shared
        let sampleURL = URL(fileURLWithPath: "/tmp/sample.zip")
        let desc = ArchiveDescriptor(
            url: sampleURL,
            format: .zip,
            isEncrypted: false,
            totalCompressedSize: 205_824,
            entryCountHint: 4
        )
        let session = ArchiveBrowsingSession(url: sampleURL, descriptor: desc)
        let entries = [
            ArchiveEntry(path: "sub", type: .directory, uncompressedSize: 0, modifiedAt: Date()),
            ArchiveEntry(path: "blob.bin", type: .file, uncompressedSize: 204_800, compressedSize: 198_000, modifiedAt: Date()),
            ArchiveEntry(path: "readme.txt", type: .file, uncompressedSize: 13, compressedSize: 13, modifiedAt: Date())
        ]
        try await session.loadEntries(entries)

        let artifactDir = URL(fileURLWithPath: "/tmp/cu/snapshots")
        try? FileManager.default.createDirectory(at: artifactDir, withIntermediateDirectories: true)

        func saveRendered<V: View>(_ view: V, width: CGFloat, height: CGFloat, filename: String) {
            let root = view
                .environmentObject(appVM)
                .frame(width: width, height: height)
                .background(Color(NSColor.windowBackgroundColor))
                .environment(\.colorScheme, .light)

            let hostingView = NSHostingView(rootView: root)
            hostingView.appearance = NSAppearance(named: .aqua)
            hostingView.frame = NSRect(x: 0, y: 0, width: width, height: height)

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.appearance = NSAppearance(named: .aqua)
            window.contentView = hostingView
            hostingView.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            hostingView.layoutSubtreeIfNeeded()

            if let rep = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) {
                hostingView.cacheDisplay(in: hostingView.bounds, to: rep)
                if let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: artifactDir.appendingPathComponent(filename))
                }
            }
        }

        saveRendered(WorkspaceWindowView(session: session), width: 1040, height: 740, filename: "prozip_workspace.png")
        saveRendered(MiniArchiveView(session: session), width: 560, height: 422, filename: "prozip_mini.png")
        saveRendered(ProZipSettingsView(initialTab: .general), width: 900, height: 712, filename: "prozip_settings_general.png")
        saveRendered(ProZipSettingsView(initialTab: .compression), width: 900, height: 712, filename: "prozip_settings_compression.png")
        saveRendered(ProZipSettingsView(initialTab: .extraction), width: 900, height: 712, filename: "prozip_settings_extraction.png")
        saveRendered(ProZipSettingsView(initialTab: .flow), width: 900, height: 712, filename: "prozip_settings_flow.png")
        saveRendered(ArchiveCreationDialogView(defaultName: "sample", appViewModel: appVM), width: 900, height: 600, filename: "prozip_creation_dialog.png")
        saveRendered(PasswordPromptSheetView(), width: 260, height: 275, filename: "prozip_password_sheet.png")
        saveRendered(TrashConfirmationDialogView(), width: 260, height: 202, filename: "prozip_completion_dialog.png")
        saveRendered(ArchiveProgressWindowView(), width: 380, height: 260, filename: "prozip_progress_panel.png")
        appVM.alertTitle = "无法完成操作"
        appVM.alertMessage = "压缩包包含不安全路径：../evil.txt"
        saveRendered(ProZipAlertDialogView(), width: 260, height: 202, filename: "prozip_alert_dialog.png")
        saveRendered(ConflictResolutionDialogView(), width: 260, height: 325, filename: "prozip_conflict_dialog.png")
        saveRendered(DiskImageLicenseDialogView(), width: 413, height: 305, filename: "prozip_sla_dialog.png")
        appVM.shelfModel.populateDemoStagedItems()
        appVM.shelfModel.isQuickActionsExpanded = true
        saveRendered(MenuBarShelfView(model: appVM.shelfModel), width: 521, height: 497, filename: "prozip_shelf_actions.png")

        appVM.shelfModel.isQuickActionsExpanded = true
        saveRendered(MenuBarShelfView(model: appVM.shelfModel), width: 521, height: 497, filename: "prozip_shelf.png")
        saveRendered(FirstLaunchOnboardingView(), width: 704, height: 582, filename: "prozip_onboarding.png")
        for step in 1...7 {
            saveRendered(FirstLaunchOnboardingView(initialStep: step), width: 704, height: 582, filename: "prozip_onboarding_\(step).png")
        }
        saveRendered(ProZipUIDialogGalleryView(), width: 920, height: 660, filename: "prozip_dialog_gallery.png")

        XCTAssertTrue(FileManager.default.fileExists(atPath: artifactDir.appendingPathComponent("prozip_workspace.png").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifactDir.appendingPathComponent("prozip_mini.png").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifactDir.appendingPathComponent("prozip_settings_compression.png").path))
    }
}

// MARK: - Private Little Endian Byte Helper for Test Binary Construction

private extension FixedWidthInteger {
    var littleEndianBytes: Data {
        var val = self.littleEndian
        return Data(bytes: &val, count: MemoryLayout<Self>.size)
    }
}
