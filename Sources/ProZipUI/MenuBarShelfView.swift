import AppKit
import ProZipCore
import ProZipEngines
import ProZipShared
import SwiftUI
import UniformTypeIdentifiers
import QuickLookThumbnailing

// MARK: - MenuBarShelfView (ShelfPanel / ProZip 菜单栏暂存盒)

public struct MenuBarShelfView: View {
    @ObservedObject public var model: MenuBarShelfModel
    @ObservedObject private var appViewModel = ProZipAppViewModel.shared
    @ObservedObject public var preferences = ProZipPreferences.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var isDropTargeted: Bool = false
    @State private var isHoveringActionArea: Bool = false
    @State private var holdsActionsOpen: Bool = false
    @State private var actionCollapseTask: Task<Void, Never>?
    @State private var isHoveringLightning: Bool = false
    @State private var isFileListVisible = false

    public init(model: MenuBarShelfModel? = nil) {
        self.model = model ?? ProZipAppViewModel.shared.shelfModel
    }

    private var isActionsPanelVisible: Bool {
        holdsActionsOpen || model.isQuickActionsExpanded
    }

    @Environment(\.dismiss) private var dismissExtra

    public var body: some View {
        ZStack(alignment: .topLeading) {
            shelfCard
                .frame(width: 260, height: 267)
                .offset(x: 221, y: 25)

            if !model.collectedFiles.isEmpty {
                ZStack {
                    arcActionButton(index: 0, title: "放入工作区", icon: "macwindow") { moveStagedFilesToWorkspace() }
                    arcActionButton(index: 1, title: "快速压缩", icon: "archivebox") { performQuickCompress() }
                    arcActionButton(index: 2, title: "解压到文件夹", icon: "arrow.down.to.line") { performBatchExtractToOneFolder() }
                    arcActionButton(index: 3, title: "放入文件夹", icon: "folder") { collectStagedFilesIntoFolder() }
                }
                .frame(width: 136, height: 136, alignment: .topTrailing)
                .contentShape(Rectangle())
                .position(x: 197, y: 314)
                .allowsHitTesting(isActionsPanelVisible)
                .onHover { hovering in
                    isHoveringActionArea = hovering
                    updateActionHover()
                }
            }
        }
        .frame(width: 521, height: 497, alignment: .topLeading)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDroppedProviders(providers)
        }
        .onDisappear {
            actionCollapseTask?.cancel()
            isHoveringLightning = false
            isHoveringActionArea = false
            holdsActionsOpen = false
        }
    }

    private var shelfCard: some View {
        VStack(spacing: 0) {
            shelfHeaderBar

            if model.collectedFiles.isEmpty {
                emptyDropZoneView
            } else {
                VStack(spacing: 0) {
                    if isFileListVisible {
                        stagedItemsScrollView
                    } else if let file = model.collectedFiles.first {
                        ShelfFilePreview(fileURL: file)
                    }
                    shelfBottomBar
                }
                .background(colorScheme == .dark ? Color(white: 0.12) : .white)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
            }
        }
        .background(
            ZStack {
                if colorScheme == .dark {
                    Color(red: 0.13, green: 0.14, blue: 0.13)
                } else {
                    Color(red: 0.97, green: 0.98, blue: 0.96)
                }
                shelfColor.opacity(min(1, max(0, preferences.boxShellColorOpacity)) * (colorScheme == .dark ? 0.4 : 1.0))
                if isDropTargeted {
                    ProZipTheme.accent.opacity(0.12)
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
    }

    private func arcActionButton(index: Int, title: String, icon: String, action: @escaping () -> Void) -> some View {
        ArcActionButton(
            index: index,
            title: title,
            icon: icon,
            isExpanded: isActionsPanelVisible,
            colorScheme: colorScheme,
            action: action
        )
    }

    private var shelfBottomBar: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.8)) {
                    model.isQuickActionsExpanded.toggle()
                }
            } label: {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [ProZipTheme.accentBright, ProZipTheme.accent],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .shadow(color: ProZipTheme.accent.opacity(0.30), radius: 3, y: 1)
                    )
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(ProZipPressScaleStyle(hoverScale: 1.05, pressedScale: 0.93))
            .onHover { hovering in
                isHoveringLightning = hovering
                updateActionHover()
            }
            .help("快捷操作")

            Spacer(minLength: 0)

            Button {
                isFileListVisible.toggle()
            } label: {
                HStack(spacing: 5) {
                    Text("\(model.collectedFiles.count) 个文件")
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 6)
                .frame(height: 30)
                .background(Capsule().fill(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.94)))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.8)) { model.clear() }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.8))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.94)))
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
            }
            .buttonStyle(ProZipPressScaleStyle(hoverScale: 1.05, pressedScale: 0.94))
            .help("清空文件盒")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
    }

    private var shelfHeaderBar: some View {
        HStack(spacing: 6) {
            Button { presentMainWindow() } label: {
            HStack(spacing: 6) {
            ProZipBrandIcon(size: 28, showAppSquircle: true)

            VStack(alignment: .leading, spacing: 1) {
                Text("ProZip")
                    .font(.system(size: 13, weight: .bold))
                Text("文件盒")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.62))
                    )
            }

            }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("打开 ProZip")

            Spacer()

            Button {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                    model.isPinned.toggle()
                }
            } label: {
                Image(systemName: model.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(model.isPinned ? Color.white : Color.primary)
                    .frame(width: 26, height: 26)
                    .background(
                        Circle()
                            .fill(model.isPinned ? ProZipTheme.accent : Color.white.opacity(colorScheme == .dark ? 0.16 : 0.45))
                            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                    )
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8))
            }
            .buttonStyle(ProZipPressScaleStyle(hoverScale: 1.04, pressedScale: 0.94))
            .help("固定文件盒")

            Button {
                NotificationCenter.default.post(name: .proZipCloseShelf, object: nil)
                dismissExtra()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 26, height: 26)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.45))
                            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                    )
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8))
            }
            .buttonStyle(ProZipPressScaleStyle(hoverScale: 1.04, pressedScale: 0.94))
            .help("收起文件盒")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(height: 50)
    }

    // MARK: - Empty Dashed Drop Zone (BoxOutline.png + Vector Fallback)

    private var emptyDropZoneView: some View {
        Image(systemName: "tray.and.arrow.down")
            .font(.system(size: 42, weight: .light))
            .foregroundStyle(.primary.opacity(0.22))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(colorScheme == .dark ? Color(white: 0.12) : .white)
            .overlay { if isDropTargeted { shelfColor.opacity(0.12) } }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
            .accessibilityLabel("ProZip 文件盒")
    }

    // MARK: - Staged Items List & Inline Folder Browser (ShelfFolderBrowser)

    private var stagedItemsScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(model.collectedFiles, id: \.path) { fileURL in
                    ShelfStagedItemRow(
                        fileURL: fileURL,
                        shelfColor: shelfColor,
                        model: model
                    )
                }
            }
            .padding(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions & Helpers

    private var shelfColor: Color {
        switch preferences.boxColor {
        case "chartreuse": return ProZipTheme.accent
        case "blue": return .blue
        case "purple": return .purple
        case "orange": return .orange
        case "pink": return .pink
        case "red": return .red
        case "yellow": return .yellow
        case "green": return .green
        case "cyan": return .cyan
        case "gray": return .gray
        default: return ProZipTheme.accent
        }
    }

    private func updateActionHover() {
        actionCollapseTask?.cancel()
        if isHoveringLightning || isHoveringActionArea {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.8)) {
                holdsActionsOpen = true
            }
        } else {
            // Keep the radial targets reachable while crossing the gap from the trigger.
            actionCollapseTask = Task { @MainActor in
                do { try await Task.sleep(nanoseconds: 180_000_000) } catch { return }
                withAnimation(.spring(response: 0.24, dampingFraction: 0.8)) {
                    holdsActionsOpen = false
                }
            }
        }
    }

    private func handleDroppedProviders(_ providers: [NSItemProvider]) -> Bool {
        guard providers.contains(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else { return false }
        Task { @MainActor in
            let urls = await FileURLDrop.loadURLs(from: providers)
            do {
                try ShelfFileActions.validateSources(urls)
                model.addFiles(urls)
            } catch { showShelfError(error, title: "无法加入文件盒") }
        }
        return true
    }

    private func performQuickCompress() {
        let sources = model.collectedFiles
        guard !sources.isEmpty else { return }
        do {
            let profile = preferences.makeDefaultCreationProfile()
            let destination = try ShelfFileActions.quickArchiveDestination(for: sources, format: profile.format)
            presentMainWindow()
            appViewModel.createArchive(sources: sources, destinationURL: destination, profile: profile)
        } catch {
            showShelfError(error, title: "无法压缩文件")
        }
    }

    private func performBatchExtractToOneFolder() {
        let sources = model.collectedFiles
        guard !sources.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.title = "选择解压目标文件夹"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = sources.first?.deletingLastPathComponent()
        panel.prompt = "解压到此处"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        presentMainWindow()
        Task { @MainActor in
            var completedCount = 0
            for source in sources {
                do {
                    let descriptor = try await ArchiveEngineBroker.shared.probe(source)
                    let session = ArchiveBrowsingSession(url: source, descriptor: descriptor)
                    appViewModel.extractAll(in: session, to: destination)
                    guard let task = appViewModel.tasks.first else { return }
                    for await phase in task.$phase.values {
                        if phase == .completed || phase == .failed || phase == .cancelled { break }
                    }
                    guard task.phase == .completed else {
                        model.statusMessage = "已完成 \(completedCount) / \(sources.count) 个压缩包"
                        return
                    }
                    completedCount += 1
                } catch {
                    showShelfError(error, title: "无法解压 \(source.lastPathComponent)")
                    return
                }
            }
            model.statusMessage = "已解压 \(completedCount) 个压缩包"
        }
    }

    private func moveStagedFilesToWorkspace() {
        let sources = model.collectedFiles
        guard !sources.isEmpty else { return }
        do {
            try ShelfFileActions.validateSources(sources)
            appViewModel.createNewArchiveSession()
            if let session = appViewModel.activeSession {
                try session.addFiles(sources)
            }
            model.statusMessage = "已放入工作区"
            presentMainWindow()
        } catch {
            showShelfError(error, title: "无法放入工作区")
        }
    }

    private func collectStagedFilesIntoFolder() {
        let sources = model.collectedFiles
        guard !sources.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.title = "选择存放文件的文件夹"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = sources.first?.deletingLastPathComponent()
        panel.prompt = "放入此文件夹"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        model.statusMessage = "正在复制文件…"
        Task { @MainActor in
            do {
                let copiedURLs = try await Task.detached(priority: .userInitiated) {
                    try ShelfFileActions.copy(sources, to: destination)
                }.value
                model.recentResults.insert(
                    ShelfCompletedResult(
                        title: destination.lastPathComponent,
                        subtitle: "已放入 \(copiedURLs.count) 个项目 · 刚刚",
                        outputURL: destination,
                        isArchive: false
                    ),
                    at: 0
                )
                model.statusMessage = "已放入 \(copiedURLs.count) 个项目"
                NSWorkspace.shared.activateFileViewerSelecting(copiedURLs)
            } catch {
                showShelfError(error, title: "无法放入文件夹")
            }
        }
    }

    private func presentMainWindow() {
        NotificationCenter.default.post(name: .proZipCloseShelf, object: nil)
        NotificationCenter.default.post(name: .proZipShowMainWindow, object: nil)
    }

    private func showShelfError(_ error: Error, title: String) {
        model.statusMessage = error.localizedDescription
        presentMainWindow()
        appViewModel.alertTitle = title
        appViewModel.alertMessage = error.localizedDescription
        appViewModel.isAlertPresented = true
    }

}

enum ShelfFileActions {
    static func validateSources(_ sources: [URL]) throws {
        try FileURLDrop.validateSources(sources)
    }

    static func quickArchiveDestination(for sources: [URL], format: ArchiveFormat) throws -> URL {
        try validateSources(sources)
        guard let first = sources.first else { throw ProZipError.invalidArchive("没有可压缩的文件") }
        let isDirectory = try first.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
        let name = sources.count > 1 ? "压缩包" : (isDirectory ? first.lastPathComponent : first.deletingPathExtension().lastPathComponent)
        let proposed = first.deletingLastPathComponent().appendingPathComponent(name).appendingPathExtension(format.defaultExtension)
        return availableDestination(for: proposed)
    }

    static func copy(_ sources: [URL], to destination: URL) throws -> [URL] {
        try validateSources(sources)
        let fm = FileManager.default
        let resolvedDestination = destination.resolvingSymlinksInPath().standardizedFileURL
        guard try resolvedDestination.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw ProZipError.invalidArchive("请选择一个目标文件夹")
        }
        for source in sources {
            let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values.isDirectory == true && values.isSymbolicLink != true {
                let root = source.resolvingSymlinksInPath().standardizedFileURL.path
                guard resolvedDestination.path != root, !resolvedDestination.path.hasPrefix(root + "/") else {
                    throw ProZipError.invalidArchive("不能将文件夹复制到它自身或内部")
                }
            }
        }
        let stagingDirectory = destination.appendingPathComponent(".prozip-copy-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: stagingDirectory, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: stagingDirectory) }
        var copiedURLs: [URL] = []
        for source in sources {
            try Task.checkCancellation()
            let staged = stagingDirectory.appendingPathComponent(UUID().uuidString)
            try fm.copyItem(at: source, to: staged)
            let output = availableDestination(for: destination.appendingPathComponent(source.lastPathComponent))
            try fm.moveItem(at: staged, to: output)
            copiedURLs.append(output)
        }
        return copiedURLs
    }

    private static func availableDestination(for url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else { return url }
        let directory = url.deletingLastPathComponent()
        let suffix = url.pathExtension
        let base = suffix.isEmpty ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
        var index = 2
        while true {
            var candidate = directory.appendingPathComponent("\(base) (\(index))")
            if !suffix.isEmpty { candidate.appendPathExtension(suffix) }
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            index += 1
        }
    }
}

private struct ShelfFilePreview: View {
    let fileURL: URL
    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: thumbnail ?? NSWorkspace.shared.icon(forFile: fileURL.path))
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 6)
                .padding(.horizontal, 16)
            Text(fileURL.lastPathComponent)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 10)
                .padding(.bottom, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: fileURL) {
            let request = QLThumbnailGenerator.Request(fileAt: fileURL, size: CGSize(width: 180, height: 150), scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
            if let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request), !Task.isCancelled {
                thumbnail = representation.nsImage
            }
        }
    }
}

// MARK: - ShelfStagedItemRow & Inline ShelfFolderBrowser

private struct ShelfStagedItemRow: View {
    let fileURL: URL
    let shelfColor: Color
    @ObservedObject var model: MenuBarShelfModel

    private var isDirectoryOrArchive: Bool {
        let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        if isDir { return true }
        let ext = fileURL.pathExtension.lowercased()
        return ["zip", "7z", "rar", "tar", "gz", "dmg", "iso"].contains(ext)
    }

    private var isExpanded: Bool {
        model.expandedItemPaths.contains(fileURL.path)
    }

    private var formattedItemSize: String {
        let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
        if values?.isDirectory == true { return "文件夹" }
        return ByteCountFormatter.string(fromByteCount: Int64(values?.fileSize ?? 0), countStyle: .file)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if isDirectoryOrArchive {
                    Button {
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.80)) {
                            model.toggleExpand(fileURL)
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(shelfColor)
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.plain)
                    .help(isExpanded ? "收起内联目录浏览" : "展开浏览文件夹或归档内容")
                } else {
                    Spacer()
                        .frame(width: 14)
                }

                Image(
                    nsImage: ProZipResourceLoader.systemFileIcon(
                        for: fileURL.path,
                        isDirectory: ((try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false)
                    )
                )
                .resizable()
                .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(fileURL.lastPathComponent)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(formattedItemSize)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Reveal in Finder button
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help("在访达中显示")

                // Remove from Shelf button
                Button {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                        model.removeFile(fileURL)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help("从暂存盒移除")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            // Inline Folder/Archive Browser (ShelfFolderBrowser)
            if isExpanded {
                Divider()
                    .padding(.leading, 26)
                ShelfFolderBrowser(rootURL: fileURL, shelfColor: shelfColor, model: model)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.75))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isExpanded ? shelfColor.opacity(0.45) : Color.primary.opacity(0.06), lineWidth: 0.8)
        )
    }
}

public struct ShelfFolderBrowser: View {
    public let rootURL: URL
    public let shelfColor: Color
    @ObservedObject public var model: MenuBarShelfModel

    private var currentDirURL: URL {
        model.browsingSubdirectoryByRoot[rootURL.path] ?? rootURL
    }

    private var childURLs: [URL] {
        model.childItems(for: rootURL)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Subdirectory Breadcrumb Strip if navigated inside a subfolder
            if currentDirURL.path != rootURL.path {
                HStack(spacing: 4) {
                    Button {
                        let parent = currentDirURL.deletingLastPathComponent()
                        model.browsingSubdirectoryByRoot[rootURL.path] = parent.path.hasPrefix(rootURL.path) ? parent : rootURL
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 9, weight: .bold))
                            Text("返回上级")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(shelfColor)
                    }
                    .buttonStyle(.plain)

                    Text("· \(currentDirURL.lastPathComponent)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.top, 4)
            }

            if childURLs.isEmpty {
                Text("文件夹为空")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 6)
            } else {
                ForEach(childURLs, id: \.path) { child in
                    let isSubDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    HStack(spacing: 6) {
                        Image(nsImage: ProZipResourceLoader.systemFileIcon(for: child.path, isDirectory: isSubDir))
                            .resizable()
                            .frame(width: 14, height: 14)

                        Text(child.lastPathComponent)
                            .font(.system(size: 11))
                            .foregroundStyle(.primary.opacity(0.88))
                            .lineLimit(1)

                        Spacer()

                        if isSubDir {
                            Button {
                                model.browsingSubdirectoryByRoot[rootURL.path] = child
                            } label: {
                                Image(systemName: "arrow.right.circle")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(shelfColor)
                            }
                            .buttonStyle(.plain)
                            .help("进入子文件夹")
                        }

                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([child])
                        } label: {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("在访达中显示")
                    }
                    .padding(.leading, 26)
                    .padding(.trailing, 10)
                    .padding(.vertical, 3)
                }
            }
        }
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.025))
    }
}

private struct ArcActionButton: View {
    let index: Int
    let title: String
    let icon: String
    let isExpanded: Bool
    let colorScheme: ColorScheme
    let action: () -> Void

    @State private var isHovered = false

    private var geometry: (angle: Double, radius: CGFloat) {
        let angles: [Double] = [180, 150, 120, 90]
        return (angles[index] * .pi / 180, 68)
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary.opacity(0.85))
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.97))
                        .shadow(color: .black.opacity(0.16), radius: 3, y: 1)
                )
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .help(title)
        .overlay(alignment: .center) {
            if isHovered {
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.9))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(colorScheme == .dark ? 0.18 : 0.97))
                            .shadow(color: .black.opacity(0.14), radius: 4, y: 2)
                    )
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
                    .alignmentGuide(.leading) { $0[.trailing] + 4 }
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                    .allowsHitTesting(false)
            }
        }
        .onHover { hovering in
            withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                isHovered = hovering
            }
        }
        .offset(
            x: isExpanded ? CGFloat(cos(geometry.angle)) * geometry.radius : 0,
            y: isExpanded ? CGFloat(sin(geometry.angle)) * geometry.radius : 0
        )
        .scaleEffect(isExpanded ? 1 : 0.25)
        .opacity(isExpanded ? 1 : 0)
        .animation(
            .spring(response: 0.34, dampingFraction: 0.72)
                .delay(Double(index) * 0.035),
            value: isExpanded
        )
    }
}
