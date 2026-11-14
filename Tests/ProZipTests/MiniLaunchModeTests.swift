import AppKit
import Foundation
import SwiftUI
import XCTest
import ProZipShared
@testable import ProZipCore
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

    func testMiniArchiveViewSubtitleIncludesArchiveFileSize() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("prozip-mini-size-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archiveURL = directory.appendingPathComponent("sample.zip")
        let payload = Data([0x50, 0x4b, 0x05, 0x06] + Array(repeating: UInt8(0), count: 2048))
        try payload.write(to: archiveURL)

        let session = ArchiveBrowsingSession(archiveURL: archiveURL, isMiniMode: true)
        let stat = try XCTUnwrap(session.initialSourceStat)
        XCTAssertEqual(stat.size, Int64(payload.count))
        let formatted = ByteCountFormatter.string(fromByteCount: stat.size, countStyle: .file)
        XCTAssertFalse(formatted.isEmpty)

        let view = MiniArchiveView(session: session)
        let hosting = NSHostingView(rootView: view.environmentObject(makeTestAppViewModel()))
        hosting.frame = NSRect(x: 0, y: 0, width: 560, height: 422)
        hosting.layoutSubtreeIfNeeded()
        XCTAssertEqual(hosting.fittingSize.width, 560)
    }

    func testForceMiniModeOpensMiniEvenWhenPreferenceIsFalse() throws {
        let preferences = ProZipPreferences.shared
        let original = preferences.prefersMiniWindow
        let recent = preferences.recentArchives
        let vm = makeTestAppViewModel()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("prozip-mini-force-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            vm.cancelBackgroundWork()
            preferences.prefersMiniWindow = original
            preferences.recentArchives = recent
            try? FileManager.default.removeItem(at: directory)
        }
        let zipURL = directory.appendingPathComponent("spacebar.zip")
        try Data([0x50, 0x4b, 0x05, 0x06] + Array(repeating: UInt8(0), count: 18)).write(to: zipURL)

        preferences.prefersMiniWindow = false
        let workspaceFirst = vm.openArchive(at: zipURL, honorMiniPreference: true)
        XCTAssertFalse(workspaceFirst.isMiniMode)

        let forcedMini = vm.openArchive(at: zipURL, forceMiniMode: true)
        XCTAssertTrue(forcedMini === workspaceFirst)
        XCTAssertTrue(forcedMini.isMiniMode)
    }

    func testFinderSpacebarArchivePolicyRespectsClaimedAndSupportedScopes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("prozip-spacebar-policy-\(UUID().uuidString)")
        let folder = directory.appendingPathComponent("Folder.zip")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let zipURL = directory.appendingPathComponent("claimed.zip")
        let rarURL = directory.appendingPathComponent("unclaimed.rar")
        let pngURL = directory.appendingPathComponent("image.png")
        let missingURL = directory.appendingPathComponent("missing.zip")
        try Data([0x50, 0x4b, 0x05, 0x06]).write(to: zipURL)
        try Data("Rar!".utf8).write(to: rarURL)
        try Data([0x89, 0x50, 0x4e, 0x47]).write(to: pngURL)

        struct MockAssociations: FileAssociationSystem {
            var applicationBundleID: String? = "org.prozip.ProZip"
            var isPackagedApplication: Bool = true
            func contentType(forExtension ext: String) -> String? { "mock.\(ext)" }
            func defaultHandler(forContentType type: String) -> String? {
                type == "mock.zip" ? "org.prozip.ProZip" : "com.other.app"
            }
            func setDefaultHandler(_ identifier: String, forContentType type: String) throws {}
        }

        let mock = MockAssociations()
        XCTAssertFalse(FinderSpacebarArchivePolicy.isCandidateArchive(
            url: folder,
            scope: .allSupported,
            cachedAssociatedExtensions: ["zip"],
            bundleIdentifier: "org.prozip.ProZip",
            fileAssociationSystem: mock
        ))
        XCTAssertFalse(FinderSpacebarArchivePolicy.isCandidateArchive(
            url: missingURL,
            scope: .allSupported,
            cachedAssociatedExtensions: ["zip"],
            bundleIdentifier: "org.prozip.ProZip",
            fileAssociationSystem: mock
        ))
        XCTAssertFalse(FinderSpacebarArchivePolicy.isCandidateArchive(
            url: pngURL,
            scope: .allSupported,
            cachedAssociatedExtensions: ["zip", "png"],
            bundleIdentifier: "org.prozip.ProZip",
            fileAssociationSystem: mock
        ))
        XCTAssertTrue(FinderSpacebarArchivePolicy.isCandidateArchive(
            url: zipURL,
            scope: .claimedOnly,
            cachedAssociatedExtensions: [],
            bundleIdentifier: "org.prozip.ProZip",
            fileAssociationSystem: mock
        ))
        XCTAssertFalse(FinderSpacebarArchivePolicy.isCandidateArchive(
            url: rarURL,
            scope: .claimedOnly,
            cachedAssociatedExtensions: ["zip"],
            bundleIdentifier: "org.prozip.ProZip",
            fileAssociationSystem: mock
        ))
        XCTAssertTrue(FinderSpacebarArchivePolicy.isCandidateArchive(
            url: rarURL,
            scope: .claimedOnly,
            cachedAssociatedExtensions: ["rar"],
            bundleIdentifier: "org.prozip.ProZip",
            fileAssociationSystem: mock
        ))
        XCTAssertTrue(FinderSpacebarArchivePolicy.isCandidateArchive(
            url: rarURL,
            scope: .allSupported,
            cachedAssociatedExtensions: [],
            bundleIdentifier: "org.prozip.ProZip",
            fileAssociationSystem: mock
        ))
    }

    func testFinderSpacebarTextInputRoleFiltering() {
        XCTAssertTrue(FinderSpacebarArchivePolicy.isTextInputOrControlRole(kAXTextFieldRole as String, subrole: nil))
        XCTAssertTrue(FinderSpacebarArchivePolicy.isTextInputOrControlRole("AXSearchField", subrole: nil))
        XCTAssertTrue(FinderSpacebarArchivePolicy.isTextInputOrControlRole(kAXMenuItemRole as String, subrole: nil))
        XCTAssertTrue(FinderSpacebarArchivePolicy.isTextInputOrControlRole("AXUnknown", subrole: "AXSearchField"))
        XCTAssertFalse(FinderSpacebarArchivePolicy.isTextInputOrControlRole(kAXRowRole as String, subrole: nil))
        XCTAssertFalse(FinderSpacebarArchivePolicy.isTextInputOrControlRole(kAXGroupRole as String, subrole: nil))
    }
}
