import Foundation
import XCTest
@testable import ProZipCore

final class AppUpdateServiceTests: XCTestCase {
    func testParseSHA256SumsMatchesFilenameAndBinaryMarker() {
        let content = """
        1bd6a9a8fcf2901461ac6f7fb46a99b846eb41926601b5eefeb64a9151d0d78f  ProZip-v0.1.4-macos.dmg
        32490d71ea41f5759573543f68ca83d111efd2f2f337d816403d8741a4b2d7b0 *ProZip-v0.1.4-macos.zip
        """

        XCTAssertEqual(
            AppUpdateService.parseSHA256Sums(content, filename: "ProZip-v0.1.4-macos.zip"),
            "32490d71ea41f5759573543f68ca83d111efd2f2f337d816403d8741a4b2d7b0"
        )
        XCTAssertEqual(
            AppUpdateService.parseSHA256Sums(content, filename: "ProZip-v0.1.4-macos.dmg"),
            "1bd6a9a8fcf2901461ac6f7fb46a99b846eb41926601b5eefeb64a9151d0d78f"
        )
        XCTAssertNil(AppUpdateService.parseSHA256Sums(content, filename: "missing.zip"))
    }

    func testSHA256HexMatchesKnownDigest() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("prozip-sha-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try Data("abc".utf8).write(to: tmp)

        let digest = try AppUpdateService.sha256Hex(of: tmp)
        XCTAssertEqual(digest, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testExtractStagedAppValidatesBundleIdentifier() throws {
        let fm = FileManager.default
        let workDir = fm.temporaryDirectory.appendingPathComponent("prozip-stage-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: workDir) }

        let fakeApp = workDir.appendingPathComponent("src/ProZip.app/Contents", isDirectory: true)
        try fm.createDirectory(at: fakeApp, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.prozip.app",
            "CFBundleShortVersionString": "0.1.5"
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try plistData.write(to: fakeApp.appendingPathComponent("Info.plist"))

        let zipURL = workDir.appendingPathComponent("ProZip-v0.1.5-macos.zip")
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-ck", "--keepParent", workDir.appendingPathComponent("src/ProZip.app").path, zipURL.path]
        try ditto.run()
        ditto.waitUntilExit()
        XCTAssertEqual(ditto.terminationStatus, 0)

        let extractDir = workDir.appendingPathComponent("out", isDirectory: true)
        let staged = try AppUpdateService.extractStagedApp(
            from: zipURL,
            into: extractDir,
            expectedBundleIdentifier: "com.prozip.app"
        )
        XCTAssertEqual(staged.lastPathComponent, "ProZip.app")

        let mismatchDir = workDir.appendingPathComponent("out-mismatch", isDirectory: true)
        XCTAssertThrowsError(
            try AppUpdateService.extractStagedApp(
                from: zipURL,
                into: mismatchDir,
                expectedBundleIdentifier: "com.other.app"
            )
        )
    }

    func testInstallRejectsNonAppBundleTarget() {
        let fakeStaged = URL(fileURLWithPath: "/tmp/staged/ProZip.app")
        let nonAppTarget = URL(fileURLWithPath: "/tmp/ProZip")
        XCTAssertThrowsError(
            try AppUpdateService.shared.installStagedUpdateAndRelaunch(
                stagedAppURL: fakeStaged,
                targetAppURL: nonAppTarget
            )
        )
    }
}
