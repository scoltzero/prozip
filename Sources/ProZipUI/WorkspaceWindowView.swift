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
    @State private var isRightInspectorVisible: Bool = true
    @State private var expandedFolderPaths: Set<String> = []
    @State private var columnDirectoryEntry: ArchiveEntry?
    @State private var isWindowFullScreen: Bool = false

    // Inline Archive Rename State
    @State private var isRenamingArchiveInline: Bool = false
    @State private var inlineArchiveNameDraft: String = ""
    @State private var isHoveringTitleRename: Bool = false
    @State private var isHoveringAuxPill: Bool = false

    // Encryption Notice Popover State
    @State private var isEncryptionPopoverPresented: Bool = false

    // Sorting State
    @State private var sortField: WorkspaceSortField = .name
    @State private var sortAscending: Bool = true

    // Hover & Floating Preview State
    @State private var hasActiveRowHover: Bool = false
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
        let outerCornerRadius: CGFloat = isWindowFullScreen ? 0 : 28
        let mainCardShape = RoundedRectangle(cornerRadius: 22, style: .continuous)

        HStack(spacing: 6) {
            // 1. Left Main Workspace Card: (6, 6, W - 282, H - 12), r = 22
            VStack(spacing: 0) {
                // Unified Top Toolbar: window y = 13..51 (7pt inside y=6 card)
                workspaceToolbar
                    .frame(height: 38)
                    .padding(.top, 7)
                    .padding(.leading, 86)
                    .padding(.trailing, 14)

                // Sub-toolbar / Breadcrumb Pill Bar: window y = 58..94 (36pt high)
                breadcrumbBarContainer
                    .frame(height: 36)
                    .padding(.top, 7)
                    .padding(.horizontal, 14)

                // Preliminary / Error Banner
                if case .preliminary = session.phase {
                    phaseBanner
                        .padding(.horizontal, 14)
                        .padding(.top, 8)
                } else if case .failed(let message) = session.phase {
                    errorBanner(message: message)
                        .padding(.horizontal, 14)
                        .padding(.top, 8)
                }

                // Main Content Area (scrolls all the way under bottom progressive blur + Flow bar)
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
                                    expandedFolderPaths: $expandedFolderPaths,
                                    onHoverEntryChanged: { entry in
                                        handleEntryHover(entry)
                                    }
                                )
                            case .icons:
                                WorkspaceIconsGridView(
                                    session: session,
                                    onHoverEntryChanged: { entry in
                                        handleEntryHover(entry)
                                    }
                                )
                            case .columns:
                                WorkspaceColumnsView(
                                    session: session,
                                    directoryEntry: $columnDirectoryEntry,
                                    onHoverEntryChanged: { entry in
                                        handleEntryHover(entry)
                                    }
                                )
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 16)

                    // Legacy bottom surface veil only on pre-macOS 26; on macOS 26+ rows stay crisp and refract directly through the floating Liquid Glass capsule.
                    if #unavailable(macOS 26.0) {
                        ZStack {
                            ProZipVariableBlurView(direction: .bottomToTop, material: .headerView)
                            LinearGradient(
                                colors: [
                                    mainCardFill.opacity(0.0),
                                    mainCardFill.opacity(0.58),
                                    mainCardFill.opacity(0.90)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                        .frame(height: 56)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .allowsHitTesting(false)
                        .zIndex(5)
                    }

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
                        .padding(.leading, 14)
                        .padding(.bottom, 66)
                        .onHover { hovering in
                            isHoverPreviewHovered = hovering
                            if hovering { hoverDebounceTask?.cancel() }
                            else if !hasActiveRowHover { handleEntryHover(nil) }
                        }
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.94, anchor: .bottomLeading).combined(with: .opacity),
                            removal: .opacity
                        ))
                        .zIndex(20)
                    }

                    // Bottom Anchored Flow Bar (WorkspaceFlowOrbitBar)
                    WorkspaceFlowOrbitBar(session: session, navigationEntry: session.viewMode == .columns ? columnDirectoryEntry : nil)
                        .padding(.leading, 13)
                        .padding(.bottom, 15)
                        .zIndex(10)
                }
            }
            .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
            .background(mainCardShape.fill(mainCardFill))
            .clipShape(mainCardShape)
            .overlay {
                mainCardShape
                    .strokeBorder(
                        colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.055),
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)
            }

            // 2. Right Inspector Card: fixed 270pt width, (W - 276, 6, 270, H - 12), r = 22
            if isRightInspectorVisible {
                WorkspaceInspectorPane(
                    session: session,
                    navigationEntry: session.viewMode == .columns ? columnDirectoryEntry : nil,
                    isEncryptionPopoverPresented: $isEncryptionPopoverPresented
                )
                .frame(width: 270)
                .frame(maxHeight: .infinity)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(6)
        .frame(minWidth: 900, idealWidth: 1040, maxWidth: .infinity, minHeight: 600, idealHeight: 740, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: .top)
        .background {
            ZStack {
                bezelFill
                WorkspaceFullScreenObserver(isFullScreen: $isWindowFullScreen)
                Button("") {
                    guard session.phase.canSearch else { return }
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                        session.isSearchExpanded = true
                    }
                    isSearchFocused = true
                }
                .keyboardShortcut("f", modifiers: [.command])
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            }
        }
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
        .clipShape(RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous))
        .overlay {
            if !isWindowFullScreen {
                RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                    .allowsHitTesting(false)
            }
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

    private var bezelFill: Color {
        colorScheme == .dark
            ? Color(red: 28.0 / 255.0, green: 29.0 / 255.0, blue: 32.0 / 255.0)     // #1C1D20
            : Color(red: 237.0 / 255.0, green: 238.0 / 255.0, blue: 241.0 / 255.0) // #EDEEF1
    }

    private var mainCardFill: Color {
        colorScheme == .dark
            ? Color(red: 30.0 / 255.0, green: 31.0 / 255.0, blue: 34.0 / 255.0)     // #1E1F22
            : Color.white
    }

    // MARK: - Unified Top Toolbar

    private var workspaceToolbar: some View {
        let canDelete = !session.selectedEntryIDs.isEmpty && session.safeDescriptor.editingEligibility.allowed

        return HStack(spacing: 10) {
            // Left Cluster: Archive Title + Pencil @ x = 92, maxWidth = 248 + Encryption Badge
            HStack(spacing: 6) {
                if isRenamingArchiveInline {
                    HStack(spacing: 6) {
                        TextField("压缩包名称", text: $inlineArchiveNameDraft)
                            .textFieldStyle(.plain)
                            .font(.system(size: 15, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(NSColor.controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .stroke(ProZipTheme.accent, lineWidth: 1.2)
                            )
                            .frame(width: 176)
                            .onSubmit {
                                commitInlineArchiveRename()
                            }
                            .onExitCommand {
                                isRenamingArchiveInline = false
                            }

                        Button {
                            commitInlineArchiveRename()
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(ProZipTheme.accent)
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.plain)
                        .help("确认重命名")
                    }
                } else {
                    Button {
                        inlineArchiveNameDraft = session.archiveName
                        isRenamingArchiveInline = true
                    } label: {
                        HStack(spacing: 6) {
                            Text(session.archiveName)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Image(systemName: "pencil")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(isHoveringTitleRename ? .secondary : .tertiary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isHoveringTitleRename ? Color.primary.opacity(0.05) : Color.clear)
                        )
                    }
                    .buttonStyle(ProZipPressScaleStyle(hoverScale: 1.0, pressedScale: 0.98, hoverBrightness: 0))
                    .frame(maxWidth: 248, alignment: .leading)
                    .offset(x: -6)
                    .onHover { hovering in
                        withAnimation(.easeOut(duration: 0.12)) { isHoveringTitleRename = hovering }
                    }
                    .accessibilityLabel("重命名压缩包")
                    .help("重命名压缩包")
                }

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
                        .foregroundStyle(Color(red: 0.78, green: 0.48, blue: 0.08))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(red: 0.90, green: 0.62, blue: 0.21).opacity(0.16))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $isEncryptionPopoverPresented, arrowEdge: .bottom) {
                        WorkspaceArchiveEncryptionPopover(session: session)
                            .environmentObject(appViewModel)
                    }
                }
            }

            Spacer(minLength: 8)
                .overlay { WindowDragArea() }

            // Right Cluster: View Mode Capsule (108×38) + Delete (38×38) + Save (38×38) + Search (38×38 / 220×38)
            ProZipGlassGroup(spacing: 4) {
                HStack(spacing: 8) {
                    HStack(spacing: 2) {
                        viewModeCapsuleButton(.icons, icon: "square.grid.2x2", label: "图标视图", tooltip: "图标视图 (⌘1)")
                        viewModeCapsuleButton(.list, icon: "list.bullet", label: "列表视图", tooltip: "列表视图 (⌘2)")
                        viewModeCapsuleButton(.columns, icon: "rectangle.split.3x1", label: "分栏视图", tooltip: "分栏视图 (⌘3)")
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 3)
                    .frame(width: 108, height: 38)
                    .proZipLiquidGlassCapsule(interactive: true)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("显示方式")

                    // Delete Button: crimson-pink #E1385A Liquid Glass circle + WHITE trash icon when items selected
                    toolbarCircleButton(
                        icon: "trash",
                        accessibilityID: "trash",
                        label: "删除",
                        tooltip: "删除",
                        isEnabled: canDelete,
                        activeSolidFill: canDelete ? Color(red: 0.882, green: 0.220, blue: 0.353) : nil
                    ) {
                        session.removeSelectedDraftEntries()
                    }

                    // Save Button: emerald-green #1EA854 Liquid Glass circle + WHITE floppy icon when dirty
                    toolbarCircleButton(
                        icon: "externaldrive.badge.checkmark",
                        customFloppyGraphic: true,
                        accessibilityID: nil,
                        label: "保存",
                        tooltip: "保存",
                        isEnabled: session.hasUnsavedChanges,
                        activeSolidFill: session.hasUnsavedChanges ? Color(red: 0.118, green: 0.659, blue: 0.329) : nil
                    ) {
                        Task {
                            appViewModel.saveChanges(for: session)
                        }
                    }

                    // Expandable Search Bar (220×38) or Collapsed Search Circle Button (38×38)
                    if session.isSearchExpanded {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(ProZipTheme.accent)

                            TextField("搜索压缩包", text: $session.searchQuery)
                                .textFieldStyle(.plain)
                                .focused($isSearchFocused)
                                .onAppear { isSearchFocused = true }
                                .onExitCommand {
                                    session.searchQuery = ""
                                    withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                                        session.isSearchExpanded = false
                                    }
                                }
                                .font(.system(size: 13))
                                .frame(maxWidth: .infinity)

                            Button {
                                session.searchQuery = ""
                                withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                                    session.isSearchExpanded = false
                                }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.primary.opacity(0.75))
                                    .frame(width: 28, height: 28)
                            }
                            .buttonStyle(ProZipGlassSegmentButtonStyle(shape: .circle, hoverDarkOpacity: 0.10, hoverLightOpacity: 0.06))
                            .proZipLiquidGlassCircle(interactive: true)
                            .accessibilityLabel("清除并关闭搜索")
                            .help("关闭搜索")
                        }
                        .padding(.leading, 12)
                        .padding(.trailing, 5)
                        .frame(width: 220, height: 38)
                        .proZipLiquidGlassCapsule(interactive: false)
                        .overlay(
                            Capsule()
                                .strokeBorder(ProZipTheme.accent, lineWidth: 1.5)
                                .allowsHitTesting(false)
                        )
                        .transition(.scale(scale: 0.92, anchor: .trailing).combined(with: .opacity))
                    } else {
                        toolbarCircleButton(
                            icon: "magnifyingglass",
                            accessibilityID: "ProZip.WorkspaceSearch",
                            label: "搜索压缩包",
                            tooltip: "搜索压缩包",
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
    }

    private func viewModeCapsuleButton(_ mode: WorkspaceViewMode, icon: String, label: String, tooltip: String) -> some View {
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
                        .frame(width: 32, height: 32)
                        .shadow(color: ProZipTheme.accent.opacity(0.28), radius: 4, y: 1)
                        .matchedGeometryEffect(id: "ViewModeActivePill", in: viewModeAnimationNamespace)
                }
                Image(systemName: icon)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.74))
            }
            .frame(width: 32, height: 32)
            .contentShape(Circle())
        }
        .buttonStyle(
            ProZipGlassSegmentButtonStyle(
                shape: .circle,
                hoverDarkOpacity: isSelected ? 0 : 0.10,
                hoverLightOpacity: isSelected ? 0 : 0.055
            )
        )
        .accessibilityIdentifier(icon)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .help(tooltip)
    }

    private func toolbarCircleButton(
        icon: String,
        customFloppyGraphic: Bool = false,
        accessibilityID: String? = nil,
        label: String,
        tooltip: String,
        isEnabled: Bool = true,
        isActive: Bool = false,
        activeSolidFill: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let button = Button(action: action) {
            ZStack {
                if let activeSolidFill {
                    Circle()
                        .fill(activeSolidFill.opacity(0.88))
                        .frame(width: 38, height: 38)
                } else if isActive {
                    Circle()
                        .fill(ProZipTheme.accentSoft)
                        .frame(width: 38, height: 38)
                }

                if customFloppyGraphic {
                    FloppyDiskSaveIcon(
                        strokeColor: activeSolidFill != nil
                            ? Color.white
                            : (isEnabled ? Color.primary.opacity(0.80) : Color.primary.opacity(0.32))
                    )
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 13.5, weight: activeSolidFill != nil ? .semibold : .medium))
                        .foregroundStyle(
                            activeSolidFill != nil
                                ? Color.white
                                : (isActive
                                    ? ProZipTheme.accent
                                    : (isEnabled ? Color.primary.opacity(0.82) : Color.primary.opacity(0.32)))
                        )
                }
            }
            .frame(width: 38, height: 38)
        }
        .buttonStyle(
            ProZipGlassSegmentButtonStyle(
                shape: .circle,
                hoverDarkOpacity: activeSolidFill != nil ? 0.14 : 0.10,
                hoverLightOpacity: activeSolidFill != nil ? 0.08 : 0.055
            )
        )
        .proZipLiquidGlassCircle(interactive: isEnabled, tint: activeSolidFill?.opacity(0.45))
        .disabled(!isEnabled)
        .accessibilityLabel(label)
        .help(tooltip)

        return Group {
            if let accessibilityID {
                button.accessibilityIdentifier(accessibilityID)
            } else {
                button
            }
        }
    }

    // MARK: - Sub-Toolbar / Breadcrumb Pill Bar & Auxiliary Entries Toggle

    private var breadcrumbBarContainer: some View {
        HStack(spacing: 12) {
            // Intrinsic content-hugging Liquid Glass Breadcrumb Capsule (expands via horizontal ScrollView only on deep paths)
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    breadcrumbNavButton(icon: "chevron.left", id: "chevron.left", label: "后退", isEnabled: session.canGoBack) {
                        Task { await session.goBack() }
                    }
                    breadcrumbNavButton(icon: "chevron.right", id: "chevron.right", label: "前进", isEnabled: session.canGoForward) {
                        Task { await session.goForward() }
                    }
                    breadcrumbNavButton(icon: "arrow.up", id: "arrow.up", label: "上一级", isEnabled: session.canGoUp) {
                        Task { await session.goUp() }
                    }
                }

                Rectangle()
                    .fill(Color.primary.opacity(0.09))
                    .frame(width: 1, height: 14)

                ViewThatFits(in: .horizontal) {
                    breadcrumbSegmentsRow
                    ScrollView(.horizontal, showsIndicators: false) {
                        breadcrumbSegmentsRow
                    }
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .proZipLiquidGlassCapsule(interactive: false)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("文件夹导航")

            Spacer(minLength: 12)

            if session.auxiliaryEntryCount > 0 {
                let showingAux = preferences.showsAuxiliaryEntries
                Button {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                        preferences.showsAuxiliaryEntries.toggle()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: showingAux ? "eye" : "eye.slash")
                            .font(.system(size: 11, weight: .medium))
                        Text("\(showingAux ? "已显示" : "已隐藏") \(session.auxiliaryEntryCount) 项")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 25)
                    .foregroundStyle(
                        showingAux
                            ? (colorScheme == .dark ? ProZipTheme.accentBright : ProZipTheme.accentDeep)
                            : (colorScheme == .dark ? Color.white.opacity(0.75) : Color(red: 0.35, green: 0.36, blue: 0.38))
                    )
                }
                .buttonStyle(
                    ProZipGlassSegmentButtonStyle(
                        shape: .capsule,
                        baseTint: showingAux ? ProZipTheme.accent : nil,
                        hoverDarkOpacity: 0.10,
                        hoverLightOpacity: 0.055
                    )
                )
                .proZipLiquidGlassCapsule(interactive: true, tint: showingAux ? ProZipTheme.accent.opacity(0.18) : nil)
                .fixedSize()
                .onHover { hovering in
                    isHoveringAuxPill = hovering
                }
                .accessibilityLabel(showingAux ? "隐藏辅助项目" : "显示辅助项目")
                .accessibilityValue("\(session.auxiliaryEntryCount) 个辅助项目")
            }
        }
    }

    private func breadcrumbNavButton(
        icon: String,
        id: String,
        label: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        BreadcrumbNavButton(icon: icon, id: id, label: label, isEnabled: isEnabled, action: action)
    }

    private var breadcrumbSegmentsRow: some View {
        let crumbs = session.breadcrumbs
        return HStack(spacing: 4) {
            ForEach(Array(crumbs.indices), id: \.self) { idx in
                let crumb = crumbs[idx]
                let isLast = idx == crumbs.count - 1

                if idx > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }

                BreadcrumbSegmentButton(
                    title: crumb.title,
                    isRootArchive: idx == 0,
                    isLast: isLast
                ) {
                    Task { await session.enterDirectory(crumb.path) }
                }
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
        .background(Color.primary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        hasActiveRowHover = (entry != nil)
        hoverDebounceTask?.cancel()
        guard preferences.hoverPreviewEnabled, let entry = entry, !entry.isDirectory else {
            hoverDebounceTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 180_000_000)
                if !Task.isCancelled && !hasActiveRowHover && !isHoverPreviewHovered {
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

private struct BreadcrumbNavButton: View {
    let icon: String
    let id: String
    let label: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 28, height: 28)
                .foregroundStyle(isEnabled ? Color.primary.opacity(0.76) : Color.secondary.opacity(0.35))
        }
        .buttonStyle(ProZipGlassSegmentButtonStyle(shape: .circle, hoverDarkOpacity: 0.10, hoverLightOpacity: 0.055))
        .disabled(!isEnabled)
        .accessibilityIdentifier(id)
        .accessibilityLabel(label)
        .help(label)
    }
}

private struct BreadcrumbSegmentButton: View {
    let title: String
    let isRootArchive: Bool
    let isLast: Bool
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if isRootArchive {
                    ArchiveMiniDocBadgeIcon()
                } else {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(red: 0.33, green: 0.68, blue: 0.96))
                }

                Text(title)
                    .font(.system(size: 11.5, weight: isLast ? .semibold : .medium))
                    .foregroundStyle(isLast ? Color.primary.opacity(0.88) : Color.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        isHovering
                            ? (colorScheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.055))
                            : Color.clear
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        .accessibilityLabel(title)
    }
}

private struct WorkspaceFullScreenObserver: NSViewRepresentable {
    @Binding var isFullScreen: Bool

    func makeNSView(context: Context) -> NSView {
        let view = ObserverView()
        view.onChange = { fullScreen in
            if isFullScreen != fullScreen {
                isFullScreen = fullScreen
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ObserverView)?.onChange = { fullScreen in
            if isFullScreen != fullScreen {
                isFullScreen = fullScreen
            }
        }
    }

    private final class ObserverView: NSView {
        var onChange: ((Bool) -> Void)?
        private var tokens: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            tokens.forEach { NotificationCenter.default.removeObserver($0) }
            tokens.removeAll()
            guard let window else { return }
            let report: (Bool) -> Void = { [weak self] value in
                DispatchQueue.main.async { self?.onChange?(value) }
            }
            report(window.styleMask.contains(.fullScreen))
            let center = NotificationCenter.default
            tokens.append(center.addObserver(forName: NSWindow.willEnterFullScreenNotification, object: window, queue: .main) { _ in report(true) })
            tokens.append(center.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: window, queue: .main) { _ in report(true) })
            tokens.append(center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main) { _ in report(false) })
        }

        deinit {
            tokens.forEach { NotificationCenter.default.removeObserver($0) }
        }
    }
}

// MARK: - Interactive macOS Window Traffic Lights (Offscreen Fallback; Hidden in Native Titled Windows)

public struct MainWindowTrafficLightsView: View {
    public var zoomBehaviorIsFullScreen: Bool
    public var isZoomEnabled: Bool
    public var onClose: () -> Void
    public var onMinimize: () -> Void
    public var onZoom: () -> Void

    @State private var isHoveringCluster: Bool = false
    @State private var isOptionHeld: Bool = false

    public init(
        zoomBehaviorIsFullScreen: Bool = false,
        isZoomEnabled: Bool = true,
        onClose: @escaping () -> Void = {},
        onMinimize: @escaping () -> Void = {},
        onZoom: @escaping () -> Void = {}
    ) {
        self.zoomBehaviorIsFullScreen = zoomBehaviorIsFullScreen
        self.isZoomEnabled = isZoomEnabled
        self.onClose = onClose
        self.onMinimize = onMinimize
        self.onZoom = onZoom
    }

    public var body: some View {
        TrafficLightsFallbackHost {
            HStack(spacing: 4) {
                trafficLightButton(
                    fill: Color(red: 1.0, green: 0.373, blue: 0.341), // #FF5F57
                    stroke: Color(red: 0.88, green: 0.27, blue: 0.25),
                    symbol: "xmark",
                    isEnabled: true,
                    action: onClose
                )

                trafficLightButton(
                    fill: Color(red: 0.996, green: 0.737, blue: 0.180), // #FEBC2E
                    stroke: Color(red: 0.87, green: 0.62, blue: 0.10),
                    symbol: "minus",
                    isEnabled: true,
                    action: onMinimize
                )

                trafficLightButton(
                    fill: isZoomEnabled
                        ? Color(red: 0.157, green: 0.784, blue: 0.251)
                        : Color.secondary.opacity(0.28),
                    stroke: isZoomEnabled
                        ? Color(red: 0.11, green: 0.66, blue: 0.18)
                        : Color.secondary.opacity(0.22),
                    symbol: (zoomBehaviorIsFullScreen && !isOptionHeld)
                        ? "arrow.up.left.and.arrow.down.right"
                        : "plus",
                    isEnabled: isZoomEnabled,
                    action: onZoom
                )
            }
            .onHover { hovering in
                isOptionHeld = NSEvent.modifierFlags.contains(.option)
                withAnimation(.easeInOut(duration: 0.12)) {
                    isHoveringCluster = hovering
                }
            }
        }
        .fixedSize()
    }

    private func trafficLightButton(
        fill: Color,
        stroke: Color,
        symbol: String,
        isEnabled: Bool,
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

                if isHoveringCluster && isEnabled {
                    Image(systemName: symbol)
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.65))
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .frame(width: 16, height: 16)
        .accessibilityLabel(symbol == "xmark" ? "关闭" : symbol == "minus" ? "最小化" : zoomBehaviorIsFullScreen ? "全屏幕" : "缩放窗口")
    }
}

private struct TrafficLightsFallbackHost<Content: View>: NSViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeNSView(context: Context) -> FallbackHostingView<Content> {
        let view = FallbackHostingView(rootView: content)
        view.syncVisibility()
        return view
    }

    func updateNSView(_ nsView: FallbackHostingView<Content>, context: Context) {
        nsView.rootView = content
        nsView.syncVisibility()
    }

    final class FallbackHostingView<Hosted: View>: NSHostingView<Hosted> {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            syncVisibility()
        }

        override func layout() {
            syncVisibility()
            super.layout()
        }

        func syncVisibility() {
            let hideForNativeWindow = window.map {
                $0.styleMask.contains(.titled) || $0.styleMask.contains(.fullScreen)
            } ?? false
            if isHidden != hideForNativeWindow {
                isHidden = hideForNativeWindow
            }
        }
    }
}

// MARK: - Custom Toolbar & Breadcrumb Graphics

private struct FloppyDiskSaveIcon: View {
    let strokeColor: Color

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let rect = CGRect(x: w * 0.22, y: h * 0.22, width: w * 0.56, height: h * 0.56)
            let bodyPath = Path(roundedRect: rect, cornerRadius: 2.5, style: .continuous)
            let shutterRect = CGRect(x: w * 0.33, y: h * 0.22, width: w * 0.34, height: h * 0.20)
            let labelRect = CGRect(x: w * 0.31, y: h * 0.52, width: w * 0.38, height: h * 0.26)

            context.stroke(bodyPath, with: .color(strokeColor), lineWidth: 1.4)
            context.stroke(Path(roundedRect: shutterRect, cornerRadius: 1), with: .color(strokeColor), lineWidth: 1.15)
            context.stroke(Path(roundedRect: labelRect, cornerRadius: 1), with: .color(strokeColor), lineWidth: 1.15)
        }
        .frame(width: 24, height: 24)
    }
}

private struct ArchiveMiniDocBadgeIcon: View {
    var body: some View {
        Image(systemName: "doc.zipper")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 14, height: 14)
    }
}

// MARK: - FoldspaceLanding Welcome & Empty Archive Drop Zone

public struct FoldspaceLandingView: View {
    @ObservedObject public var session: ArchiveBrowsingSession
    @Binding public var isDropTargeted: Bool
    @EnvironmentObject public var appViewModel: ProZipAppViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHoveringCard = false

    public init(session: ArchiveBrowsingSession, isDropTargeted: Binding<Bool>) {
        self.session = session
        self._isDropTargeted = isDropTargeted
    }

    public var body: some View {
        GeometryReader { geo in
            let cardTop = max(24, (geo.size.height - 104 - 187) / 2)
            ZStack(alignment: .top) {
                Color.clear
                dropCard
                    .padding(.top, cardTop)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(alignment: .top) {
            skeletonBackdrop
                .allowsHitTesting(false)
        }
        .clipped()
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
    }

    private var skeletonBackdrop: some View {
        // Faint list skeleton (exact 107pt / 154pt columns + 30pt-pitch #F4F5F5 odd zebra rhythm)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("名称")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 10)
                Text("大小")
                    .frame(width: 107, alignment: .leading)
                    .padding(.leading, 8)
                Text("修改时间")
                    .frame(width: 154, alignment: .leading)
                    .padding(.leading, 8)
            }
            .padding(.horizontal, 10)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(.primary.opacity(0.20))
            .frame(height: 28)

            Divider()

            VStack(spacing: 30) {
                ForEach(0..<12, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.028))
                        .frame(height: 30)
                        .padding(.horizontal, 10)
                }
            }
            .padding(.top, 30)
        }
    }

    private var dropCard: some View {
        // 420×187 dashed drop card
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
                .fill(
                    colorScheme == .dark
                        ? Color.white.opacity(isHoveringCard ? 0.07 : 0.04)
                        : Color.white.opacity(isHoveringCard ? 0.90 : 0.78)
                )
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.04), radius: 10, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? ProZipTheme.accent : Color.secondary.opacity(isHoveringCard ? 0.44 : 0.30),
                    style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1.5, dash: [6, 4])
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) { isHoveringCard = hovering }
        }
        .onTapGesture {
            appViewModel.promptAddFiles(to: session)
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
                        .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.045))
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
                                .foregroundStyle(Color(red: 0.78, green: 0.48, blue: 0.08))
                        }
                    }

                    HStack(spacing: 6) {
                        Text(entry.fileExtension.isEmpty ? "文件" : entry.fileExtension.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.primary.opacity(0.06))
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
                .buttonStyle(ProZipPressScaleStyle(hoverScale: 1.02, pressedScale: 0.96, hoverBrightness: 0))

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
                .buttonStyle(ProZipPressScaleStyle(hoverScale: 1.02, pressedScale: 0.96, hoverBrightness: 0))
            }
        }
        .padding(14)
        .frame(width: 300)
        .background {
            let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
            ZStack {
                WorkspacePassThroughGlassView(material: .hudWindow, blendingMode: .withinWindow)
                (colorScheme == .dark
                    ? Color(red: 0.14, green: 0.15, blue: 0.17).opacity(0.92)
                    : Color.white.opacity(0.94))
            }
            .clipShape(shape)
            .allowsHitTesting(false)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.24 : 0.68),
                            Color.primary.opacity(0.08)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
        }
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.34 : 0.14), radius: 16, x: 0, y: 6)
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

// MARK: - Bottom Anchored Flow Bar (WorkspaceFlowOrbitBar)

public struct WorkspaceFlowOrbitBar: View {
    @ObservedObject public var session: ArchiveBrowsingSession
    public var navigationEntry: ArchiveEntry?
    @EnvironmentObject public var appViewModel: ProZipAppViewModel
    @Environment(\.colorScheme) private var colorScheme

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

        ProZipGlassGroup(spacing: 4) {
            HStack(alignment: .bottom, spacing: 9) {
                // Left Native Liquid Glass Capsule: [⤡ 34×34] [↑ 全部解压 ⏎ 129×34] [👁 预览 空格 118×34]
                FlowOrbitCapsule {
                    HStack(spacing: 1) {
                        if session.initialSourceStat != nil {
                            Button {
                                session.isMiniMode = true
                            } label: {
                                Image(systemName: "arrow.down.right.and.arrow.up.left")
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(Color.primary.opacity(0.82))
                                    .frame(width: 34, height: 34)
                            }
                            .buttonStyle(ProZipGlassSegmentButtonStyle(shape: .circle, hoverDarkOpacity: 0.11, hoverLightOpacity: 0.065))
                            .accessibilityIdentifier("ProZip.SwitchToMini")
                            .accessibilityLabel("切换到 Mini")
                            .help("切换到 Mini (⌥⌘M)")
                        }

                        let canExtract = session.initialSourceStat != nil && session.phase.canExtractAll
                        Button {
                            appViewModel.extractAll(in: session)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.up.square")
                                    .font(.system(size: 13.5, weight: .semibold))

                                Text("全部解压")
                                    .font(.system(size: 13, weight: .semibold))

                                keyboardShortcutBadge("⏎", isEnabled: canExtract)
                            }
                            .frame(width: 129, height: 34)
                            .foregroundStyle(
                                canExtract
                                    ? (colorScheme == .dark ? Color.white.opacity(0.92) : Color(red: 0.10, green: 0.11, blue: 0.12))
                                    : Color.secondary.opacity(0.45)
                            )
                        }
                        .buttonStyle(ProZipGlassSegmentButtonStyle(shape: .capsule, hoverDarkOpacity: 0.11, hoverLightOpacity: 0.065))
                        .disabled(!canExtract)
                        .accessibilityLabel("全部解压")
                        .help("按回车键执行")

                        let hasSelection = !session.selectedEntryIDs.isEmpty
                        Button {
                            appViewModel.previewSelected(in: session)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "eye")
                                    .font(.system(size: 12.5, weight: .semibold))
                                Text("预览")
                                    .font(.system(size: 13, weight: .semibold))
                                keyboardShortcutBadge("空格", isEnabled: hasSelection)
                            }
                            .frame(width: 118, height: 34)
                            .foregroundStyle(
                                hasSelection
                                    ? (colorScheme == .dark ? Color.white.opacity(0.92) : Color(red: 0.10, green: 0.11, blue: 0.12))
                                    : (colorScheme == .dark ? Color.white.opacity(0.36) : Color(red: 0.55, green: 0.56, blue: 0.58))
                            )
                        }
                        .buttonStyle(ProZipGlassSegmentButtonStyle(shape: .capsule, hoverDarkOpacity: 0.11, hoverLightOpacity: 0.065))
                        .disabled(!hasSelection)
                        .accessibilityLabel("预览")
                        .help("按空格键执行")
                    }
                }

                // Right Independent Floating Flow CTA
                if let flowRec = rec {
                    WorkspaceFlowButton(recommendation: flowRec, selection: selection, session: session) {
                        if session.selectedEntries.isEmpty, let navigationEntry {
                            appViewModel.extractSelection([navigationEntry], in: session)
                        } else {
                            appViewModel.executeFlowAction(flowRec, in: session)
                        }
                    }
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                } else if session.initialSourceStat == nil || session.hasUnsavedChanges || session.displayedEntries.isEmpty {
                    ProZipFlowOrbitButton(title: "添加文件", icon: "bolt.fill", shortcut: nil, minimumSize: CGSize(width: 116, height: 40)) {
                        appViewModel.promptAddFiles(to: session)
                    }
                    .accessibilityLabel("添加文件")
                }
            }
        }
    }

    private func keyboardShortcutBadge(_ text: String, isEnabled: Bool) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(
                colorScheme == .dark
                    ? Color.white.opacity(isEnabled ? 0.86 : 0.45)
                    : Color(red: 0.24, green: 0.25, blue: 0.27).opacity(isEnabled ? 0.90 : 0.58)
            )
            .padding(.horizontal, 5.5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .fill(
                        colorScheme == .dark
                            ? Color.white.opacity(isEnabled ? 0.16 : 0.09)
                            : Color.white.opacity(isEnabled ? 0.94 : 0.82)
                    )
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.04), radius: 0.5, x: 0, y: 0.5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .strokeBorder(
                        Color.black.opacity(colorScheme == .dark ? 0.22 : 0.06),
                        lineWidth: 0.5
                    )
            )
    }
}

/// `NSVisualEffectView` whose `hitTest(_:)` returns `nil` so AppKit never intercepts
/// mouse clicks meant for SwiftUI buttons rendered by `NSHostingView`.
private struct WorkspacePassThroughGlassView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    private final class PassThroughEffectView: NSVisualEffectView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = PassThroughEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        if nsView.material != material { nsView.material = material }
        if nsView.blendingMode != blendingMode { nsView.blendingMode = blendingMode }
    }
}

/// Native macOS 26+ Liquid Glass capsule container for Workspace bottom actions.
private struct FlowOrbitCapsule<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(4)
            .proZipLiquidGlassCapsule(interactive: true)
    }
}

// MARK: - Workspace List View

public struct WorkspaceListView: View {
    @ObservedObject public var session: ArchiveBrowsingSession
    @Binding public var sortField: WorkspaceSortField
    @Binding public var sortAscending: Bool
    public var isTreeMode: Bool
    @Binding public var expandedFolderPaths: Set<String>
    private var externalHoveredEntryID: Binding<String?>?
    @State private var localHoveredEntryID: String?
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

    private var activeHoveredEntryID: String? {
        externalHoveredEntryID?.wrappedValue ?? localHoveredEntryID
    }

    private func setHoveredEntryID(_ id: String?) {
        if let externalHoveredEntryID {
            externalHoveredEntryID.wrappedValue = id
        } else {
            localHoveredEntryID = id
        }
    }

    public init(
        session: ArchiveBrowsingSession,
        sortField: Binding<WorkspaceSortField> = .constant(.name),
        sortAscending: Binding<Bool> = .constant(true),
        isTreeMode: Bool = false,
        expandedFolderPaths: Binding<Set<String>> = .constant([]),
        hoveredEntryID: Binding<String?>? = nil,
        onHoverEntryChanged: ((ArchiveEntry?) -> Void)? = nil
    ) {
        self.session = session
        self._sortField = sortField
        self._sortAscending = sortAscending
        self.isTreeMode = isTreeMode
        self._expandedFolderPaths = expandedFolderPaths
        self.externalHoveredEntryID = hoveredEntryID
        self.onHoverEntryChanged = onHoverEntryChanged
    }

    public var body: some View {
        let visibleItems = sortedVisibleItems
        return VStack(spacing: 0) {
            // Column Headers Bar: 名称 (flex, W - 569) | 大小 (107pt fixed) | 修改时间 (154pt fixed)
            HStack(spacing: 0) {
                sortableHeaderButton(field: .name, title: "名称")
                    .padding(.leading, 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                HStack(spacing: 0) {
                    headerColumnDivider
                    sortableHeaderButton(field: .size, title: "大小")
                        .padding(.leading, 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
                .frame(width: 107)

                HStack(spacing: 0) {
                    headerColumnDivider
                    sortableHeaderButton(field: .modifiedDate, title: "修改时间")
                        .padding(.leading, 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    headerColumnDivider
                }
                .frame(width: 154)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)

            Divider()

            // Main Table Rows + Full-Viewport 30pt-Pitch Odd Zebra Rhythm
            GeometryReader { geo in
                let fillerCount = max(0, Int(ceil(geo.size.height / 60.0)) + 2)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                            let entry = item.entry
                            let isSelected = session.selectedEntryIDs.contains(entry.id)
                            let isHovered = activeHoveredEntryID == entry.id

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
                            .overlay {
                                ArchiveFileDragHitArea(entry: entry, session: session, orderedEntries: cachedKeyboardEntries, onClick: { count, modifiers in
                                    if count >= 2 { handleDoubleClick(on: entry) }
                                    else { ArchiveSelectionInteraction.click(entry, in: session, orderedEntries: cachedKeyboardEntries, modifiers: modifiers) }
                                }, onHover: { hovering in
                                    let current = activeHoveredEntryID
                                    setHoveredEntryID(hovering ? entry.id : (current == entry.id ? nil : current))
                                    onHoverEntryChanged?(hovering ? entry : nil)
                                })
                                .padding(.leading, isTreeMode ? 20 + CGFloat(item.depth * 18) : 0)
                            }
                            .contextMenu {
                                FileItemContextMenu(entry: entry, session: session)
                                    .environmentObject(appViewModel)
                            }
                        }

                        // Seamless 30pt-pitch odd filler bands continuing immediately after visibleItems
                        VStack(spacing: 30) {
                            ForEach(0..<fillerCount, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.035) : Color.black.opacity(0.035))
                                    .frame(height: 30)
                                    .padding(.horizontal, 10)
                            }
                        }
                        .padding(.top, visibleItems.count.isMultiple(of: 2) ? 30 : 0)
                        .padding(.bottom, 72)
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
                    .font(.system(size: 11.5, weight: .medium))
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
        .accessibilityLabel(title)
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

// MARK: - Workspace Row Item View (30pt Neutral Zebra / #DDDCDD Selected Rows)

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

    private var isDimmedAuxiliary: Bool {
        entry.isAuxiliary || entry.isDiskImageBackground || entry.isApplicationsShortcut
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Name Column (flex: W - 569)
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

                EntryRichFileIconView(entry: entry, size: 17)

                Text(entry.name)
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if entry.isEncrypted {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(red: 0.78, green: 0.48, blue: 0.08))
                }
            }
            .padding(.leading, 18)
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Size Column (107pt fixed)
            Text(entry.isDirectory ? "—" : WorkspaceDateFormatters.sizeString(for: entry.uncompressedSize))
                .font(.system(size: 12.5))
                .foregroundStyle(.primary.opacity(0.84))
                .lineLimit(1)
                .padding(.leading, 8)
                .frame(width: 107, alignment: .leading)

            // Modified Time Column (154pt fixed)
            Text(WorkspaceDateFormatters.displayString(from: entry.modifiedAt))
                .font(.system(size: 12.5))
                .foregroundStyle(.primary.opacity(0.84))
                .lineLimit(1)
                .padding(.leading, 8)
                .padding(.trailing, 6)
                .frame(width: 154, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .opacity(isDimmedAuxiliary ? 0.55 : 1.0)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
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
            // ArcZip neutral selected row: #DDDCDD (RGBA = 221, 220, 221) with dark primary text
            return colorScheme == .dark
                ? Color.white.opacity(0.15)
                : Color(red: 221.0 / 255.0, green: 220.0 / 255.0, blue: 221.0 / 255.0)
        }
        if isHovered {
            // ArcZip neutral row hover: black.opacity(0.055) (~#EFEFF1), ZERO green tint
            return colorScheme == .dark
                ? Color.white.opacity(0.07)
                : Color.black.opacity(0.055)
        }
        if index % 2 == 1 {
            // ArcZip odd zebra row: #F4F5F5 (black.opacity(0.035))
            return colorScheme == .dark
                ? Color.white.opacity(0.035)
                : Color.black.opacity(0.035)
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
        } else if entry.fileExtension == "txt" || entry.fileExtension == "md" || entry.fileExtension == "log" || entry.fileExtension == "json" {
            // Landscape White Card with Text Lines
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
            // Portrait White Document Page Icon
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

// MARK: - Workspace Icons Grid View (144×150pt Tiles)

public struct WorkspaceIconsGridView: View {
    @ObservedObject public var session: ArchiveBrowsingSession
    private var externalHoveredEntryID: Binding<String?>?
    @State private var localHoveredEntryID: String?
    public var onHoverEntryChanged: ((ArchiveEntry?) -> Void)?
    @EnvironmentObject public var appViewModel: ProZipAppViewModel
    @ObservedObject private var preferences = ProZipPreferences.shared
    @Environment(\.colorScheme) private var colorScheme

    public init(
        session: ArchiveBrowsingSession,
        hoveredEntryID: Binding<String?>? = nil,
        onHoverEntryChanged: ((ArchiveEntry?) -> Void)? = nil
    ) {
        self.session = session
        self.externalHoveredEntryID = hoveredEntryID
        self.onHoverEntryChanged = onHoverEntryChanged
    }

    private var activeHoveredEntryID: String? {
        externalHoveredEntryID?.wrappedValue ?? localHoveredEntryID
    }

    private func setHoveredEntryID(_ id: String?) {
        if let externalHoveredEntryID {
            externalHoveredEntryID.wrappedValue = id
        } else {
            localHoveredEntryID = id
        }
    }

    private var visibleEntries: [ArchiveEntry] {
        session.currentItems.filter { preferences.showsAuxiliaryEntries || !$0.isAuxiliary }
    }

    public var body: some View {
        let items = visibleEntries
        return GeometryReader { geometry in
            let columnCount = max(1, Int((geometry.size.width - 20) / 146))
            let columns = Array(repeating: GridItem(.fixed(144), spacing: 2), count: columnCount)
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    ForEach(items, id: \.id) { entry in
                        iconTile(entry, orderedEntries: items)
                            .id(entry.id)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 72)
                .accessibilityElement(children: .contain)
            }
            .modifier(ArchiveKeyboardNavigation(session: session, entries: items, columnCount: columnCount, handlesHorizontalSelection: true))
        }
    }

    private func iconTile(_ entry: ArchiveEntry, orderedEntries: [ArchiveEntry]) -> some View {
        let isSelected = session.selectedEntryIDs.contains(entry.id)
        let isHovered = activeHoveredEntryID == entry.id
        let isDimmed = entry.isAuxiliary || entry.isDiskImageBackground || entry.isApplicationsShortcut

        return VStack(spacing: 4) {
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
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: 138, minHeight: 36, alignment: .top)
        }
        .opacity(isDimmed ? 0.55 : 1.0)
        .frame(width: 144, height: 150)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    isSelected
                        ? (colorScheme == .dark ? Color.white.opacity(0.14) : Color(red: 221.0 / 255.0, green: 220.0 / 255.0, blue: 221.0 / 255.0))
                        : (isHovered
                            ? (colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.045))
                            : Color.clear)
                )
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.name)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityAction { ArchiveSelectionInteraction.click(entry, in: session, orderedEntries: orderedEntries) }
        .onTapGesture(count: 2) {
            if entry.isDirectory {
                Task { await session.enterDirectory(entry.path) }
            } else {
                session.selectOnly(entry.id)
                appViewModel.openEntryExternally(entry, in: session)
            }
        }
        .onTapGesture {
            ArchiveSelectionInteraction.click(entry, in: session, orderedEntries: orderedEntries)
        }
        .overlay {
            ArchiveFileDragHitArea(entry: entry, session: session, orderedEntries: orderedEntries, onHover: { hovering in
                let current = activeHoveredEntryID
                setHoveredEntryID(hovering ? entry.id : (current == entry.id ? nil : current))
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
    private var externalHoveredEntryID: Binding<String?>?
    @State private var localHoveredEntryID: String?
    public var onHoverEntryChanged: ((ArchiveEntry?) -> Void)?
    @EnvironmentObject public var appViewModel: ProZipAppViewModel
    @Environment(\.colorScheme) private var colorScheme
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
        hoveredEntryID: Binding<String?>? = nil,
        onHoverEntryChanged: ((ArchiveEntry?) -> Void)? = nil
    ) {
        self.session = session
        self._directoryEntry = directoryEntry
        self.externalHoveredEntryID = hoveredEntryID
        self.onHoverEntryChanged = onHoverEntryChanged
    }

    private var activeHoveredEntryID: String? {
        externalHoveredEntryID?.wrappedValue ?? localHoveredEntryID
    }

    private func setHoveredEntryID(_ id: String?) {
        if let externalHoveredEntryID {
            externalHoveredEntryID.wrappedValue = id
        } else {
            localHoveredEntryID = id
        }
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
                                .padding(.bottom, 72)
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
        let isHovered = activeHoveredEntryID == entry.id
        let isDimmed = entry.isAuxiliary || entry.isDiskImageBackground || entry.isApplicationsShortcut

        return HStack(spacing: 10) {
            EntryRichFileIconView(entry: entry, size: 17)
            Text(entry.name)
                .font(.system(size: 13.5))
                .foregroundStyle(.primary)
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
        .opacity(isDimmed ? 0.55 : 1.0)
        .padding(.leading, 16)
        .padding(.trailing, 18)
        .frame(height: 28)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 0.5).padding(.horizontal, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(
                    isSelected
                        ? (colorScheme == .dark ? Color.white.opacity(0.15) : Color(red: 221.0 / 255.0, green: 220.0 / 255.0, blue: 221.0 / 255.0))
                        : (isHovered
                            ? (colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.045))
                            : Color.clear)
                )
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
        )
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
                let current = activeHoveredEntryID
                setHoveredEntryID(hovering ? entry.id : (current == entry.id ? nil : current))
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
        let outerShape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        let innerShape = RoundedRectangle(cornerRadius: 20, style: .continuous)

        VStack(alignment: .leading, spacing: 0) {
            // Top 46pt Header Strip ("压缩包详情" or "项目详情")
            Text(session.selectedEntries.isEmpty && navigationEntry == nil ? "压缩包详情" : "项目详情")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(
                    colorScheme == .dark
                        ? Color.white.opacity(0.80)
                        : Color(red: 74.0 / 255.0, green: 73.0 / 255.0, blue: 82.0 / 255.0)
                )
                .padding(.horizontal, 20)
                .frame(height: 46, alignment: .leading)

            // Continuous White Inner Sheet: (W - 272, 52, 262, H - 62), r = 20
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
            .background(innerShape.fill(ProZipTheme.inspectorCardBackground(for: colorScheme)))
            .clipShape(innerShape)
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.035), radius: 4, y: 1)
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
        }
        .background(outerShape.fill(ProZipTheme.inspectorBackground(for: colorScheme)))
        .clipShape(outerShape)
        .overlay(
            outerShape
                .strokeBorder(
                    colorScheme == .dark
                        ? Color.white.opacity(0.08)
                        : Color(red: 213.0 / 255.0, green: 210.0 / 255.0, blue: 223.0 / 255.0),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("检查器")
        .task(id: "\(inspectedEntry?.id ?? ""): \(session.displayedEntriesRevision)") {
            await loadSelectedPreview()
        }
    }

    // MARK: - Archive Root Inspector Content

    private var archiveRootInspectorContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Spacer()
                ProZipArchivePocketGraphic(size: 112)
                Spacer()
            }
            .padding(.top, 18)
            .padding(.bottom, 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(session.archiveName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .help(session.archiveName)

                Text(session.safeDescriptor.format.displayName)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

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
            .padding(.top, 2)

            Spacer()
        }
    }

    // MARK: - Selected Entry Inspector Content

    private func selectedEntryInspectorContent(_ selected: ArchiveEntry) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // 300pt Preview Hero Slot with Elevated White Card (230pt, r = 14)
            Group {
                if let image = previewImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 230, maxHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: Color.black.opacity(0.08), radius: 14, y: 4)
                } else if selected.isDirectory {
                    Image(nsImage: NSWorkspace.shared.icon(for: .folder))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 156, height: 156)
                } else if isTextEntry(selected) {
                    selectedTextPreview(selected)
                } else {
                    ArchiveEntryThumbnail(entry: selected, session: session, size: CGSize(width: 230, height: 220))
                        .shadow(color: Color.black.opacity(0.08), radius: 14, y: 4)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 300)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("所选项目缩略图")

            VStack(alignment: .leading, spacing: 4) {
                Text(selected.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .help(selected.name)

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
                    .foregroundStyle(.primary.opacity(0.84))
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
        .padding(14)
        .frame(width: 230)
        .frame(minHeight: 140)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(colorScheme == .dark ? Color(red: 0.18, green: 0.19, blue: 0.21) : Color.white)
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.08), radius: 14, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        )
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
        guard date > .distantPast else { return "—" }
        return dateFormatter.string(from: date)
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

