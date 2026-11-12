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
    @State private var isHoveringActionBridge: Bool = false
    @State private var hoveredOrbitIndices: Set<Int> = []
    @State private var holdsActionsOpen: Bool = false
    @State private var actionCollapseTask: Task<Void, Never>?
    @State private var isHoveringLightning: Bool = false
    @State private var isHoveringCountCapsule: Bool = false
    @State private var isHoveringTrash: Bool = false
    @State private var isFileListVisible = false
    public var isInteractive: Bool

    public init(model: MenuBarShelfModel? = nil, isInteractive: Bool = true) {
        self.model = model ?? ProZipAppViewModel.shared.shelfModel
        self.isInteractive = isInteractive
    }

    private var isHoveringActionArea: Bool {
        isHoveringActionBridge || !hoveredOrbitIndices.isEmpty
    }

    private var isActionsPanelVisible: Bool {
        holdsActionsOpen || model.isQuickActionsExpanded
    }

    @Environment(\.dismiss) private var dismissExtra

    public var body: some View {
        ZStack(alignment: .topLeading) {
            if !model.collectedFiles.isEmpty && isActionsPanelVisible {
                Color.clear
                    .frame(width: 104, height: 104)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        isHoveringActionBridge = hovering
                        updateActionHover()
                    }
                    .offset(x: 166, y: 242)
            }

            Group {
                if isInteractive {
                    ShelfDropHostingContainer(
                        rootView: shelfCardContent.environment(\.colorScheme, colorScheme),
                        onTargetChanged: { targeted in
                            if isDropTargeted != targeted {
                                isDropTargeted = targeted
                            }
                        },
                        onDropURLs: { urls in
                            acceptDroppedURLs(urls)
                        },
                        onError: { error in
                            showShelfError(error, title: "无法加入文件盒")
                        }
                    )
                } else {
                    shelfCardContent
                }
            }
            .frame(width: 260, height: 267)
            .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
            .offset(x: 221, y: 25)

            if !model.collectedFiles.isEmpty {
                arcActionButton(index: 0, title: "放入工作区", icon: "macwindow") { moveStagedFilesToWorkspace() }
                arcActionButton(index: 1, title: "快速压缩", icon: "bolt.square") { performQuickCompress() }
                arcActionButton(index: 2, title: "压缩", icon: "arrow.down.square") { openCreationDialogForStagedFiles() }
                arcActionButton(index: 3, title: "放入文件夹", icon: "folder.badge.plus") { collectStagedFilesIntoFolder() }
            }
        }
        .frame(width: 521, height: 497, alignment: .topLeading)
        .onChange(of: model.collectedFiles.isEmpty) { _, empty in
            if empty {
                isHoveringActionBridge = false
                hoveredOrbitIndices.removeAll()
                holdsActionsOpen = false
            }
        }
        .onDisappear {
            actionCollapseTask?.cancel()
            isHoveringLightning = false
            isHoveringActionBridge = false
            hoveredOrbitIndices.removeAll()
            holdsActionsOpen = false
            isDropTargeted = false
        }
    }

    private var shelfCardContent: some View {
        VStack(spacing: 0) {
            shelfHeaderBar

            if model.collectedFiles.isEmpty {
                emptyDropZoneView
            } else {
                ZStack(alignment: .bottom) {
                    if isFileListVisible {
                        stagedItemsScrollView
                    } else if let file = model.collectedFiles.first {
                        ShelfFilePreview(fileURL: file)
                            .padding(.bottom, 46)
                    }
                    shelfBottomBar
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(shelfInnerGlassFill)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(
                            Color.white.opacity(colorScheme == .dark ? 0.18 : 0.85),
                            lineWidth: 1
                        )
                )
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
            }
        }
        .frame(width: 260, height: 267)
        .background(
            ZStack {
                ProZipGlassMaterialView(
                    material: colorScheme == .dark ? .hudWindow : .underWindowBackground,
                    blendingMode: .behindWindow
                )
                Color.white.opacity(colorScheme == .dark ? 0.05 : 0.44)
                shelfColor.opacity(min(1, max(0, preferences.boxShellColorOpacity)) * (colorScheme == .dark ? 0.44 : 0.85))
                if isDropTargeted {
                    ProZipTheme.accent.opacity(0.14)
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.24 : 0.72),
                            Color.black.opacity(colorScheme == .dark ? 0.28 : 0.12)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
    }

    private var shelfInnerGlassFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.58)
    }

    private func arcActionButton(index: Int, title: String, icon: String, action: @escaping () -> Void) -> some View {
        ArcActionButton(
            index: index,
            title: title,
            icon: icon,
            isExpanded: isActionsPanelVisible,
            colorScheme: colorScheme,
            onHoverChange: { hovering in
                if hovering {
                    hoveredOrbitIndices.insert(index)
                } else {
                    hoveredOrbitIndices.remove(index)
                }
                updateActionHover()
            },
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
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(ProZipTheme.accent)
                            .shadow(color: ProZipTheme.accent.opacity(0.32), radius: 3, y: 1)
                    )
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.32), lineWidth: 1))
            }
            .buttonStyle(ProZipPressScaleStyle(hoverScale: 1.032, pressedScale: 0.94))
            .onHover { hovering in
                isHoveringLightning = hovering
                updateActionHover()
            }
            .help("快捷操作")

            Spacer(minLength: 0)

            Button {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                    isFileListVisible.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    Text("\(model.collectedFiles.count) 个文件")
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: isFileListVisible ? "chevron.up" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 11)
                .frame(minWidth: 83.5, minHeight: 29, maxHeight: 29)
                .background(
                    Capsule()
                        .fill(
                            Color.white.opacity(
                                colorScheme == .dark
                                    ? (isHoveringCountCapsule ? 0.22 : 0.15)
                                    : (isHoveringCountCapsule ? 1.0 : 0.94)
                            )
                        )
                        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(
                            Color.primary.opacity(isHoveringCountCapsule ? 0.12 : 0.06),
                            lineWidth: 1
                        )
                )
            }
            .buttonStyle(ProZipPressScaleStyle(hoverScale: 1.02, pressedScale: 0.96))
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) {
                    isHoveringCountCapsule = hovering
                }
            }

            Spacer(minLength: 0)

            Button {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.8)) { model.clear() }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.86))
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(
                                colorScheme == .dark
                                    ? Color.white.opacity(isHoveringTrash ? 0.22 : 0.14)
                                    : (isHoveringTrash ? Color(white: 0.91) : Color.white.opacity(0.92))
                            )
                            .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                    )
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
            }
            .buttonStyle(ProZipPressScaleStyle(hoverScale: 1.03, pressedScale: 0.95))
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) {
                    isHoveringTrash = hovering
                }
            }
            .help("清空文件盒")
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 11)
        .padding(.top, 6)
    }

    private var shelfHeaderBar: some View {
        let pinSkyBlue = Color(red: 0.251, green: 0.663, blue: 1.0) // #40A9FF
        return HStack(spacing: 7) {
            Button { presentMainWindow() } label: {
                HStack(spacing: 6) {
                    ProZipBrandIcon(size: 26, showAppSquircle: true)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("ProZip")
                            .font(.system(size: 13, weight: .bold))
                        Text("文件盒")
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().fill(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.56))
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
                            .fill(model.isPinned ? pinSkyBlue : Color.white.opacity(colorScheme == .dark ? 0.16 : 0.48))
                            .shadow(color: model.isPinned ? pinSkyBlue.opacity(0.28) : .black.opacity(0.08), radius: 2, y: 1)
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(
                                model.isPinned ? Color.white.opacity(0.65) : Color.primary.opacity(0.10),
                                lineWidth: 0.8
                            )
                    )
            }
            .buttonStyle(ProZipPressScaleStyle(hoverScale: 1.04, pressedScale: 0.94))
            .help(model.isPinned ? "取消固定文件盒" : "固定文件盒")

            Button {
                NotificationCenter.default.post(name: .proZipCloseShelf, object: nil)
                dismissExtra()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 26, height: 26)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.48))
                            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                    )
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.8))
            }
            .buttonStyle(ProZipPressScaleStyle(hoverScale: 1.04, pressedScale: 0.94))
            .help("收起文件盒")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(height: 49)
    }

    // MARK: - Empty Frosted Liquid Glass Drop Zone

    private var emptyDropZoneView: some View {
        Image(systemName: "tray.and.arrow.down")
            .font(.system(size: 44, weight: .regular))
            .foregroundStyle(.primary.opacity(0.25))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(shelfInnerGlassFill)
            .overlay { if isDropTargeted { shelfColor.opacity(0.14) } }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(
                        Color.white.opacity(colorScheme == .dark ? 0.18 : 0.85),
                        lineWidth: 1
                    )
            )
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
            .accessibilityLabel("ProZip 文件盒")
    }

    // MARK: - Staged Items 2-Column Tile Gallery (2x 114x104)

    private var stagedItemsScrollView: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.fixed(114), spacing: 8),
                    GridItem(.fixed(114), spacing: 8)
                ],
                spacing: 8
            ) {
                ForEach(model.collectedFiles, id: \.path) { fileURL in
                    ShelfGalleryTileView(
                        fileURL: fileURL,
                        model: model
                    )
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 50)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions & Helpers

    private var shelfColor: Color {
        switch preferences.boxColor {
        case "chartreuse": return ProZipTheme.accent
        case "lavender": return Color(red: 0.56, green: 0.50, blue: 0.85)
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

    private func acceptDroppedURLs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        do {
            try ShelfFileActions.validateSources(urls)
            model.addFiles(urls)
        } catch {
            showShelfError(error, title: "无法加入文件盒")
        }
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

    private func openCreationDialogForStagedFiles() {
        let sources = model.collectedFiles
        guard !sources.isEmpty else { return }
        do {
            try ShelfFileActions.validateSources(sources)
            presentMainWindow()
            appViewModel.beginCreation(
                sources: sources,
                originalSources: sources,
                ownerSessionID: appViewModel.activeSessionID
            )
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
                    _ = try await ArchiveEngineBroker.shared.probe(source)
                    let session = appViewModel.sessionForExternalExtraction(at: source)
                    let previousTopTaskID = appViewModel.tasks.first?.id
                    appViewModel.extractAll(in: session, to: destination)
                    guard let task = appViewModel.tasks.first, task.id != previousTopTaskID else {
                        model.statusMessage = "已完成 \(completedCount) / \(sources.count) 个压缩包"
                        return
                    }
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
                .frame(maxWidth: 164, maxHeight: 112)
                .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
                .padding(.top, 10)
            Text(fileURL.lastPathComponent)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
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

private struct ShelfGalleryTileView: View {
    let fileURL: URL
    @ObservedObject var model: MenuBarShelfModel
    @State private var thumbnail: NSImage?
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: thumbnail ?? NSWorkspace.shared.icon(forFile: fileURL.path))
                .resizable()
                .scaledToFit()
                .frame(width: 62, height: 62)
                .shadow(color: .black.opacity(0.10), radius: 3, y: 1.5)

            Text(fileURL.lastPathComponent)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 6)
        }
        .frame(width: 114, height: 104)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    isHovered
                        ? (colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.65))
                        : Color.clear
                )
        )
        .overlay(alignment: .topTrailing) {
            if isHovered {
                HStack(spacing: 3) {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(.primary.opacity(0.75))
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Color.white.opacity(colorScheme == .dark ? 0.22 : 0.92)))
                    }
                    .buttonStyle(.plain)
                    .help("在访达中显示")

                    Button {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                            model.removeFile(fileURL)
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.primary.opacity(0.75))
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Color.white.opacity(colorScheme == .dark ? 0.22 : 0.92)))
                    }
                    .buttonStyle(.plain)
                    .help("从文件盒移除")
                }
                .padding(5)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .task(id: fileURL) {
            let request = QLThumbnailGenerator.Request(
                fileAt: fileURL,
                size: CGSize(width: 128, height: 128),
                scale: NSScreen.main?.backingScaleFactor ?? 2,
                representationTypes: .thumbnail
            )
            if let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request),
               !Task.isCancelled {
                thumbnail = representation.nsImage
            }
        }
    }
}

// MARK: - Inline ShelfFolderBrowser

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
    let onHoverChange: (Bool) -> Void
    let action: () -> Void

    @State private var isHovered = false

    private var geometry: (angle: Double, radius: CGFloat) {
        let angles: [Double] = [180, 150, 120, 90]
        return (angles[index] * .pi / 180, 68)
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(.primary.opacity(isHovered ? 1.0 : 0.88))
                .frame(width: 30, height: 30)
                .background(
                    ZStack {
                        ProZipGlassMaterialView(
                            material: colorScheme == .dark ? .hudWindow : .popover,
                            blendingMode: .behindWindow
                        )
                        Color.white.opacity(colorScheme == .dark ? (isHovered ? 0.22 : 0.14) : (isHovered ? 0.82 : 0.68))
                    }
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(isHovered ? 0.22 : 0.15), radius: isHovered ? 5 : 3, y: 1.5)
                )
                .overlay(
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.36 : 0.90),
                                    Color.black.opacity(colorScheme == .dark ? 0.24 : 0.14)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(ProZipPressScaleStyle(hoverScale: 1.03, pressedScale: 0.93))
        .accessibilityLabel(title)
        .help(title)
        .overlay(alignment: .trailing) {
            if isHovered {
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.92))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 11)
                    .frame(height: 26)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(colorScheme == .dark ? 0.20 : 0.97))
                            .shadow(color: .black.opacity(0.14), radius: 4, y: 2)
                    )
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
                    .offset(x: -38)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                    .allowsHitTesting(false)
            }
        }
        .onHover { hovering in
            withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                isHovered = hovering
            }
            onHoverChange(hovering)
        }
        .scaleEffect(isExpanded ? 1 : 0.25)
        .opacity(isExpanded ? 1 : 0)
        .offset(
            x: 238 + (isExpanded ? CGFloat(cos(geometry.angle)) * geometry.radius : 0),
            y: 245 + (isExpanded ? CGFloat(sin(geometry.angle)) * geometry.radius : 0)
        )
        .allowsHitTesting(isExpanded)
        .animation(
            .spring(response: 0.34, dampingFraction: 0.72)
                .delay(Double(index) * 0.035),
            value: isExpanded
        )
    }
}

// MARK: - AppKit Drop-Hosting Container (Preserves 100% SwiftUI Hit-Testing + Accepts NSURL & NSFilePromiseReceiver)

private struct ShelfDropHostingContainer<Content: View>: NSViewRepresentable {
    var rootView: Content
    var onTargetChanged: @MainActor (Bool) -> Void
    var onDropURLs: @MainActor ([URL]) -> Void
    var onError: @MainActor (Error) -> Void

    func makeNSView(context: Context) -> ShelfDropHostingView<Content> {
        let view = ShelfDropHostingView(rootView: rootView)
        view.onTargetChanged = onTargetChanged
        view.onDropURLs = onDropURLs
        view.onError = onError
        return view
    }

    func updateNSView(_ nsView: ShelfDropHostingView<Content>, context: Context) {
        nsView.onTargetChanged = onTargetChanged
        nsView.onDropURLs = onDropURLs
        nsView.onError = onError
        nsView.update(rootView: rootView)
    }
}

private enum ShelfDropSupport {
    static let legacyFilenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
    static let promiseQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "org.prozip.ProZip.shelfPromiseReceiver"
        queue.qualityOfService = .userInitiated
        return queue
    }()
}

@MainActor
private final class ShelfFirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
private final class ShelfDropHostingView<Content: View>: NSView {
    var onTargetChanged: (@MainActor (Bool) -> Void)?
    var onDropURLs: (@MainActor ([URL]) -> Void)?
    var onError: (@MainActor (Error) -> Void)?

    private let hostingView: ShelfFirstMouseHostingView<Content>

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(rootView: Content) {
        self.hostingView = ShelfFirstMouseHostingView(rootView: rootView)
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 267))
        wantsLayer = true
        layer?.backgroundColor = .clear

        hostingView.frame = bounds
        hostingView.autoresizingMask = [.width, .height]
        hostingView.sizingOptions = []
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        if !hostingView.registeredDraggedTypes.isEmpty {
            hostingView.unregisterDraggedTypes()
        }
        addSubview(hostingView)
        registerDropTypes()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(rootView: Content) {
        hostingView.rootView = rootView
        if !hostingView.registeredDraggedTypes.isEmpty {
            hostingView.unregisterDraggedTypes()
        }
    }

    override func layout() {
        super.layout()
        if hostingView.frame != bounds {
            hostingView.frame = bounds
        }
    }

    private func registerDropTypes() {
        let promiseTypes = NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
        let allTypes = Array(Set(promiseTypes + [.fileURL, ShelfDropSupport.legacyFilenamesType]))
        registerForDraggedTypes(allTypes)
    }

    private func canAccept(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        if let types = pb.types {
            let promiseSet = Set(NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) })
            if !promiseSet.isDisjoint(with: types) {
                return true
            }
        }
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           urls.contains(where: \.isFileURL) {
            return true
        }
        if let paths = pb.propertyList(forType: ShelfDropSupport.legacyFilenamesType) as? [String],
           !paths.isEmpty {
            return true
        }
        return false
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let valid = canAccept(sender)
        onTargetChanged?(valid)
        return valid ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let valid = canAccept(sender)
        onTargetChanged?(valid)
        return valid ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onTargetChanged?(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        canAccept(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onTargetChanged?(false)
        let pb = sender.draggingPasteboard
        let receivers = (pb.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver]) ?? []

        if !receivers.isEmpty {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("org.prozip.ProZip-shelf-promise-\(UUID().uuidString)", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            } catch {
                onError?(error)
                return false
            }
            Task {
                _ = try? await ManagedTemporaryArtifactRegistry.shared.registerArtifact(
                    at: tempDir,
                    purpose: .previewMaterialization,
                    sessionID: "managed-temp:shelf-promise:\(UUID().uuidString)"
                )
            }
            for receiver in receivers {
                receiver.receivePromisedFiles(
                    atDestination: tempDir,
                    options: [:],
                    operationQueue: ShelfDropSupport.promiseQueue
                ) { [weak self] fileURL, error in
                    Task { @MainActor in
                        if let error {
                            self?.onError?(error)
                            return
                        }
                        self?.onDropURLs?([fileURL])
                    }
                }
            }
            return true
        }

        var directURLs = ((pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? [])
            .filter(\.isFileURL)
        if directURLs.isEmpty,
           let paths = pb.propertyList(forType: ShelfDropSupport.legacyFilenamesType) as? [String] {
            directURLs = paths.map { URL(fileURLWithPath: $0) }
        }

        var seen = Set<String>()
        let uniqueURLs = directURLs.filter { seen.insert($0.standardizedFileURL.path).inserted }
        guard !uniqueURLs.isEmpty else { return false }
        onDropURLs?(uniqueURLs)
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        onTargetChanged?(false)
    }
}
