import SwiftUI
import AppKit
import ProZipShared
import ProZipCore
import ProZipEngines
import UniformTypeIdentifiers
import ImageIO

// MARK: - Sorting & Sub-Mode Types

public enum WorkspaceSortField: String, CaseIterable, Sendable {
    case name = "名称"
    case size = "大小"
    case compressedSize = "压缩后"
    case modifiedDate = "修改时间"
    case kind = "类型"
    case crc32 = "CRC32"
}

// MARK: - Main Workspace Window View (FoldspaceWorkspace)

public struct WorkspaceWindowView: View {
    @ObservedObject public var session: ArchiveBrowsingSession
    @EnvironmentObject public var appViewModel: ProZipAppViewModel
    @ObservedObject private var preferences = ProZipPreferences.shared
    @Environment(\.colorScheme) private var colorScheme

    // UI States
    @State private var isLeftSidebarVisible: Bool = false
    @State private var isRightInspectorVisible: Bool = true
    @State private var isTreeExpansionEnabled: Bool = false
    @State private var expandedFolderPaths: Set<String> = []
    @State private var columnDirectoryEntry: ArchiveEntry?

    // Inline Archive Rename State
    @State private var isRenamingArchiveInline: Bool = false
    @State private var inlineArchiveNameDraft: String = ""

    // Encryption Notice Popover State
    @State private var isEncryptionPopoverPresented: Bool = false

    // Sorting State
    @State private var sortField: WorkspaceSortField = .name
    @State private var sortAscending: Bool = true

    // Hover & Floating Preview State
    @State private var hoveredEntryID: String?
    @State private var hoverPreviewEntry: ArchiveEntry?
    @State private var isHoverPreviewHovered = false
    @State private var hoverDebounceTask: Task<Void, Never>?

    // Drag & Drop State
    @State private var isDropTargeted: Bool = false

    @FocusState private var isSearchFocused: Bool
    @Namespace private var viewModeAnimationNamespace

    public init(session: ArchiveBrowsingSession) {
        self.session = session
    }

    public var body: some View {
        HStack(spacing: 0) {
            // 1. Collapsible Left Sidebar (210pt width)
            if isLeftSidebarVisible {
                WorkspaceLeftSidebarView(
                    session: session,
                    expandedFolderPaths: $expandedFolderPaths
                )
                .frame(width: 210)
                .transition(.move(edge: .leading).combined(with: .opacity))

                Divider()
            }

            // 2. Main Center Workspace Area
            VStack(spacing: 0) {
                // Unified Top Toolbar: ArcZip measures 38pt high, top edge at y=13
                workspaceToolbar
                    .frame(height: 38)
                    .padding(.top, 13)
                    .padding(.horizontal, 20)

                // Sub-toolbar / Breadcrumb Pill Bar: 36pt pill at y=58
                breadcrumbBarContainer
                    .padding(.horizontal, 20)
                    .padding(.top, 7)

                // Preliminary Phase Banner
                if case .preliminary = session.phase {
                    phaseBanner
                        .padding(.horizontal, 18)
                        .padding(.bottom, 8)
                } else if case .failed(let message) = session.phase {
                    errorBanner(message: message)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 8)
                }

                // Main Content Area (FoldspaceLanding / List / Tree / Icons / Columns)
                ZStack(alignment: .bottomLeading) {
                    Group {
                        if session.displayedEntries.isEmpty && !session.hasUnsavedChanges && session.currentDirectoryPath.isEmpty && session.searchQuery.isEmpty {
                            FoldspaceLandingView(
                                session: session,
                                isDropTargeted: $isDropTargeted
                            )
                        } else {
                            switch session.viewMode {
                            case .list:
                                WorkspaceListView(
                                    session: session,
                                    sortField: $sortField,
                                    sortAscending: $sortAscending,
                                    isTreeMode: isTreeExpansionEnabled,
                                    expandedFolderPaths: $expandedFolderPaths,
                                    hoveredEntryID: $hoveredEntryID,
                                    onHoverEntryChanged: { entry in
                                        handleEntryHover(entry)
                                    }
                                )
                            case .icons:
                                WorkspaceIconsGridView(
                                    session: session,
                                    hoveredEntryID: $hoveredEntryID,
                                    onHoverEntryChanged: { entry in
                                        handleEntryHover(entry)
                                    }
                                )
                            case .columns:
                                WorkspaceColumnsView(
                                    session: session,
                                    directoryEntry: $columnDirectoryEntry,
                                    hoveredEntryID: $hoveredEntryID,
                                    onHoverEntryChanged: { entry in
                                        handleEntryHover(entry)
                                    }
                                )
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 6)
                    .padding(.top, 16)
                    .padding(.bottom, 72)

                    // Floating Hover Preview Panel (ArchiveHoverPreviewOverlay)
                    if preferences.hoverPreviewEnabled, let previewEntry = hoverPreviewEntry {
                        ArchiveHoverPreviewOverlay(
                            entry: previewEntry,
                            session: session,
                            onClose: {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                                    hoverPreviewEntry = nil
                                }
                            }
                        )
                        .padding(.leading, 18)
                        .padding(.bottom, 66)
                        .onHover { hovering in
                            isHoverPreviewHovered = hovering
                            if hovering { hoverDebounceTask?.cancel() }
                            else if hoveredEntryID == nil { handleEntryHover(nil) }
                        }
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.94, anchor: .bottomLeading).combined(with: .opacity),
                            removal: .opacity
                        ))
                        .zIndex(20)
                    }

                    // Bottom Anchored Flow Bar (WorkspaceFlowOrbitBar)
                    WorkspaceFlowOrbitBar(session: session, navigationEntry: session.viewMode == .columns ? columnDirectoryEntry : nil)
                        .padding(.leading, 20)
                        .padding(.bottom, 21)
                        .zIndex(10)
                }
            }
            .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)

            // 3. Right Inspector Pane (Matching workspace.png pixel-for-pixel)
            if isRightInspectorVisible {
                WorkspaceInspectorPane(
                    session: session,
                    navigationEntry: session.viewMode == .columns ? columnDirectoryEntry : nil,
                    isEncryptionPopoverPresented: $isEncryptionPopoverPresented
                )
                .frame(width: 270)
                .padding(.vertical, 6)
                .padding(.trailing, 6)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(minWidth: 880, idealWidth: 900, maxWidth: .infinity, minHeight: 600, idealHeight: 600, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: .top)
        .overlay(alignment: .topLeading) {
            MainWindowTrafficLightsView(
                zoomBehaviorIsFullScreen: true,
                onClose: { appViewModel.closeSession(id: session.id) },
                onMinimize: { NSApp.keyWindow?.miniaturize(nil) },
                onZoom: {
                    if NSEvent.modifierFlags.contains(.option) { NSApp.keyWindow?.zoom(nil) }
                    else { NSApp.keyWindow?.toggleFullScreen(nil) }
                }
            )
            .padding(.leading, 19)
            .padding(.top, 24)
        }
        .background(colorScheme == .dark ? Color(red: 0.11, green: 0.12, blue: 0.11) : Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
        .sheet(isPresented: Binding(
            get: { appViewModel.isRenameSheetPresented && appViewModel.renamingSessionID == session.id },
            set: { if appViewModel.renamingSessionID == session.id { appViewModel.isRenameSheetPresented = $0 } }
        )) {
            RenameEntrySheetView()
                .environmentObject(appViewModel)
        }
        .onDisappear {
            hoverDebounceTask?.cancel()
        }
    }

    // MARK: - Unified Top Toolbar

    private var workspaceToolbar: some View {
        HStack(spacing: 10) {
            // Left Cluster: Native traffic lights are used (ArcZip parity); reserve 74pt.
            HStack(spacing: 12) {
                // Archive Title + Draft Dot + Inline Rename + Encryption Badge
                HStack(spacing: 6) {
                    if isRenamingArchiveInline {
                        TextField("压缩包名称", text: $inlineArchiveNameDraft)
                            .textFieldStyle(.plain)
                            .font(.system(size: 15, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(NSColor.controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .stroke(ProZipTheme.accent, lineWidth: 1)
                            )
                            .frame(width: 160)
                            .onSubmit {
                                commitInlineArchiveRename()
                            }
                    } else {
                        Text(session.archiveName)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }

                    if session.hasUnsavedChanges {
                        Circle()
                            .fill(ProZipTheme.accent)
                            .frame(width: 7, height: 7)
                            .help("存在未保存的修改")
                    }

                    // Inline Rename Pencil Button
                    Button {
                        if isRenamingArchiveInline {
                            commitInlineArchiveRename()
                        } else {
                            inlineArchiveNameDraft = session.archiveName
                            isRenamingArchiveInline = true
                        }
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("重命名压缩包")

                    // Encryption Status Lock Badge -> ArchiveEncryptionNoticePopover
                    if session.safeDescriptor.isEncrypted || session.displayedEntries.contains(where: \.isEncrypted) {
                        Button {
                            isEncryptionPopoverPresented.toggle()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 10, weight: .semibold))
                                Text(session.safeDescriptor.hasEncryptedHeaders ? "加密头" : "已加密")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundStyle(ProZipTheme.accentDeep)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(ProZipTheme.accentSoft)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $isEncryptionPopoverPresented, arrowEdge: .bottom) {
                            WorkspaceArchiveEncryptionPopover(session: session)
                                .environmentObject(appViewModel)
                        }
                    }
                }
                .padding(.leading, 74)
            }

            Spacer(minLength: 8)
                .overlay { WindowDragArea() }

            // Right Cluster: View Mode Capsule + Action Circle Buttons
            HStack(spacing: 8) {
                // View Mode Switcher Capsule (Matching workspace.png)
                HStack(spacing: 2) {
                    viewModeCapsuleButton(.icons, icon: "square.grid.2x2", tooltip: "图标视图 (⌘1)")
                    viewModeCapsuleButton(.list, icon: "list.bullet", tooltip: "列表视图 (⌘2)")
                    viewModeCapsuleButton(.columns, icon: "rectangle.split.3x1", tooltip: "分栏视图 (⌘3)")
                }
                .padding(4)
                .background(
                    Capsule()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color(white: 0.96))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )

                // Delete Button (Matching workspace.png trash circle button; turns #F2264B crimson when items selected)
                toolbarCircleButton(
                    icon: "trash",
                    tooltip: "删除所选项目",
                    isEnabled: !session.selectedEntryIDs.isEmpty,
                    activeSolidFill: !session.selectedEntryIDs.isEmpty ? Color(red: 0.949, green: 0.149, blue: 0.294) : nil
                ) {
                    session.removeSelectedDraftEntries()
                }

                // Save Button (Matching workspace.png floppy/save circle button; turns #16A34A green when draft modified)
                toolbarCircleButton(
                    icon: "externaldrive.badge.checkmark",
                    customFloppyGraphic: true,
                    tooltip: "保存对压缩包的修改 (⌘S)",
                    isEnabled: session.hasUnsavedChanges,
                    activeSolidFill: session.hasUnsavedChanges ? Color(red: 0.086, green: 0.639, blue: 0.290) : nil
                ) {
                    Task {
                        appViewModel.saveChanges(for: session)
                    }
                }

                // Expandable Search Bar or Search Circle Button
                if session.isSearchExpanded {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)

                        TextField("搜索包内文件…", text: $session.searchQuery)
                            .textFieldStyle(.plain)
                            .focused($isSearchFocused)
                            .onAppear { isSearchFocused = true }
                            .font(.system(size: 12))
                            .frame(width: 136)

                        Button {
                            session.searchQuery = ""
                            withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                                session.isSearchExpanded = false
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(colorScheme == .dark ? Color.white.opacity(0.08) : Color(white: 0.96))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(ProZipTheme.accent.opacity(0.45), lineWidth: 1))
                    .transition(.scale(scale: 0.9, anchor: .trailing).combined(with: .opacity))
                } else {
                    toolbarCircleButton(
                        icon: "magnifyingglass",
                        tooltip: "搜索压缩包 (⌘F)",
                        isEnabled: true
                    ) {
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                            session.isSearchExpanded = true
                        }
                    }
                }
            }
        }
    }

    private func viewModeCapsuleButton(_ mode: WorkspaceViewMode, icon: String, tooltip: String) -> some View {
        let isSelected = session.viewMode == mode
        return Button {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                session.viewMode = mode
            }
        } label: {
            ZStack {
                if isSelected {
                    Circle()
                        .fill(ProZipTheme.accent)
                        .frame(width: 28, height: 28)
                        .matchedGeometryEffect(id: "ViewModeActivePill", in: viewModeAnimationNamespace)
                }
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.68))
            }
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(ProZipPressScaleStyle(hoverScale: 1.04, pressedScale: 0.94))
        .help(tooltip)
    }

    private func toolbarCircleButton(
        icon: String,
        customFloppyGraphic: Bool = false,
        tooltip: String,
        isEnabled: Bool = true,
        isActive: Bool = false,
        activeSolidFill: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        activeSolidFill
                            ?? (isActive
                                ? ProZipTheme.accentSoft
                                : (colorScheme == .dark ? Color.white.opacity(0.06) : Color(white: 0.965)))
                    )
                    .frame(width: 38, height: 38)
                    .overlay(
                        Circle()
                            .stroke(
                                activeSolidFill != nil
                                    ? Color.clear
                                    : (isActive ? ProZipTheme.accent.opacity(0.5) : Color.primary.opacity(0.08)),
                                lineWidth: 1
                            )
                    )

                if customFloppyGraphic {
                    if activeSolidFill != nil {
                        FloppyDiskSaveIcon(isEnabled: true)
                            .colorInvert()
                    } else {
                        FloppyDiskSaveIcon(isEnabled: isEnabled)
                    }
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(
                            activeSolidFill != nil
                                ? Color.white
                                : (isActive
                                    ? ProZipTheme.accent
                                    : (isEnabled ? Color.primary.opacity(0.78) : Color.primary.opacity(0.32)))
                        )
                }
            }
        }
        .buttonStyle(ProZipPressScaleStyle(hoverScale: 1.04, pressedScale: 0.94))
        .disabled(!isEnabled)
        .help(tooltip)
    }

    // MARK: - Sub-Toolbar / Breadcrumb Pill Bar (Matching workspace.png)

    private var breadcrumbBarContainer: some View {
        HStack(spacing: 10) {
            // Rounded White/Glass Pill with Back / Forward / Up + Archive Path Segments
            HStack(spacing: 10) {
                // Navigation Arrows
                HStack(spacing: 6) {
                    Button {
                        Task { await session.goBack() }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 28, height: 28)
                            .foregroundStyle(session.canGoBack ? Color.primary.opacity(0.75) : Color.secondary.opacity(0.35))
                    }
                    .buttonStyle(.plain)
                    .disabled(!session.canGoBack)
                    .help("后退")

                    Button {
                        Task { await session.goForward() }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 28, height: 28)
                            .foregroundStyle(session.canGoForward ? Color.primary.opacity(0.75) : Color.secondary.opacity(0.35))
                    }
                    .buttonStyle(.plain)
                    .disabled(!session.canGoForward)
                    .help("前进")

                    Button {
                        Task { await session.goUp() }
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 28, height: 28)
                            .foregroundStyle(session.canGoUp ? Color.primary.opacity(0.75) : Color.secondary.opacity(0.35))
                    }
                    .buttonStyle(.plain)
                    .disabled(!session.canGoUp)
                    .help("返回上一级目录")
                }

                Divider()
                    .frame(height: 14)

                // Clickable Breadcrumb Segments
                HStack(spacing: 4) {
                    let crumbs = session.breadcrumbs
                    ForEach(Array(crumbs.indices), id: \.self) { idx in
                        let crumb = crumbs[idx]
                        let isLast = idx == crumbs.count - 1

                        if idx > 0 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }

                        Button {
                            Task { await session.enterDirectory(crumb.path) }
                        } label: {
                            HStack(spacing: 5) {
                                if idx == 0 {
                                    ArchiveMiniDocBadgeIcon()
                                } else {
                                    Image(systemName: "folder.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color(red: 0.33, green: 0.68, blue: 0.96))
                                }

                                Text(crumb.title)
                                    .font(.system(size: 11, weight: isLast ? .semibold : .medium))
                                    .foregroundStyle(isLast ? .primary : .secondary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                isLast
                                    ? (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.045))
                                    : Color.clear
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: 470, alignment: .leading)
            .fixedSize(horizontal: true, vertical: false)
            .frame(height: 36)
            .background(
                Capsule()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.06), radius: 6, x: 0, y: 2)
            )
            .overlay(
                Capsule()
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )

            // Modified Draft Banner if session has unsaved mutations
            if session.hasUnsavedChanges {
                HStack(spacing: 8) {
                    Circle()
                        .fill(ProZipTheme.accent)
                        .frame(width: 6, height: 6)

                    Text("已修改 — 待保存 (\(session.pendingMutations.count))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    if session.canUndo {
                        Button("撤销") {
                            Task { await session.undo() }
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ProZipTheme.accent)
                        .buttonStyle(.plain)
                    }

                    Button("保存") {
                        appViewModel.saveChanges(for: session)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(ProZipTheme.accent)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(ProZipTheme.accentSoft)
                .clipShape(Capsule())
            }

            Spacer()

            if session.auxiliaryEntryCount > 0 {
                Button {
                    preferences.showsAuxiliaryEntries.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: preferences.showsAuxiliaryEntries ? "eye" : "eye.slash")
                            .font(.system(size: 12, weight: .medium))
                        Text("\(preferences.showsAuxiliaryEntries ? "已显示" : "已隐藏") \(session.auxiliaryEntryCount) 项")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .foregroundStyle(preferences.showsAuxiliaryEntries ? ProZipTheme.accent : .secondary)
                    .background(preferences.showsAuxiliaryEntries ? ProZipTheme.accentSoft : Color.clear, in: Capsule())
                    .overlay(Capsule().stroke(preferences.showsAuxiliaryEntries ? ProZipTheme.accent.opacity(0.25) : Color.primary.opacity(0.06), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .fixedSize()
                .accessibilityLabel(preferences.showsAuxiliaryEntries ? "隐藏辅助项目" : "显示辅助项目")
                .accessibilityValue("\(session.auxiliaryEntryCount) 个辅助项目")
            }
        }
    }

    // MARK: - Banners

    private var phaseBanner: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.65)
                .frame(width: 14, height: 14)

            Text(session.phase.statusBannerText ?? "正在建立文件索引… 可以浏览和全部解压。文件列表读取完成后可搜索、预览、拖出或解压所选文件。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(ProZipTheme.accentSoft)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 12))

            Text(message)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    // MARK: - Helpers

    private func commitInlineArchiveRename() {
        isRenamingArchiveInline = false
        do {
            try appViewModel.renameArchive(session, to: inlineArchiveNameDraft)
        } catch {
            appViewModel.alertTitle = "无法重命名压缩包"
            appViewModel.alertMessage = error.localizedDescription
            appViewModel.isAlertPresented = true
        }
    }

    private func handleEntryHover(_ entry: ArchiveEntry?) {
        hoverDebounceTask?.cancel()
        guard preferences.hoverPreviewEnabled, let entry = entry, !entry.isDirectory else {
            hoverDebounceTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 180_000_000)
                if !Task.isCancelled && hoveredEntryID == nil && !isHoverPreviewHovered {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                        hoverPreviewEntry = nil
                    }
                }
            }
            return
        }

        hoverDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                hoverPreviewEntry = entry
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard providers.contains(where: { $0.hasItemConformingToTypeIdentifier("public.file-url") }) else { return false }
        Task { @MainActor in
            let urls = await FileURLDrop.loadURLs(from: providers)
            do { try session.addFiles(urls) }
            catch {
                appViewModel.alertTitle = "无法添加文件"
                appViewModel.alertMessage = error.localizedDescription
                appViewModel.isAlertPresented = true
            }
        }
        return true
    }
}

// MARK: - Interactive macOS Window Traffic Lights (#FF5F57, #FEBC2E, #28C840)

public struct MainWindowTrafficLightsView: View {
    public var zoomBehaviorIsFullScreen: Bool
    public var onClose: () -> Void
    public var onMinimize: () -> Void
    public var onZoom: () -> Void

    @State private var isHoveringCluster: Bool = false

    public init(
        zoomBehaviorIsFullScreen: Bool = false,
        onClose: @escaping () -> Void = {},
        onMinimize: @escaping () -> Void = {},
        onZoom: @escaping () -> Void = {}
    ) {
        self.zoomBehaviorIsFullScreen = zoomBehaviorIsFullScreen
        self.onClose = onClose
        self.onMinimize = onMinimize
        self.onZoom = onZoom
    }

    public var body: some View {
        HStack(spacing: 4) {
            trafficLightButton(
                fill: Color(red: 1.0, green: 0.373, blue: 0.341), // #FF5F57
                stroke: Color(red: 0.88, green: 0.27, blue: 0.25),
                symbol: "xmark",
                action: onClose
            )

            trafficLightButton(
                fill: Color(red: 0.996, green: 0.737, blue: 0.180), // #FEBC2E
                stroke: Color(red: 0.87, green: 0.62, blue: 0.10),
                symbol: "minus",
                action: onMinimize
            )

            trafficLightButton(
                fill: Color(red: 0.157, green: 0.784, blue: 0.251), // #28C840
                stroke: Color(red: 0.11, green: 0.66, blue: 0.18),
                symbol: zoomBehaviorIsFullScreen ? "arrow.up.left.and.arrow.down.right" : "plus",
                action: onZoom
            )
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHoveringCluster = hovering
            }
        }
    }

    private func trafficLightButton(
        fill: Color,
        stroke: Color,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(fill)
                    .frame(width: 14, height: 14)
                    .overlay(
                        Circle()
                            .stroke(stroke.opacity(0.65), lineWidth: 0.5)
                    )

                if isHoveringCluster {
                    Image(systemName: symbol)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.65))
                }
            }
        }
        .buttonStyle(.plain)
        .frame(width: 16, height: 16)
        .accessibilityLabel(symbol == "xmark" ? "关闭" : symbol == "minus" ? "最小化" : zoomBehaviorIsFullScreen ? "全屏幕" : "缩放窗口")
    }
}

// MARK: - Custom Toolbar & Breadcrumb Graphics (Matching workspace.png)

private struct FloppyDiskSaveIcon: View {
    let isEnabled: Bool

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let rect = CGRect(x: w * 0.22, y: h * 0.22, width: w * 0.56, height: h * 0.56)
            let bodyPath = Path(roundedRect: rect, cornerRadius: 2.5, style: .continuous)
            let shutterRect = CGRect(x: w * 0.33, y: h * 0.22, width: w * 0.34, height: h * 0.20)
            let labelRect = CGRect(x: w * 0.31, y: h * 0.52, width: w * 0.38, height: h * 0.26)

            let strokeColor = isEnabled ? Color.primary.opacity(0.75) : Color.primary.opacity(0.32)
            context.stroke(bodyPath, with: .color(strokeColor), lineWidth: 1.3)
            context.stroke(Path(roundedRect: shutterRect, cornerRadius: 1), with: .color(strokeColor), lineWidth: 1.1)
            context.stroke(Path(roundedRect: labelRect, cornerRadius: 1), with: .color(strokeColor), lineWidth: 1.1)
        }
        .frame(width: 24, height: 24)
    }
}

private struct ArchiveMiniDocBadgeIcon: View {
    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(for: .zip))
            .resizable()
            .scaledToFit()
            .frame(width: 14, height: 14)
    }
}

// MARK: - Left Sidebar View (210pt Width)

public struct WorkspaceLeftSidebarView: View {
    @ObservedObject public var session: ArchiveBrowsingSession
    @Binding public var expandedFolderPaths: Set<String>
    @EnvironmentObject public var appViewModel: ProZipAppViewModel
    @Environment(\.colorScheme) private var colorScheme

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section 1: Directory Tree
            VStack(alignment: .leading, spacing: 6) {
                Text("当前位置")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)

                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        sidebarFolderRow(
                            title: session.archiveName,
                            path: "",
                            icon: "doc.zipper",
                            depth: 0
                        )

                        ForEach(topLevelFolders, id: \.id) { folder in
                            sidebarFolderRow(
                                title: folder.name,
                                path: folder.path,
                                icon: "folder.fill",
                                depth: 1
                            )
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .frame(maxHeight: 200)
            }

            Divider()

            // Section 2: Quick Shortcuts
            VStack(alignment: .leading, spacing: 6) {
                Text("快捷入口")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)

                VStack(spacing: 2) {
                    sidebarActionButton(title: "添加文件到压缩包…", icon: "plus.circle") {
                        appViewModel.promptAddFiles(to: session)
                    }
                    sidebarActionButton(title: "新建压缩包…", icon: "doc.badge.plus") {
                        appViewModel.beginCreation(sources: [], ownerSessionID: session.id)
                    }
                    sidebarActionButton(title: "切换到 Mini 窗口", icon: "pip.enter") {
                        session.isMiniMode = true
                    }
                    sidebarActionButton(title: "打开任务队列", icon: "checklist") {
                        appViewModel.isTaskProgressPresented = true
                    }
                }
                .padding(.horizontal, 8)
            }

            Divider()

            // Section 3: Archive Statistics
            VStack(alignment: .leading, spacing: 8) {
                Text("统计信息")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                let totalUncompressed = session.displayedEntries.reduce(Int64(0)) { $0 + $1.uncompressedSize }
                let totalCompressed = max(session.safeDescriptor.totalCompressedSize, session.displayedEntries.reduce(Int64(0)) { $0 + $1.compressedSize })
                let ratio = totalUncompressed > 0 ? min(1.0, max(0.0, Double(totalCompressed) / Double(totalUncompressed))) : 1.0

                VStack(spacing: 6) {
                    statRow(label: "当前目录条目", value: "\(session.displayedEntries.count)")
                    statRow(label: "原始大小", value: ByteCountFormatter.string(fromByteCount: totalUncompressed, countStyle: .file))
                    statRow(label: "压缩后大小", value: ByteCountFormatter.string(fromByteCount: totalCompressed, countStyle: .file))

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("压缩体积占比")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int((ratio * 100).rounded()))%")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(ProZipTheme.accent)
                        }

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.primary.opacity(0.08))
                                    .frame(height: 5)
                                Capsule()
                                    .fill(ProZipTheme.accent)
                                    .frame(width: max(6, geo.size.width * ratio), height: 5)
                            }
                        }
                        .frame(height: 5)
                    }
                    .padding(.top, 2)
                }
                .padding(10)
                .background(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .padding(.horizontal, 12)

            Spacer()
        }
        .padding(.vertical, 14)
        .background(colorScheme == .dark ? Color(red: 0.13, green: 0.14, blue: 0.13) : Color(white: 0.975))
    }

    private var topLevelFolders: [ArchiveEntry] {
        session.displayedEntries.filter(\.isDirectory)
    }

    private func sidebarFolderRow(title: String, path: String, icon: String, depth: Int) -> some View {
        let isCurrent = session.currentDirectoryPath == path
        return Button {
            Task { await session.enterDirectory(path) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(isCurrent ? ProZipTheme.accent : Color(red: 0.33, green: 0.68, blue: 0.96))
                Text(title)
                    .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? .primary : .secondary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.leading, CGFloat(depth * 14) + 8)
            .padding(.trailing, 8)
            .padding(.vertical, 5)
            .background(isCurrent ? ProZipTheme.accentSoft : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func sidebarActionButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(ProZipTheme.accent)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - FoldspaceLanding Welcome & Empty Archive Drop Zone

public struct FoldspaceLandingView: View {
    @ObservedObject public var session: ArchiveBrowsingSession
    @Binding public var isDropTargeted: Bool
    @EnvironmentObject public var appViewModel: ProZipAppViewModel
    @Environment(\.colorScheme) private var colorScheme

    public init(session: ArchiveBrowsingSession, isDropTargeted: Binding<Bool>) {
        self.session = session
        self._isDropTargeted = isDropTargeted
    }

    public var body: some View {
        ZStack(alignment: .top) {
            // Faint list skeleton (ArcZip shows the header + zebra rhythm behind the card)
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text("名称")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 16)
                    Text("大小")
                        .frame(width: 96, alignment: .leading)
                        .padding(.leading, 10)
                    Text("修改时间")
                        .frame(width: 144, alignment: .leading)
                        .padding(.leading, 1)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary.opacity(0.18))
                .frame(height: 28)

                Divider().padding(.horizontal, 8)

                VStack(spacing: 24) {
                    ForEach(0..<12, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.028))
                            .frame(height: 24)
                            .padding(.horizontal, 10)
                    }
                }
                .padding(.top, 2)
                Spacer(minLength: 0)
            }
            .allowsHitTesting(false)

            // 420×187 dashed drop card at y=166 inside the content area
            VStack(spacing: 8) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(.secondary)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "cursorarrow")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .offset(x: 8, y: 4)
                    }
                    .padding(.bottom, 4)

                Text("添加文件到压缩包")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("点击添加文件，或直接将文件拖到这里")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 420, height: 187)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.white.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        isDropTargeted ? ProZipTheme.accent : Color.secondary.opacity(0.32),
                        style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1.5, dash: [6, 4])
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .onTapGesture {
                appViewModel.promptAddFiles(to: session)
            }
            .padding(.top, 166)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard providers.contains(where: { $0.hasItemConformingToTypeIdentifier("public.file-url") }) else { return false }
        Task { @MainActor in
            let urls = await FileURLDrop.loadURLs(from: providers)
            do { try session.addFiles(urls) }
            catch {
                appViewModel.alertTitle = "无法添加文件"
                appViewModel.alertMessage = error.localizedDescription
                appViewModel.isAlertPresented = true
            }
        }
        return true
    }
}

// MARK: - Archive Encryption Notice Popover

public struct WorkspaceArchiveEncryptionPopover: View {
    @ObservedObject public var session: ArchiveBrowsingSession
    @EnvironmentObject public var appViewModel: ProZipAppViewModel
    @Environment(\.dismiss) private var dismiss

    public init(session: ArchiveBrowsingSession) {
        self.session = session
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(ProZipTheme.accentSoft)
                        .frame(width: 34, height: 34)
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(ProZipTheme.accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.safeDescriptor.hasEncryptedHeaders ? "加密文件名与内容" : "密码保护归档")
                        .font(.system(size: 13, weight: .bold))
                    Text("\(session.safeDescriptor.format.displayName) · AES-256 / ZipCrypto")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Text("此压缩包包含受密码保护的条目。解压或预览加密文件时将自动查询密码本，或提示您输入密码。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("密码本设置…") {
                    dismiss()
                    appViewModel.settingsSelectedTab = .passwordBook
                    appViewModel.isSettingsPresented = true
                }
                .font(.system(size: 11))

                Spacer()

                Button("输入密码…") {
                    dismiss()
                    appViewModel.requestArchivePassword(for: session)
                }
                .buttonStyle(.borderedProminent)
                .tint(ProZipTheme.accent)
                .font(.system(size: 11))
            }
        }
        .padding(14)
        .frame(width: 280)
    }
}

// MARK: - Floating Hover Preview Overlay (ArchiveHoverPreviewPanel / Surface)

public struct ArchiveHoverPreviewOverlay: View {
    public let entry: ArchiveEntry
    @ObservedObject public var session: ArchiveBrowsingSession
    public var onClose: () -> Void
    @EnvironmentObject public var appViewModel: ProZipAppViewModel
    @Environment(\.colorScheme) private var colorScheme

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top Header: Thumbnail / Visual Preview + File Identity
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(ProZipTheme.accentSoft)
                        .frame(width: 44, height: 44)

                    EntryRichFileIconView(entry: entry, size: 26)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(entry.name)
                            .font(.system(size: 13, weight: .bold))
                            .lineLimit(1)

                        if entry.isEncrypted {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(ProZipTheme.accent)
                        }
                    }

                    HStack(spacing: 6) {
                        Text(entry.fileExtension.isEmpty ? "文件" : entry.fileExtension.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(ProZipTheme.accentDeep)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(ProZipTheme.accentSoft)
                            .clipShape(Capsule())

                        Text(ByteCountFormatter.string(fromByteCount: entry.uncompressedSize, countStyle: .file))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            ArchiveHoverContent(entry: entry, session: session)

            // Metadata Grid
            VStack(spacing: 5) {
                hoverMetaRow(
                    label: "压缩后大小",
                    value: ByteCountFormatter.string(fromByteCount: entry.compressedSize, countStyle: .file)
                )
                hoverMetaRow(
                    label: "压缩率",
                    value: compressionRatioString(for: entry)
                )
                hoverMetaRow(
                    label: "CRC32 校验",
                    value: entry.crc32 == 0 ? "—" : String(format: "%08X", entry.crc32)
                )
                hoverMetaRow(
                    label: "修改时间",
                    value: WorkspaceDateFormatters.displayString(from: entry.modifiedAt)
                )
            }

            Divider()

            // Quick Actions
            HStack(spacing: 8) {
                Button {
                    session.selectOnly(entry.id)
                    appViewModel.previewSelected(in: session)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "eye")
                            .font(.system(size: 11))
                        Text("快速预览")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    appViewModel.extractSelection([entry], in: session)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.system(size: 11))
                        Text("解压此项")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(ProZipTheme.accent)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(width: 280)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(colorScheme == .dark ? Color(red: 0.16, green: 0.18, blue: 0.15).opacity(0.96) : Color.white.opacity(0.97))
                .shadow(color: Color.black.opacity(0.18), radius: 14, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(ProZipTheme.accent.opacity(0.35), lineWidth: 1)
        )
    }

    private func hoverMetaRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium, design: label.contains("CRC") ? .monospaced : .default))
                .foregroundStyle(.primary)
        }
    }

    private func compressionRatioString(for entry: ArchiveEntry) -> String {
        guard entry.uncompressedSize > 0 else { return "—" }
        let ratio = Double(entry.compressedSize) / Double(entry.uncompressedSize) * 100.0
        return String(format: "%.0f%%", min(100, max(1, ratio)))
    }
}

// MARK: - Bottom Anchored Flow Bar (WorkspaceFlowOrbitBar, Matching workspace.png)

public struct WorkspaceFlowOrbitBar: View {
    @ObservedObject public var session: ArchiveBrowsingSession
    public var navigationEntry: ArchiveEntry?
    @EnvironmentObject public var appViewModel: ProZipAppViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var orbitPoint: CGPoint?

    public init(session: ArchiveBrowsingSession, navigationEntry: ArchiveEntry? = nil) {
        self.session = session
        self.navigationEntry = navigationEntry
    }

    public var body: some View {
        let selection = session.selectedEntries.isEmpty ? navigationEntry.map { [$0] } ?? [] : session.selectedEntries
        let rec = session.initialSourceStat == nil ? nil : FlowActionRouter.recommendAction(
            for: selection,
            in: session.safeDescriptor,
            allowedFormats: ProZipPreferences.shared.allowedOpenFormats
        )

        HStack(alignment: .bottom, spacing: 10) {
            // Left White Capsule: [⤡] [↑ 全部解压 ⏎] [👁 预览 空格]
            HStack(spacing: 1) {
                if session.initialSourceStat != nil {
                Button {
                    session.isMiniMode = true
                } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.72))
                        .frame(width: 34, height: 34)
                        .contentShape(Circle())
                }
                .buttonStyle(ProZipPressScaleStyle(hoverScale: 1.05, pressedScale: 0.93))
                .help("切换到 Mini 窗口 (⌥⌘M)")

                }

                Button {
                    appViewModel.extractAll(in: session)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "arrow.up.square")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)

                        Text("全部解压")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)

                        keyboardShortcutBadge("⏎", isHighlighted: false)
                    }
                    .frame(width: 129, height: 34)
                    .contentShape(Capsule())
                }
                .buttonStyle(ProZipPressScaleStyle(hoverScale: 1.02, pressedScale: 0.97))
                .disabled(session.initialSourceStat == nil || !session.phase.canExtractAll)
                .help("解压全部文件 (回车)")

                Button {
                    appViewModel.previewSelected(in: session)
                } label: {
                    let hasSelection = !session.selectedEntryIDs.isEmpty
                    HStack(spacing: 6) {
                        Image(systemName: "eye")
                            .font(.system(size: 12, weight: .medium))
                        Text("预览")
                            .font(.system(size: 13, weight: .medium))
                        keyboardShortcutBadge("空格", isHighlighted: false)
                    }
                    .frame(width: 108, height: 34)
                    .foregroundStyle(hasSelection ? Color.primary.opacity(0.85) : Color.secondary.opacity(0.55))
                    .contentShape(Capsule())
                }
                .buttonStyle(ProZipPressScaleStyle(hoverScale: 1.02, pressedScale: 0.97))
                .disabled(session.selectedEntryIDs.isEmpty)
                .help("使用快速查看预览所选文件 (空格)")
            }
            .padding(.leading, 3)
            .padding(.trailing, 14)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(colorScheme == .dark ? Color(red: 0.16, green: 0.17, blue: 0.16).opacity(0.96) : Color.white.opacity(0.96))
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.32 : 0.08), radius: 8, x: 0, y: 3)
            )
            .overlay(
                Capsule()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .overlay(alignment: .leading) {
                if let point = orbitPoint {
                    Circle()
                        .fill(ProZipTheme.accent.opacity(0.20))
                        .frame(width: 86, height: 86)
                        .blur(radius: 18)
                        .offset(x: max(0, point.x - 43), y: 0)
                        .allowsHitTesting(false)
                }
            }
            .clipShape(Capsule())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    withAnimation(.easeOut(duration: 0.10)) { orbitPoint = point }
                case .ended:
                    withAnimation(.easeOut(duration: 0.18)) { orbitPoint = nil }
                }
            }

            // Right Independent Floating Flow Pill (Matching arczip_live_workspace_selected_search.png & draft.png!)
            if let flowRec = rec {
                WorkspaceFlowButton(recommendation: flowRec, selection: selection, session: session) {
                    if session.selectedEntries.isEmpty, let navigationEntry {
                        appViewModel.extractSelection([navigationEntry], in: session)
                    } else {
                        appViewModel.executeFlowAction(flowRec, in: session)
                    }
                }
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            } else if session.initialSourceStat == nil || session.hasUnsavedChanges || session.displayedEntries.isEmpty {
                Button {
                    appViewModel.promptAddFiles(to: session)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("添加文件")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 40)
                    .background(ProZipTheme.accent)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .shadow(color: ProZipTheme.accent.opacity(0.28), radius: 6, y: 2)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func keyboardShortcutBadge(_ text: String, isHighlighted: Bool) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(isHighlighted ? Color.white : Color.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isHighlighted ? Color.white.opacity(0.22) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(isHighlighted ? Color.white.opacity(0.35) : Color.primary.opacity(0.10), lineWidth: 0.6)
            )
    }
}

// MARK: - Workspace List View (Matching workspace.png Pixel-for-Pixel)

public struct WorkspaceListView: View {
    @ObservedObject public var session: ArchiveBrowsingSession
    @Binding public var sortField: WorkspaceSortField
    @Binding public var sortAscending: Bool
    public var isTreeMode: Bool
    @Binding public var expandedFolderPaths: Set<String>
    @Binding public var hoveredEntryID: String?
    public var onHoverEntryChanged: ((ArchiveEntry?) -> Void)?

    @EnvironmentObject public var appViewModel: ProZipAppViewModel
    @ObservedObject private var preferences = ProZipPreferences.shared
    @Environment(\.colorScheme) private var colorScheme

    private struct SortInput: Equatable {
        let revision: UInt
        let field: WorkspaceSortField
        let ascending: Bool
        let showsAuxiliary: Bool
        let treeMode: Bool
        let expandedPaths: Set<String>
    }
    @State private var cachedSortInput: SortInput?
    @State private var cachedVisibleItems: [FlattenedTreeItem] = []
    @State private var cachedKeyboardEntries: [ArchiveEntry] = []

    private var sortInput: SortInput {
        SortInput(revision: session.displayedEntriesRevision, field: sortField, ascending: sortAscending, showsAuxiliary: preferences.showsAuxiliaryEntries, treeMode: isTreeMode, expandedPaths: expandedFolderPaths)
    }

    public init(
        session: ArchiveBrowsingSession,
        sortField: Binding<WorkspaceSortField> = .constant(.name),
        sortAscending: Binding<Bool> = .constant(true),
        isTreeMode: Bool = false,
        expandedFolderPaths: Binding<Set<String>> = .constant([]),
        hoveredEntryID: Binding<String?> = .constant(nil),
        onHoverEntryChanged: ((ArchiveEntry?) -> Void)? = nil
    ) {
        self.session = session
        self._sortField = sortField
        self._sortAscending = sortAscending
        self.isTreeMode = isTreeMode
        self._expandedFolderPaths = expandedFolderPaths
        self._hoveredEntryID = hoveredEntryID
        self.onHoverEntryChanged = onHoverEntryChanged
    }

    public var body: some View {
        let visibleItems = sortedVisibleItems
        return VStack(spacing: 0) {
            // Column Headers Bar (名称 | 大小 | 修改时间)
            HStack(spacing: 0) {
                sortableHeaderButton(field: .name, title: "名称")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 19)

                headerColumnDivider

                sortableHeaderButton(field: .size, title: "大小")
                    .frame(width: 96, alignment: .leading)
                    .padding(.leading, 13)

                headerColumnDivider

                sortableHeaderButton(field: .modifiedDate, title: "修改时间")
                    .frame(width: 144, alignment: .leading)
                    .padding(.leading, 10)

                headerColumnDivider
                    .padding(.trailing, 10)
            }
            .frame(height: 28)

            Divider()

            // Main Table Rows with Full-Viewport Alternating Zebra Stripes (Matching workspace.png)
            GeometryReader { geo in
                // ArcZip draws a decorative zebra pattern under the real rows:
                // 24pt rounded bands with a 24pt gap, starting one row-gap below the content.
                let fillerCount = max(0, Int(ceil(geo.size.height / 48.0)) + 1)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                            let entry = item.entry
                            let isSelected = session.selectedEntryIDs.contains(entry.id)
                            let isHovered = hoveredEntryID == entry.id

                            WorkspaceRowItemView(
                                entry: entry,
                                session: session,
                                index: index,
                                depth: item.depth,
                                showDisclosure: isTreeMode && entry.isDirectory,
                                isExpanded: expandedFolderPaths.contains(entry.path),
                                isSelected: isSelected,
                                isHovered: isHovered,
                                onToggleExpand: {
                                    toggleFolderExpansion(entry.path)
                                },
                                onSingleClick: {
                                    ArchiveSelectionInteraction.click(entry, in: session, orderedEntries: cachedKeyboardEntries)
                                },
                                onDoubleClick: {
                                    handleDoubleClick(on: entry)
                                }
                            )
                            .overlay(alignment: .leading) {
                                GeometryReader { geometry in
                                    ArchiveFileDragHitArea(entry: entry, session: session, orderedEntries: cachedKeyboardEntries, onClick: { count, modifiers in
                                        if count >= 2 { handleDoubleClick(on: entry) }
                                        else { ArchiveSelectionInteraction.click(entry, in: session, orderedEntries: cachedKeyboardEntries, modifiers: modifiers) }
                                    }, onHover: { hovering in
                                        hoveredEntryID = hovering ? entry.id : (hoveredEntryID == entry.id ? nil : hoveredEntryID)
                                        onHoverEntryChanged?(hovering ? entry : nil)
                                    })
                                    .frame(width: max(0, geometry.size.width - 270))
                                    .padding(.leading, isTreeMode ? 20 + CGFloat(item.depth * 18) : 0)
                                }
                            }
                            .contextMenu {
                                FileItemContextMenu(entry: entry, session: session)
                                    .environmentObject(appViewModel)
                            }
                        }

                        // Decorative zebra filler bands (ArcZip-style background rhythm)
                        VStack(spacing: 24) {
                            ForEach(0..<fillerCount, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.040))
                                    .frame(height: 24)
                                    .padding(.horizontal, 10)
                            }
                        }
                        .padding(.top, 0)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            session.selectedEntryIDs.removeAll()
                        }
                    }
                    .padding(.top, 4)
                    .accessibilityElement(children: .contain)
                }
                .scrollIndicators(.never)
            }
        }
        .modifier(ArchiveKeyboardNavigation(session: session, entries: cachedSortInput == sortInput ? cachedKeyboardEntries : visibleItems.map(\.entry)))
        .onAppear { refreshSortCache() }
        .onChange(of: sortInput) { _, _ in refreshSortCache() }
    }

    private var headerColumnDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.10))
            .frame(width: 1, height: 14)
    }

    private func sortableHeaderButton(field: WorkspaceSortField, title: String) -> some View {
        Button {
            if sortField == field {
                sortAscending.toggle()
            } else {
                sortField = field
                sortAscending = true
            }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                if sortField == field {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func zebraFillColor(index: Int, isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected {
            return ProZipTheme.accent.opacity(colorScheme == .dark ? 0.30 : 0.20)
        }
        if isHovered {
            return ProZipTheme.accent.opacity(colorScheme == .dark ? 0.14 : 0.09)
        }
        if index % 2 == 1 {
            return colorScheme == .dark
                ? Color.white.opacity(0.04)
                : Color.black.opacity(0.038)
        }
        return Color.clear
    }

    private struct FlattenedTreeItem: Identifiable {
        var id: String { entry.id }
        let entry: ArchiveEntry
        let depth: Int
    }

    private var sortedVisibleItems: [FlattenedTreeItem] {
        cachedSortInput == sortInput ? cachedVisibleItems : makeVisibleItems()
    }

    private func refreshSortCache() {
        cachedVisibleItems = makeVisibleItems()
        cachedKeyboardEntries = cachedVisibleItems.map(\.entry)
        cachedSortInput = sortInput
    }

    private func makeVisibleItems() -> [FlattenedTreeItem] {
        let baseItems = session.currentItems.filter { entry in
            preferences.showsAuxiliaryEntries || !entry.isAuxiliary
        }
        let sorted = sortEntries(baseItems)
        var result: [FlattenedTreeItem] = []
        for entry in sorted {
            result.append(FlattenedTreeItem(entry: entry, depth: 0))
            if isTreeMode && entry.isDirectory && expandedFolderPaths.contains(entry.path) {
                let childItems = session.displayedEntries.filter { $0.parentPath == entry.path }
                for child in sortEntries(childItems) {
                    result.append(FlattenedTreeItem(entry: child, depth: 1))
                }
            }
        }
        return result
    }

    private func sortEntries(_ entries: [ArchiveEntry]) -> [ArchiveEntry] {
        entries.sorted { a, b in
            if a.isDirectory != b.isDirectory {
                return a.isDirectory && !b.isDirectory
            }
            let lhs = sortAscending ? a : b
            let rhs = sortAscending ? b : a
            let comparison: Bool
            switch sortField {
            case .name:
                comparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .size:
                comparison = lhs.uncompressedSize < rhs.uncompressedSize
            case .compressedSize:
                comparison = lhs.compressedSize < rhs.compressedSize
            case .modifiedDate:
                comparison = lhs.modifiedAt < rhs.modifiedAt
            case .kind:
                comparison = lhs.fileExtension < rhs.fileExtension
            case .crc32:
                comparison = lhs.crc32 < rhs.crc32
            }
            return comparison
        }
    }

    private func toggleFolderExpansion(_ path: String) {
        withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
            if expandedFolderPaths.contains(path) {
                expandedFolderPaths.remove(path)
            } else {
                expandedFolderPaths.insert(path)
            }
        }
    }

    private func handleDoubleClick(on entry: ArchiveEntry) {
        if entry.isDirectory {
            Task { await session.enterDirectory(entry.path) }
        } else {
            let rec = FlowActionRouter.recommendAction(
                for: [entry],
                in: session.safeDescriptor,
                allowedFormats: ProZipPreferences.shared.allowedOpenFormats
            )
            if let r = rec, r.isEnabled {
                appViewModel.executeFlowAction(r, in: session)
            } else {
                appViewModel.previewSelected(in: session)
            }
        }
    }
}

// MARK: - Workspace Row Item View (Matching workspace.png Zebra Pill Rows)

public struct WorkspaceRowItemView: View {
    public let entry: ArchiveEntry
    public var session: ArchiveBrowsingSession?
    public let index: Int
    public var depth: Int = 0
    public var showDisclosure: Bool = false
    public var isExpanded: Bool = false
    public let isSelected: Bool
    public var isHovered: Bool = false
    public var onToggleExpand: (() -> Void)? = nil
    public let onSingleClick: () -> Void
    public let onDoubleClick: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    public init(
        entry: ArchiveEntry,
        session: ArchiveBrowsingSession? = nil,
        index: Int,
        depth: Int = 0,
        showDisclosure: Bool = false,
        isExpanded: Bool = false,
        isSelected: Bool,
        isHovered: Bool = false,
        onToggleExpand: (() -> Void)? = nil,
        onSingleClick: @escaping () -> Void,
        onDoubleClick: @escaping () -> Void
    ) {
        self.entry = entry
        self.session = session
        self.index = index
        self.depth = depth
        self.showDisclosure = showDisclosure
        self.isExpanded = isExpanded
        self.isSelected = isSelected
        self.isHovered = isHovered
        self.onToggleExpand = onToggleExpand
        self.onSingleClick = onSingleClick
        self.onDoubleClick = onDoubleClick
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Name Column (Icon + Name + Lock Badge)
            HStack(spacing: 10) {
                if depth > 0 {
                    Spacer()
                        .frame(width: CGFloat(depth * 18))
                }

                if showDisclosure {
                    Button {
                        onToggleExpand?()
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .frame(width: 12, height: 12)
                    }
                    .buttonStyle(.plain)
                }

                if let session {
                    ArchiveEntryThumbnail(entry: entry, session: session, size: CGSize(width: 19, height: 17))
                } else {
                    EntryRichFileIconView(entry: entry, size: 17)
                }

                Text(entry.name)
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .lineLimit(1)

                if entry.isEncrypted {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(ProZipTheme.accent)
                }

                if entry.isAuxiliary {
                    Text("辅助")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 29)

            // Size Column
            Text(entry.isDirectory ? "—" : WorkspaceDateFormatters.sizeString(for: entry.uncompressedSize))
                .font(.system(size: 12.5))
                .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.82))
                .frame(width: 107, alignment: .leading)
                .padding(.leading, 0)
                .offset(x: -11)

            // Modified Time Column
            Text(WorkspaceDateFormatters.displayString(from: entry.modifiedAt))
                .font(.system(size: 12.5))
                .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.82))
                .lineLimit(1)
                .frame(width: 134, alignment: .leading)
                .padding(.leading, 1)
                .padding(.trailing, 10)
                .offset(x: -10.5)
        }
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(rowBackgroundColor)
                .padding(.horizontal, 10)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.name)
        .accessibilityValue("\(entry.isDirectory ? "文件夹" : WorkspaceDateFormatters.sizeString(for: entry.uncompressedSize))，\(WorkspaceDateFormatters.displayString(from: entry.modifiedAt))")
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityAction { onSingleClick() }
        .accessibilityAction(named: Text("打开")) { onDoubleClick() }
        .animation(.easeOut(duration: 0.10), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: isSelected)
        .onTapGesture(count: 2, perform: onDoubleClick)
        .onTapGesture(count: 1, perform: onSingleClick)
    }

    private var rowBackgroundColor: Color {
        if isSelected {
            return Color(nsColor: .selectedContentBackgroundColor)
        }
        if isHovered {
            return ProZipTheme.accent.opacity(colorScheme == .dark ? 0.14 : 0.08)
        }
        if index % 2 == 1 {
            return colorScheme == .dark
                ? Color.white.opacity(0.04)
                : Color.black.opacity(0.038)
        }
        return Color.clear
    }
}

// MARK: - Rich Entry File Icon View (Matching workspace.png Folder / Bin / Txt Icons)

public struct EntryRichFileIconView: View {
    public let entry: ArchiveEntry
    public var size: CGFloat = 18

    public init(entry: ArchiveEntry, size: CGFloat = 18) {
        self.entry = entry
        self.size = size
    }

    public var body: some View {
        if entry.isDirectory {
            // macOS Aqua Blue Folder Graphic
            ZStack {
                Image(systemName: "folder.fill")
                    .font(.system(size: size))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.42, green: 0.76, blue: 0.98),
                                Color(red: 0.22, green: 0.60, blue: 0.92)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .frame(width: size + 2, height: size)
        } else if entry.fileExtension == "txt" || entry.fileExtension == "md" || entry.fileExtension == "log" {
            // Landscape White Card with Text Lines (Matching readme.txt in workspace.png)
            ZStack {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(Color.white)
                    .frame(width: size, height: size * 0.72)
                    .shadow(color: Color.black.opacity(0.12), radius: 1, y: 0.5)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .stroke(Color.black.opacity(0.12), lineWidth: 0.5)
                    )

                VStack(alignment: .leading, spacing: 1.5) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.55))
                        .frame(width: size * 0.45, height: 1.2)
                    Capsule()
                        .fill(Color.secondary.opacity(0.35))
                        .frame(width: size * 0.62, height: 1.2)
                }
            }
            .frame(width: size + 2, height: size)
        } else if entry.fileExtension == "bin" || entry.fileExtension == "dat" {
            // Portrait White Document Page Icon (Matching blob.bin in workspace.png)
            ZStack {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(Color.white)
                    .frame(width: size * 0.76, height: size * 0.96)
                    .shadow(color: Color.black.opacity(0.12), radius: 1, y: 0.5)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .stroke(Color.black.opacity(0.12), lineWidth: 0.5)
                    )

                VStack(spacing: 1.5) {
                    ForEach(0..<3, id: \.self) { _ in
                        Rectangle()
                            .fill(Color.secondary.opacity(0.45))
                            .frame(width: size * 0.38, height: 1.2)
                    }
                }
            }
            .frame(width: size + 2, height: size)
        } else {
            Image(systemName: symbolForEntry(entry))
                .font(.system(size: size * 0.88))
                .foregroundStyle(colorForEntry(entry))
                .frame(width: size + 2, height: size)
        }
    }

    private func symbolForEntry(_ entry: ArchiveEntry) -> String {
        let ext = entry.fileExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "gif", "webp", "heic", "svg", "bmp", "tiff": return "photo.fill"
        case "mp3", "m4a", "wav", "flac", "ogg": return "waveform"
        case "mp4", "mov", "mkv", "avi", "webm": return "film"
        case "pdf": return "doc.richtext.fill"
        case "zip", "7z", "tar", "gz", "rar", "xz", "bz2": return "doc.zipper"
        case "app": return "app.badge.checkmark.fill"
        case "pkg", "mpkg", "dmg": return "shippingbox.fill"
        case "ttf", "otf", "ttc", "woff", "woff2": return "textformat"
        default: return "doc.fill"
        }
    }

    private func colorForEntry(_ entry: ArchiveEntry) -> Color {
        let ext = entry.fileExtension.lowercased()
        switch ext {
        case "app", "zip", "7z": return ProZipTheme.accent
        case "pdf": return .red.opacity(0.8)
        case "jpg", "jpeg", "png", "gif", "webp", "heic": return .purple.opacity(0.8)
        case "mp3", "m4a", "wav", "flac": return .pink.opacity(0.8)
        case "mp4", "mov", "mkv": return .orange.opacity(0.8)
        default: return .secondary
        }
    }
}

// MARK: - Right-Click Context Menu (FileItemContextMenu)

public struct FileItemContextMenu: View {
    public let entry: ArchiveEntry
    @ObservedObject public var session: ArchiveBrowsingSession
    @EnvironmentObject public var appViewModel: ProZipAppViewModel

    public var body: some View {
        let flowRec = FlowActionRouter.recommendAction(
            for: [entry],
            in: session.safeDescriptor,
            allowedFormats: ProZipPreferences.shared.allowedOpenFormats
        )

        Button("快速预览 (空格)") {
            session.selectOnly(entry.id)
            appViewModel.previewSelected(in: session)
        }

        if let rec = flowRec, rec.isEnabled {
            Button("智能操作：\(rec.title) (⏎)") {
                session.selectOnly(entry.id)
                appViewModel.executeFlowAction(rec, in: session)
            }
        }

        Divider()

        Button("解压所选项目…") {
            appViewModel.extractSelection([entry], in: session)
        }

        if !entry.isDirectory {
            Button("打开文件") {
                appViewModel.openEntryExternally(entry, in: session)
            }
        }

        Button("添加文件到当前目录…") {
            appViewModel.promptAddFiles(to: session)
        }

        Divider()

        Button("重命名项目…") {
            appViewModel.beginRenaming(entry, in: session)
        }

        Button("删除所选项目…", role: .destructive) {
            session.selectOnly(entry.id)
            session.removeSelectedDraftEntries()
        }

        Divider()

        Button("复制文件名") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(entry.name, forType: .string)
        }

        Button("复制完整路径") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(entry.path, forType: .string)
        }
    }
}

// MARK: - Workspace Icons Grid View (116×112pt Tiles)

public struct WorkspaceIconsGridView: View {
    @ObservedObject public var session: ArchiveBrowsingSession
    @Binding public var hoveredEntryID: String?
    public var onHoverEntryChanged: ((ArchiveEntry?) -> Void)?
    @EnvironmentObject public var appViewModel: ProZipAppViewModel
    @Environment(\.colorScheme) private var colorScheme

    public init(
        session: ArchiveBrowsingSession,
        hoveredEntryID: Binding<String?> = .constant(nil),
        onHoverEntryChanged: ((ArchiveEntry?) -> Void)? = nil
    ) {
        self.session = session
        self._hoveredEntryID = hoveredEntryID
        self.onHoverEntryChanged = onHoverEntryChanged
    }

    public var body: some View {
        GeometryReader { geometry in
            let columnCount = max(1, Int((geometry.size.width - 20) / 146))
            let columns = Array(repeating: GridItem(.fixed(144), spacing: 2), count: columnCount)
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    ForEach(session.currentItems, id: \.id) { entry in
                        iconTile(entry)
                            .id(entry.id)
                    }
                }
                .padding(.horizontal, 11)
                .padding(.top, 12)
                .accessibilityElement(children: .contain)
            }
            .modifier(ArchiveKeyboardNavigation(session: session, entries: session.displayedEntries, columnCount: columnCount, handlesHorizontalSelection: true))
        }
    }

    private func iconTile(_ entry: ArchiveEntry) -> some View {
        let isSelected = session.selectedEntryIDs.contains(entry.id)
        let isHovered = hoveredEntryID == entry.id
        return VStack(spacing: 0) {
            ArchiveEntryThumbnail(entry: entry, session: session)
                .overlay(alignment: .bottomTrailing) {
                    if entry.isEncrypted {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(4)
                            .background(.regularMaterial, in: Circle())
                    }
                }
            Text(entry.name)
                .font(.system(size: 13.5, weight: .medium))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: 138, minHeight: 36, alignment: .top)
        }
        .frame(width: 144, height: 150)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.16) : isHovered ? Color.primary.opacity(0.035) : Color.clear)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.name)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityAction { ArchiveSelectionInteraction.click(entry, in: session, orderedEntries: session.displayedEntries) }
        .onTapGesture(count: 2) {
            if entry.isDirectory {
                Task { await session.enterDirectory(entry.path) }
            } else {
                session.selectOnly(entry.id)
                appViewModel.openEntryExternally(entry, in: session)
            }
        }
        .onTapGesture {
            ArchiveSelectionInteraction.click(entry, in: session, orderedEntries: session.displayedEntries)
        }
        .overlay {
            ArchiveFileDragHitArea(entry: entry, session: session, orderedEntries: session.displayedEntries, onHover: { hovering in
                hoveredEntryID = hovering ? entry.id : (hoveredEntryID == entry.id ? nil : hoveredEntryID)
                onHoverEntryChanged?(hovering ? entry : nil)
            })
        }
        .contextMenu {
            FileItemContextMenu(entry: entry, session: session)
                .environmentObject(appViewModel)
        }
    }
}

// MARK: - Workspace Columns Browser View (Finder Miller Columns)

public struct WorkspaceColumnsView: View {
    @ObservedObject public var session: ArchiveBrowsingSession
    @Binding public var directoryEntry: ArchiveEntry?
    @Binding public var hoveredEntryID: String?
    public var onHoverEntryChanged: ((ArchiveEntry?) -> Void)?
    @EnvironmentObject public var appViewModel: ProZipAppViewModel
    @State private var columns: [Column] = []

    private struct Column: Identifiable {
        var id: String { path }
        let path: String
        let entries: [ArchiveEntry]
    }

    private struct Input: Equatable {
        let path: String
        let revision: UInt
    }

    public init(
        session: ArchiveBrowsingSession,
        directoryEntry: Binding<ArchiveEntry?> = .constant(nil),
        hoveredEntryID: Binding<String?> = .constant(nil),
        onHoverEntryChanged: ((ArchiveEntry?) -> Void)? = nil
    ) {
        self.session = session
        self._directoryEntry = directoryEntry
        self._hoveredEntryID = hoveredEntryID
        self.onHoverEntryChanged = onHoverEntryChanged
    }

    public var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { scroll in
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(columns) { column in
                            ScrollView {
                                LazyVStack(spacing: 0) {
                                    ForEach(column.entries) { entry in
                                        columnRow(entry, in: column)
                                            .id(entry.id)
                                    }
                                }
                                .accessibilityElement(children: .contain)
                            }
                            .frame(width: 223, height: geometry.size.height)
                            .accessibilityLabel(column.path.isEmpty ? "压缩包根目录" : column.path + " 文件夹")
                            Divider()
                                .frame(height: geometry.size.height)
                                .id(column.path)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(minWidth: geometry.size.width, alignment: .leading)
                }
                .scrollIndicators(.hidden)
                .onChange(of: columns.count) { _, _ in
                    if let last = columns.last { scroll.scrollTo(last.path, anchor: .trailing) }
                }
            }
        }
        .modifier(ArchiveKeyboardNavigation(session: session, entries: session.displayedEntries, opensFoldersWithRightArrow: true))
        .task(id: Input(path: session.currentDirectoryPath, revision: session.displayedEntriesRevision)) {
            await loadColumns()
        }
    }

    private func columnRow(_ entry: ArchiveEntry, in column: Column) -> some View {
        let isAncestor = entry.isDirectory && (session.currentDirectoryPath == entry.path || session.currentDirectoryPath.hasPrefix(entry.path + "/"))
        let isSelected = session.selectedEntryIDs.contains(entry.id) || isAncestor
        return HStack(spacing: 10) {
            ArchiveEntryThumbnail(entry: entry, session: session, size: CGSize(width: 18, height: 16))
            Text(entry.name)
                .font(.system(size: 13.5))
                .lineLimit(1)
            Spacer(minLength: 4)
            if entry.isEncrypted {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            if entry.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 18)
        .frame(height: 28)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 0.5).padding(.horizontal, 8)
        }
        .background(isSelected ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.14) : Color.clear)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.name)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityAction { select(entry, in: column) }
        .onTapGesture(count: 2) {
            guard !entry.isDirectory else { return }
            Task {
                await session.enterDirectory(column.path)
                session.selectOnly(entry.id)
                appViewModel.openEntryExternally(entry, in: session)
            }
        }
        .onTapGesture { select(entry, in: column) }
        .overlay {
            ArchiveFileDragHitArea(entry: entry, session: session, orderedEntries: column.entries, onClick: { count, modifiers in
                if count >= 2, !entry.isDirectory {
                    Task {
                        await session.enterDirectory(column.path)
                        session.selectOnly(entry.id)
                        appViewModel.openEntryExternally(entry, in: session)
                    }
                } else { select(entry, in: column, modifiers: modifiers) }
            }, onHover: { hovering in
                hoveredEntryID = hovering ? entry.id : (hoveredEntryID == entry.id ? nil : hoveredEntryID)
                onHoverEntryChanged?(hovering ? entry : nil)
            })
        }
        .contextMenu {
            FileItemContextMenu(entry: entry, session: session)
                .environmentObject(appViewModel)
        }
    }

    private func select(_ entry: ArchiveEntry, in column: Column, modifiers: NSEvent.ModifierFlags? = nil) {
        if entry.isDirectory {
            directoryEntry = entry
            Task { await session.enterDirectory(entry.path) }
        } else if session.currentDirectoryPath == column.path {
            ArchiveSelectionInteraction.click(entry, in: session, orderedEntries: column.entries, modifiers: modifiers)
        } else {
            Task {
                await session.enterDirectory(column.path)
                session.selectOnly(entry.id)
            }
        }
    }

    private func loadColumns() async {
        let path = session.currentDirectoryPath
        var paths = [""]
        var current = ""
        for component in path.split(separator: "/") {
            current = current.isEmpty ? String(component) : current + "/" + component
            paths.append(current)
        }
        do {
            var loaded: [Column] = []
            for path in paths {
                let entries = try await session.directoryEntries(at: path)
                try Task.checkCancellation()
                loaded.append(Column(path: path, entries: entries))
            }
            guard session.currentDirectoryPath == path else { return }
            columns = loaded
            directoryEntry = loaded.dropLast().last?.entries.first { $0.path == path }
        } catch is CancellationError {
        } catch {
            appViewModel.alertTitle = "无法读取文件夹"
            appViewModel.alertMessage = error.localizedDescription
            appViewModel.isAlertPresented = true
        }
    }
}

// MARK: - Right Inspector Pane (Matching workspace.png Right Pane Pixel-for-Pixel)

public struct WorkspaceInspectorPane: View {
    @ObservedObject public var session: ArchiveBrowsingSession
    public var navigationEntry: ArchiveEntry?
    @Binding public var isEncryptionPopoverPresented: Bool
    @EnvironmentObject public var appViewModel: ProZipAppViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var previewText: String?
    @State private var previewImage: NSImage?
    @State private var directoryBytes: Int64?

    private var inspectedEntry: ArchiveEntry? { session.selectedEntries.first ?? navigationEntry }

    public init(
        session: ArchiveBrowsingSession,
        navigationEntry: ArchiveEntry? = nil,
        isEncryptionPopoverPresented: Binding<Bool> = .constant(false)
    ) {
        self.session = session
        self.navigationEntry = navigationEntry
        self._isEncryptionPopoverPresented = isEncryptionPopoverPresented
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header ("压缩包详情" or "项目详情")
            Text(session.selectedEntries.isEmpty && navigationEntry == nil ? "压缩包详情" : "项目详情")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.78))
                .padding(.horizontal, 19)
                .padding(.top, 14)
                .padding(.bottom, 16)

            // Full-Height Inner Card (Matching workspace.png white rounded card inside tinted inspector)
            ScrollView {
                Group {
                    if let selected = session.selectedEntries.first ?? navigationEntry {
                        selectedEntryInspectorContent(selected)
                    } else {
                        archiveRootInspectorContent
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(ProZipTheme.inspectorCardBackground(for: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.04), radius: 5, y: 2)
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
        }
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(ProZipTheme.inspectorBackground(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .task(id: "\(inspectedEntry?.id ?? ""): \(session.displayedEntriesRevision)") {
            await loadSelectedPreview()
        }
    }

    // MARK: - Archive Root Inspector Content (Matching workspace.png)

    private var archiveRootInspectorContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Centered 3D Pocket Graphic
            HStack {
                Spacer()
                ProZipArchivePocketGraphic(size: 120)
                Spacer()
            }
            .padding(.top, 12)
            .padding(.bottom, 21)

            // Left-Aligned Archive Name & Format Subtitle (Matching workspace.png!)
            VStack(alignment: .leading, spacing: 4) {
                Text(session.archiveName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(session.safeDescriptor.format.displayName)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            // Key-Value Metadata Rows separated by light dividers
            VStack(spacing: 7) {
                let displayBytes = session.initialSourceStat?.size ?? session.displayedEntries.reduce(Int64(0)) { $0 + $1.uncompressedSize }

                inspectorRow(
                    label: "大小",
                    value: WorkspaceDateFormatters.sizeString(for: displayBytes)
                )

                Divider()
                    .opacity(0.5)

                inspectorRow(
                    label: "项目",
                    value: "\(session.safeDescriptor.entryCountHint ?? session.displayedEntries.count)"
                )

                Divider()
                    .opacity(0.5)

                inspectorRow(
                    label: "加密",
                    value: session.safeDescriptor.isEncrypted ? "是" : "否"
                )

                Divider()
                    .opacity(0.5)

                inspectorRow(
                    label: "修改日期",
                    value: session.initialSourceStat.map { WorkspaceDateFormatters.displayString(from: $0.mtime) } ?? "—"
                )
            }
            .padding(.top, 1)

            Spacer()
        }
    }

    // MARK: - Selected Entry Inspector Content

    private func selectedEntryInspectorContent(_ selected: ArchiveEntry) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Preview Canvas Card (Matching arczip_live_workspace_selected_search.png!)
            Group {
                if let image = previewImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 260)
                        .offset(y: -6)
                } else if selected.isDirectory {
                    Image(nsImage: NSWorkspace.shared.icon(for: .folder))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 230, height: 230)
                        .offset(y: -6)
                } else if isTextEntry(selected) {
                    selectedTextPreview(selected)
                } else {
                    ArchiveEntryThumbnail(entry: selected, session: session, size: CGSize(width: 230, height: 260))
                        .offset(y: -6)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 300)

            VStack(alignment: .leading, spacing: 4) {
                Text(selected.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(selected.isDirectory ? "文件夹" : (UTType(filenameExtension: selected.fileExtension)?.localizedDescription ?? "文件"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 7) {
                inspectorRow(
                    label: "原始大小",
                    value: selected.isDirectory ? directoryBytes.map(WorkspaceDateFormatters.sizeString(for:)) ?? "—" : WorkspaceDateFormatters.sizeString(for: selected.uncompressedSize)
                )
                Divider().opacity(0.5)
                inspectorRow(label: "加密", value: selected.isEncrypted ? "是" : "否")
                Divider().opacity(0.5)
                inspectorRow(label: "修改日期", value: WorkspaceDateFormatters.displayString(from: selected.modifiedAt))
            }
        }
    }

    private func selectedTextPreview(_ selected: ArchiveEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
                Text(selected.name)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Divider()
                    .opacity(0.45)

                if let text = previewText {
                    Text(text.dropLast(text.last?.isNewline == true ? 1 : 0))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.primary.opacity(0.82))
                        .lineLimit(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                } else {
                    HStack {
                        Spacer()
                        EntryRichFileIconView(entry: selected, size: 46)
                        Spacer()
                    }
                    .padding(.vertical, 12)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.white)
                    .shadow(color: Color.black.opacity(0.06), radius: 8, y: 3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
            .padding(.bottom, 12)
    }

    @MainActor
    private func loadSelectedPreview() async {
        previewText = nil
        previewImage = nil
        directoryBytes = nil
        guard let entry = inspectedEntry else { return }
        if entry.isDirectory {
            directoryBytes = try? await session.totalUncompressedSize(inDirectory: entry.path)
            return
        }
        let type = UTType(filenameExtension: entry.fileExtension)
        let isImage = type?.conforms(to: .image) == true
        let isText = isTextEntry(entry)
        let limit = isImage ? 16 * 1024 * 1024 : 64 * 1024
        guard isText || isImage, entry.uncompressedSize <= Int64(isImage ? limit : 8 * 1024 * 1024) else { return }
        do {
            let data = try await appViewModel.previewBytes(for: entry, in: session, maximumCount: limit)
            if isImage, let source = CGImageSourceCreateWithData(data as CFData, nil),
               let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1024,
                    kCGImageSourceCreateThumbnailWithTransform: true
               ] as CFDictionary) {
                previewImage = NSImage(cgImage: image, size: .zero)
            } else if isText, !data.contains(0) {
                previewText = String(decoding: data, as: UTF8.self)
            }
        } catch {
            // A locked or unsupported member keeps its file icon until opened.
        }
    }

    private func isTextEntry(_ entry: ArchiveEntry) -> Bool {
        UTType(filenameExtension: entry.fileExtension)?.conforms(to: .text) == true || ["json", "yaml", "yml", "toml", "md", "log", "swift", "js", "ts", "py", "sh"].contains(entry.fileExtension.lowercased())
    }

    private func inspectorRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: label == "修改日期" ? 154 : nil, alignment: .trailing)
        }
    }
}

// MARK: - Date & Size Formatting Helpers (Matching workspace.png Chinese Locale Strings)

private enum WorkspaceDateFormatters {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日 Bh:mm"
        return formatter
    }()

    static func displayString(from date: Date) -> String {
        dateFormatter.string(from: date)
    }

    static func sizeString(for bytes: Int64) -> String {
        if bytes < 1000 {
            return "\(bytes) 字节"
        }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - ArcZip-parity interaction styles (hover lift + press compression)

public struct ProZipPressScaleStyle: ButtonStyle {
    public var hoverScale: CGFloat
    public var pressedScale: CGFloat
    public var hoverBrightness: Double

    public init(hoverScale: CGFloat = 1.02, pressedScale: CGFloat = 0.95, hoverBrightness: Double = 0.025) {
        self.hoverScale = hoverScale
        self.pressedScale = pressedScale
        self.hoverBrightness = hoverBrightness
    }

    public func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, hoverScale: hoverScale, pressedScale: pressedScale, hoverBrightness: hoverBrightness)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        let hoverScale: CGFloat
        let pressedScale: CGFloat
        let hoverBrightness: Double
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? pressedScale : (isHovering ? hoverScale : 1))
                .brightness(isHovering && !configuration.isPressed ? hoverBrightness : 0)
                .animation(.spring(response: 0.22, dampingFraction: 0.78), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.12), value: isHovering)
                .onHover { isHovering = $0 }
        }
    }
}

