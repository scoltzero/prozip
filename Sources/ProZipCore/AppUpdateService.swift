import CryptoKit
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
        let appVersion = currentVersion ?? (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.1.5"
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

    // MARK: - In-App Download, Verification & Self-Update

    /// Returns the `.zip` archive asset suitable for in-app replacement, if present in the release.
    public static func zipAsset(in release: GitHubReleaseInfo) -> GitHubReleaseAsset? {
        release.assets.first(where: { $0.name.lowercased().hasSuffix(".zip") })
    }

    /// Parses a `SHA256SUMS.txt` file and returns the lowercase hex digest matching `filename`.
    public static func parseSHA256Sums(_ text: String, filename: String) -> String? {
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let parts = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard parts.count == 2 else { continue }
            let hash = String(parts[0]).lowercased()
            let name = String(parts[1]).trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "*"))
            if name == filename || URL(fileURLWithPath: name).lastPathComponent == filename {
                return hash
            }
        }
        return nil
    }

    /// Streams a file from disk and returns its lowercase SHA-256 hex digest.
    public static func sha256Hex(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let chunk = handle.readData(ofLength: 256 * 1024)
            if chunk.isEmpty { return false }
            hasher.update(data: chunk)
            return true
        }) {}
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Extracts a downloaded `.zip` release into `stagingDir` via `/usr/bin/ditto` and validates the `.app` bundle.
    public static func extractStagedApp(
        from zipURL: URL,
        into stagingDir: URL,
        expectedBundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)

        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-xk", zipURL.path, stagingDir.path]
        let stderrPipe = Pipe()
        ditto.standardError = stderrPipe
        try ditto.run()
        ditto.waitUntilExit()

        guard ditto.terminationStatus == 0 else {
            let errText = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw NSError(domain: "ProZipUpdate", code: Int(ditto.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: errText.isEmpty ? "解压更新包失败。" : "解压更新包失败：\(errText)"
            ])
        }

        let entries = try fm.contentsOfDirectory(at: stagingDir, includingPropertiesForKeys: nil)
        guard let appURL = entries.first(where: { $0.lastPathComponent == "ProZip.app" })
            ?? entries.first(where: { $0.pathExtension == "app" }) else {
            throw NSError(domain: "ProZipUpdate", code: 2001, userInfo: [
                NSLocalizedDescriptionKey: "更新包中未找到 ProZip.app。"
            ])
        }

        let infoPlistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard fm.fileExists(atPath: infoPlistURL.path),
              let plistData = try? Data(contentsOf: infoPlistURL),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
              let bundleID = plist["CFBundleIdentifier"] as? String else {
            throw NSError(domain: "ProZipUpdate", code: 2002, userInfo: [
                NSLocalizedDescriptionKey: "更新包中的应用信息不完整，已中止安装。"
            ])
        }

        if let expected = expectedBundleIdentifier, !expected.isEmpty, bundleID != expected {
            throw NSError(domain: "ProZipUpdate", code: 2003, userInfo: [
                NSLocalizedDescriptionKey: "更新包应用标识不匹配（\(bundleID)），已中止安装。"
            ])
        }

        return appURL
    }

    /// Downloads the release `.zip`, verifies `SHA256SUMS.txt` when present, and extracts `ProZip.app` into a temp staging directory.
    public func downloadAndStageUpdate(
        release: GitHubReleaseInfo,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        guard let zipAsset = Self.zipAsset(in: release),
              let zipURL = URL(string: zipAsset.browserDownloadUrl) else {
            throw NSError(domain: "ProZipUpdate", code: 2000, userInfo: [
                NSLocalizedDescriptionKey: "该版本未提供可用于应用内更新的 .zip 安装包。"
            ])
        }

        let stagingRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProZipUpdate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingRoot, withIntermediateDirectories: true)

        do {
            let downloadedZip = stagingRoot.appendingPathComponent(zipAsset.name)
            try await downloadFile(from: zipURL, to: downloadedZip, expectedBytes: zipAsset.size, onProgress: onProgress)

            if let sumsAsset = release.assets.first(where: { $0.name == "SHA256SUMS.txt" }),
               let sumsURL = URL(string: sumsAsset.browserDownloadUrl) {
                let (sumsData, sumsResp) = try await session.data(from: sumsURL)
                if let http = sumsResp as? HTTPURLResponse, http.statusCode == 200,
                   let sumsText = String(data: sumsData, encoding: .utf8),
                   let expectedHash = Self.parseSHA256Sums(sumsText, filename: zipAsset.name) {
                    let actualHash = try Self.sha256Hex(of: downloadedZip)
                    guard actualHash == expectedHash else {
                        throw NSError(domain: "ProZipUpdate", code: 2004, userInfo: [
                            NSLocalizedDescriptionKey: "安装包 SHA-256 校验失败，请重试。"
                        ])
                    }
                }
            }

            let extractDir = stagingRoot.appendingPathComponent("extracted", isDirectory: true)
            let stagedApp = try Self.extractStagedApp(from: downloadedZip, into: extractDir)
            try? FileManager.default.removeItem(at: downloadedZip)
            return stagedApp
        } catch {
            try? FileManager.default.removeItem(at: stagingRoot)
            throw error
        }
    }

    /// Launches a detached helper that waits for the current process to exit, atomically swaps the `.app` bundle, and relaunches ProZip.
    public func installStagedUpdateAndRelaunch(
        stagedAppURL: URL,
        targetAppURL: URL = Bundle.main.bundleURL,
        currentPID: Int32 = ProcessInfo.processInfo.processIdentifier
    ) throws {
        guard targetAppURL.pathExtension == "app" else {
            throw NSError(domain: "ProZipUpdate", code: 2005, userInfo: [
                NSLocalizedDescriptionKey: "当前不是从 .app 应用包运行，无法自动替换安装。"
            ])
        }

        let stagingRoot = stagedAppURL.deletingLastPathComponent().deletingLastPathComponent()
        let parentDir = targetAppURL.deletingLastPathComponent()
        let backupURL = parentDir.appendingPathComponent(".\(targetAppURL.lastPathComponent).backup-\(currentPID)")

        let qStaged = Self.shellQuote(stagedAppURL.path)
        let qTarget = Self.shellQuote(targetAppURL.path)
        let qBackup = Self.shellQuote(backupURL.path)
        let qStagingRoot = Self.shellQuote(stagingRoot.path)

        let swapCommands = [
            "/usr/bin/xattr -dr com.apple.quarantine \(qStaged) 2>/dev/null || true",
            "/bin/rm -rf \(qBackup)",
            "/bin/mv \(qTarget) \(qBackup)",
            "if /bin/mv \(qStaged) \(qTarget); then /bin/rm -rf \(qBackup) \(qStagingRoot); else /bin/mv \(qBackup) \(qTarget) 2>/dev/null || true; exit 1; fi"
        ].joined(separator: "; ")

        let script: String
        if FileManager.default.isWritableFile(atPath: parentDir.path) {
            script = """
            for _ in $(/usr/bin/seq 1 50); do
                /bin/kill -0 \(currentPID) 2>/dev/null || break
                /bin/sleep 0.2
            done
            \(swapCommands)
            /usr/bin/open \(qTarget)
            """
        } else {
            let escapedForAppleScript = swapCommands
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            script = """
            for _ in $(/usr/bin/seq 1 50); do
                /bin/kill -0 \(currentPID) 2>/dev/null || break
                /bin/sleep 0.2
            done
            /usr/bin/osascript -e 'do shell script "\(escapedForAppleScript)" with administrator privileges' && /usr/bin/open \(qTarget)
            """
        }

        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = ["-c", script]
        helper.standardInput = FileHandle.nullDevice
        helper.standardOutput = FileHandle.nullDevice
        helper.standardError = FileHandle.nullDevice
        try helper.run()
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func downloadFile(
        from url: URL,
        to destinationURL: URL,
        expectedBytes: Int64,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let delegate = UpdateDownloadDelegate(
            destinationURL: destinationURL,
            expectedBytes: expectedBytes,
            onProgress: onProgress
        )
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 600
        let downloadSession = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        let task = downloadSession.downloadTask(with: url)

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                delegate.start(task: task, continuation: continuation, session: downloadSession)
            }
        } onCancel: {
            task.cancel()
            downloadSession.invalidateAndCancel()
        }
    }
}

private final class UpdateDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destinationURL: URL
    private let expectedBytes: Int64
    private let onProgress: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var session: URLSession?
    private var finished = false

    init(destinationURL: URL, expectedBytes: Int64, onProgress: @escaping @Sendable (Double) -> Void) {
        self.destinationURL = destinationURL
        self.expectedBytes = expectedBytes
        self.onProgress = onProgress
    }

    func start(task: URLSessionDownloadTask, continuation: CheckedContinuation<Void, Error>, session: URLSession) {
        lock.lock()
        self.continuation = continuation
        self.session = session
        lock.unlock()
        task.resume()
    }

    private func complete(with result: Result<Void, Error>) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let cont = continuation
        let sess = session
        continuation = nil
        session = nil
        lock.unlock()

        sess?.finishTasksAndInvalidate()
        switch result {
        case .success:
            cont?.resume()
        case .failure(let error):
            cont?.resume(throwing: error)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let denom = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedBytes
        guard denom > 0 else { return }
        let ratio = min(max(Double(totalBytesWritten) / Double(denom), 0), 1)
        onProgress(ratio)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            complete(with: .failure(NSError(domain: "ProZipUpdate", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "下载更新失败，服务器返回 HTTP \(http.statusCode)。"
            ])))
            return
        }
        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: location, to: destinationURL)
            onProgress(1.0)
            complete(with: .success(()))
        } catch {
            complete(with: .failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            complete(with: .failure(error))
        }
    }
}
