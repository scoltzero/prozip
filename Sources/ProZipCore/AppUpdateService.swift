import Foundation

/// Release information returned from the public GitHub Releases API.
public struct GitHubReleaseInfo: Codable, Sendable, Equatable {
    public let tagName: String
    public let name: String?
    public let body: String?
    public let htmlUrl: String
    public let publishedAt: String?
    public let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlUrl = "html_url"
        case publishedAt = "published_at"
        case assets
    }

    public init(
        tagName: String,
        name: String? = nil,
        body: String? = nil,
        htmlUrl: String,
        publishedAt: String? = nil,
        assets: [GitHubReleaseAsset] = []
    ) {
        self.tagName = tagName
        self.name = name
        self.body = body
        self.htmlUrl = htmlUrl
        self.publishedAt = publishedAt
        self.assets = assets
    }
}

public struct GitHubReleaseAsset: Codable, Sendable, Equatable {
    public let name: String
    public let browserDownloadUrl: String
    public let size: Int64

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
        case size
    }

    public init(name: String, browserDownloadUrl: String, size: Int64) {
        self.name = name
        self.browserDownloadUrl = browserDownloadUrl
        self.size = size
    }
}

public struct UpdateCheckResult: Sendable, Equatable {
    public let hasUpdate: Bool
    public let currentVersion: String
    public let latestVersion: String
    public let release: GitHubReleaseInfo
    public let preferredDownloadURL: URL?

    public init(
        hasUpdate: Bool,
        currentVersion: String,
        latestVersion: String,
        release: GitHubReleaseInfo,
        preferredDownloadURL: URL? = nil
    ) {
        self.hasUpdate = hasUpdate
        self.currentVersion = currentVersion
        self.latestVersion = latestVersion
        self.release = release
        self.preferredDownloadURL = preferredDownloadURL
    }
}

/// Service dedicated to checking software updates from GitHub Releases.
public final class AppUpdateService: Sendable {
    public static let shared = AppUpdateService()

    public static let defaultRepository = "scoltzero/prozip"
    public static let lastCheckTimestampKey = "updates.lastCheckTimestamp.v1"
    public static let autoCheckUpdatesKey = "updates.autoCheck.v1"

    private let session: URLSession

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 12
            config.timeoutIntervalForResource = 20
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: config)
        }
    }

    /// Fetches the latest published release and compares it with the currently installed application version.
    public func checkForUpdates(
        repository: String = defaultRepository,
        currentVersion: String? = nil
    ) async throws -> UpdateCheckResult {
        let appVersion = currentVersion ?? (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.1.3"
        let endpoint = "https://api.github.com/repos/\(repository)/releases/latest"
        guard let url = URL(string: endpoint) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("ProZip-macOS/\(appVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 404 {
                throw NSError(domain: "ProZipUpdate", code: 404, userInfo: [
                    NSLocalizedDescriptionKey: "暂无公开发布的 Release 版本。"
                ])
            }
            if httpResponse.statusCode == 403 {
                throw NSError(domain: "ProZipUpdate", code: 403, userInfo: [
                    NSLocalizedDescriptionKey: "已达到 GitHub API 访问频率限制，请稍后再试。"
                ])
            }
            throw NSError(domain: "ProZipUpdate", code: httpResponse.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "检查更新失败，服务器返回 HTTP \(httpResponse.statusCode)"
            ])
        }

        let decoder = JSONDecoder()
        let release = try decoder.decode(GitHubReleaseInfo.self, from: data)

        // Record check timestamp
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckTimestampKey)

        let latestTag = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        let currentTrimmed = appVersion.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))

        let comparison = Self.compareSemVer(currentTrimmed, latestTag)
        let isNewer = comparison == .orderedAscending

        // Locate DMG or fallback asset
        var downloadURL: URL?
        if let dmgAsset = release.assets.first(where: { $0.name.hasSuffix(".dmg") }) {
            downloadURL = URL(string: dmgAsset.browserDownloadUrl)
        } else if let zipAsset = release.assets.first(where: { $0.name.hasSuffix(".zip") }) {
            downloadURL = URL(string: zipAsset.browserDownloadUrl)
        } else {
            downloadURL = URL(string: release.htmlUrl)
        }

        return UpdateCheckResult(
            hasUpdate: isNewer,
            currentVersion: appVersion,
            latestVersion: release.tagName,
            release: release,
            preferredDownloadURL: downloadURL
        )
    }

    /// Compares two SemVer strings (e.g. "0.1.0" and "0.2.0").
    public static func compareSemVer(_ v1: String, _ v2: String) -> ComparisonResult {
        let clean1 = v1.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        let clean2 = v2.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))

        let parts1 = clean1.split(separator: "-").first?.split(separator: ".").compactMap { Int($0) } ?? []
        let parts2 = clean2.split(separator: "-").first?.split(separator: ".").compactMap { Int($0) } ?? []

        let maxCount = max(parts1.count, parts2.count)
        for i in 0..<maxCount {
            let p1 = i < parts1.count ? parts1[i] : 0
            let p2 = i < parts2.count ? parts2[i] : 0
            if p1 < p2 { return .orderedAscending }
            if p1 > p2 { return .orderedDescending }
        }
        return .orderedSame
    }

    /// Last check date recorded in UserDefaults.
    public static var lastCheckDate: Date? {
        let ts = UserDefaults.standard.double(forKey: lastCheckTimestampKey)
        guard ts > 0 else { return nil }
        return Date(timeIntervalSince1970: ts)
    }

    /// Whether automatic updates check is enabled.
    public static var isAutoCheckEnabled: Bool {
        if UserDefaults.standard.object(forKey: autoCheckUpdatesKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: autoCheckUpdatesKey)
    }
}
