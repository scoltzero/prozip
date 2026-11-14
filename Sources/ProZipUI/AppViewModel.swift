import SwiftUI
import AppKit
import Combine
import QuickLookUI
import ProZipShared
import ProZipCore
import ProZipEngines

// MARK: - Bundled & Repo Resource Image Loader

public enum ProZipResourceImageLoader {
    private static let lock = NSLock()
    private static var cache: [String: NSImage] = [:]

    public static func nsImage(named name: String) -> NSImage? {
        let baseName = (name as NSString).deletingPathExtension
        lock.lock()
        if let cached = cache[baseName] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let candidates: [NSImage?] = [
            Bundle.main.image(forResource: NSImage.Name(baseName)),
            Bundle.main.path(forResource: baseName, ofType: "png").flatMap { NSImage(contentsOfFile: $0) },
            NSImage(contentsOfFile: "/Users/luochuhan/repo/prozip/Resources/\(baseName).png"),
            NSImage(contentsOfFile: FileManager.default.currentDirectoryPath + "/Resources/\(baseName).png")
        ]

        for candidate in candidates {
            if let img = candidate {
                lock.lock()
                cache[baseName] = img
                lock.unlock()
                return img
            }
        }
        return nil
    }
}

public struct ProZipBundledImage: View {
    public let name: String
    public let fallbackSymbol: String
    public var contentMode: ContentMode
    public var tintColor: Color?

    public init(
        name: String,
        fallbackSymbol: String = "photo",
        contentMode: ContentMode = .fit,
        tintColor: Color? = nil
    ) {
        self.name = name
        self.fallbackSymbol = fallbackSymbol
        self.contentMode = contentMode
        self.tintColor = tintColor
    }

    public var body: some View {
        if let nsImg = ProZipResourceImageLoader.nsImage(named: name) {
            if let tint = tintColor {
                Image(nsImage: nsImg)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .foregroundStyle(tint)
            } else {
                Image(nsImage: nsImg)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            }
        } else {
            Image(systemName: fallbackSymbol)
                .resizable()
                .aspectRatio(contentMode: contentMode)
                .foregroundStyle(tintColor ?? ProZipTheme.accent)
        }
    }
}

// MARK: - Flow Action Router (doc/09 Section 3)

public enum FlowActionRouter {
    /// Implements the exact 8-step decision order from doc/09 section 3:
    /// 1. Selection check: No selection -> nil
    /// 2. Multiple selection -> extractSelection
    /// 3. Single directory selected -> extractDirectory
    /// 4. Single .app selected:
    ///      - In disk image -> openDiskImageApplication (or diskImageApplicationPrefersOpen)
    ///      - In regular archive -> installApplication
    /// 5. Single font file selected -> installFont
    /// 6. Single .pkg selected -> installPackage
    /// 7. Single regular file and extension in allowedFormats -> openFile
    /// 8. Fallback -> unavailable
    public static func recommendAction(
        for selection: [ArchiveEntry],
        in descriptor: ArchiveDescriptor,
        allowedFormats: Set<String>
    ) -> FlowActionRecommendation? {
        // Step 1: Selection check
        guard !selection.isEmpty else {
            return nil
        }

        // Step 2: Multiple selection
        if selection.count > 1 {
            return FlowActionRecommendation(
                actionID: .extractSelection,
                title: "解压所选项目 (\(selection.count))",
                systemIcon: "arrow.up.doc.fill",
                isEnabled: true
            )
        }

        // Single item
        let entry = selection[0]
        let ext = entry.fileExtension.lowercased()

        // Step 4 (checked before generic directory since .app bundles are directories): Single .app selected
        if ext == "app" || entry.name.lowercased().hasSuffix(".app") {
            if descriptor.format.isDiskImage {
                return FlowActionRecommendation(
                    actionID: .openDiskImageApplication,
                    title: "打开应用",
                    systemIcon: "app.badge.checkmark",
                    isEnabled: true
                )
            } else {
                return FlowActionRecommendation(
                    actionID: .installApplication,
                    title: "安装到“应用程序”",
                    systemIcon: "arrow.down.app",
                    isEnabled: true
                )
            }
        }

        // Step 3: Single directory selected
        if entry.isDirectory {
            return FlowActionRecommendation(
                actionID: .extractDirectory,
                title: "解压",
                systemIcon: "folder.badge.gearshape",
                isEnabled: true
            )
        }

        // Step 5: Single font file selected
        let fontExtensions: Set<String> = ["ttf", "otf", "ttc", "woff", "woff2", "dfont"]
        if fontExtensions.contains(ext) {
            return FlowActionRecommendation(
                actionID: .installFont,
                title: "安装字体",
                systemIcon: "textformat",
                isEnabled: true
            )
        }

        // Step 6: Single .pkg selected
        if ext == "pkg" || ext == "mpkg" {
            return FlowActionRecommendation(
                actionID: .installPackage,
                title: "运行安装器",
                systemIcon: "shippingbox",
                isEnabled: true
            )
        }

        // Step 7: Single regular file and extension in allowedFormats
        if let formatID = AllowedOpenFormat.formatID(forExtension: ext), allowedFormats.contains(formatID) {
            return FlowActionRecommendation(
                actionID: .openFile,
                title: "打开文件",
                systemIcon: "arrow.up.forward.app",
                isEnabled: true
            )
        }

        // Step 8: Fallback
        return FlowActionRecommendation(
            actionID: .unavailable,
            title: "打开文件（未关联）",
            systemIcon: "exclamationmark.circle",
            isEnabled: false,
            unavailableReason: "系统未在白名单中找到用于安全打开 .\(ext) 的默认应用"
        )
    }
}

public struct FlowActionRecommendation: Hashable, Sendable {
    public let actionID: FlowActionID
    public let title: String
    public let systemIcon: String
    public let isEnabled: Bool
    public var unavailableReason: String?

    public init(
        actionID: FlowActionID,
        title: String,
        systemIcon: String,
        isEnabled: Bool,
        unavailableReason: String? = nil
    ) {
        self.actionID = actionID
        self.title = title
        self.systemIcon = systemIcon
        self.isEnabled = isEnabled
        self.unavailableReason = unavailableReason
    }
}

// MARK: - Dialog Payload Models

public struct ConflictItemInfo: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public var fileName: String
    public var destinationPath: String
    public var existingSize: Int64
    public var existingModifiedAt: Date
    public var incomingSize: Int64
    public var incomingModifiedAt: Date

    public init(
        fileName: String = "设计规范_v2.fig",
        destinationPath: String = "~/Downloads/产品交付包",
        existingSize: Int64 = 14_820_100,
        existingModifiedAt: Date = Date().addingTimeInterval(-86400 * 2),
        incomingSize: Int64 = 16_450_880,
        incomingModifiedAt: Date = Date()
    ) {
        self.fileName = fileName
        self.destinationPath = destinationPath
        self.existingSize = existingSize
        self.existingModifiedAt = existingModifiedAt
        self.incomingSize = incomingSize
        self.incomingModifiedAt = incomingModifiedAt
    }
}

public struct FilenameRepairItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var originalPath: String
    public var issueReason: String
    public var suggestedName: String
    public var editedName: String

    public init(
        id: UUID = UUID(),
        originalPath: String,
        issueReason: String,
        suggestedName: String,
        editedName: String? = nil
    ) {
        self.id = id
        self.originalPath = originalPath
        self.issueReason = issueReason
        self.suggestedName = suggestedName
        self.editedName = editedName ?? suggestedName
    }

    public static let sampleItems: [FilenameRepairItem] = [
        FilenameRepairItem(
            originalPath: "财务报表:2026*Q4?.xlsx",
            issueReason: "含有 Windows 不支持的字符 (: * ?)",
            suggestedName: "财务报表_2026_Q4_.xlsx"
        ),
        FilenameRepairItem(
            originalPath: "docs/CON.txt",
            issueReason: "使用了 Windows 保留的设备名称 (CON)",
            suggestedName: "docs/_CON.txt"
        ),
        FilenameRepairItem(
            originalPath: "归档说明 | 备份<最终版>.md.",
            issueReason: "含有非法字符 (| < >) 且名称末尾包含句点",
            suggestedName: "归档说明 _ 备份_最终版_.md"
        )
    ]
}

public struct EntryIndexIssueItem: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public var path: String
    public var category: String
    public var detail: String
    public var icon: String

    public init(path: String, category: String, detail: String, icon: String = "exclamationmark.triangle.fill") {
        self.path = path
        self.category = category
        self.detail = detail
        self.icon = icon
    }

    public static let sampleItems: [EntryIndexIssueItem] = [
        EntryIndexIssueItem(
            path: "runtime/ipc_socket.sock",
            category: "Unix 套接字",
            detail: "套接字是进程间通信端点，不包含可恢复的文件内容，离开当前系统后也无法使用。",
            icon: "network.slash"
        ),
        EntryIndexIssueItem(
            path: "links/external_passwd -> /etc/passwd",
            category: "符号链接越界",
            detail: "ZIP 符号链接目标超出提取范围，为防止路径穿越已拦截。",
            icon: "link.badge.plus"
        ),
        EntryIndexIssueItem(
            path: "private/locked_vault.key",
            category: "没有读取权限",
            detail: "ProZip 当前没有读取该项目所需的权限，继续处理可能得到不完整内容。",
            icon: "lock.slash.fill"
        ),
        EntryIndexIssueItem(
            path: "pipes/worker_fifo",
            category: "命名管道（FIFO）",
            detail: "命名管道不是静态文件；读取它可能一直等待其他进程写入，导致压缩任务无法结束。",
            icon: "pipe.and.drop"
        )
    ]
}

public struct StructuredArchiveError: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public var title: String
    public var summaryReason: String
    public var affectedItemPath: String
    public var recoverySuggestion: String
    public var errorCode: String
    public var requestID: String
    public var engineName: String
    public var technicalDetails: String

    public init(
        title: String = "无法读取压缩包中的文件",
        summaryReason: String = "无法读取文件。压缩包返回的数据与目录索引不一致（CRC-32 校验和不匹配）。当前项目无法预览或导出，但其他项目仍可继续浏览。",
        affectedItemPath: String = "/Users/luochuhan/Downloads/Release_Bundle_v0.1.0.zip → Payload/CoreEngine.dylib",
        recoverySuggestion: String = "源压缩包没有被修改。你可以重新打开压缩包后再试。如果问题持续出现，请检查源文件是否下载完整，或复制下方诊断信息以供排查。",
        errorCode: String = "PZ-ERR-CRC32-MISMATCH (0x8004020B)",
        requestID: String = "REQ-20261110-9F4A2C8E",
        engineName: String = "NativeZipEngine (Zero-Copy LocalHeader Reader)",
        technicalDetails: String = """
        阶段：extract-member [verify-crc32]
        来源：/Users/luochuhan/Downloads/Release_Bundle_v0.1.0.zip
        条目：Payload/CoreEngine.dylib (offset=0x0041A820, compressed=418,902 B, uncompressed=1,048,576 B)
        期望 CRC32：0x9A8F3C12
        实际 CRC32：0x4401E7B9
        系统：macOS 15.2 (arm64) · ProZip 0.1.0 (1) Open Source
        事务状态：Staging 已安全清理，原压缩包保持未修改状态
        """
    ) {
        self.title = title
        self.summaryReason = summaryReason
        self.affectedItemPath = affectedItemPath
        self.recoverySuggestion = recoverySuggestion
        self.errorCode = errorCode
        self.requestID = requestID
        self.engineName = engineName
        self.technicalDetails = technicalDetails
    }
}

// MARK: - Archive Task Record

public final class ArchiveTaskRecord: ObservableObject, Identifiable {
    public let id: UUID
    public let title: String
    public let archiveURL: URL
    @Published public var phase: OperationPhase
    @Published public var completedBytes: Int64
    @Published public var totalBytes: Int64
    @Published public var fractionCompleted: Double
    @Published public var currentItem: String?
    @Published public var errorMessage: String?
    @Published public var speedBytesPerSec: Int64
    @Published public var outputResultURL: URL?
    public let isCancelable: Bool
    private var cancelAction: (() -> Void)?

    public init(
        id: UUID = UUID(),
        title: String,
        archiveURL: URL,
        phase: OperationPhase = .preparing,
        completedBytes: Int64 = 0,
        totalBytes: Int64 = 0,
        currentItem: String? = nil,
        speedBytesPerSec: Int64 = 0,
        outputResultURL: URL? = nil,
        isCancelable: Bool = true,
        cancelAction: (() -> Void)? = nil
    ) {
        self.id = id
        self.title = title
        self.archiveURL = archiveURL
        self.phase = phase
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
        self.currentItem = currentItem
        self.fractionCompleted = totalBytes > 0 ? Double(completedBytes) / Double(totalBytes) : (phase == .completed ? 1.0 : 0)
        self.speedBytesPerSec = speedBytesPerSec
        self.outputResultURL = outputResultURL ?? archiveURL
        self.isCancelable = isCancelable
        self.cancelAction = cancelAction
    }

    public func update(progress: OperationProgress) {
        guard phase != .cancelled, phase != .completed, phase != .failed else { return }
        self.phase = progress.phase
        self.completedBytes = progress.completedBytes
        self.totalBytes = progress.totalBytes
        self.fractionCompleted = progress.fractionCompleted
        self.currentItem = progress.currentItem
    }

    public func cancel() {
        guard isCancelable, phase != .completed, phase != .failed, phase != .cancelled else { return }
        phase = .cancelled
        cancelAction?()
        cancelAction = nil
    }

    public func bindCancellation(to operation: Task<Void, Never>) {
        cancelAction = { operation.cancel() }
        if phase == .cancelled { operation.cancel() }
    }

    public func clearCancellation() {
        cancelAction = nil
    }
}

// MARK: - Menu Bar Shelf Completed Result

public struct ShelfCompletedResult: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let title: String
    public let subtitle: String
    public let outputURL: URL
    public let completedAt: Date
    public let isArchive: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        subtitle: String,
        outputURL: URL,
        completedAt: Date = Date(),
        isArchive: Bool = true
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.outputURL = outputURL
        self.completedAt = completedAt
        self.isArchive = isArchive
    }
}

// MARK: - Menu Bar Shelf Model (ProZip 暂存盒 / 文件盒)

public final class MenuBarShelfModel: ObservableObject {
    @Published public var collectedFiles: [URL] = []
    @Published public var isHoveringActions: Bool = false
    @Published public var isQuickActionsExpanded: Bool = false
    @Published public var isPinned: Bool = false
    @Published public var expandedItemPaths: Set<String> = []
    @Published public var browsingSubdirectoryByRoot: [String: URL] = [:]
    @Published public var recentResults: [ShelfCompletedResult] = []
    @Published public var isResultsStripExpanded: Bool = true
    @Published public var statusMessage: String?

    public init() {}

    public var totalSize: Int64 {
        collectedFiles.reduce(0) { sum, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return sum + Int64(size)
        }
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }

    public var stagedURLs: [URL] {
        get { collectedFiles }
        set { collectedFiles = newValue }
    }

    public func addFiles(_ urls: [URL]) {
        for url in urls {
            if !collectedFiles.contains(where: { $0.path == url.path }) {
                collectedFiles.append(url)
            }
        }
    }

    public func removeFile(_ url: URL) {
        collectedFiles.removeAll { $0.path == url.path }
        expandedItemPaths.remove(url.path)
        browsingSubdirectoryByRoot.removeValue(forKey: url.path)
    }

    public func clear() {
        collectedFiles.removeAll()
        expandedItemPaths.removeAll()
        browsingSubdirectoryByRoot.removeAll()
    }

    public func toggleExpand(_ url: URL) {
        if expandedItemPaths.contains(url.path) {
            expandedItemPaths.remove(url.path)
        } else {
            expandedItemPaths.insert(url.path)
            if browsingSubdirectoryByRoot[url.path] == nil {
                browsingSubdirectoryByRoot[url.path] = url
            }
        }
    }

    public func populateDemoStagedItems() {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ProZipShelfDemo")
        let folderURL = tempRoot.appendingPathComponent("UI设计稿与切图")
        let subFolderURL = folderURL.appendingPathComponent("2x_Assets")
        try? FileManager.default.createDirectory(at: subFolderURL, withIntermediateDirectories: true)
        let f1 = folderURL.appendingPathComponent("Banner_Main.png")
        let f2 = folderURL.appendingPathComponent("色彩规范说明.md")
        let f3 = subFolderURL.appendingPathComponent("Icon_512@2x.png")
        try? "PNG Mock Data".write(to: f1, atomically: true, encoding: .utf8)
        try? "# ProZip Color Spec\nAccent: #A8E000".write(to: f2, atomically: true, encoding: .utf8)
        try? "Icon 2x Data".write(to: f3, atomically: true, encoding: .utf8)

        let docURL = tempRoot.appendingPathComponent("架构设计白皮书_v1.2.pdf")
        let archiveURL = tempRoot.appendingPathComponent("第三方依赖源码包.zip")
        try? "PDF Content Placeholder".write(to: docURL, atomically: true, encoding: .utf8)
        try? "PK\u{03}\u{04}DemoZip".write(to: archiveURL, atomically: true, encoding: .utf8)

        addFiles([folderURL, archiveURL, docURL])
        expandedItemPaths.insert(folderURL.path)
    }

    public func childItems(for rootURL: URL) -> [URL] {
        let currentURL = browsingSubdirectoryByRoot[rootURL.path] ?? rootURL
        if let items = try? FileManager.default.contentsOfDirectory(
            at: currentURL,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ), !items.isEmpty {
            return items.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        }
        // Fallback virtual preview for archives or non-materialized folders
        let ext = rootURL.pathExtension.lowercased()
        if ["zip", "7z", "rar", "tar", "gz", "dmg"].contains(ext) {
            return [
                rootURL.appendingPathComponent("Sources"),
                rootURL.appendingPathComponent("README.md"),
                rootURL.appendingPathComponent("LICENSE.txt"),
                rootURL.appendingPathComponent("Package.swift")
            ]
        }
        return []
    }
}

// MARK: - Main Application View Model

@MainActor
public final class ProZipAppViewModel: ObservableObject {
    public static let shared = ProZipAppViewModel()
    private let passwordBookOverride: PasswordBook?

    private var presentationOwners: [AnyKeyPath: UUID?] = [:]

    private func capturePresentationOwner(_ keyPath: ReferenceWritableKeyPath<ProZipAppViewModel, Bool>, presented: Bool) {
        if presented { presentationOwners.updateValue(activeSessionID, forKey: keyPath) }
        else { presentationOwners.removeValue(forKey: keyPath) }
    }

    public func ownsPresentation(_ keyPath: ReferenceWritableKeyPath<ProZipAppViewModel, Bool>, sessionID: UUID?) -> Bool {
        if let owner = presentationOwners[keyPath] { return owner == sessionID }
        return activeSessionID == sessionID
    }

    public func presentDialog(_ keyPath: ReferenceWritableKeyPath<ProZipAppViewModel, Bool>, for sessionID: UUID?) {
        self[keyPath: keyPath] = true
        presentationOwners.updateValue(sessionID, forKey: keyPath)
    }

    private struct PasswordRequest {
        let session: ArchiveBrowsingSession
        let message: String
        let onCancel: (() -> Void)?
        let retry: (String) -> Void
    }
    private var passwordRequests: [PasswordRequest] = []
    private var activePasswordRequest: PasswordRequest?
    private var passwordPromptIsDismissing = false
    private var completedPasswordPrompt: (() -> Void)?

    private struct SaveRequest {
        let sessionID: UUID
        let conflict: Bool
        let completion: (() -> Void)?
    }
    private var saveRequests: [SaveRequest] = []

    private struct ConflictRequest {
        let item: ConflictItemInfo
        let owner: UUID?
        let resolve: (ConflictResolution) -> Void
    }
    private var conflictRequests: [ConflictRequest] = []
    private var activeConflictRequest: ConflictRequest?
    private var conflictIsDismissing = false
    private var completedConflictAction: (() -> Void)?

    private struct ExtractionCompletionRequest {
        let archiveURL: URL
        let sourceStat: SourceArchiveStat?
        let owner: UUID?
    }
    private var extractionCompletionRequests: [ExtractionCompletionRequest] = []
    private var activeExtractionCompletion: ExtractionCompletionRequest?
    private var extractionCompletionIsDismissing = false

    private struct CreationRequest {
        let sources: [URL]
        let originalSources: [URL]?
        let owner: UUID?
        let completion: ((URL) -> Void)?
        let draftSessionID: UUID?
        let sourcesToTrash: [URL]?
    }
    private var creationRequests: [CreationRequest] = []
    private var creationIsDismissing = false
    private var creationDraftSessionID: UUID?

    @Published public private(set) var isTerminationRequested = false

    public func prepareForTermination() -> Bool {
        guard !isTerminationRequested else { return false }
        let dirty = sessions.filter(\.hasUnsavedChanges)
        if dirty.isEmpty { cancelBackgroundWork(); return true }
        isTerminationRequested = true
        advanceTermination()
        return false
    }

    public func cancelBackgroundWork() {
        for task in tasks { task.cancel() }
        for task in indexOperations.values { task.cancel() }
    }

    private func advanceTermination() {
        guard isTerminationRequested else { return }
        let dirty = sessions.filter(\.hasUnsavedChanges)
        if dirty.isEmpty {
            NotificationCenter.default.post(name: .proZipTerminationReady, object: self)
        } else {
            for session in dirty where !savingSessionIDs.contains(session.id) { closeSession(id: session.id) }
        }
    }

    private func cancelTermination() {
        guard isTerminationRequested else { return }
        isTerminationRequested = false
        saveRequests.removeAll()
        NotificationCenter.default.post(name: .proZipTerminationCancelled, object: self)
    }

    // Active browsing sessions
    @Published public var sessions: [ArchiveBrowsingSession] = [] {
        didSet { observeSessionChanges() }
    }
    private var sessionSubscriptions: [AnyCancellable] = []

    private func observeSessionChanges() {
        sessionSubscriptions = sessions.map { session in
            Publishers.MergeMany(
                session.$isMiniMode.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
                session.$viewMode.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
                session.$showsAuxiliaryEntries.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
                session.$isAlwaysOnTop.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
                session.$selectedEntryIDs.map { min($0.count, 2) }.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
                session.$pendingMutations.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
                session.$redoMutations.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
                session.$currentDirectoryPath.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
                session.$descriptor.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher()
            )
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
        }
    }
    @Published public var activeSessionID: UUID? {
        didSet {
            if let id = activeSessionID {
                recentSessionIDs.removeAll { $0 == id }
                recentSessionIDs.append(id)
            }
        }
    }
    private var recentSessionIDs: [UUID] = []
    private var sessionPasswords: [UUID: String] = [:]
    private let diskImageEngine = DiskImageEngine()
    private var savingSessionIDs: Set<UUID> = []
    private var indexOperations: [UUID: Task<Void, Never>] = [:]

    // Multi-task management (active, waiting, failed counts)
    @Published public var tasks: [ArchiveTaskRecord] = [] {
        didSet { observeTaskPhases() }
    }
    private var taskPhaseSubscriptions: [UUID: AnyCancellable] = [:]

    private func observeTaskPhases() {
        let ids = Set(tasks.map(\.id))
        taskPhaseSubscriptions = taskPhaseSubscriptions.filter { ids.contains($0.key) }
        for task in tasks where taskPhaseSubscriptions[task.id] == nil {
            taskPhaseSubscriptions[task.id] = task.$phase
                .removeDuplicates()
                .dropFirst()
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.objectWillChange.send() }
        }
    }

    @Published public var isTaskProgressPresented: Bool = false

    // Menu Bar Shelf
    @Published public var shelfModel = MenuBarShelfModel()

    // Primary Modals & Sheets
    @Published public var isCreationDialogPresented: Bool = false {
        didSet {
            if oldValue != isCreationDialogPresented { capturePresentationOwner(\.isCreationDialogPresented, presented: isCreationDialogPresented) }
            if oldValue && !isCreationDialogPresented { creationIsDismissing = true }
        }
    }
    @Published public var creationSources: [URL] = []
    @Published public var creationDestination: URL?

    @Published public var isSettingsPresented: Bool = false
    @Published public var settingsSelectedTab: SettingsTab = .general

    @Published public var isPasswordPromptPresented: Bool = false {
        didSet {
            if oldValue != isPasswordPromptPresented { capturePresentationOwner(\.isPasswordPromptPresented, presented: isPasswordPromptPresented) }
        }
    }
    @Published public var isAlertPresented: Bool = false
    public func resolvePendingCreationConflict(_ resolution: ConflictResolution) {
        guard !conflictIsDismissing else { return }
        let request = activeConflictRequest
        completedConflictAction = { request?.resolve(resolution) }
        conflictIsDismissing = true
        isConflictResolutionPresented = false
    }

    private func requestConflictResolution(_ item: ConflictItemInfo, owner: UUID?, resolve: @escaping (ConflictResolution) -> Void) {
        let request = ConflictRequest(item: item, owner: owner, resolve: resolve)
        if isConflictResolutionPresented || conflictIsDismissing { conflictRequests.append(request); return }
        showConflict(request)
    }

    private func showConflict(_ request: ConflictRequest) {
        activeConflictRequest = request
        activeConflictItem = request.item
        presentDialog(\.isConflictResolutionPresented, for: request.owner)
    }

    public func conflictDialogDidDismiss() {
        guard !isConflictResolutionPresented, conflictIsDismissing || activeConflictRequest != nil else { return }
        let request = activeConflictRequest
        let action = completedConflictAction ?? { request?.resolve(.skip) }
        activeConflictRequest = nil
        completedConflictAction = nil
        conflictIsDismissing = true
        action()
        conflictIsDismissing = false
        if !conflictRequests.isEmpty { showConflict(conflictRequests.removeFirst()) }
    }
    @Published public var alertTitle: String = "无法完成操作"
    @Published public var alertMessage: String = ""
    @Published public var passwordPromptTitle: String = ""
    @Published public var passwordPromptMessage: String = ""
    @Published public var passwordPromptIsBatch: Bool = false
    @Published public var passwordPromptCompletion: ((String?) -> Void)?

    @Published public var isRenameSheetPresented: Bool = false
    @Published public private(set) var renamingSessionID: UUID?
    @Published public var renamingEntry: ArchiveEntry?
    @Published public var renameInput: String = ""

    @Published public var isOnboardingPresented: Bool = false {
        didSet {
            if oldValue != isOnboardingPresented { capturePresentationOwner(\.isOnboardingPresented, presented: isOnboardingPresented) }
        }
    }

    // All 16+ ArcZipDialogKit / FoldspaceDialogs & Application Menu Popups
    @Published public var isAboutPresented: Bool = false {
        didSet {
            if oldValue != isAboutPresented { capturePresentationOwner(\.isAboutPresented, presented: isAboutPresented) }
        }
    }
    @Published public var isCheckForUpdatesPresented: Bool = false {
        didSet {
            if oldValue != isCheckForUpdatesPresented { capturePresentationOwner(\.isCheckForUpdatesPresented, presented: isCheckForUpdatesPresented) }
        }
    }

    public enum UpdateCheckPhase: Equatable, Sendable {
        case idle
        case checking
        case upToDate(currentVersion: String)
        case updateAvailable(currentVersion: String, latestVersion: String, release: GitHubReleaseInfo, downloadURL: URL?)
        case failed(errorDescription: String)
    }

    @Published public var updatePhase: UpdateCheckPhase = .idle
    @Published public var latestAvailableRelease: GitHubReleaseInfo?
    @Published public var preferredUpdateDownloadURL: URL?
    @Published public var isUpdateChecking: Bool = false

    public func checkForUpdates(userInitiated: Bool = true) {
        if userInitiated {
            isCheckForUpdatesPresented = true
        }
        updatePhase = .checking
        isUpdateChecking = true

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let result = try await AppUpdateService.shared.checkForUpdates()
                self.isUpdateChecking = false
                if result.hasUpdate {
                    self.latestAvailableRelease = result.release
                    self.preferredUpdateDownloadURL = result.preferredDownloadURL
                    self.updatePhase = .updateAvailable(
                        currentVersion: result.currentVersion,
                        latestVersion: result.latestVersion,
                        release: result.release,
                        downloadURL: result.preferredDownloadURL
                    )
                    if !userInitiated {
                        self.isCheckForUpdatesPresented = true
                    }
                } else {
                    self.updatePhase = .upToDate(currentVersion: result.currentVersion)
                }
            } catch {
                self.isUpdateChecking = false
                let description = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.updatePhase = .failed(errorDescription: description)
            }
        }
    }

    public func checkAutoUpdatesOnLaunchIfNeeded() {
        guard AppUpdateService.isAutoCheckEnabled else { return }
        let lastCheck = AppUpdateService.lastCheckDate
        let now = Date()
        if let lastCheck, now.timeIntervalSince(lastCheck) < 86400 {
            // Already checked within 24 hours
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.checkForUpdates(userInitiated: false)
        }
    }
    @Published public var isReleaseOverviewPresented: Bool = false {
        didSet {
            if oldValue != isReleaseOverviewPresented { capturePresentationOwner(\.isReleaseOverviewPresented, presented: isReleaseOverviewPresented) }
        }
    }
    @Published public var isPasswordBookProtectionPresented: Bool = false {
        didSet {
            if oldValue != isPasswordBookProtectionPresented { capturePresentationOwner(\.isPasswordBookProtectionPresented, presented: isPasswordBookProtectionPresented) }
        }
    }
    @Published public var isPasswordBookManagerPresented: Bool = false
    @Published public var isConflictResolutionPresented: Bool = false {
        didSet {
            if oldValue != isConflictResolutionPresented { capturePresentationOwner(\.isConflictResolutionPresented, presented: isConflictResolutionPresented) }
        }
    }
    @Published public var isSaveChangesPresented: Bool = false {
        didSet {
            if oldValue != isSaveChangesPresented { capturePresentationOwner(\.isSaveChangesPresented, presented: isSaveChangesPresented) }
        }
    }
    public private(set) var saveConfirmationSessionID: UUID?
    private var saveConfirmationCompletion: (() -> Void)?
    private var confirmedSaveContinuation: (() -> Void)?
    public var creationCompletion: ((URL) -> Void)?
    public var creationOriginalSources: [URL]?
    // Partial origins still supply the creation form's destination hint, but must never be trashed.
    private(set) var creationSourcesToTrash: [URL]?

    @Published public var isDeleteConfirmationPresented: Bool = false {
        didSet {
            if oldValue != isDeleteConfirmationPresented { capturePresentationOwner(\.isDeleteConfirmationPresented, presented: isDeleteConfirmationPresented) }
        }
    }
    @Published public var isTrashConfirmationPresented: Bool = false {
        didSet {
            if oldValue != isTrashConfirmationPresented { capturePresentationOwner(\.isTrashConfirmationPresented, presented: isTrashConfirmationPresented) }
        }
    }
    @Published public var isFilenameRepairPresented: Bool = false {
        didSet {
            if oldValue != isFilenameRepairPresented { capturePresentationOwner(\.isFilenameRepairPresented, presented: isFilenameRepairPresented) }
        }
    }
    @Published public var isEntryIndexIssuePresented: Bool = false {
        didSet {
            if oldValue != isEntryIndexIssuePresented { capturePresentationOwner(\.isEntryIndexIssuePresented, presented: isEntryIndexIssuePresented) }
        }
    }
    @Published public var isDiskImageLicensePresented: Bool = false {
        didSet {
            if oldValue != isDiskImageLicensePresented { capturePresentationOwner(\.isDiskImageLicensePresented, presented: isDiskImageLicensePresented) }
        }
    }
    @Published public var isSourceAccessAlertPresented: Bool = false {
        didSet {
            if oldValue != isSourceAccessAlertPresented { capturePresentationOwner(\.isSourceAccessAlertPresented, presented: isSourceAccessAlertPresented) }
        }
    }
    @Published public var isErrorDetailPresented: Bool = false {
        didSet {
            if oldValue != isErrorDetailPresented { capturePresentationOwner(\.isErrorDetailPresented, presented: isErrorDetailPresented) }
        }
    }
    @Published public var isDialogGalleryPresented: Bool = false {
        didSet {
            if oldValue != isDialogGalleryPresented { capturePresentationOwner(\.isDialogGalleryPresented, presented: isDialogGalleryPresented) }
        }
    }

    // Convenience aliases matching prompt & view bindings
    public var isShowingReleaseOverview: Bool {
        get { isReleaseOverviewPresented }
        set { isReleaseOverviewPresented = newValue }
    }

    public var isShowingDialogGallery: Bool {
        get { isDialogGalleryPresented }
        set { isDialogGalleryPresented = newValue }
    }

    public var isShowingAbout: Bool {
        get { isAboutPresented }
        set { isAboutPresented = newValue }
    }

    public var isShowingCheckForUpdates: Bool {
        get { isCheckForUpdatesPresented }
        set { isCheckForUpdatesPresented = newValue }
    }

    public var creationSourceURLs: [URL] {
        get { creationSources }
        set { creationSources = newValue }
    }

    public var currentArchiveURL: URL? {
        activeSession?.url
    }

    public var preferences: ProZipPreferences {
        ProZipPreferences.shared
    }

    public var passwordBook: PasswordBook {
        passwordBookOverride ?? .shared
    }

    public var passwordEntries: [PasswordBookEntry] {
        passwordBook.entries
    }

    // Active Dialog Payloads
    @Published public var activeConflictItem: ConflictItemInfo = ConflictItemInfo()
    @Published public var activeFilenameRepairItems: [FilenameRepairItem] = FilenameRepairItem.sampleItems
    @Published public var activeEntryIndexIssues: [EntryIndexIssueItem] = EntryIndexIssueItem.sampleItems
    @Published public var activeStructuredError: StructuredArchiveError = StructuredArchiveError()
    @Published public var saveChangesArchiveName: String = "季度设计交付包.zip"
    @Published public var saveChangesIsSourceModifiedConflict: Bool = false
    @Published public var deleteTargetNames: [String] = ["旧版草稿_v1.sketch", "临时导出缓存/"]
    @Published public var trashTargetArchiveName: String = "macOS_SDK_Components.7z"
    @Published public var sourceAccessTargetFolder: String = "~/Library/Containers/com.tencent.xinWeChat/Data/Library/Application Support/com.tencent.xinWeChat"
    @Published public var diskImageName: String = "ProDeveloperTools_0.1.0.dmg"
    @Published public var diskImageLicenseText: String = ""
    private var pendingLicenseArchiveURL: URL?

    public func acceptDiskImageLicense() {
        if let url = pendingLicenseArchiveURL {
            DiskImageLicenseConsent.shared.agree(url)
            pendingLicenseArchiveURL = nil
            // macOS 27 removed `hdiutil attach -agree`; only the GUI DiskImageMounter
            // can accept an SLA. Hand off to the system so the user can finish mounting.
            NSWorkspace.shared.open(url)
        }
        isDiskImageLicensePresented = false
    }

    // Quick Look Preview
    @Published public var previewURL: URL?

    public init(passwordBook: PasswordBook? = nil) {
        self.passwordBookOverride = passwordBook
        self.tasks = []
    }

    public var activeSession: ArchiveBrowsingSession? {
        guard let id = activeSessionID else { return nil }
        return sessions.first { $0.id == id }
    }

    public var activeTasksCount: Int {
        tasks.filter { $0.phase != .completed && $0.phase != .failed && $0.phase != .cancelled }.count
    }

    public var waitingTasksCount: Int {
        tasks.filter { $0.phase == .preparing || $0.phase == .starting }.count
    }

    public var failedTasksCount: Int {
        tasks.filter { $0.phase == .failed }.count
    }

    public var completedTasksCount: Int {
        tasks.filter { $0.phase == .completed }.count
    }

    // MARK: - Opening & Session Management

    public func importFiles(_ urls: [URL], honorMiniPreference: Bool = false) async throws -> [ArchiveBrowsingSession] {
        guard !isTerminationRequested else { throw ProZipError.cancelled }
        guard !urls.isEmpty else { return [] }
        try FileURLDrop.validateSources(urls)
        if await Self.areArchives(urls) { return urls.map { openArchive(at: $0, honorMiniPreference: honorMiniPreference) } }
        let session = createNewArchiveSession()
        do { try session.addFiles(urls) }
        catch { forceCloseSession(id: session.id); throw error }
        return [session]
    }

    private nonisolated static func areArchives(_ urls: [URL]) async -> Bool {
        for url in urls {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { return false }
            var format = ArchiveFormat.detect(from: url)
            if format == .unknown, let handle = try? FileHandle(forReadingFrom: url) {
                let header = try? handle.read(upToCount: 32)
                try? handle.close()
                format = ArchiveFormat.detect(from: url, magicBytes: header)
            }
            if format == .unknown { return false }
        }
        return true
    }

    @discardableResult
    public func openArchive(
        at url: URL,
        preferredMode: WorkspaceViewMode? = nil,
        honorMiniPreference: Bool = false,
        forceMiniMode: Bool = false
    ) -> ArchiveBrowsingSession {
        // Record in recent archives
        ProZipPreferences.shared.recordRecentArchive(url)

        // Check if already open
        if let existing = sessions.first(where: { $0.url.path == url.path }) {
            if forceMiniMode && !existing.isMiniMode {
                existing.isMiniMode = true
            }
            activeSessionID = existing.id
            return existing
        }

        let isMini = forceMiniMode || (honorMiniPreference && ProZipPreferences.shared.prefersMiniWindow)
        let mode = preferredMode ?? ProZipPreferences.shared.workspaceViewMode
        let format = ArchiveFormat.detect(from: url)
        let descriptor = ArchiveDescriptor(url: url, format: format)

        let session = ArchiveBrowsingSession(
            url: url,
            descriptor: descriptor,
            isMiniMode: isMini,
            viewMode: mode
        )
        sessions.append(session)
        activeSessionID = session.id

        // Begin indexing the archive
        loadArchiveIndex(for: session)
        return session
    }

    public func closeSession(id: UUID) {
        if let session = sessions.first(where: { $0.id == id }), session.hasUnsavedChanges {
            requestSaveConfirmation(for: session, conflict: false) { [weak self] in self?.forceCloseSession(id: id) }
            return
        }
        forceCloseSession(id: id)
    }

    public func forceCloseSession(id: UUID) {
        saveRequests.removeAll { $0.sessionID == id }
        creationRequests.removeAll { $0.owner == id }
        let cancelledConflicts = conflictRequests.filter { $0.owner == id }
        conflictRequests.removeAll { $0.owner == id }
        for request in cancelledConflicts { request.resolve(.skip) }
        if let request = activeConflictRequest, request.owner == id {
            completedConflictAction = { request.resolve(.skip) }
            conflictIsDismissing = true
            isConflictResolutionPresented = false
            conflictDialogDidDismiss()
        }
        extractionCompletionRequests.removeAll { $0.owner == id }
        if activeExtractionCompletion?.owner == id {
            completedExtractionArchiveURL = nil
            isTrashConfirmationPresented = false
            extractionCompletionDidDismiss()
        }
        let cancelledRequests = passwordRequests.filter { $0.session.id == id }
        passwordRequests.removeAll { $0.session.id == id }
        for request in cancelledRequests { request.onCancel?() }
        if activePasswordRequest?.session.id == id {
            submitPassword(nil)
            passwordPromptDidDismiss()
        }
        if renamingSessionID == id {
            renamingSessionID = nil
            renamingEntry = nil
            isRenameSheetPresented = false
        }
        indexOperations.removeValue(forKey: id)?.cancel()
        sessionPasswords.removeValue(forKey: id)
        sessions.removeAll { $0.id == id }
        recentSessionIDs.removeAll { $0 == id }
        if activeSessionID == id {
            activeSessionID = recentSessionIDs.last(where: { candidate in sessions.contains(where: { $0.id == candidate }) }) ?? sessions.last?.id
        }
        presentNextSaveConfirmation()
        advanceTermination()
    }

    @discardableResult
    public func createNewArchiveSession() -> ArchiveBrowsingSession {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ProZip-Drafts/\(UUID().uuidString)/未命名压缩包.zip")
        let session = ArchiveBrowsingSession(url: tempURL, descriptor: ArchiveDescriptor(url: tempURL, format: .zip))
        session.phase = .ready(totalCount: 0)
        session.isDraftEdited = true
        sessions.append(session)
        activeSessionID = session.id
        return session
    }

    // MARK: - Indexing Simulation & Integration

    public func loadArchiveIndex(for session: ArchiveBrowsingSession, password suppliedPassword: String? = nil) {
        let password = suppliedPassword ?? sessionPasswords[session.id]
        indexOperations[session.id]?.cancel()
        session.phase = .preliminary(loadedCount: 0)

        indexOperations[session.id] = Task {
            let fm = FileManager.default
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: session.url.path, isDirectory: &isDir) else {
                session.phase = .failed(message: "源文件不存在或已被移动")
                alertTitle = "无法打开压缩包"
                alertMessage = "源文件不存在或已被移动：\(session.archiveName)"
                isAlertPresented = true
                return
            }

            if isDir.boolValue {
                do {
                    let parsedEntries = try await Self.listDirectoryEntries(at: session.url)
                    try Task.checkCancellation()
                    try await session.loadEntries(parsedEntries)
                } catch {
                    guard !Task.isCancelled else { return }
                    session.phase = .failed(message: error.localizedDescription)
                }
                return
            }

            do {
                // Real archive: probe header, then parse the central directory.
                let descriptor = try await ArchiveEngineBroker.shared.probe(session.url)
                session.descriptor = descriptor
                let entries = try await ArchiveEngineBroker.shared.list(session.url, password: password)
                try Task.checkCancellation()
                if let password { rememberPassword(password, for: session) }
                for entry in entries { _ = try ArchiveExtractionPolicy.validateRelativeArchivePath(entry.path) }
                try await session.loadEntries(entries)
            } catch let error as ProZipError {
                guard !Task.isCancelled else { return }
                switch error {
                case .passwordRequired, .wrongPassword:
                    if password == nil, preferences.passwordBookAutoUnlock {
                        for candidate in passwordBook.candidatePasswords() {
                            do {
                                let entries = try await ArchiveEngineBroker.shared.list(session.url, password: candidate)
                                try Task.checkCancellation()
                                for entry in entries { _ = try ArchiveExtractionPolicy.validateRelativeArchivePath(entry.path) }
                                try await session.loadEntries(entries)
                                rememberPassword(candidate, for: session)
                                return
                            } catch { if Task.isCancelled { return } }
                        }
                    }
                    await MainActor.run {
                        self.presentPasswordPrompt(for: session, message: password == nil ? "请输入 \(session.archiveName) 的解密密码" : "密码不正确，请重试。", onCancel: { session.phase = .failed(message: "操作已取消") }) { entered in
                            self.loadArchiveIndex(for: session, password: entered)
                        }
                    }
                case .licenseAgreementRequired(let name):
                    session.phase = .ready(totalCount: 0)
                    diskImageName = session.url.lastPathComponent
                    diskImageLicenseText = name
                    pendingLicenseArchiveURL = session.url
                    isDiskImageLicensePresented = true
                case .unsafePath(let path):
                    session.phase = .failed(message: "压缩包包含不安全路径")
                    self.alertTitle = "无法完成操作"
                    self.alertMessage = "压缩包包含不安全路径：\(path)"
                    self.isAlertPresented = true
                default:
                    session.phase = .failed(message: error.errorDescription ?? "无法读取压缩包")
                    self.alertTitle = "无法完成操作"
                    self.alertMessage = error.errorDescription ?? "无法读取压缩包"
                    self.isAlertPresented = true
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                session.phase = .failed(message: error.localizedDescription)
            }
        }
    }

    private nonisolated static func listDirectoryEntries(at root: URL) async throws -> [ArchiveEntry] {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys)) else {
            throw ProZipError.invalidArchive("无法读取文件夹内容")
        }
        var entries: [ArchiveEntry] = []
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        while let url = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            let values = try url.resourceValues(forKeys: keys)
            let path = String(url.path.dropFirst(prefix.count))
            let isSymlink = values.isSymbolicLink == true
            entries.append(ArchiveEntry(
                path: path,
                type: isSymlink ? .symlink : (values.isDirectory == true ? .directory : .file),
                uncompressedSize: Int64(values.fileSize ?? 0),
                compressedSize: Int64(values.fileSize ?? 0),
                modifiedAt: values.contentModificationDate ?? Date(),
                symlinkTarget: isSymlink ? try FileManager.default.destinationOfSymbolicLink(atPath: url.path) : nil
            ))
        }
        return entries
    }

    /// Applies pending draft mutations through the engine and atomically replaces the source archive.
    public func saveChanges(for session: ArchiveBrowsingSession, completion: (() -> Void)? = nil) {
        guard !session.pendingMutations.isEmpty else { completion?(); return }
        guard !savingSessionIDs.contains(session.id) else { return }
        if session.initialSourceStat == nil, !FileManager.default.fileExists(atPath: session.url.path) {
            prepareDraftCreation(for: session, completion: completion)
            return
        }
        guard !session.hasSourceArchiveChangedOnDisk() else {
            requestSaveConfirmation(for: session, conflict: true, completion: completion)
            return
        }
        savingSessionIDs.insert(session.id)
        let sourceURL = session.url
        let fm = FileManager.default
        let tempURL = sourceURL.deletingLastPathComponent()
            .appendingPathComponent(".prozip-save-\(UUID().uuidString).\(sourceURL.pathExtension.isEmpty ? "zip" : sourceURL.pathExtension)")
        let mutations = session.pendingMutations
        var profile = CreationProfile(format: session.safeDescriptor.format)
        profile.password = sessionPasswords[session.id]
        profile.encryptHeaders = session.safeDescriptor.hasEncryptedHeaders

        let task = ArchiveTaskRecord(
            title: "保存修改 \(session.archiveName)",
            archiveURL: sourceURL,
            phase: .savingSafely,
            totalBytes: max(1024, session.safeDescriptor.totalCompressedSize),
            outputResultURL: sourceURL
        )
        tasks.insert(task, at: 0)
        isTaskProgressPresented = true

        let operation = Task {
            var succeeded = false
            defer {
                task.clearCancellation()
                savingSessionIDs.remove(session.id)
                if succeeded { advanceTermination() } else { cancelTermination() }
            }
            do {
                try await ArchiveEngineBroker.shared.applyMutations(
                    mutations,
                    to: sourceURL,
                    outputURL: tempURL,
                    profile: profile,
                    password: profile.password
                ) { progress in
                    if progress.phase != .completed {
                        Task { @MainActor in task.update(progress: progress) }
                    }
                }

                try Task.checkCancellation()
                guard !session.hasSourceArchiveChangedOnDisk(), session.pendingMutations == mutations else {
                    throw ProZipError.structureConflict("保存期间源压缩包或待保存内容发生变化，请重新确认后保存。")
                }
                // Atomically publish only after rechecking the source and the draft.
                _ = try fm.replaceItemAt(sourceURL, withItemAt: tempURL)
                session.captureSourceStat()

                await MainActor.run {
                    task.update(progress: OperationProgress(
                        phase: .completed,
                        completedBytes: task.totalBytes,
                        totalBytes: task.totalBytes,
                        currentItem: "已保存",
                        fractionCompleted: 1.0
                    ))
                }
                session.acceptSavedChanges()
                succeeded = true
                self.loadArchiveIndex(for: session)
                completion?()
            } catch is CancellationError {
                try? fm.removeItem(at: tempURL)
                task.cancel()
            } catch let error as ProZipError where error == .cancelled {
                try? fm.removeItem(at: tempURL)
                task.cancel()
            } catch let error as ProZipError {
                try? fm.removeItem(at: tempURL)
                await MainActor.run {
                    task.update(progress: OperationProgress(
                        phase: .failed,
                        completedBytes: 0,
                        totalBytes: task.totalBytes,
                        currentItem: error.errorDescription ?? "保存失败",
                        fractionCompleted: 0
                    ))
                    self.alertTitle = "无法保存修改"
                    self.alertMessage = error.errorDescription ?? "保存失败"
                    self.isAlertPresented = true
                }
            } catch {
                try? fm.removeItem(at: tempURL)
                await MainActor.run {
                    task.update(progress: OperationProgress(
                        phase: .failed,
                        completedBytes: 0,
                        totalBytes: task.totalBytes,
                        currentItem: error.localizedDescription,
                        fractionCompleted: 0
                    ))
                }
            }
        }
        task.bindCancellation(to: operation)
    }

    private func requestSaveConfirmation(for session: ArchiveBrowsingSession, conflict: Bool, completion: (() -> Void)? = nil) {
        if isSaveChangesPresented {
            if saveConfirmationSessionID != session.id, !saveRequests.contains(where: { $0.sessionID == session.id }) {
                saveRequests.append(SaveRequest(sessionID: session.id, conflict: conflict, completion: completion))
            }
            return
        }
        saveConfirmationSessionID = session.id
        saveConfirmationCompletion = completion
        saveChangesArchiveName = session.archiveName
        saveChangesIsSourceModifiedConflict = conflict
        presentDialog(\.isSaveChangesPresented, for: session.id)
    }

    private func presentNextSaveConfirmation() {
        guard !isSaveChangesPresented else { return }
        while !saveRequests.isEmpty {
            let request = saveRequests.removeFirst()
            if let session = sessions.first(where: { $0.id == request.sessionID }) {
                requestSaveConfirmation(for: session, conflict: request.conflict, completion: request.completion)
                return
            }
        }
    }

    public func confirmSaveChanges(merge: Bool = false) {
        guard let id = saveConfirmationSessionID, let session = sessions.first(where: { $0.id == id }) else { return }
        let completion = saveConfirmationCompletion
        confirmedSaveContinuation = { [weak self] in
            if merge { session.captureSourceStat() }
            self?.saveChanges(for: session, completion: completion)
        }
        saveConfirmationCompletion = nil
        isSaveChangesPresented = false
    }

    public func performConfirmedSave() {
        let continuation = confirmedSaveContinuation
        confirmedSaveContinuation = nil
        saveConfirmationSessionID = nil
        continuation?()
        presentNextSaveConfirmation()
    }

    public func cancelSaveChanges() {
        clearSaveConfirmation()
        cancelTermination()
    }

    private func clearSaveConfirmation() {
        confirmedSaveContinuation = nil
        saveConfirmationCompletion = nil
        saveConfirmationSessionID = nil
        isSaveChangesPresented = false
    }

    public func discardSaveChanges(reload: Bool = false) {
        guard let id = saveConfirmationSessionID, let session = sessions.first(where: { $0.id == id }) else { return }
        let completion = saveConfirmationCompletion
        clearSaveConfirmation()
        if !reload, let completion { completion(); return }
        Task {
            await session.discardChanges()
            loadArchiveIndex(for: session)
        }
    }

    private func prepareDraftCreation(for session: ArchiveBrowsingSession, completion: (() -> Void)?) {
        guard !savingSessionIDs.contains(session.id) else { return }
        savingSessionIDs.insert(session.id)
        let mutations = session.pendingMutations
        Task { [self] in
            defer { savingSessionIDs.remove(session.id) }
            do {
                let staged = try await Self.prepareNewArchiveDraft(mutations)
                guard session.pendingMutations == mutations else { throw ProZipError.structureConflict("准备期间待保存内容发生变化，请重试。") }
                let created: (URL) -> Void = { [weak self] url in
                    Task { @MainActor in
                        session.archiveURL = url
                        session.acceptSavedChanges()
                        self?.loadArchiveIndex(for: session)
                        completion?()
                    }
                }
                enqueueCreation(CreationRequest(sources: staged.sources, originalSources: staged.originalSources, owner: session.id, completion: created, draftSessionID: session.id, sourcesToTrash: staged.sourcesToTrash))
            } catch {
                cancelTermination()
                alertTitle = "无法准备压缩包"
                alertMessage = error.localizedDescription
                isAlertPresented = true
            }
        }
    }

    // shortcut: staging preserves edited paths before the creation dialog; a mapped-source writer would avoid copies for very large drafts.
    public nonisolated static func stageNewArchiveDraft(_ mutations: [ArchiveMutation]) async throws -> [URL] {
        try await prepareNewArchiveDraft(mutations).sources
    }

    private nonisolated static func prepareNewArchiveDraft(_ mutations: [ArchiveMutation]) async throws -> (sources: [URL], originalSources: [URL], sourcesToTrash: [URL]) {
        let root = try await ManagedTemporaryArtifactRegistry.shared.createManagedTemporaryDirectory(purpose: "creation-draft")
        let fm = FileManager.default
        // Merged directories may belong to several originals; overwritten leaves retain only their latest owner.
        var owners: [String: Set<Int>] = [:]
        var originals: [(url: URL, itemCount: Int)] = []
        func target(_ path: String) throws -> URL {
            let relative = try ArchiveExtractionPolicy.validateRelativeArchivePath(path)
            let url = root.appendingPathComponent(relative)
            try ArchiveExtractionPolicy.validateDestinationDirectory(url.deletingLastPathComponent())
            return url
        }
        func exists(_ url: URL) -> Bool {
            fm.fileExists(atPath: url.path) || (try? fm.destinationOfSymbolicLink(atPath: url.path)) != nil
        }
        func relativePath(of url: URL) -> String { String(url.path.dropFirst(root.path.count + 1)) }
        func removeOwners(under path: String) {
            owners = owners.filter { $0.key != path && !$0.key.hasPrefix(path + "/") }
        }
        func recordSourceTree(_ source: URL, copiedTo destination: URL, owner: Int) throws -> Int {
            var itemCount = 0
            var pending = [(source, relativePath(of: destination))]
            while let (item, path) = pending.popLast() {
                try Task.checkCancellation()
                owners[path, default: []].insert(owner)
                itemCount += 1
                if try fm.attributesOfItem(atPath: item.path)[.type] as? FileAttributeType == .typeDirectory {
                    // Enumeration can resolve /var to /private/var; carry archive paths explicitly.
                    for child in try fm.contentsOfDirectory(at: item, includingPropertiesForKeys: nil) {
                        pending.append((child, path + "/" + child.lastPathComponent))
                    }
                }
            }
            return itemCount
        }
        func copySource(_ source: URL, to destination: URL, owner: Int?, mergingDirectories: Bool = true) throws -> Int {
            try Task.checkCancellation()
            try ArchiveExtractionPolicy.validateDestinationDirectory(destination.deletingLastPathComponent())
            let attributes = try fm.attributesOfItem(atPath: source.path)
            let destinationExists = exists(destination)
            if destinationExists {
                let actualName = try destination.resourceValues(forKeys: [.nameKey]).name
                guard actualName == destination.lastPathComponent else {
                    throw ProZipError.structureConflict("暂存位置不支持仅大小写不同的同名项目：\(destination.lastPathComponent)")
                }
            }
            if mergingDirectories, attributes[.type] as? FileAttributeType == .typeDirectory,
               destinationExists, try fm.attributesOfItem(atPath: destination.path)[.type] as? FileAttributeType == .typeDirectory {
                let path = relativePath(of: destination)
                if let owner { owners[path, default: []].insert(owner) }
                var count = 1
                for child in try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
                    count += try copySource(child, to: destination.appendingPathComponent(child.lastPathComponent), owner: owner)
                }
                try fm.setAttributes(attributes.filter { $0.key == .posixPermissions || $0.key == .modificationDate }, ofItemAtPath: destination.path)
                return count
            }
            if destinationExists { try fm.removeItem(at: destination) }
            removeOwners(under: relativePath(of: destination))
            try fm.copyItem(at: source, to: destination)
            return try owner.map { try recordSourceTree(source, copiedTo: destination, owner: $0) } ?? 0
        }
        do {
            for mutation in mutations {
                try Task.checkCancellation()
                switch mutation {
                case .addFile(let source, let path):
                    let destination = try target(path)
                    try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    let count = try copySource(source, to: destination, owner: originals.count)
                    originals.append((source, count))
                case .replaceEntry(let path, let source):
                    let destination = try target(path)
                    try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    _ = try copySource(source, to: destination, owner: nil, mergingDirectories: false)
                case .deleteEntry(let path):
                    let destination = try target(path)
                    if exists(destination) { try fm.removeItem(at: destination) }
                    removeOwners(under: relativePath(of: destination))
                case .renameEntry(let oldPath, let newPath):
                    let source = try target(oldPath)
                    let destination = try target(newPath)
                    try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.moveItem(at: source, to: destination)
                    let old = relativePath(of: source)
                    let new = relativePath(of: destination)
                    let moved = owners.filter { $0.key == old || $0.key.hasPrefix(old + "/") }
                    removeOwners(under: old)
                    for (path, owner) in moved { owners[new + path.dropFirst(old.count)] = owner }
                }
            }
            let counts = owners.values.reduce(into: [Int: Int]()) { counts, owners in
                for owner in owners { counts[owner, default: 0] += 1 }
            }
            var seen = Set<URL>()
            let originalSources = originals.enumerated().compactMap { offset, original -> URL? in
                guard counts[offset, default: 0] > 0, seen.insert(original.url.standardizedFileURL).inserted else { return nil }
                return original.url
            }
            seen.removeAll()
            let sourcesToTrash = originals.enumerated().compactMap { offset, original -> URL? in
                guard counts[offset] == original.itemCount, seen.insert(original.url.standardizedFileURL).inserted else { return nil }
                return original.url
            }
            let sources = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            return (sources, originalSources, sourcesToTrash)
        } catch {
            try? fm.removeItem(at: root)
            throw error
        }
    }

    // MARK: - Flow Action Execution

    public func executeFlowAction(_ recommendation: FlowActionRecommendation, in session: ArchiveBrowsingSession) {
        switch recommendation.actionID {
        case .extractAll:
            extractAll(in: session)

        case .extractSelection:
            extractSelection(session.selectedEntries, in: session)

        case .extractDirectory:
            if let dir = session.selectedEntries.first(where: { $0.isDirectory }) {
                extractSelection([dir], in: session)
            } else {
                extractAll(in: session)
            }

        case .openFile:
            if let entry = session.selectedEntries.first {
                openEntryExternally(entry, in: session)
            }

        case .installApplication:
            if let entry = session.selectedEntries.first { installApplication(entry, in: session) }

        case .openDiskImageApplication, .diskImageApplicationPrefersOpen:
            if let entry = session.selectedEntries.first { openDiskImageApplication(entry, in: session) }

        case .installFont:
            if let entry = session.selectedEntries.first {
                installFont(entry, in: session)
            }

        case .installPackage:
            if let entry = session.selectedEntries.first {
                installPackage(entry, in: session)
            }

        case .addFiles:
            promptAddFiles(to: session)

        case .openInstalledApplication, .unavailable, .openFileAllowedExtensions:
            break
        }
    }

    private static let unsavedExtractionMessage = "压缩包有未保存的修改，请先保存后再解压。"

    private func rejectPendingExtraction(in session: ArchiveBrowsingSession) -> Bool {
        guard session.hasUnsavedChanges else { return false }
        alertTitle = "请先保存修改"
        alertMessage = Self.unsavedExtractionMessage
        isAlertPresented = true
        return true
    }

    public func extractAll(in session: ArchiveBrowsingSession, to suppliedDestination: URL? = nil) {
        guard !rejectPendingExtraction(in: session) else { return }
        guard session.initialSourceStat != nil else { return }
        let destination = suppliedDestination ?? ArchiveExtractionPolicy.defaultDestinationFolder(for: session.url)
        startExtraction(selection: nil, session: session, destination: destination)
    }

    /// Finder quick actions reuse an open draft so its unsaved-change and password state still apply.
    public func sessionForExternalExtraction(at url: URL) -> ArchiveBrowsingSession {
        if let existing = sessions.first(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) { return existing }
        let session = ArchiveBrowsingSession(url: url, isMiniMode: preferences.prefersMiniWindow, viewMode: preferences.workspaceViewMode)
        sessions.append(session)
        activeSessionID = session.id
        preferences.recordRecentArchive(url)
        // Extraction populates the index; do not start a second indexing operation here.
        return session
    }

    public func extractSelection(_ entries: [ArchiveEntry], in session: ArchiveBrowsingSession, to destination: URL? = nil) {
        guard !rejectPendingExtraction(in: session) else { return }
        guard session.initialSourceStat != nil else { return }
        guard !entries.isEmpty else { return }
        let selectedDestination: URL
        if let suppliedDestination = destination {
            selectedDestination = suppliedDestination
        } else {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.prompt = "解压"
            panel.directoryURL = session.url.deletingLastPathComponent()
            guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
            selectedDestination = selectedURL
        }
        startExtraction(selection: entries, session: session, destination: selectedDestination)
    }

    /// Read the complete index so directory navigation and search never narrow an extraction.
    public func extractionEntries(for selection: [ArchiveEntry]?, in session: ArchiveBrowsingSession, password: String? = nil) async throws -> [ArchiveEntry] {
        guard !session.hasUnsavedChanges else { throw ProZipError.structureConflict(Self.unsavedExtractionMessage) }
        let entries = try await archivedExtractionEntries(for: selection, in: session, password: password)
        guard !session.hasUnsavedChanges else { throw ProZipError.structureConflict(Self.unsavedExtractionMessage) }
        return entries
    }

    private func archivedExtractionEntries(for selection: [ArchiveEntry]?, in session: ArchiveBrowsingSession, password: String?) async throws -> [ArchiveEntry] {
        let allEntries: [ArchiveEntry]
        if case .ready = session.phase {
            allEntries = try await session.index.allEntries(includeAuxiliary: true)
        } else {
            let url = session.url
            session.phase = .preliminary(loadedCount: 0)
            do {
                let descriptor = try await ArchiveEngineBroker.shared.probe(url)
                allEntries = try await ArchiveEngineBroker.shared.list(url, password: password)
                guard session.url == url else { throw ProZipError.structureConflict("源压缩包位置已发生变化，请重试。") }
                session.descriptor = descriptor
                try await session.loadEntries(allEntries)
            } catch {
                session.phase = .failed(message: error.localizedDescription)
                throw error
            }
        }
        guard let selection else { return allEntries }
        guard !selection.isEmpty else { throw ProZipError.structureConflict("没有可解压的所选项目，请重新选择。") }
        let entriesByID = allEntries.reduce(into: [String: ArchiveEntry]()) { $0[$1.id] = $1 }
        let nonDirectoryPaths = Set(allEntries.filter { !$0.isDirectory }.map(\.path))
        var directoryPaths = Set<String>()
        for entry in allEntries {
            if entry.isDirectory { directoryPaths.insert(entry.path) }
            var parent = entry.parentPath
            while !parent.isEmpty {
                directoryPaths.insert(parent)
                parent = (parent as NSString).deletingLastPathComponent
            }
        }
        var virtualDirectories: [ArchiveEntry] = []
        for selected in selection {
            if let current = entriesByID[selected.id], current.path == selected.path, current.type == selected.type { continue }
            guard selected.isDirectory, directoryPaths.contains(selected.path), !nonDirectoryPaths.contains(selected.path) else {
                throw ProZipError.structureConflict("所选项目已不在当前压缩包目录中，请重新载入并选择：\(selected.path)")
            }
            virtualDirectories.append(selected)
        }
        let selectedIDs = Set(selection.map(\.id))
        let directories = Set(selection.filter(\.isDirectory).map(\.path))
        let selectedEntries = allEntries.filter { entry in
            if selectedIDs.contains(entry.id) { return true }
            var parent = entry.parentPath
            while !parent.isEmpty {
                if directories.contains(parent) { return true }
                parent = (parent as NSString).deletingLastPathComponent
            }
            return false
        }
        return selectedEntries + virtualDirectories
    }

    private func startExtraction(selection: [ArchiveEntry]?, session: ArchiveBrowsingSession, destination: URL) {
        let task = ArchiveTaskRecord(
            title: selection.map { "解压所选项目 (\($0.count))" } ?? "全部解压 \(session.archiveName)",
            archiveURL: session.url,
            phase: .preparing,
            totalBytes: max(1000, session.safeDescriptor.totalCompressedSize),
            outputResultURL: destination
        )
        tasks.insert(task, at: 0)
        isTaskProgressPresented = true
        var candidates = preferences.passwordBookAutoUnlock ? passwordBook.candidatePasswords() : []
        let password = sessionPasswords[session.id] ?? candidates.first
        candidates.removeAll { $0 == password }
        runExtraction(selection: selection, session: session, destination: destination, task: task, password: password, remainingPasswords: candidates)
    }

    private func runExtraction(
        selection: [ArchiveEntry]?,
        session: ArchiveBrowsingSession,
        destination: URL,
        task: ArchiveTaskRecord,
        password: String?,
        conflictResolution: ConflictResolution = .ask,
        remainingPasswords: [String] = [],
        sourceStat suppliedSourceStat: SourceArchiveStat? = nil
    ) {
        guard task.phase != .cancelled else { return }
        let archiveURL = task.archiveURL
        let sourceStat = suppliedSourceStat ?? SourceArchiveStat.read(from: archiveURL)
        let operation = Task { [self] in
            defer { task.clearCancellation() }
            do {
                let entries = try await extractionEntries(for: selection, in: session, password: password)
                try Task.checkCancellation()
                guard session.url == archiveURL, sourceStat != nil, SourceArchiveStat.read(from: archiveURL) == sourceStat else {
                    throw ProZipError.structureConflict("源压缩包已发生变化，请重新载入后再解压。")
                }
                var options = ExtractionOptions()
                options.filterSystemAuxiliaryFiles = preferences.filtersSystemAuxiliaryFiles
                options.filterDMGInstallerArtifacts = preferences.filtersDMGInstallerArtifacts
                options.explicitlySelectedEntryIDs = Set(selection?.map(\.id) ?? [])
                options.conflictResolution = conflictResolution
                let plan = try ArchiveExtractionPolicy.buildPlan(entries: entries, archiveURL: archiveURL, destinationURL: destination, options: options)
                if conflictResolution == .ask,
                   let conflict = plan.itemsToExtract.first(where: {
                       !$0.entry.isDirectory && FileManager.default.fileExists(atPath: $0.destinationURL.path)
                   }) {
                    let values = try? conflict.destinationURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                    let conflictItem = ConflictItemInfo(
                        fileName: conflict.destinationURL.lastPathComponent,
                        destinationPath: conflict.destinationURL.deletingLastPathComponent().path,
                        existingSize: Int64(values?.fileSize ?? 0),
                        existingModifiedAt: values?.contentModificationDate ?? Date(),
                        incomingSize: conflict.entry.uncompressedSize,
                        incomingModifiedAt: conflict.entry.modifiedAt
                    )
                    let owner = sessions.contains(where: { $0.id == session.id }) ? session.id : activeSessionID
                    requestConflictResolution(conflictItem, owner: owner) { [weak self] resolution in
                        guard resolution == .replace || resolution == .keepBoth else {
                            task.cancel()
                            return
                        }
                        self?.runExtraction(selection: selection, session: session, destination: destination, task: task, password: password, conflictResolution: resolution, remainingPasswords: remainingPasswords, sourceStat: sourceStat)
                    }
                    return
                }
                let report = try await ArchiveEngineBroker.shared.extract(
                    entries,
                    from: archiveURL,
                    to: destination,
                    password: password,
                    options: options
                ) { progress in
                    if progress.phase != .completed {
                        Task { @MainActor in task.update(progress: progress) }
                    }
                }
                try Task.checkCancellation()
                if let password { rememberPassword(password, for: session) }
                task.outputResultURL = report.destinationURL
                task.update(progress: OperationProgress(
                    phase: report.failedCount == 0 ? .completed : .failed,
                    completedBytes: task.totalBytes,
                    totalBytes: task.totalBytes,
                    currentItem: report.failedCount == 0 ? "解压完成（\(report.extractedCount) 项）" : "已解压可用内容，跳过 \(report.failedCount) 个文件；源压缩包已保留。",
                    fractionCompleted: 1
                ))
                if preferences.automaticallySelectsResults, report.extractedCount > 0 {
                    NSWorkspace.shared.activateFileViewerSelecting([report.destinationURL])
                }
                guard selection == nil, report.isFullSuccess, !session.hasUnsavedChanges else { return }
                if preferences.extractionCompletionAction == .ask {
                    isTaskProgressPresented = false
                    enqueueExtractionCompletion(for: session, archiveURL: archiveURL, sourceStat: sourceStat)
                } else if preferences.extractionCompletionAction == .trash {
                    guard canRemoveExtractedSource(at: archiveURL, expectedStat: sourceStat) else { return }
                    try FileManager.default.trashItem(at: archiveURL, resultingItemURL: nil)
                    forceCloseSession(id: session.id)
                } else if preferences.automaticallyClosesArchive {
                    guard canRemoveExtractedSource(at: archiveURL, expectedStat: sourceStat) else { return }
                    forceCloseSession(id: session.id)
                }
            } catch is CancellationError {
                task.cancel()
            } catch let error as ProZipError {
                switch error {
                case .cancelled:
                    task.cancel()
                case .passwordRequired, .wrongPassword:
                    if let nextPassword = remainingPasswords.first {
                        DispatchQueue.main.async {
                            self.runExtraction(selection: selection, session: session, destination: destination, task: task, password: nextPassword, conflictResolution: conflictResolution, remainingPasswords: Array(remainingPasswords.dropFirst()), sourceStat: sourceStat)
                        }
                        return
                    }
                    presentPasswordPrompt(for: session, message: "请输入 \(session.archiveName) 的解密密码", onCancel: { task.cancel() }) { entered in
                        self.runExtraction(selection: selection, session: session, destination: destination, task: task, password: entered, conflictResolution: conflictResolution, sourceStat: sourceStat)
                    }
                default:
                    fail(task, title: "无法完成操作", error: error)
                }
            } catch {
                fail(task, title: "无法完成操作", error: error)
            }
        }
        task.bindCancellation(to: operation)
    }

    @Published public var completedExtractionArchiveURL: URL?

    private func enqueueExtractionCompletion(for session: ArchiveBrowsingSession, archiveURL: URL, sourceStat: SourceArchiveStat?) {
        let owner = sessions.contains(where: { $0.id == session.id }) ? session.id : activeSessionID
        let request = ExtractionCompletionRequest(archiveURL: archiveURL, sourceStat: sourceStat, owner: owner)
        if isTrashConfirmationPresented || extractionCompletionIsDismissing { extractionCompletionRequests.append(request); return }
        showExtractionCompletion(request)
    }

    private func showExtractionCompletion(_ request: ExtractionCompletionRequest) {
        activeExtractionCompletion = request
        completedExtractionArchiveURL = request.archiveURL
        trashTargetArchiveName = request.archiveURL.lastPathComponent
        presentDialog(\.isTrashConfirmationPresented, for: request.owner)
    }

    public func resolveExtractionCompletion(moveToTrash: Bool) {
        guard let url = completedExtractionArchiveURL else { return }
        completedExtractionArchiveURL = nil
        extractionCompletionIsDismissing = true
        isTrashConfirmationPresented = false
        if moveToTrash || preferences.automaticallyClosesArchive {
            guard canRemoveExtractedSource(at: url, expectedStat: activeExtractionCompletion?.sourceStat) else { return }
        }
        if moveToTrash {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                for session in sessions where session.url == url { forceCloseSession(id: session.id) }
            } catch {
                alertTitle = "解压已完成，但无法将原压缩包移入废纸篓"
                alertMessage = error.localizedDescription
                isAlertPresented = true
            }
        } else if preferences.automaticallyClosesArchive {
            for session in sessions where session.url == url { forceCloseSession(id: session.id) }
        }
    }

    private func canRemoveExtractedSource(at url: URL, expectedStat: SourceArchiveStat?) -> Bool {
        let dirty = sessions.contains { $0.url.standardizedFileURL == url.standardizedFileURL && $0.hasUnsavedChanges }
        guard !dirty, let expectedStat, SourceArchiveStat.read(from: url) == expectedStat else {
            alertTitle = "已保留原压缩包"
            alertMessage = dirty ? Self.unsavedExtractionMessage : "源压缩包在解压后发生变化，请核对新版本后再处理。"
            isAlertPresented = true
            return false
        }
        return true
    }

    public func extractionCompletionDidDismiss() {
        guard !isTrashConfirmationPresented, activeExtractionCompletion != nil else { return }
        if completedExtractionArchiveURL != nil { resolveExtractionCompletion(moveToTrash: false) }
        activeExtractionCompletion = nil
        extractionCompletionIsDismissing = false
        if !extractionCompletionRequests.isEmpty { showExtractionCompletion(extractionCompletionRequests.removeFirst()) }
    }

    private func fail(_ task: ArchiveTaskRecord, title: String, error: Error) {
        guard task.phase != .cancelled else { return }
        task.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        task.update(progress: OperationProgress(phase: .failed, totalBytes: task.totalBytes, currentItem: task.errorMessage))
        alertTitle = title
        alertMessage = task.errorMessage ?? error.localizedDescription
        isAlertPresented = true
    }

    public func openEntryExternally(_ entry: ArchiveEntry, in session: ArchiveBrowsingSession) {
        openEntryExternally(entry, in: session, password: sessionPasswords[session.id])
    }

    private func openEntryExternally(_ entry: ArchiveEntry, in session: ArchiveBrowsingSession, password: String?) {
        Task {
            do {
                let fileURL = try await exportEntry(entry, in: session, password: password)
                if let password { rememberPassword(password, for: session) }
                guard NSWorkspace.shared.open(fileURL) else {
                    throw ProZipError.invalidArchive("没有可用于打开 \(entry.name) 的应用程序")
                }
            } catch let error as ProZipError {
                switch error {
                case .passwordRequired, .wrongPassword:
                    await MainActor.run {
                        self.presentPasswordPrompt(for: session, message: "打开 \(entry.name) 需要密码") { entered in
                            self.openEntryExternally(entry, in: session, password: entered)
                        }
                    }
                default:
                    NSLog("[ProZip] Open entry failed: \(error)")
                }
            } catch {
                NSLog("[ProZip] Open entry failed: \(error)")
            }
        }
    }

    public func installApplication(_ entry: ArchiveEntry, in session: ArchiveBrowsingSession) {
        let task = ArchiveTaskRecord(
            title: "安装 \(entry.name) 到“应用程序”",
            archiveURL: session.url,
            phase: .preparing,
            totalBytes: max(1, entry.uncompressedSize),
            isCancelable: true
        )
        tasks.insert(task, at: 0)
        isTaskProgressPresented = true
        runApplicationInstallation(entry, in: session, task: task, password: sessionPasswords[session.id])
    }

    private func runApplicationInstallation(_ entry: ArchiveEntry, in session: ArchiveBrowsingSession, task: ArchiveTaskRecord, password: String?) {
        let operation = Task {
            defer { task.clearCancellation() }
            do {
                let appURL: URL
                if session.safeDescriptor.format.isDiskImage {
                    let mounted = try await diskImageEngine.mountReadOnly(session.url, password: password)
                    appURL = mounted.mountPoint.appendingPathComponent(entry.path)
                } else {
                    let entries = try await extractionEntries(for: [entry], in: session, password: password)
                    let directory = try await ManagedTemporaryArtifactRegistry.shared.createManagedTemporaryDirectory(purpose: "application-installation")
                    var options = ExtractionOptions(filterSystemAuxiliaryFiles: false, filterDMGInstallerArtifacts: false)
                    options.stripSingleRootFolderIfMatching = false
                    let report = try await ArchiveEngineBroker.shared.extract(entries, from: session.url, to: directory, password: password, options: options) { progress in
                        if progress.phase != .completed {
                        Task { @MainActor in task.update(progress: progress) }
                    }
                    }
                    guard report.failedCount == 0 else {
                        throw ProZipError.installationError(stage: "extract-application", reason: report.errors.joined(separator: "\n"))
                    }
                    appURL = directory.appendingPathComponent(entry.path)
                }
                try Task.checkCancellation()
                let installedURL = try await diskImageEngine.installApplication(
                    from: appURL,
                    quickInstallRemoveQuarantine: preferences.quickInstallApplication,
                    allowReplace: false
                ) { stage in
                    Task { @MainActor in
                        task.update(progress: OperationProgress(phase: .savingSafely, totalBytes: task.totalBytes, currentItem: stage.rawValue))
                    }
                }
                try Task.checkCancellation()
                if let password { rememberPassword(password, for: session) }
                task.outputResultURL = installedURL
                task.update(progress: OperationProgress(phase: .completed, completedBytes: task.totalBytes, totalBytes: task.totalBytes, currentItem: "安装完成", fractionCompleted: 1))
                if preferences.installAutomaticallyClosesArchive { forceCloseSession(id: session.id) }
            } catch is CancellationError {
                task.cancel()
            } catch let error as ProZipError where error == .cancelled {
                task.cancel()
            } catch let error as ProZipError {
                switch error {
                case .passwordRequired, .wrongPassword:
                    presentPasswordPrompt(for: session, message: "安装 \(entry.name) 需要密码", onCancel: { task.cancel() }) { password in
                        self.runApplicationInstallation(entry, in: session, task: task, password: password)
                    }
                default:
                    fail(task, title: "无法安装应用程序", error: error)
                }
            } catch {
                fail(task, title: "无法安装应用程序", error: error)
            }
        }
        task.bindCancellation(to: operation)
    }

    public func openDiskImageApplication(_ entry: ArchiveEntry, in session: ArchiveBrowsingSession) {
        Task {
            do {
                let mounted = try await diskImageEngine.mountReadOnly(session.url, password: sessionPasswords[session.id])
                _ = try ArchiveExtractionPolicy.validateRelativeArchivePath(entry.path)
                let appURL = mounted.mountPoint.appendingPathComponent(entry.path)
                guard NSWorkspace.shared.open(appURL) else { throw ProZipError.invalidArchive("无法打开 \(entry.name)") }
            } catch {
                alertTitle = "无法打开应用程序"
                alertMessage = error.localizedDescription
                isAlertPresented = true
            }
        }
    }

    public func installFont(_ entry: ArchiveEntry, in session: ArchiveBrowsingSession) {
        let task = ArchiveTaskRecord(title: "安装字体 \(entry.name)", archiveURL: session.url, phase: .preparing, totalBytes: max(1, entry.uncompressedSize))
        tasks.insert(task, at: 0)
        isTaskProgressPresented = true
        let password = sessionPasswords[session.id]
        let operation = Task {
            defer { task.clearCancellation() }
            do {
                let fileURL = try await Self.materializeMember(entry, in: session.url, password: password)
                try Task.checkCancellation()
                let engine = diskImageEngine
                let installedURL = try await Task.detached {
                    try engine.installFont(at: fileURL, allowReplace: false)
                }.value
                try Task.checkCancellation()
                task.outputResultURL = installedURL
                task.update(progress: OperationProgress(phase: .completed, completedBytes: task.totalBytes, totalBytes: task.totalBytes, currentItem: "安装完成", fractionCompleted: 1))
            } catch is CancellationError {
                task.cancel()
            } catch {
                fail(task, title: "无法安装字体", error: error)
            }
        }
        task.bindCancellation(to: operation)
    }

    public func installPackage(_ entry: ArchiveEntry, in session: ArchiveBrowsingSession) {
        openEntryExternally(entry, in: session)
    }

    public func promptAddFiles(to session: ArchiveBrowsingSession) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "添加"
        guard panel.runModal() == .OK else { return }
        do {
            try session.addFiles(panel.urls)
        } catch {
            alertTitle = "无法添加文件"
            alertMessage = error.localizedDescription
            isAlertPresented = true
        }
    }

    public func beginRenaming(_ entry: ArchiveEntry, in session: ArchiveBrowsingSession) {
        renamingSessionID = session.id
        renamingEntry = entry
        renameInput = entry.name
        isRenameSheetPresented = true
    }

    public func commitEntryRename() throws {
        guard let id = renamingSessionID, let session = sessions.first(where: { $0.id == id }), let entry = renamingEntry else {
            throw ProZipError.invalidArchive("重命名的归档窗口已关闭")
        }
        try session.renameEntry(entry, to: renameInput.trimmingCharacters(in: .whitespacesAndNewlines))
        isRenameSheetPresented = false
        renamingEntry = nil
        renamingSessionID = nil
    }

    public func renameArchive(_ session: ArchiveBrowsingSession, to name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != ".", trimmed != "..", !trimmed.contains("/"), !trimmed.contains("\0") else {
            throw ProZipError.invalidArchive("请输入有效的压缩包名称")
        }
        let source = session.url
        var destination = source.deletingLastPathComponent().appendingPathComponent(trimmed)
        if destination.pathExtension.isEmpty, !source.pathExtension.isEmpty {
            destination.appendPathExtension(source.pathExtension)
        }
        guard destination != source else { return }
        if FileManager.default.fileExists(atPath: source.path) {
            try FileManager.default.moveItem(at: source, to: destination)
        } else if session.initialSourceStat != nil {
            throw ProZipError.invalidArchive("源压缩包已被移动或删除")
        }
        session.archiveURL = destination
        preferences.recordRecentArchive(destination)
    }

    // MARK: - Archive Creation Coordinator Integration

    public func createArchive(
        sources: [URL],
        destinationURL: URL,
        profile: CreationProfile,
        moveSourcesToTrash: Bool = false,
        savePasswordToBook: Bool = false,
        sourcesToTrash: [URL]? = nil,
        completion: ((URL) -> Void)? = nil
    ) {
        let draftSessionID = completion == nil ? nil : creationDraftSessionID
        var trashSources = sourcesToTrash
        if draftSessionID != nil, let allowed = creationSourcesToTrash {
            let safe = Set(allowed.map(\.standardizedFileURL))
            trashSources = (sourcesToTrash ?? allowed).filter { safe.contains($0.standardizedFileURL) }
        }
        let existing: [URL]
        do { existing = try SplitArchivePublication.existingItems(baseURL: destinationURL) }
        catch { reportCreationFailure(error); return }
        if let firstExisting = existing.first {
            let conflictItem = ConflictItemInfo(
                fileName: firstExisting.lastPathComponent,
                destinationPath: destinationURL.deletingLastPathComponent().path,
                existingSize: (try? firstExisting.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0,
                existingModifiedAt: (try? firstExisting.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date(),
                incomingSize: 0,
                incomingModifiedAt: Date()
            )
            let owner = presentationOwners[\ProZipAppViewModel.isCreationDialogPresented] ?? activeSessionID
            requestConflictResolution(conflictItem, owner: owner) { [weak self] resolution in
                guard let self else { return }
                switch resolution {
                case .replace:
                    // shortcut: Replacing a split family requires a cross-file recovery journal; offer Keep Both instead.
                    guard profile.split == nil,
                          !existing.contains(where: { $0.lastPathComponent.caseInsensitiveCompare(destinationURL.lastPathComponent) != .orderedSame }) else {
                        self.reportCreationFailure(ProZipError.destinationNotWritable(SplitArchivePublication.replacementUnavailableMessage))
                        return
                    }
                    self.performCreateArchive(sources: sources, destinationURL: destinationURL, profile: profile, moveSourcesToTrash: moveSourcesToTrash, savePasswordToBook: savePasswordToBook, sourcesToTrash: trashSources, draftSessionID: draftSessionID, completion: completion)
                case .keepBoth:
                    do {
                        let unique = try Self.uniqueDestination(for: destinationURL)
                        self.performCreateArchive(sources: sources, destinationURL: unique, profile: profile, moveSourcesToTrash: moveSourcesToTrash, savePasswordToBook: savePasswordToBook, sourcesToTrash: trashSources, draftSessionID: draftSessionID, completion: completion)
                    } catch { self.reportCreationFailure(error) }
                case .skip, .ask:
                    break
                }
            }
            return
        }
        performCreateArchive(sources: sources, destinationURL: destinationURL, profile: profile, moveSourcesToTrash: moveSourcesToTrash, savePasswordToBook: savePasswordToBook, sourcesToTrash: trashSources, draftSessionID: draftSessionID, completion: completion)
    }

    private static func uniqueDestination(for url: URL) throws -> URL {
        try SplitArchivePublication.uniqueBaseURL(for: url)
    }

    private func reportCreationFailure(_ error: Error) {
        cancelTermination()
        alertTitle = "无法创建压缩包"
        alertMessage = error.localizedDescription
        isAlertPresented = true
    }

    private func performCreateArchive(
        sources: [URL],
        destinationURL: URL,
        profile: CreationProfile,
        moveSourcesToTrash: Bool = false,
        savePasswordToBook: Bool = false,
        sourcesToTrash: [URL]? = nil,
        draftSessionID: UUID? = nil,
        completion: ((URL) -> Void)? = nil
    ) {
        let totalBytes = sources.reduce(Int64(0)) { sum, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 512_000
            return sum + Int64(max(size, 4096))
        }
        let task = ArchiveTaskRecord(
            title: "创建压缩包 \(destinationURL.lastPathComponent)",
            archiveURL: destinationURL,
            phase: .compressing,
            completedBytes: 0,
            totalBytes: max(1024, totalBytes),
            currentItem: sources.first?.lastPathComponent ?? "正在打包…",
            outputResultURL: destinationURL
        )
        task.outputResultURL = nil
        tasks.insert(task, at: 0)
        isTaskProgressPresented = true

        let operation = Task {
            defer { task.clearCancellation() }
            do {
                try await ArchiveEngineBroker.shared.create(
                    sources: sources,
                    at: destinationURL,
                    profile: profile,
                    password: profile.password
                ) { progress in
                    if progress.phase != .completed {
                        Task { @MainActor in
                            guard ![.completed, .failed, .cancelled].contains(task.phase) else { return }
                            task.update(progress: progress)
                        }
                    }
                }

                let resultURL: URL
                if profile.split != nil { resultURL = try SplitArchivePublication.publishedFirstPart(baseURL: destinationURL) }
                else {
                    guard FileManager.default.fileExists(atPath: destinationURL.path) else { throw ProZipError.invalidArchive("未找到已创建的压缩包") }
                    resultURL = destinationURL
                }
                try Task.checkCancellation()
                await MainActor.run {
                    task.outputResultURL = resultURL
                    task.update(progress: OperationProgress(
                        phase: .completed,
                        completedBytes: task.totalBytes,
                        totalBytes: task.totalBytes,
                        currentItem: "已完成 · \(profile.format.displayName)",
                        fractionCompleted: 1.0
                    ))
                    shelfModel.recentResults.insert(
                        ShelfCompletedResult(
                            title: resultURL.lastPathComponent,
                            subtitle: "\(profile.format.displayName) · \(ByteCountFormatter.string(fromByteCount: task.totalBytes, countStyle: .file)) · 刚刚",
                            outputURL: resultURL,
                            isArchive: true
                        ),
                        at: 0
                    )
                    if savePasswordToBook, let password = profile.password, !passwordBook.isLocked {
                        passwordBook.addEntry(title: resultURL.lastPathComponent, password: password)
                        if let error = passwordBook.lastError {
                            self.cancelTermination()
                            self.alertTitle = "压缩包已创建"
                            self.alertMessage = "密码未能保存到密码本。\n" + error
                            self.isAlertPresented = true
                        }
                    }
                    if let draftSessionID, sessions.contains(where: { $0.id == draftSessionID }) {
                        sessionPasswords[draftSessionID] = profile.password
                    }
                    completion?(resultURL)
                    if moveSourcesToTrash {
                        var failures: [String] = []
                        for source in sourcesToTrash ?? sources {
                            let sourcePath = source.standardizedFileURL.path
                            let destinationPath = resultURL.standardizedFileURL.path
                            guard destinationPath != sourcePath, !destinationPath.hasPrefix(sourcePath + "/") else { continue }
                            do { try FileManager.default.trashItem(at: source, resultingItemURL: nil) }
                            catch { failures.append("\(source.lastPathComponent)：\(error.localizedDescription)") }
                        }
                        if !failures.isEmpty {
                            self.alertTitle = "压缩包已创建"
                            self.alertMessage = "以下来源文件未能移到废纸篓：\n" + failures.joined(separator: "\n")
                            self.isAlertPresented = true
                        }
                    }
                    NotificationCenter.default.post(name: .proZipArchiveCreated, object: resultURL)
                }
            } catch is CancellationError {
                cancelTermination()
                task.cancel()
            } catch let error as ProZipError where error == .cancelled {
                cancelTermination()
                task.cancel()
            } catch {
                cancelTermination()
                await MainActor.run {
                    task.update(progress: OperationProgress(
                        phase: .failed,
                        completedBytes: 0,
                        totalBytes: task.totalBytes,
                        currentItem: (error as? ProZipError)?.errorDescription ?? error.localizedDescription,
                        fractionCompleted: 0
                    ))
                }
            }
        }
        task.bindCancellation(to: operation)
    }

    // MARK: - Quick Look Preview

    public func previewSelected(in session: ArchiveBrowsingSession) {
        guard let entry = session.selectedEntries.first else { return }
        materializeForPreview(entry, in: session, password: sessionPasswords[session.id])
    }

    private func materializeForPreview(_ entry: ArchiveEntry, in session: ArchiveBrowsingSession, password: String?) {
        Task {
            do {
                let targetURL = try await exportEntry(entry, in: session, password: password)
                if let password { rememberPassword(password, for: session) }
                await MainActor.run {
                    self.previewURL = targetURL
                    ProZipQuickLookPresenter.shared.present(url: targetURL)
                }
            } catch let error as ProZipError {
                switch error {
                case .passwordRequired, .wrongPassword:
                    await MainActor.run {
                        self.presentPasswordPrompt(for: session, message: "预览 \(entry.name) 需要密码") { entered in
                            self.materializeForPreview(entry, in: session, password: entered)
                        }
                    }
                default:
                    self.alertTitle = "无法预览文件"
                    self.alertMessage = error.localizedDescription
                    self.isAlertPresented = true
                }
            } catch {
                self.alertTitle = "无法预览文件"
                self.alertMessage = error.localizedDescription
                self.isAlertPresented = true
            }
        }
    }

    public func previewBytes(for entry: ArchiveEntry, in session: ArchiveBrowsingSession, maximumCount: Int) async throws -> Data {
        let limit = max(0, maximumCount)
        if let source = try sourceFile(for: entry, in: session) {
            return try await Self.readPreviewBytes(at: source, maximumCount: limit)
        }
        let original = try archivedEntry(for: entry, in: session)
        if original.isEncrypted, sessionPasswords[session.id] == nil { throw ProZipError.passwordRequired(entry.name) }
        let stream = try await ArchiveEngineBroker.shared.openMember(original, in: session.url, password: sessionPasswords[session.id], range: 0..<min(entry.uncompressedSize, Int64(limit)))
        var data = Data()
        for try await chunk in stream {
            try Task.checkCancellation()
            data.append(chunk.prefix(max(0, limit - data.count)))
            if data.count >= limit { break }
        }
        try Task.checkCancellation()
        return data
    }

    public func materializePreview(_ entry: ArchiveEntry, in session: ArchiveBrowsingSession) async throws -> URL {
        try await exportEntry(entry, in: session)
    }

    /// Exports without presenting panels; directories with uncommitted subtree edits require saving first.
    public func exportEntry(_ entry: ArchiveEntry, in session: ArchiveBrowsingSession) async throws -> URL {
        try await exportEntry(entry, in: session, password: sessionPasswords[session.id])
    }

    private func exportEntry(_ entry: ArchiveEntry, in session: ArchiveBrowsingSession, password: String?) async throws -> URL {
        let hasDirectoryAddition = entry.isDirectory ? try validateDirectoryExport(entry, in: session) : false
        let source = try sourceFile(for: entry, in: session)
        if let source, !entry.isDirectory { return source }
        let original = try archivedEntry(for: entry, in: session)
        if hasDirectoryAddition {
            if session.initialSourceStat != nil {
                guard case .ready = session.phase else { throw ProZipError.structureConflict("请等待索引完成并保存目录修改后再导出。") }
            }
            if try await session.index.entry(forPath: original.path) != nil {
                throw ProZipError.structureConflict("目录包含尚未保存的合并内容，请先保存后再导出。")
            }
        }
        if let source { return source }
        guard password != nil || (!original.isEncrypted && !session.safeDescriptor.hasEncryptedHeaders) else {
            throw ProZipError.passwordRequired(entry.name)
        }
        if entry.type == .special { throw ProZipError.editingNotSupported("此类型暂不支持导出。") }
        if entry.type == .symlink { throw ProZipError.editingNotSupported("请连同父目录导出归档中的符号链接。") }
        if entry.type == .file {
            return try await Self.materializeMember(original, in: session.url, password: password, displayName: entry.name)
        }

        let entries = try await archivedExtractionEntries(for: [original], in: session, password: password)
        if password == nil, entries.contains(where: \.isEncrypted) { throw ProZipError.passwordRequired(entry.name) }
        for member in entries {
            guard try ArchiveExtractionPolicy.validateRelativeArchivePath(member.path) == member.path else { throw ProZipError.unsafePath(member.path) }
        }
        let root = try await ManagedTemporaryArtifactRegistry.shared.createManagedTemporaryDirectory(purpose: "entry-export")
        var succeeded = false
        defer { if !succeeded { try? FileManager.default.removeItem(at: root) } }
        let payload = root.appendingPathComponent("payload", isDirectory: true)
        let sourcePath = try ArchiveExtractionPolicy.validateRelativeArchivePath(original.path)
        _ = try ArchiveExtractionPolicy.validateRelativeArchivePath(entry.name)
        let result = root.appendingPathComponent(entry.name, isDirectory: true)
        for member in entries where member.type == .symlink {
            guard let target = member.symlinkTarget else { throw ProZipError.structureConflict("符号链接缺少目标，无法完整导出。") }
            let relative = String(member.path.dropFirst(original.path.count + 1))
            try ArchiveExtractionPolicy.validateSymlinkTarget(linkDestinationURL: result.appendingPathComponent(relative), targetPath: target, extractionRootURL: result)
        }
        let options = ExtractionOptions(filterSystemAuxiliaryFiles: false, filterDMGInstallerArtifacts: false, stripSingleRootFolderIfMatching: false)
        let report = try await ArchiveEngineBroker.shared.extract(entries, from: session.url, to: payload, password: password, options: options)
        guard report.failedCount == 0, report.skippedCount == 0 else {
            throw ProZipError.structureConflict("目录未能完整导出，请保存后重试。")
        }
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: payload.appendingPathComponent(sourcePath), to: result)
        succeeded = true
        return result
    }

    private func validateDirectoryExport(_ entry: ArchiveEntry, in session: ArchiveBrowsingSession) throws -> Bool {
        var directory = entry.path
        var hasAddition = false
        for mutation in session.pendingMutations.reversed() {
            switch mutation {
            case .renameEntry(let old, let new):
                if directory == new || directory.hasPrefix(new + "/") {
                    directory = old + directory.dropFirst(new.count)
                } else if old.hasPrefix(directory + "/") || new.hasPrefix(directory + "/") {
                    throw ProZipError.structureConflict("目录包含尚未保存的修改，请先保存后再导出。")
                }
            case .addFile(_, let path), .replaceEntry(let path, _):
                if path.hasPrefix(directory + "/") {
                    throw ProZipError.structureConflict("目录包含尚未保存的修改，请先保存后再导出。")
                }
                if case .addFile = mutation, directory == path || directory.hasPrefix(path + "/") { hasAddition = true }
            case .deleteEntry(let path):
                if directory == path || directory.hasPrefix(path + "/") || path.hasPrefix(directory + "/") {
                    throw ProZipError.structureConflict("目录包含尚未保存的删除，请先保存后再导出。")
                }
            }
        }
        return hasAddition
    }

    private func archivedEntry(for entry: ArchiveEntry, in session: ArchiveBrowsingSession) throws -> ArchiveEntry {
        var path = entry.path
        for mutation in session.pendingMutations.reversed() {
            switch mutation {
            case .renameEntry(let old, let new):
                if path == new || path.hasPrefix(new + "/") { path = old + path.dropFirst(new.count) }
            case .deleteEntry(let deleted):
                if path == deleted || path.hasPrefix(deleted + "/") { throw ProZipError.structureConflict("此项目已从草稿中删除。") }
            default: break
            }
        }
        return ArchiveEntry(path: path, type: entry.type, uncompressedSize: entry.uncompressedSize, compressedSize: entry.compressedSize, modifiedAt: entry.modifiedAt, permissions: entry.permissions, crc32: entry.crc32, isEncrypted: entry.isEncrypted, symlinkTarget: entry.symlinkTarget, encryptionGroupID: entry.encryptionGroupID)
    }

    private func sourceFile(for entry: ArchiveEntry, in session: ArchiveBrowsingSession) throws -> URL? {
        var path = entry.path
        mutations: for mutation in session.pendingMutations.reversed() {
            switch mutation {
            case .renameEntry(let old, let new):
                if path == new || path.hasPrefix(new + "/") { path = old + path.dropFirst(new.count) }
            case .addFile(let source, let archivePath), .replaceEntry(let archivePath, let source):
                if path == archivePath {
                    _ = try FileManager.default.attributesOfItem(atPath: source.path)
                    return source
                }
                if path.hasPrefix(archivePath + "/") {
                    var candidate = source
                    for component in path.dropFirst(archivePath.count + 1).split(separator: "/", omittingEmptySubsequences: false) {
                        guard !component.isEmpty, component != ".", component != "..", !component.contains("\0") else { throw ProZipError.unsafePath(path) }
                        guard let attributes = try? FileManager.default.attributesOfItem(atPath: candidate.path) else {
                            if case .replaceEntry = mutation { throw ProZipError.structureConflict("替换目录不包含此项目。") }
                            continue mutations
                        }
                        guard attributes[.type] as? FileAttributeType == .typeDirectory else {
                            throw ProZipError.structureConflict("此项目的父目录已被来源文件替换。")
                        }
                        candidate.appendPathComponent(String(component))
                    }
                    if (try? FileManager.default.attributesOfItem(atPath: candidate.path)) != nil { return candidate }
                    if case .replaceEntry = mutation { throw ProZipError.structureConflict("替换目录不包含此项目。") }
                }
            case .deleteEntry(let deleted):
                if path == deleted || path.hasPrefix(deleted + "/") { throw ProZipError.structureConflict("此项目已从草稿中删除。") }
            }
        }
        return nil
    }

    private nonisolated static func readPreviewBytes(at url: URL, maximumCount: Int) async throws -> Data {
        try Task.checkCancellation()
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumCount) ?? Data()
        try Task.checkCancellation()
        return data
    }

    private func rememberPassword(_ password: String, for session: ArchiveBrowsingSession) {
        let isNewPassword = sessionPasswords[session.id] != password
        sessionPasswords[session.id] = password
        guard isNewPassword, preferences.passwordBookAutoSave, !passwordBook.isLocked,
              !passwordBook.candidatePasswords().contains(password) else { return }
        passwordBook.addEntry(title: session.archiveName, password: password)
        if let error = passwordBook.lastError {
            alertTitle = "密码未能保存到密码本"
            alertMessage = error
            isAlertPresented = true
        }
    }

    /// Write each chunk immediately; previews and external opens do not retain a second full copy in RAM.
    public nonisolated static func materializeMember(_ entry: ArchiveEntry, in archiveURL: URL, password: String? = nil, displayName: String? = nil) async throws -> URL {
        let directory = try await ManagedTemporaryArtifactRegistry.shared.createManagedTemporaryDirectory(purpose: "quicklook")
        let safeName = URL(fileURLWithPath: displayName ?? entry.name).lastPathComponent
        let targetURL = directory.appendingPathComponent(safeName.isEmpty ? "entry" : safeName)
        var completed = false
        defer { if !completed { try? FileManager.default.removeItem(at: directory) } }
        guard FileManager.default.createFile(atPath: targetURL.path, contents: nil) else {
            throw ProZipError.destinationNotWritable("无法创建预览文件")
        }
        let handle = try FileHandle(forWritingTo: targetURL)
        defer { try? handle.close() }
        let stream = try await ArchiveEngineBroker.shared.openMember(entry, in: archiveURL, password: password)
        for try await chunk in stream {
            try Task.checkCancellation()
            try handle.write(contentsOf: chunk)
        }
        try Task.checkCancellation()
        completed = true
        return targetURL
    }

    public func requestArchivePassword(for session: ArchiveBrowsingSession) {
        presentPasswordPrompt(for: session, message: "请输入 \(session.archiveName) 的解密密码") { entered in
            self.loadArchiveIndex(for: session, password: entered)
        }
    }

    private func presentPasswordPrompt(for session: ArchiveBrowsingSession, message: String, onCancel: (() -> Void)? = nil, retry: @escaping (String) -> Void) {
        let request = PasswordRequest(session: session, message: message, onCancel: onCancel, retry: retry)
        if isPasswordPromptPresented || passwordPromptIsDismissing { passwordRequests.append(request); return }
        showPasswordPrompt(request)
    }

    private func showPasswordPrompt(_ request: PasswordRequest) {
        activePasswordRequest = request
        passwordPromptTitle = request.session.archiveName
        passwordPromptMessage = request.message
        passwordPromptCompletion = { entered in
            guard let entered, !entered.isEmpty else { request.onCancel?(); return }
            request.retry(entered)
        }
        let owner = sessions.contains(where: { $0.id == request.session.id }) ? request.session.id : activeSessionID
        presentDialog(\.isPasswordPromptPresented, for: owner)
    }

    public func submitPassword(_ password: String?) {
        let completion = passwordPromptCompletion
        passwordPromptCompletion = nil
        completedPasswordPrompt = { completion?(password) }
        passwordPromptIsDismissing = true
        isPasswordPromptPresented = false
    }

    public func passwordPromptDidDismiss() {
        guard !isPasswordPromptPresented else { return }
        let fallback = passwordPromptCompletion
        let action = completedPasswordPrompt ?? { fallback?(nil) }
        completedPasswordPrompt = nil
        passwordPromptCompletion = nil
        activePasswordRequest = nil
        passwordPromptIsDismissing = false
        action()
        if !isPasswordPromptPresented, !passwordRequests.isEmpty { showPasswordPrompt(passwordRequests.removeFirst()) }
    }

    public func beginCreation(sources: [URL], originalSources: [URL]? = nil, ownerSessionID: UUID?, completion: ((URL) -> Void)? = nil) {
        enqueueCreation(CreationRequest(sources: sources, originalSources: originalSources, owner: ownerSessionID, completion: completion, draftSessionID: nil, sourcesToTrash: nil))
    }

    private func enqueueCreation(_ request: CreationRequest) {
        if isCreationDialogPresented || creationIsDismissing { creationRequests.append(request); return }
        showCreation(request)
    }

    private func showCreation(_ request: CreationRequest) {
        creationSources = request.sources
        creationOriginalSources = request.originalSources
        creationCompletion = request.completion
        creationDraftSessionID = request.draftSessionID
        creationSourcesToTrash = request.sourcesToTrash
        presentDialog(\.isCreationDialogPresented, for: request.owner)
    }

    public func creationDialogDidDismiss() {
        guard !isCreationDialogPresented, creationIsDismissing else { return }
        if creationCompletion != nil { cancelTermination() }
        creationSources = []
        creationOriginalSources = nil
        creationCompletion = nil
        creationDraftSessionID = nil
        creationSourcesToTrash = nil
        creationIsDismissing = false
        if !creationRequests.isEmpty { showCreation(creationRequests.removeFirst()) }
    }

}

public extension Notification.Name {
    static let proZipArchiveCreated = Notification.Name("ProZipArchiveCreated")
    static let proZipShowWelcome = Notification.Name("ProZipShowWelcome")
    static let proZipShowMainWindow = Notification.Name("ProZipShowMainWindow")
    static let proZipTerminationReady = Notification.Name("ProZipTerminationReady")
    static let proZipTerminationCancelled = Notification.Name("ProZipTerminationCancelled")
}

/// Minimal Quick Look panel presenter for materialized archive members.
public final class ProZipQuickLookPresenter: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    public static let shared = ProZipQuickLookPresenter()
    private var url: URL?

    public func present(url: URL) {
        self.url = url
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    public func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        url == nil ? 0 : 1
    }

    public func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        url as NSURL?
    }
}
