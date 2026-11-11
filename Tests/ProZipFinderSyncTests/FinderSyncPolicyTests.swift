import Foundation
import XCTest
import ProZipShared
import ProZipFinderSync

final class FinderSyncPolicyTests: XCTestCase {
    private func item(_ path: String, directory: Bool = false) -> FinderSelectionItem {
        FinderSelectionItem(url: URL(fileURLWithPath: path, isDirectory: directory), isDirectory: directory)
    }

    func testSingleArchiveOffersOnlyBrowseAndExtraction() {
        for path in ["/fixture/a.zip", "/fixture/a.ZIPX", "/fixture/a.tar.gz", "/fixture/a.7z.001", "/fixture/a.z99", "/fixture/a.r00"] {
            let commands = FinderMenuPolicy.commands(for: [item(path)])
            XCTAssertEqual(commands.map(\.action), [.browseArchive, .extractHere, .extractTo])
            XCTAssertEqual(commands.map(\.title), ["用 ProZip 浏览", "快速解压到当前目录", "快速解压到指定目录…"])
        }
    }

    func testMultipleArchivesOfferCountedExtractionWithoutBrowse() {
        let commands = FinderMenuPolicy.commands(for: [item("/fixture/a.zip"), item("/fixture/b.rar")])
        XCTAssertEqual(commands.map(\.action), [.extractHere, .extractTo])
        XCTAssertEqual(commands.map(\.title), ["将 2 个文件解压到当前目录", "将 2 个文件解压到指定目录…"])
        XCTAssertTrue(commands.allSatisfy { $0.files.count == 2 })
    }

    func testOrdinaryFilesFoldersAndMixedSelectionOfferCompression() {
        let fileCommands = FinderMenuPolicy.commands(for: [item("/fixture/report.pdf")])
        XCTAssertEqual(fileCommands.map(\.action), [.compressConfigured, .compressDefault])
        XCTAssertEqual(fileCommands.map(\.title), ["压缩为…", "快速压缩"])
        let folder = FinderMenuPolicy.commands(for: [item("/fixture/project.zip", directory: true)])
        XCTAssertEqual(folder.map(\.action), [.compressConfigured, .compressDefault])
        XCTAssertEqual(folder.last?.title, "压缩为 \"project.zip\"")
        let mixed = FinderMenuPolicy.commands(for: [item("/fixture/a.zip"), item("/fixture/report.pdf")])
        XCTAssertEqual(mixed.map(\.action), [.compressConfigured, .compressDefault])
        XCTAssertFalse(mixed.contains { $0.action == .sendToProZip })
    }

    func testRequestUsesSharedCodecWithRepeatedEncodedFileURLs() throws {
        let selections = [item("/fixture/中文 #&+%=?.zip"), item("/fixture/second 归档.7z")]
        let commands = FinderMenuPolicy.commands(for: selections)
        let command = try XCTUnwrap(commands.first)
        let url = try command.requestURL()
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "prozip")
        XCTAssertEqual(components.host, "finder-action")
        XCTAssertEqual(components.queryItems?.map(\.name), ["action", "file", "file"])
        let decoded = try FinderActionRequest(url: url)
        XCTAssertEqual(decoded.action, .extractHere)
        XCTAssertEqual(decoded.files, selections.map { $0.url.standardizedFileURL })
        XCTAssertNil(components.fragment)
    }

    func testEmptyInvalidAndOverLimitSelectionsDoNotProduceMenus() {
        XCTAssertTrue(FinderMenuPolicy.commands(for: []).isEmpty)
        for raw in ["https://example.invalid/a.zip", "file://remote.invalid/a.zip", "file:relative.zip", "file:///fixture/a.zip?extra=value"] {
            let selected = FinderSelectionItem(url: URL(string: raw)!, isDirectory: false)
            XCTAssertTrue(FinderMenuPolicy.commands(for: [selected]).isEmpty)
        }
        let many = (0..<1001).map { item("/fixture/\($0).zip") }
        XCTAssertTrue(FinderMenuPolicy.commands(for: many).isEmpty)
        let duplicate = FinderMenuPolicy.commands(for: [item("/fixture/a.zip"), item("/fixture/a.zip")])
        XCTAssertEqual(duplicate.first?.action, .browseArchive)
        XCTAssertEqual(duplicate.first?.files.count, 1)
    }

    func testMonitoringDefaultsToHomeAndOnlyAddsEligibleLocalVolumesWhenEnabled() {
        let home = URL(fileURLWithPath: "/fixture/home", isDirectory: true)
        let usb = URL(fileURLWithPath: "/Volumes/USB", isDirectory: true)
        let card = URL(fileURLWithPath: "/Volumes/Card", isDirectory: true)
        let volumes = [
            FinderMonitoredVolume(url: usb, isInternal: false, isRemovable: false),
            FinderMonitoredVolume(url: card, isInternal: true, isRemovable: true),
            FinderMonitoredVolume(url: URL(fileURLWithPath: "/"), isInternal: true, isRemovable: false),
            FinderMonitoredVolume(url: URL(fileURLWithPath: "/Volumes/Network"), isInternal: false, isRemovable: false, isLocal: false),
            FinderMonitoredVolume(url: URL(fileURLWithPath: "/Volumes/Hidden"), isInternal: false, isRemovable: true, isBrowsable: false)
        ]
        XCTAssertEqual(FinderMonitoringPolicy.directories(home: home, externalVolumesEnabled: false, volumes: volumes), [home])
        XCTAssertEqual(FinderMonitoringPolicy.directories(home: home, externalVolumesEnabled: true, volumes: volumes), [home, usb, card])
        XCTAssertEqual(FinderMonitoringPolicy.applicationID, "org.prozip.ProZip")
        XCTAssertEqual(FinderMonitoringPolicy.externalVolumesKey, "finder.monitorsExternalVolumes.v1")
        XCTAssertEqual(FinderMonitoringPolicy.preferencesChanged.rawValue, "org.prozip.ProZip.finderPreferencesChanged")
    }

    func testBundleMetadataAndEntitlementsHaveOnlyTheRequiredCapabilities() throws {
        let project = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        func plist(_ path: String) throws -> [String: Any] {
            let data = try Data(contentsOf: project.appendingPathComponent(path))
            return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        }
        let info = try plist("Resources/Extensions/FinderSync-Info.plist")
        XCTAssertEqual(info["CFBundleIdentifier"] as? String, "org.prozip.ProZip.FinderSync")
        XCTAssertEqual(info["CFBundleExecutable"] as? String, "ProZipFinderSync")
        XCTAssertEqual(info["CFBundlePackageType"] as? String, "XPC!")
        let extensionInfo = try XCTUnwrap(info["NSExtension"] as? [String: Any])
        XCTAssertEqual(extensionInfo["NSExtensionPointIdentifier"] as? String, "com.apple.FinderSync")
        XCTAssertEqual(extensionInfo["NSExtensionPrincipalClass"] as? String, "ProZipFinderSync.FinderSync")
        let entitlements = try plist("Resources/Extensions/FinderSync.entitlements")
        XCTAssertEqual(Set(entitlements.keys), ["com.apple.security.app-sandbox", "com.apple.security.files.user-selected.read-only", "com.apple.security.temporary-exception.shared-preference.read-only"])
        XCTAssertEqual(entitlements["com.apple.security.app-sandbox"] as? Bool, true)
        XCTAssertEqual(entitlements["com.apple.security.files.user-selected.read-only"] as? Bool, true)
        XCTAssertEqual(entitlements["com.apple.security.temporary-exception.shared-preference.read-only"] as? [String], ["org.prozip.ProZip"])
    }
}
