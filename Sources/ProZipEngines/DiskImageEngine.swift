import Foundation
import Darwin
import CoreText
import ProZipShared
import ProZipCore

// MARK: - Disk Image Data Models (doc/08-磁盘映像与安装.md)

public struct DiskImageIconPosition: Codable, Hashable, Sendable {
    public let fileName: String
    public let x: Double
    public let y: Double

    public init(fileName: String, x: Double, y: Double) {
        self.fileName = fileName
        self.x = x
        self.y = y
    }
}

public struct MountedDiskImage: Sendable {
    public let mountPoint: URL
    public let devicePath: String
    public let volumeName: String
    public let hasSLA: Bool
    public let slaText: String?
    public let iconPositions: [DiskImageIconPosition]
    public let backgroundImageURL: URL?
    public let applicationsShortcutURL: URL?

    public init(
        mountPoint: URL,
        devicePath: String,
        volumeName: String,
        hasSLA: Bool = false,
        slaText: String? = nil,
        iconPositions: [DiskImageIconPosition] = [],
        backgroundImageURL: URL? = nil,
        applicationsShortcutURL: URL? = nil
    ) {
        self.mountPoint = mountPoint
        self.devicePath = devicePath
        self.volumeName = volumeName
        self.hasSLA = hasSLA
        self.slaText = slaText
        self.iconPositions = iconPositions
        self.backgroundImageURL = backgroundImageURL
        self.applicationsShortcutURL = applicationsShortcutURL
    }
}

// MARK: - 14-Stage Application Installation Pipeline (doc/08 section 5)

public enum ApplicationInstallStage: String, CaseIterable, Sendable {
    case prepareStage = "prepare-stage"                     // 准备临时目录
    case extractApplication = "extract-application"         // 解压应用
    case validateApplication = "validate-application"       // 验证应用包
    case prepareDestination = "prepare-destination"         // 准备安装目录
    case preparePublication = "prepare-publication"         // 准备发布记录
    case readQuarantine = "read-quarantine"                 // 读取来源隔离属性
    case writeQuarantine = "write-quarantine"               // 写入应用隔离属性
    case copyApplication = "copy-application"               // 复制到安装目录
    case moveApplication = "move-application"               // 移入安装目录
    case replaceApplication = "replace-application"         // 替换现有应用
    case removeQuarantine = "remove-quarantine"             // 移除应用根目录隔离标记
    case finalizeMetadata = "finalize-metadata"             // 完成安装元数据
    case publishApplication = "publish-application"         // 发布新应用
    case recordInstallation = "record-installation"         // 记录安装状态

    public var title: String {
        switch self {
        case .prepareStage: return "准备临时目录"
        case .extractApplication: return "解压应用"
        case .validateApplication: return "验证应用包"
        case .prepareDestination: return "准备安装目录"
        case .preparePublication: return "准备发布记录"
        case .readQuarantine: return "读取来源隔离属性"
        case .writeQuarantine: return "写入应用隔离属性"
        case .copyApplication: return "复制到安装目录"
        case .moveApplication: return "移入安装目录"
        case .replaceApplication: return "替换现有应用"
        case .removeQuarantine: return "移除应用根目录隔离标记"
        case .finalizeMetadata: return "完成安装元数据"
        case .publishApplication: return "发布新应用"
        case .recordInstallation: return "记录安装状态"
        }
    }
}

public enum AppSignatureStatus: String, Equatable, Sendable {
    case notarized = "notarized"
    case signedNotNotarized = "signedNotNotarized"
    case adHocSigned = "adHocSigned"
    case unsigned = "unsigned"

    public var description: String {
        switch self {
        case .notarized: return "已由 Apple 公证"
        case .signedNotNotarized: return "已签名但未公证"
        case .adHocSigned: return "仅有临时（ad-hoc）签名，无法确认发布者"
        case .unsigned: return "没有任何代码签名，无法确认发布者"
        }
    }
}

// MARK: - DiskImageEngine (L4 Engine)

/// Tracks per-URL SLA consent so the UI can show the license card once.
public final class DiskImageLicenseConsent: @unchecked Sendable {
    public static let shared = DiskImageLicenseConsent()
    private let lock = NSLock()
    private var agreed: Set<String> = []

    public func isAgreed(_ url: URL) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return agreed.contains(url.standardizedFileURL.path)
    }

    public func agree(_ url: URL) {
        lock.lock(); defer { lock.unlock() }
        agreed.insert(url.standardizedFileURL.path)
    }
}

public final class DiskImageEngine: ArchiveEngine, @unchecked Sendable {
    public static let capabilities = EngineCapabilities(
        read: [.dmg, .iso],
        write: [],
        edit: [],
        encryptedRead: true,
        encryptedWrite: false,
        headerEncryption: false,
        split: false,
        streamingMemberRead: true
    )

    public var engineName: String { "DiskImageEngine" }

    private let mountQueue = DispatchQueue(label: "com.prozip.disk-image-mounts")
    private var activeMounts: [String: URL] = [:] // mountPoint -> diskImageURL

    public init() {}

    deinit {
        // Detach any remaining mounted volumes
        let mountPoints = mountQueue.sync { Array(activeMounts.keys) }
        for mountPoint in mountPoints {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            proc.arguments = ["detach", mountPoint, "-force"]
            try? proc.run()
            proc.waitUntilExit()
        }
    }

    private func recordMount(point: String, imageURL: URL) {
        mountQueue.sync {
            activeMounts[point] = imageURL
        }
    }

    private func removeMount(point: String) {
        mountQueue.sync {
            _ = activeMounts.removeValue(forKey: point)
        }
    }

    private func allMountPoints() -> [String] {
        mountQueue.sync {
            Array(activeMounts.keys)
        }
    }

    private func findMountPoint(for imageURL: URL) -> URL? {
        mountQueue.sync {
            for (mp, img) in activeMounts where img.path == imageURL.path {
                return URL(fileURLWithPath: mp)
            }
            return nil
        }
    }

    // MARK: - Mount & Detach Management

    public func mountReadOnly(_ url: URL, password: String? = nil) async throws -> MountedDiskImage {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ProZipError.diskImageError("找不到磁盘映像，请确认文件仍然存在：\(url.lastPathComponent)")
        }

        // 1. Probe SLA
        var hasSLA = false
        var slaText: String?
        if let infoResult = try? await ProcessCancellationController.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/hdiutil"),
            arguments: ["imageinfo", "-plist", url.path]
        ) {
            if let plist = try? PropertyListSerialization.propertyList(from: infoResult.stdout, options: [], format: nil) as? [String: Any] {
                if let props = plist["Properties"] as? [String: Any] {
                    if let sla = props["Software License Agreement"] as? Bool, sla {
                        hasSLA = true
                    }
                }
                if let slaDict = plist["Software License Agreements"] as? [String: Any] {
                    hasSLA = true
                    slaText = slaDict.description
                }
            }
        }

        if hasSLA, !DiskImageLicenseConsent.shared.isAgreed(url) {
            throw ProZipError.licenseAgreementRequired(slaText ?? url.lastPathComponent)
        }

        // 2. Attach command
        var attachArgs = [
            "attach",
            "-plist",
            "-readonly",
            "-nobrowse",
            "-noautoopen"
        ]

        let hasPwd = (password != nil && !(password!.isEmpty))
        if hasPwd {
            attachArgs.append("-stdinpass")
        }
        attachArgs.append(url.path)

        let stdinData = hasPwd ? "\(password!)\n".data(using: .utf8) : nil

        let result = try await ProcessCancellationController.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/hdiutil"),
            arguments: attachArgs,
            stdinData: stdinData
        )

        let combined = result.combinedOutputString
        if result.exitCode != 0 {
            if combined.contains("authentication error") ||
                combined.contains("incorrect password") ||
                combined.contains("password required") {
                if !hasPwd {
                    throw ProZipError.passwordRequired(url.lastPathComponent)
                } else {
                    throw ProZipError.wrongPassword("密码错误：\(url.lastPathComponent)")
                }
            } else if combined.contains("no such file") {
                throw ProZipError.diskImageError("找不到磁盘映像，请确认文件仍然存在")
            } else if combined.contains("permission denied") {
                throw ProZipError.diskImageError("没有权限读取此磁盘映像：\(url.lastPathComponent)")
            } else if combined.contains("not recognized") || combined.contains("unsupported") {
                throw ProZipError.diskImageError("macOS 不支持此磁盘映像格式：\(url.lastPathComponent)")
            } else if combined.contains("checksum") {
                throw ProZipError.diskImageError("磁盘映像校验失败：\(url.lastPathComponent)")
            } else {
                throw ProZipError.diskImageError("macOS 无法挂载磁盘映像：\(combined)")
            }
        }

        // 3. Parse plist output
        guard let plist = try? PropertyListSerialization.propertyList(from: result.stdout, options: [], format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]] else {
            throw ProZipError.diskImageError("无法解析磁盘映像挂载点")
        }

        var mountPointURL: URL?
        var devicePath = ""

        for entity in entities {
            if let mp = entity["mount-point"] as? String {
                mountPointURL = URL(fileURLWithPath: mp, isDirectory: true)
                devicePath = (entity["dev-entry"] as? String) ?? ""
                break
            }
        }

        guard let targetMountPoint = mountPointURL else {
            throw ProZipError.diskImageError("挂载成功但未找到有效的文件系统挂载点")
        }

        recordMount(point: targetMountPoint.path, imageURL: url)

        // 4. Scan layout (.background, Applications shortcut, .DS_Store)
        let fm = FileManager.default
        var bgImageURL: URL?
        var appShortcutURL: URL?

        let bgDir = targetMountPoint.appendingPathComponent(".background", isDirectory: true)
        if fm.fileExists(atPath: bgDir.path) {
            if let items = try? fm.contentsOfDirectory(at: bgDir, includingPropertiesForKeys: nil) {
                bgImageURL = items.first(where: {
                    let ext = $0.pathExtension.lowercased()
                    return ["png", "jpg", "jpeg", "tiff", "gif"].contains(ext)
                })
            }
        }

        let appShortcut = targetMountPoint.appendingPathComponent("Applications")
        if (try? appShortcut.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            if let dest = try? fm.destinationOfSymbolicLink(atPath: appShortcut.path) {
                if dest == "/Applications" || dest == "/Applications/" {
                    appShortcutURL = appShortcut
                }
            }
        }

        let iconPositions = parseDSStorePositions(in: targetMountPoint)

        return MountedDiskImage(
            mountPoint: targetMountPoint,
            devicePath: devicePath,
            volumeName: targetMountPoint.lastPathComponent,
            hasSLA: hasSLA,
            slaText: slaText,
            iconPositions: iconPositions,
            backgroundImageURL: bgImageURL,
            applicationsShortcutURL: appShortcutURL
        )
    }

    public func detach(_ mountPoint: String) async {
        _ = await Task.detached {
            try? await ProcessCancellationController.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/hdiutil"),
                arguments: ["detach", mountPoint, "-force"]
            )
        }.value

        removeMount(point: mountPoint)
    }

    public func detachAll() async {
        let mounts = allMountPoints()
        for m in mounts {
            await detach(m)
        }
    }

    // MARK: - 14-Stage Application Installation Pipeline

    public static func inspectSignature(of appURL: URL) async -> AppSignatureStatus {
        guard let codesignResult = try? await ProcessCancellationController.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/codesign"),
            arguments: ["-dvvv", appURL.path]
        ), codesignResult.exitCode == 0 else {
            return .unsigned
        }

        let errStr = String(data: codesignResult.stderr, encoding: .utf8) ?? codesignResult.combinedOutputString
        if errStr.contains("Signature=adhoc") {
            return .adHocSigned
        }

        // Check Notarization via spctl
        guard let spctlResult = try? await ProcessCancellationController.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/spctl"),
            arguments: ["-a", "-vv", appURL.path]
        ) else {
            return .signedNotNotarized
        }

        let spctlErr = String(data: spctlResult.stderr, encoding: .utf8) ?? spctlResult.combinedOutputString
        if spctlResult.exitCode == 0 && (spctlErr.contains("Notarized Developer ID") || spctlErr.contains("source=Notarized")) {
            return .notarized
        }

        return .signedNotNotarized
    }

    public func installApplication(
        from appBundleURL: URL,
        to applicationsDir: URL = URL(fileURLWithPath: "/Applications"),
        quickInstallRemoveQuarantine: Bool = true,
        allowReplace: Bool = true,
        stageObserver: @Sendable (ApplicationInstallStage) -> Void
    ) async throws -> URL {
        let fm = FileManager.default

        // Stage 1: prepare-stage
        stageObserver(.prepareStage)
        let tempStageDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(".prozip-app-install-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempStageDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempStageDir) }

        // Stage 2: extract-application
        stageObserver(.extractApplication)
        let stagedAppURL = tempStageDir.appendingPathComponent(appBundleURL.lastPathComponent)
        try fm.copyItem(at: appBundleURL, to: stagedAppURL)

        // Stage 3: validate-application
        stageObserver(.validateApplication)
        let infoPlistURL = stagedAppURL.appendingPathComponent("Contents/Info.plist")
        let macosDirURL = stagedAppURL.appendingPathComponent("Contents/MacOS", isDirectory: true)
        guard fm.fileExists(atPath: infoPlistURL.path), fm.fileExists(atPath: macosDirURL.path) else {
            throw ProZipError.installationError(stage: "validate-application", reason: "磁盘映像中找不到有效的应用程序包")
        }

        // Stage 4: prepare-destination
        stageObserver(.prepareDestination)
        if !fm.fileExists(atPath: applicationsDir.path) {
            try fm.createDirectory(at: applicationsDir, withIntermediateDirectories: true)
        }
        let targetAppURL = applicationsDir.appendingPathComponent(appBundleURL.lastPathComponent)
        let appAlreadyExists = fm.fileExists(atPath: targetAppURL.path)
        if appAlreadyExists && !allowReplace {
            throw ProZipError.installationError(stage: "prepare-destination", reason: "目标已存在同名应用且未允许替换")
        }

        // Stage 5: prepare-publication
        stageObserver(.preparePublication)
        guard fm.isWritableFile(atPath: applicationsDir.path) || access(applicationsDir.path, W_OK) == 0 else {
            throw ProZipError.installationError(stage: "prepare-publication", reason: "无法写入“应用程序”文件夹，请确认访问权限")
        }

        // Stage 6: read-quarantine
        stageObserver(.readQuarantine)
        var quarantineData: Data?
        let quarantineName = "com.apple.quarantine"
        let qSize = getxattr(appBundleURL.path, quarantineName, nil, 0, 0, 0)
        if qSize > 0 {
            var buf = [UInt8](repeating: 0, count: qSize)
            if getxattr(appBundleURL.path, quarantineName, &buf, qSize, 0, 0) > 0 {
                quarantineData = Data(buf)
            }
        }

        // Stage 7: write-quarantine
        stageObserver(.writeQuarantine)
        if let qData = quarantineData {
            qData.withUnsafeBytes { ptr in
                if let base = ptr.baseAddress {
                    _ = setxattr(stagedAppURL.path, quarantineName, base, qData.count, 0, 0)
                }
            }
        }

        // Stage 8: copy-application
        stageObserver(.copyApplication)
        let intermediateTargetURL = applicationsDir.appendingPathComponent(".prozip-install-\(UUID().uuidString).app")

        // Stage 9: move-application
        stageObserver(.moveApplication)
        try fm.moveItem(at: stagedAppURL, to: intermediateTargetURL)

        // Stage 10: replace-application
        stageObserver(.replaceApplication)
        if appAlreadyExists {
            try fm.removeItem(at: targetAppURL)
        }

        // Stage 11: remove-quarantine
        stageObserver(.removeQuarantine)
        if quickInstallRemoveQuarantine {
            _ = removexattr(intermediateTargetURL.path, quarantineName, 0)
        }

        // Stage 12: finalize-metadata
        stageObserver(.finalizeMetadata)
        // Ensure standard 0755 permissions on root bundle and main executables
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: intermediateTargetURL.path)

        // Stage 13: publish-application
        stageObserver(.publishApplication)
        try fm.moveItem(at: intermediateTargetURL, to: targetAppURL)

        // Stage 14: record-installation
        stageObserver(.recordInstallation)

        return targetAppURL
    }

    // MARK: - Font Installation (doc/08 section 7)

    public func installFont(
        at fontURL: URL,
        destinationDir: URL? = nil,
        allowReplace: Bool = true
    ) throws -> URL {
        let ext = fontURL.pathExtension.lowercased()
        guard ["ttf", "otf", "ttc"].contains(ext) else {
            throw ProZipError.invalidArchive("所选项目不是字体文件（仅支持 .ttf, .otf, .ttc）")
        }

        let targetDir = destinationDir ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Fonts", isDirectory: true)

        let fm = FileManager.default
        if !fm.fileExists(atPath: targetDir.path) {
            try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)
        }

        guard fm.isWritableFile(atPath: targetDir.path) || access(targetDir.path, W_OK) == 0 else {
            throw ProZipError.destinationNotWritable("没有权限写入当前用户的字体库：\(targetDir.path)")
        }

        let targetURL = targetDir.appendingPathComponent(fontURL.lastPathComponent)
        if fm.fileExists(atPath: targetURL.path) {
            guard allowReplace else {
                throw ProZipError.structureConflict("目标已存在同名字体：\(fontURL.lastPathComponent)")
            }
            try fm.removeItem(at: targetURL)
        }

        try fm.copyItem(at: fontURL, to: targetURL)

        // Register with CoreText
        var error: Unmanaged<CFError>?
        let registered = CTFontManagerRegisterFontsForURL(targetURL as CFURL, .process, &error)
        if !registered, let err = error?.takeRetainedValue() {
            // Note: Registration in current process might be informational, file is still installed
            _ = err
        }

        return targetURL
    }

    // MARK: - ArchiveEngine Protocol Methods

    public func probe(_ url: URL) async throws -> ArchiveDescriptor {
        let format = ArchiveFormat.detect(from: url)
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0

        // Check if DMG is encrypted
        var isEncrypted = false
        if let infoRes = try? await ProcessCancellationController.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/hdiutil"),
            arguments: ["imageinfo", "-plist", url.path]
        ) {
            if let str = String(data: infoRes.stdout, encoding: .utf8), str.contains("Encrypted") {
                isEncrypted = true
            }
        }

        return ArchiveDescriptor(
            url: url,
            format: format,
            isEncrypted: isEncrypted,
            hasEncryptedHeaders: false,
            isSplitVolume: false,
            totalCompressedSize: fileSize
        )
    }

    public func list(
        _ url: URL,
        password: String?,
        progress: @escaping ProgressSink
    ) async throws -> [ArchiveEntry] {
        progress(OperationProgress(phase: .preparing, completedBytes: 0, totalBytes: 0))

        let mounted = try await mountReadOnly(url, password: password)
        let mountPoint = mounted.mountPoint

        progress(OperationProgress(phase: .indexing, completedBytes: 0, totalBytes: 0))

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: mountPoint,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isSymbolicLinkKey, .isDirectoryKey],
            options: []
        ) else {
            return []
        }

        var entries: [ArchiveEntry] = []
        let mountPath = mountPoint.standardizedFileURL.path

        let urls = enumerator.compactMap { $0 as? URL }
        for itemURL in urls {
            let itemPath = itemURL.standardizedFileURL.path
            guard itemPath.hasPrefix(mountPath) else { continue }

            var relativePath = String(itemPath.dropFirst(mountPath.count))
            if relativePath.hasPrefix("/") {
                relativePath.removeFirst()
            }
            guard !relativePath.isEmpty else { continue }

            let vals = try? itemURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isSymbolicLinkKey, .isDirectoryKey])
            let isDir = vals?.isDirectory ?? false
            let isSymlink = vals?.isSymbolicLink ?? false
            let size = Int64(vals?.fileSize ?? 0)
            let modDate = vals?.contentModificationDate ?? Date()

            let type: EntryType
            var symlinkTarget: String?
            if isSymlink {
                type = .symlink
                symlinkTarget = try? fm.destinationOfSymbolicLink(atPath: itemURL.path)
            } else if isDir {
                type = .directory
            } else {
                type = .file
            }

            let entry = ArchiveEntry(
                path: relativePath,
                type: type,
                uncompressedSize: isDir ? 0 : size,
                compressedSize: 0,
                modifiedAt: modDate,
                permissions: isDir ? 493 : 420,
                symlinkTarget: symlinkTarget
            )
            entries.append(entry)
        }

        progress(OperationProgress(phase: .completed, completedBytes: Int64(entries.count), totalBytes: Int64(entries.count)))
        return entries
    }

    public func openMember(
        _ entry: ArchiveEntry,
        in url: URL,
        password: String?,
        range: Range<Int64>?
    ) async throws -> AsyncThrowingStream<Data, Error> {
        // Find or mount disk image
        var targetMount = findMountPoint(for: url)
        if targetMount == nil {
            let m = try await mountReadOnly(url, password: password)
            targetMount = m.mountPoint
        }

        guard let mountPoint = targetMount else {
            throw ProZipError.diskImageError("磁盘映像未挂载")
        }

        let fileURL = mountPoint.appendingPathComponent(entry.path)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ProZipError.invalidArchive("卷内未找到项目：\(entry.path)")
        }
        try await MemberReadBudgetLimiter.shared.acquire(requestedBytes: entry.uncompressedSize)

        return AsyncThrowingStream { continuation in
            let task = Task {
                defer {
                    Task { await MemberReadBudgetLimiter.shared.release() }
                }
                do {
                    try Task.checkCancellation()
                    let fileHandle = try FileHandle(forReadingFrom: fileURL)
                    defer { try? fileHandle.close() }

                    if let range = range {
                        try fileHandle.seek(toOffset: UInt64(max(0, range.lowerBound)))
                        let count = Int(range.upperBound - range.lowerBound)
                        let data = try fileHandle.read(upToCount: count) ?? Data()
                        continuation.yield(data)
                    } else {
                        while let chunk = try fileHandle.read(upToCount: 65536), !chunk.isEmpty {
                            try Task.checkCancellation()
                            continuation.yield(chunk)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func extract(
        _ entries: [ArchiveEntry],
        from url: URL,
        to dir: URL,
        password: String?,
        options: ExtractionOptions,
        progress: @escaping ProgressSink
    ) async throws -> ExtractionReport {
        let plan = try ArchiveExtractionPolicy.buildPlan(
            entries: entries,
            archiveURL: url,
            destinationURL: dir,
            options: options
        )

        guard !plan.itemsToExtract.isEmpty else {
            return ExtractionReport(
                destinationURL: dir,
                extractedCount: 0,
                skippedCount: plan.skippedEntries.count,
                failedCount: 0,
                extractedURLs: [],
                skippedReasons: plan.skippedEntries.map(\.reason)
            )
        }

        let plannedBytes = plan.itemsToExtract.reduce(Int64(0)) { $0 + max(0, $1.entry.uncompressedSize) }
        let progressTotalBytes = plannedBytes > 0 ? plannedBytes : Int64(plan.itemsToExtract.count)
        let firstItemName = plan.itemsToExtract.first?.entry.name

        progress(OperationProgress(
            phase: .preparing,
            completedBytes: 0,
            totalBytes: progressTotalBytes,
            currentItem: firstItemName,
            fractionCompleted: 0.02
        ))

        // Mount volume if not already mounted
        var targetMount = findMountPoint(for: url)
        if targetMount == nil {
            let m = try await mountReadOnly(url, password: password)
            targetMount = m.mountPoint
        }

        guard let mountPoint = targetMount else {
            throw ProZipError.diskImageError("无法挂载磁盘映像以提取文件")
        }

        let fm = FileManager.default
        var publishedURLs: [URL] = []
        var skippedCount = plan.skippedEntries.count
        var skippedReasons = plan.skippedEntries.map(\.reason)
        var completedBytes: Int64 = 0
        var lastEmitTime: CFAbsoluteTime = 0
        var lastFraction: Double = 0.05

        func emitProgress(currentBytes: Int64, itemIndex: Int, itemName: String, force: Bool = false) {
            let ratio: Double
            if plannedBytes > 0 {
                ratio = min(1.0, max(0.0, Double(currentBytes) / Double(plannedBytes)))
            } else {
                ratio = min(1.0, max(0.0, Double(itemIndex) / Double(max(1, plan.itemsToExtract.count))))
            }
            let targetFraction = 0.05 + 0.93 * ratio
            let now = CFAbsoluteTimeGetCurrent()
            if force || lastEmitTime == 0 || (now - lastEmitTime) >= 0.025 || (targetFraction - lastFraction) >= 0.015 {
                lastEmitTime = now
                lastFraction = max(lastFraction, targetFraction)
                progress(OperationProgress(
                    phase: .extracting,
                    completedBytes: plannedBytes > 0 ? min(plannedBytes, currentBytes) : Int64(itemIndex),
                    totalBytes: progressTotalBytes,
                    currentItem: itemName,
                    fractionCompleted: lastFraction
                ))
            }
        }

        emitProgress(currentBytes: 0, itemIndex: 0, itemName: firstItemName ?? url.lastPathComponent, force: true)

        for (idx, item) in plan.itemsToExtract.enumerated() {
            try Task.checkCancellation()
            emitProgress(currentBytes: completedBytes, itemIndex: idx, itemName: item.entry.name)

            let sourceItemURL = mountPoint.appendingPathComponent(item.entry.path)
            guard fm.fileExists(atPath: sourceItemURL.path) else {
                skippedCount += 1
                skippedReasons.append("磁盘映像中未找到所选项目：\(item.entry.name)")
                continue
            }

            let destURL = item.destinationURL
            let destParent = destURL.deletingLastPathComponent()
            try ArchiveExtractionPolicy.validateDestinationDirectory(item.entry.isDirectory ? destURL : destParent)
            if !fm.fileExists(atPath: destParent.path) {
                try fm.createDirectory(at: destParent, withIntermediateDirectories: true)
            }

            if item.entry.isDirectory {
                try fm.createDirectory(at: destURL, withIntermediateDirectories: true)
                publishedURLs.append(destURL)
                continue
            }

            let baseCompleted = completedBytes
            let expectedItemBytes = max(0, item.entry.uncompressedSize)
            let copySingleItem: (URL, URL) throws -> Void = { src, dst in
                if item.entry.type == .file {
                    try Self.copyRegularFileWithProgress(from: src, to: dst) { copiedInFile in
                        emitProgress(
                            currentBytes: baseCompleted + min(expectedItemBytes > 0 ? expectedItemBytes : copiedInFile, copiedInFile),
                            itemIndex: idx,
                            itemName: item.entry.name
                        )
                    }
                } else {
                    try fm.copyItem(at: src, to: dst)
                }
            }

            if fm.fileExists(atPath: destURL.path) {
                switch item.conflictAction {
                case .replace:
                    let replacement = destParent.appendingPathComponent(".prozip-extract-\(UUID().uuidString)")
                    defer { try? fm.removeItem(at: replacement) }
                    try copySingleItem(sourceItemURL, replacement)
                    _ = try fm.replaceItemAt(destURL, withItemAt: replacement, options: .usingNewMetadataOnly)
                    publishedURLs.append(destURL)
                case .skip:
                    skippedCount += 1
                    skippedReasons.append("跳过已存在项目：\(destURL.lastPathComponent)")
                case .keepBoth, .ask:
                    try copySingleItem(sourceItemURL, destURL)
                    publishedURLs.append(destURL)
                }
            } else {
                try copySingleItem(sourceItemURL, destURL)
                publishedURLs.append(destURL)
            }

            completedBytes += expectedItemBytes
            emitProgress(currentBytes: completedBytes, itemIndex: idx + 1, itemName: item.entry.name)
        }

        progress(OperationProgress(
            phase: .completed,
            completedBytes: progressTotalBytes,
            totalBytes: progressTotalBytes,
            fractionCompleted: 1.0
        ))

        return ExtractionReport(
            destinationURL: dir,
            extractedCount: publishedURLs.count,
            skippedCount: skippedCount,
            failedCount: 0,
            extractedURLs: publishedURLs,
            skippedReasons: skippedReasons
        )
    }

    private final class CopyFileProgressContext {
        let onProgress: (Int64) -> Void
        var cancelled = false
        init(onProgress: @escaping (Int64) -> Void) {
            self.onProgress = onProgress
        }
    }

    private static func copyRegularFileWithProgress(
        from sourceURL: URL,
        to destinationURL: URL,
        onProgress: @escaping (Int64) -> Void
    ) throws {
        guard let state = copyfile_state_alloc() else {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            return
        }
        defer { copyfile_state_free(state) }

        let context = CopyFileProgressContext(onProgress: onProgress)
        let unmanaged = Unmanaged.passRetained(context)
        defer { unmanaged.release() }

        let callback: copyfile_callback_t = { what, stage, state, _, _, ctx in
            guard let ctx else { return COPYFILE_CONTINUE }
            let box = Unmanaged<CopyFileProgressContext>.fromOpaque(ctx).takeUnretainedValue()
            if Task.isCancelled {
                box.cancelled = true
                return COPYFILE_QUIT
            }
            if what == COPYFILE_COPY_DATA && stage == COPYFILE_PROGRESS, let state {
                var copied: off_t = 0
                if copyfile_state_get(state, UInt32(COPYFILE_STATE_COPIED), &copied) == 0 {
                    box.onProgress(Int64(max(0, copied)))
                }
            }
            return COPYFILE_CONTINUE
        }

        var cb = callback
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CB), &cb)
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CTX), unmanaged.toOpaque())

        let flags = copyfile_flags_t(COPYFILE_ALL | COPYFILE_NOFOLLOW | COPYFILE_EXCL)
        let rc = sourceURL.path.withCString { srcPath in
            destinationURL.path.withCString { dstPath in
                copyfile(srcPath, dstPath, state, flags)
            }
        }
        if context.cancelled || Task.isCancelled {
            try? FileManager.default.removeItem(at: destinationURL)
            throw CancellationError()
        }
        if rc != 0 {
            let err = errno
            try? FileManager.default.removeItem(at: destinationURL)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(err), userInfo: [
                NSLocalizedDescriptionKey: String(cString: strerror(err))
            ])
        }
    }

    public func create(
        sources: [URL],
        at url: URL,
        profile: CreationProfile,
        password: String?,
        progress: @escaping ProgressSink
    ) async throws {
        throw ProZipError.invalidCreationProfile("创建磁盘映像暂不支持")
    }

    public func applyMutations(
        _ mutations: [ArchiveMutation],
        to sourceURL: URL,
        outputURL: URL,
        profile: CreationProfile,
        password: String?,
        progress: @escaping ProgressSink
    ) async throws {
        throw ProZipError.editingNotSupported("磁盘映像不支持增量修改")
    }

    // MARK: - Private Helper

    private func parseDSStorePositions(in mountPoint: URL) -> [DiskImageIconPosition] {
        let dsStoreURL = mountPoint.appendingPathComponent(".DS_Store")
        guard let data = try? Data(contentsOf: dsStoreURL) else { return [] }

        var positions: [DiskImageIconPosition] = []
        let ilocSignature = "Iloc".data(using: .ascii)!

        // Scan for Iloc entries in .DS_Store binary
        var searchRange = 0..<(data.count - 24)
        while let foundRange = data.range(of: ilocSignature, options: [], in: searchRange) {
            let ilocOffset = foundRange.lowerBound
            // Coordinates follow after Iloc entry
            let xOffset = ilocOffset + 4
            let yOffset = ilocOffset + 8
            if yOffset + 4 <= data.count {
                let x = Double(data.subdata(in: xOffset..<(xOffset + 4)).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
                let y = Double(data.subdata(in: yOffset..<(yOffset + 4)).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
                // Search backwards for filename string
                let filenameSearchStart = max(0, ilocOffset - 128)
                let nameSlice = data.subdata(in: filenameSearchStart..<ilocOffset)
                if let str = String(data: nameSlice, encoding: .utf8) {
                    let cleanName = str.trimmingCharacters(in: .controlCharacters)
                    if !cleanName.isEmpty && x > 0 && y > 0 && x < 4000 && y < 4000 {
                        positions.append(DiskImageIconPosition(fileName: cleanName, x: x, y: y))
                    }
                }
            }
            searchRange = (foundRange.upperBound)..<(data.count - 24)
        }

        return positions
    }
}
