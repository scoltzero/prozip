import Foundation
import XCTest
import ProZipShared

final class SettingsLanguageTests: XCTestCase {
    private func isolatedDefaults(language: String = "system") -> (UserDefaults, String) {
        let name = "ProZip.SettingsLanguageTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.set(language, forKey: "localization.preferredLanguage.v1")
        return (defaults, name)
    }

    private func resourceBundle() throws -> Bundle {
        let project = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try XCTUnwrap(Bundle(url: project.appendingPathComponent("Resources", isDirectory: true)))
    }

    func testLanguageChangePersistsAndRestoringLaunchSelectionClearsRestartRequirement() {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = ProZipPreferences(defaults: defaults)
        XCTAssertEqual(preferences.languageAtLaunch, "system")
        XCTAssertFalse(preferences.isLanguageRestartRequired)

        preferences.preferredLanguage = "en"
        XCTAssertTrue(preferences.isLanguageRestartRequired)
        XCTAssertEqual(defaults.string(forKey: "localization.preferredLanguage.v1"), "en")
        XCTAssertEqual(defaults.stringArray(forKey: "AppleLanguages"), ["en"])

        preferences.preferredLanguage = "system"
        XCTAssertFalse(preferences.isLanguageRestartRequired)
        XCTAssertNil(defaults.persistentDomain(forName: name)?["AppleLanguages"])
    }

    func testRestartActionOnlyPostsARequestWhileALanguageChangeIsPending() {
        let (defaults, name) = isolatedDefaults(language: "zh-Hans")
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = ProZipPreferences(defaults: defaults)
        let center = NotificationCenter()
        let request = expectation(description: "One restart request")
        request.assertForOverFulfill = true
        let token = center.addObserver(forName: .proZipRestartRequested, object: nil, queue: nil) { notification in
            XCTAssertTrue(notification.object as? ProZipPreferences === preferences)
            request.fulfill()
        }
        defer { center.removeObserver(token) }

        preferences.requestLanguageRestart(notificationCenter: center)
        preferences.preferredLanguage = "en"
        preferences.requestLanguageRestart(notificationCenter: center)
        preferences.preferredLanguage = "zh-Hans"
        preferences.requestLanguageRestart(notificationCenter: center)
        wait(for: [request], timeout: 0.1)
    }

    func testEnglishSettingsUseBundledTranslationsUntilTheNextLaunch() throws {
        let (defaults, name) = isolatedDefaults(language: "en")
        defer { defaults.removePersistentDomain(forName: name) }
        let bundle = try resourceBundle()
        let preferences = ProZipPreferences(defaults: defaults, resourceBundle: bundle)
        let navigation = [
            "通用": "General", "压缩": "Compress", "解压": "Extract", "密码本": "Password Book",
            "ProZip 文件盒": "ProZip Box", "格式关联": "Format Associations", "高级": "Advanced", "关于": "About"
        ]
        for (key, value) in navigation { XCTAssertEqual(preferences.localizedString(key), value, key) }
        XCTAssertEqual(preferences.localizedString("应用语言"), "App language")
        XCTAssertEqual(preferences.localizedString("开机自动启动 ProZip"), "Launch ProZip at login")
        XCTAssertEqual(preferences.localizedString("重新启动 ProZip"), "Restart ProZip")
        XCTAssertEqual(preferences.localizedString("全部可用（%ld）", 12), "All available (12)")

        preferences.preferredLanguage = "zh-Hans"
        XCTAssertTrue(preferences.isLanguageRestartRequired)
        XCTAssertEqual(preferences.localizedString("通用"), "General")
        let relaunched = ProZipPreferences(defaults: defaults, resourceBundle: bundle)
        XCTAssertFalse(relaunched.isLanguageRestartRequired)
        XCTAssertEqual(relaunched.localizedString("通用"), "通用")
    }

    func testTraditionalSettingsAndAllLanguageTablesRemainReadable() throws {
        let (defaults, name) = isolatedDefaults(language: "zh-Hant")
        defer { defaults.removePersistentDomain(forName: name) }
        let bundle = try resourceBundle()
        let preferences = ProZipPreferences(defaults: defaults, resourceBundle: bundle)
        XCTAssertEqual(preferences.localizedString("应用语言"), "應用程式語言")
        XCTAssertEqual(preferences.localizedString("重新启动 ProZip"), "重新啟動 ProZip")
        for language in ["en", "zh-Hans", "zh-Hant"] {
            let path = try XCTUnwrap(bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: language))
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let table = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
            XCTAssertNotNil(table["跟随系统语言，或为 ProZip 单独指定语言。"])
            XCTAssertNotNil(table["重新启动 ProZip 后，语言设置将生效。请先保存修改。"])
        }
    }
}
