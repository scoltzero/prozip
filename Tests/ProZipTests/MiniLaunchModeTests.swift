import Foundation
import XCTest
import ProZipShared
@testable import ProZipUI

@MainActor
final class MiniLaunchModeTests: XCTestCase {
    func testOnlyExternalOpeningHonorsTheMiniPreference() async throws {
        let preferences = ProZipPreferences.shared
        let original = preferences.prefersMiniWindow
        let recent = preferences.recentArchives
        let vm = makeTestAppViewModel()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("prozip-mini-launch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            vm.cancelBackgroundWork()
            preferences.prefersMiniWindow = original
            preferences.recentArchives = recent
            try? FileManager.default.removeItem(at: directory)
        }
        let emptyZIP = Data([0x50, 0x4b, 0x05, 0x06] + Array(repeating: UInt8(0), count: 18))
        let files = ["menu.zip", "finder.zip", "full.zip"].map { directory.appendingPathComponent($0) }
        for file in files { try emptyZIP.write(to: file) }
        preferences.prefersMiniWindow = true
        let menu = vm.openArchive(at: files[0])
        XCTAssertFalse(menu.isMiniMode)
        let finder = vm.openArchive(at: files[1], honorMiniPreference: true)
        XCTAssertTrue(finder.isMiniMode)
        let reopened = vm.openArchive(at: files[0], honorMiniPreference: true)
        XCTAssertTrue(reopened === menu)
        XCTAssertFalse(reopened.isMiniMode, "An existing window keeps its current presentation")
        preferences.prefersMiniWindow = false
        let full = try await vm.importFiles([files[2]], honorMiniPreference: true)
        XCTAssertFalse(try XCTUnwrap(full.first).isMiniMode)
    }
}
