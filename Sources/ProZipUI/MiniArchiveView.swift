import SwiftUI
import AppKit
import ProZipShared
import ProZipCore

// MARK: - Mini Archive Sort Field

public enum MiniArchiveSortField: String, CaseIterable, Sendable {
    case name = "名称"
    case size = "大小"
    case modifiedDate = "修改时间"
}

// MARK: - MiniArchiveView (560 × 422 Pixel-for-Pixel Replica of mini.png with Yellow-Green Brand Theme)

public struct MiniArchiveView: View {
    @ObservedObject public var session: ArchiveBrowsingSession
    @EnvironmentObject public var appViewModel: ProZipAppViewModel
    @ObservedObject private var preferences = ProZipPreferences.shared
    @Environment(\.colorScheme) private var colorScheme

    // Interactive States
    @State private var hoveredEntryID: String?
    @State private var isHeaderHovered: Bool = false
    @State private var isBreadcrumbHovered: Bool = false
    @State private var isCloseHovered: Bool = false
    @State private var isExpandHovered: Bool = false
    @State private var isRenamingArchiveInline: Bool = false
    @State private var inlineArchiveNameDraft: String = ""
    @State private var isEncryptionPopoverPresented: Bool = false
    @State private var showColumnHeaders: Bool = false
    @State private var sortField: MiniArchiveSortField = .name
    @State private var sortAscending: Bool = true
    @State private var isDropTargeted: Bool = false
    @FocusState private var isSearchFocused: Bool

    private struct SortInput: Equatable {
        let revision: UInt
        let field: MiniArchiveSortField
        let ascending: Bool
    }
    @State private var cachedSortInput: SortInput?
    @State private var cachedEntries: [ArchiveEntry] = []
    private var sortInput: SortInput {
        SortInput(revision: session.displayedEntriesRevision, field: sortField, ascending: sortAscending)
    }

    public init(session: ArchiveBrowsingSession) {
        self.session = session
    }

    private var totalEntryCount: Int {
        if let hint = session.safeDescriptor.entryCountHint, hint > 0, session.currentDirectoryPath.isEmpty, session.searchQuery.isEmpty {
            return hint
        }
        return max(session.displayedEntries.count, session.entries.count)
    }

    private var totalUncompressedBytes: Int64 {
        session.displayedEntries.reduce(0) { $0 + $1.uncompressedSize }
    }

    private var sortedEntries: [ArchiveEntry] {
        cachedSortInput == sortInput ? cachedEntries : makeSortedEntries()
    }

    private func refreshSortCache() {
        cachedEntries = makeSortedEntries()
        cachedSortInput = sortInput
    }

    private func makeSortedEntries() -> [ArchiveEntry] {
        let base = session.displayedEntries
        return base.sorted { a, b in
            if a.isDirectory != b.isDirectory {
                return a.isDirectory && !b.isDirectory
            }
            let lhs = sortAscending ? a : b
            let rhs = sortAscending ? b : a
            let ordered: Bool
            switch sortField {
            case .name:
                ordered = lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            case .size:
                if lhs.uncompressedSize == rhs.uncompressedSize {
                    ordered = lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                } else {
                    ordered = lhs.uncompressedSize < rhs.uncompressedSize
                }
            case .modifiedDate:
                if lhs.modifiedAt == rhs.modifiedAt {
                    ordered = lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                } else {
                    ordered = lhs.modifiedAt < rhs.modifiedAt
                }
            }
            return ordered
        }
    }

    private var currentFlowRecommendation: FlowActionRecommendation? {
        FlowActionRouter.recommendAction(
            for: session.selectedEntries,
            in: session.safeDescriptor,
            allowedFormats: preferences.allowedOpenFormats
        )
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 1. Top Header Bar
            miniTopBar
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 9)

            // 2. Breadcrumb & Navigation Pill Bar
            miniBreadcrumbBar
                .padding(.horizontal, 10)
                .padding(.bottom, showColumnHeaders ? 4 : 0)

            // 3. Optional Sortable Column Header Strip
            if showColumnHeaders {
                miniSortableColumnHeader
                    .padding(.horizontal, 18)
                    .padding(.bottom, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // 4. Central Scrollable File List
            miniFileListView
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 5. Bottom Action & Flow Bar
            miniBottomBar
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 8)
        }
        .frame(width: 560, height: 422)
        .onAppear { refreshSortCache() }
        .onChange(of: sortInput) { _, _ in refreshSortCache() }
        .background(miniWindowSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.22 : 0.72),
                            Color.white.opacity(colorScheme == .dark ? 0.08 : 0.35)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.0
                )
        )
        .overlay(
            Group {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(ProZipTheme.accentBright, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(ProZipTheme.accentSoft.opacity(0.4))
                        )
                        .padding(3)
                }
            }
        )
        .background(alignment: .topLeading) {
            WindowDragArea()
                .frame(width: 360, height: 50)
                .offset(x: 80, y: 0)
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
    }

    // MARK: - Window Surface & Frosted Liquid Glass Backdrop

    @ViewBuilder
    private var miniWindowSurface: some View {
        ZStack {
            if preferences.miniUsesLiquidGlass {
                VisualEffectView(
                    material: colorScheme == .dark ? .hudWindow : .popover,
                    blendingMode: .behindWindow
                )
            }

            if colorScheme == .dark {
                LinearGradient(
                    colors: [
                        Color(red: 0.16, green: 0.18, blue: 0.15).opacity(0.95),
                        Color(red: 0.12, green: 0.14, blue: 0.12).opacity(0.97)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                // Keep the light surface near white while allowing the system material through.
                LinearGradient(
                    colors: [
                        Color.white.opacity(preferences.miniUsesLiquidGlass ? 0.94 : 1),
                        Color(red: 0.985, green: 0.985, blue: 0.99).opacity(preferences.miniUsesLiquidGlass ? 0.96 : 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }

    // MARK: - 1. Top Header Bar

    private var miniTopBar: some View {
        HStack(spacing: 10) {
            // Authentic macOS ZIP / Archive Document Icon
            Image(nsImage: ProZipResourceLoader.systemFileIcon(for: session.archiveName, isDirectory: false))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 28, height: 28)
                .shadow(color: Color.black.opacity(0.14), radius: 2, x: 0, y: 1)

            // Archive Title, Inline Rename, Encryption Badge & Subtitle
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    if isRenamingArchiveInline {
                        TextField("压缩包名称", text: $inlineArchiveNameDraft)
                            .textFieldStyle(.plain)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(colorScheme == .dark ? Color.black.opacity(0.35) : Color.white.opacity(0.85))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .stroke(ProZipTheme.accent, lineWidth: 1)
                            )
                            .frame(width: 170)
                            .onSubmit {
                                commitInlineArchiveRename()
                            }
                    } else {
                        Text(session.archiveName)
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundStyle(colorScheme == .dark ? Color.white : Color(red: 0.10, green: 0.10, blue: 0.11))
                            .lineLimit(1)
                    }

                    // Unsaved Draft Indicator Dot
                    if session.hasUnsavedChanges {
                        Circle()
                            .fill(ProZipTheme.accentBright)
                            .frame(width: 7, height: 7)
                            .help("存在未保存的修改")
                    }

                    // Encryption Lock Badge with Popover
                    if session.safeDescriptor.isEncrypted || session.displayedEntries.contains(where: \.isEncrypted) {
                        Button {
                            isEncryptionPopoverPresented.toggle()
                        } label: {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(Color(red: 0.96, green: 0.66, blue: 0.13)))
                        }
                        .buttonStyle(.plain)
                        .help("加密压缩包详情")
                        .popover(isPresented: $isEncryptionPopoverPresented, arrowEdge: .bottom) {
                            encryptionInfoPopover
                        }
                    }

                    // Inline Rename Pencil Button (shown on header hover or while editing)
                    if isHeaderHovered || isRenamingArchiveInline {
                        Button {
                            if isRenamingArchiveInline {
                                commitInlineArchiveRename()
                            } else {
                                inlineArchiveNameDraft = session.archiveName
                                isRenamingArchiveInline = true
                            }
                        } label: {
                            Image(systemName: isRenamingArchiveInline ? "checkmark.circle.fill" : "pencil")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(isRenamingArchiveInline ? ProZipTheme.accentBright : Color.primary.opacity(0.55))
                        }
                        .buttonStyle(.plain)
                        .help(isRenamingArchiveInline ? "确认重命名" : "重命名压缩包")
                    }
                }

                // Subtitle: "ZIP 压缩包 · 4 个项目"
                HStack(spacing: 6) {
                    Text("\(session.safeDescriptor.format.displayName) · \(totalEntryCount) 个项目")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.65) : Color(red: 0.25, green: 0.26, blue: 0.27))
                        .lineLimit(1)

                    if session.hasUnsavedChanges {
                        Text("· 已修改")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(colorScheme == .dark ? ProZipTheme.accentBright : ProZipTheme.accentDeep)
                    }
                }
            }

            Spacer()

            // Quick Draft / Selection / Search Actions when needed
            HStack(spacing: 6) {
                if session.hasUnsavedChanges {
                    ArcZipMiniRoundActionButton(
                        icon: "square.and.arrow.down",
                        tooltip: "保存对压缩包的修改",
                        size: 26,
                        tintColor: ProZipTheme.accentDeep
                    ) {
                        appViewModel.saveChanges(for: session)
                    }
                }

                if !session.selectedEntryIDs.isEmpty && isHeaderHovered {
                    ArcZipMiniRoundActionButton(
                        icon: "trash",
                        tooltip: "删除所选项目",
                        size: 26,
                        tintColor: Color.red.opacity(0.85)
                    ) {
                        session.removeSelectedDraftEntries()
                    }
                }

                if isHeaderHovered || session.isSearchExpanded || !session.searchQuery.isEmpty {
                    ArcZipMiniRoundActionButton(
                        icon: "magnifyingglass",
                        tooltip: "搜索压缩包内容 (⌘F)",
                        size: 26,
                        tintColor: session.isSearchExpanded ? ProZipTheme.accentDeep : nil
                    ) {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.78)) {
                            session.isSearchExpanded.toggle()
                            if !session.isSearchExpanded {
                                session.searchQuery = ""
                            }
                        }
                    }
                }
            }

            // Right Brand Cluster: ProZip 3D 'P' Icon + "ProZip" + "Mini" Capsule
            HStack(spacing: 8) {
                ProZipBrandIcon(size: 28, showAppSquircle: true)

                VStack(alignment: .leading, spacing: 1) {
                    Text("ProZip")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(colorScheme == .dark ? Color.white : Color(red: 0.11, green: 0.11, blue: 0.12))

                    Text("Mini")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(colorScheme == .dark ? ProZipTheme.accentBright : Color(red: 0.28, green: 0.31, blue: 0.26))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 1.5)
                        .background(
                            Capsule()
                                .fill(
                                    colorScheme == .dark
                                        ? ProZipTheme.accentSoft
                                        : Color.primary.opacity(0.055)
                                )
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(colorScheme == .dark ? 0.18 : 0.65), lineWidth: 0.6)
                        )
                }
            }

        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHeaderHovered = hovering
            }
        }
    }

    // MARK: - 2. Breadcrumb & Navigation Pill Bar

    private var miniBreadcrumbBar: some View {
        HStack(spacing: 6) {
            // Back Button (<)
            Button {
                Task { await session.goBack() }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12.5, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .foregroundStyle(
                        session.canGoBack
                            ? (colorScheme == .dark ? Color.white.opacity(0.88) : Color(red: 0.26, green: 0.27, blue: 0.29))
                            : (colorScheme == .dark ? Color.white.opacity(0.32) : Color(red: 0.52, green: 0.53, blue: 0.55))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!session.canGoBack)
            .help("后退")

            // Forward Button (>) when available
            if session.canGoForward {
                Button {
                    Task { await session.goForward() }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12.5, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.88) : Color(red: 0.26, green: 0.27, blue: 0.29))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("前进")
            }

            // Up / Parent Directory Button (^)
            Button {
                Task { await session.goUp() }
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 12.5, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .foregroundStyle(
                        session.canGoUp
                            ? (colorScheme == .dark ? Color.white.opacity(0.88) : Color(red: 0.26, green: 0.27, blue: 0.29))
                            : (colorScheme == .dark ? Color.white.opacity(0.32) : Color(red: 0.52, green: 0.53, blue: 0.55))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!session.canGoUp)
            .help("返回上一级")

            // Clickable Breadcrumb Segments
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    let crumbs = session.breadcrumbs
                    ForEach(Array(crumbs.enumerated()), id: \.offset) { index, crumb in
                        if index > 0 {
                            Text("/")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.40) : Color(red: 0.42, green: 0.43, blue: 0.45))
                        }
                        Button {
                            Task { await session.enterDirectory(crumb.path) }
                        } label: {
                            Text(crumb.title)
                                .font(.system(size: 13, weight: index == crumbs.count - 1 ? .semibold : .medium))
                                .foregroundStyle(
                                    colorScheme == .dark
                                        ? Color.white.opacity(index == crumbs.count - 1 ? 0.90 : 0.65)
                                        : Color(red: 0.28, green: 0.29, blue: 0.31).opacity(index == crumbs.count - 1 ? 1.0 : 0.78)
                                )
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer(minLength: 4)

            // Inline Search Field or Hover Sort/Search Controls
            if session.isSearchExpanded || !session.searchQuery.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    TextField("搜索…", text: $session.searchQuery)
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)
                        .onAppear { isSearchFocused = true }
                        .font(.system(size: 12))
                        .frame(width: 120)

                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            session.searchQuery = ""
                            session.isSearchExpanded = false
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(colorScheme == .dark ? Color.black.opacity(0.28) : Color.white.opacity(0.75))
                )
            } else if isBreadcrumbHovered {
                HStack(spacing: 8) {
                    // Toggle column sort strip
                    Menu {
                        ForEach(MiniArchiveSortField.allCases, id: \.self) { field in
                            Button {
                                if sortField == field {
                                    sortAscending.toggle()
                                } else {
                                    sortField = field
                                    sortAscending = true
                                }
                            } label: {
                                HStack {
                                    Text("按\(field.rawValue)排序")
                                    if sortField == field {
                                        Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                                    }
                                }
                            }
                        }
                        Divider()
                        Button(showColumnHeaders ? "隐藏列表表头" : "显示列表表头") {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                showColumnHeaders.toggle()
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.65) : Color(red: 0.32, green: 0.33, blue: 0.35))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("排序方式")

                    Button {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.78)) {
                            session.isSearchExpanded = true
                        }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.65) : Color(red: 0.32, green: 0.33, blue: 0.35))
                    }
                    .buttonStyle(.plain)
                    .help("搜索 (⌘F)")
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    colorScheme == .dark
                        ? Color.white.opacity(0.10)
                        : Color.primary.opacity(0.025)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    Color.white.opacity(colorScheme == .dark ? 0.14 : 0.48),
                    lineWidth: 0.8
                )
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.14)) {
                isBreadcrumbHovered = hovering
            }
        }
    }

    // MARK: - 3. Sortable Column Header Strip (Optional / Toggleable)

    private var miniSortableColumnHeader: some View {
        HStack(spacing: 0) {
            sortableHeaderButton(title: "名称", field: .name)
            Spacer()
            sortableHeaderButton(title: "修改时间", field: .modifiedDate)
                .frame(width: 110, alignment: .leading)
            sortableHeaderButton(title: "大小", field: .size)
                .frame(width: 86, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white.opacity(0.28))
        )
    }

    private func sortableHeaderButton(title: String, field: MiniArchiveSortField) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if sortField == field {
                    sortAscending.toggle()
                } else {
                    sortField = field
                    sortAscending = true
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 11, weight: sortField == field ? .semibold : .medium))
                if sortField == field {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8.5, weight: .bold))
                }
            }
            .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.70) : Color(red: 0.24, green: 0.25, blue: 0.27))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 4. Central File List & Context Menu

    private var miniFileListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                let entries = sortedEntries
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    miniFileRow(entry: entry, index: index)
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .modifier(ArchiveKeyboardNavigation(session: session, entries: sortedEntries))
    }

    private func activateMiniEntry(_ entry: ArchiveEntry) {
        session.selectOnly(entry.id)
        if entry.isDirectory {
            Task { await session.enterDirectory(entry.path) }
        } else if let recommendation = FlowActionRouter.recommendAction(
            for: [entry], in: session.safeDescriptor, allowedFormats: preferences.allowedOpenFormats
        ), recommendation.isEnabled {
            appViewModel.executeFlowAction(recommendation, in: session)
        } else {
            appViewModel.previewSelected(in: session)
        }
    }

    private func miniFileRow(entry: ArchiveEntry, index: Int) -> some View {
        let isSelected = session.selectedEntryIDs.contains(entry.id)
        let isHovered = hoveredEntryID == entry.id

        return HStack(spacing: 8) {
            // Authentic macOS File / Folder Icon + Encrypted Badge
            ZStack(alignment: .bottomTrailing) {
                Image(nsImage: miniEntryIcon(for: entry))
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 17, height: 17)

                if entry.isEncrypted {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(ProZipTheme.darkInk)
                        .padding(1.5)
                        .background(Circle().fill(ProZipTheme.accentBright))
                        .offset(x: 3, y: 2)
                }
            }
            .frame(width: 17, height: 17)

            // File Name
            Text(entry.name)
                .font(.system(size: 13.5, weight: isSelected ? .medium : .regular))
                .foregroundStyle(
                    isSelected
                        ? ProZipTheme.darkInk
                        : (colorScheme == .dark ? Color.white.opacity(0.92) : Color(red: 0.10, green: 0.11, blue: 0.12))
                )
                .lineLimit(1)

            if entry.type == .symlink {
                Image(systemName: "arrow.turn.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Optional Modified Date column when header strip is visible
            if showColumnHeaders {
                Text(Self.dateFormatter.string(from: entry.modifiedAt))
                    .font(.system(size: 11.5))
                    .foregroundStyle(
                        isSelected
                            ? ProZipTheme.darkInk.opacity(0.75)
                            : (colorScheme == .dark ? Color.white.opacity(0.55) : Color(red: 0.30, green: 0.31, blue: 0.33))
                    )
                    .frame(width: 110, alignment: .leading)
            }

            // Right Size Column (Left-aligned at x ≈ 462pt matching mini.png's 2-column NSTableView)
            Text(formattedMiniSize(for: entry))
                .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                .foregroundStyle(
                    isSelected
                        ? ProZipTheme.darkInk.opacity(0.88)
                        : (colorScheme == .dark ? Color.white.opacity(0.62) : Color(red: 0.28, green: 0.29, blue: 0.31))
                )
                .frame(width: 86, alignment: .trailing)
        }
        .padding(.leading, 15)
        .padding(.trailing, 45)
        .frame(height: 38)
        .background(
            Rectangle()
                .fill(rowBackgroundFill(isSelected: isSelected, isHovered: isHovered, index: index))
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.name)，\(formattedMiniSize(for: entry))")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .overlay {
            ArchiveFileDragHitArea(entry: entry, session: session, orderedEntries: sortedEntries, onClick: { count, modifiers in
                if count >= 2 { activateMiniEntry(entry) }
                else { ArchiveSelectionInteraction.click(entry, in: session, orderedEntries: sortedEntries, modifiers: modifiers) }
            }, onHover: { hovering in
                withAnimation(.easeOut(duration: 0.12)) {
                    if hovering { hoveredEntryID = entry.id }
                    else if hoveredEntryID == entry.id { hoveredEntryID = nil }
                }
            })
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { ArchiveSelectionInteraction.click(entry, in: session, orderedEntries: sortedEntries) }
        .accessibilityAction(named: Text("打开")) { activateMiniEntry(entry) }
        .contextMenu {
            Button {
                session.selectOnly(entry.id)
                appViewModel.previewSelected(in: session)
            } label: {
                Label("快速预览 (空格)", systemImage: "eye")
            }

            Button {
                session.selectOnly(entry.id)
                appViewModel.extractSelection([entry], in: session)
            } label: {
                Label("解压所选项目…", systemImage: "arrow.up.doc")
            }

            Divider()

            Button {
                appViewModel.promptAddFiles(to: session)
            } label: {
                Label("添加文件…", systemImage: "plus.circle")
            }

            Button {
                session.selectOnly(entry.id)
                appViewModel.beginRenaming(entry, in: session)
            } label: {
                Label("重命名…", systemImage: "pencil")
            }

            Button(role: .destructive) {
                session.selectOnly(entry.id)
                session.removeSelectedDraftEntries()
            } label: {
                Label("删除", systemImage: "trash")
            }

            Divider()

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.path, forType: .string)
            } label: {
                Label("复制路径", systemImage: "doc.on.doc")
            }

            Divider()

            Menu("排序方式") {
                ForEach(MiniArchiveSortField.allCases, id: \.self) { field in
                    Button {
                        if sortField == field {
                            sortAscending.toggle()
                        } else {
                            sortField = field
                            sortAscending = true
                        }
                    } label: {
                        HStack {
                            Text(field.rawValue)
                            if sortField == field {
                                Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                            }
                        }
                    }
                }
                Divider()
                Button(showColumnHeaders ? "隐藏列表表头" : "显示列表表头") {
                    showColumnHeaders.toggle()
                }
            }
        }
    }

    private func rowBackgroundFill(isSelected: Bool, isHovered: Bool, index: Int) -> Color {
        if isSelected {
            return ProZipTheme.accentBright
        }
        if isHovered {
            return colorScheme == .dark
                ? Color.white.opacity(0.08)
                : Color.white.opacity(0.28)
        }
        return Color.clear
    }

    // MARK: - 5. Bottom Action & Flow Bar

    private var miniBottomBar: some View {
        HStack(spacing: 10) {
            // Left 3 Circular Glass Control Buttons: Close (×), Pin (📌), Expand (⤢)
            HStack(spacing: 8) {
                // 1. Close Window Button
                ArcZipMiniRoundActionButton(
                    icon: "xmark",
                    tooltip: "关闭窗口",
                    size: 28,
                    tintColor: (isCloseHovered && preferences.miniUsesColoredControlButtons)
                        ? Color(red: 0.90, green: 0.22, blue: 0.20)
                        : nil
                ) {
                    appViewModel.closeSession(id: session.id)
                }
                .onHover { isCloseHovered = $0 }

                // 2. Pin Window Button (Always-on-Top with animated pin rotation & yellow-green active ring)
                ArcZipMiniPinButton(
                    isPinned: $session.isAlwaysOnTop,
                    size: 28,
                    tooltip: session.isAlwaysOnTop ? "取消窗口置顶" : "窗口置顶"
                )

                // 3. Expand to Full Workspace Button
                ArcZipMiniRoundActionButton(
                    icon: "arrow.up.left.and.arrow.down.right",
                    tooltip: "展开为完整工作区",
                    size: 28,
                    tintColor: (isExpandHovered && preferences.miniUsesColoredControlButtons)
                        ? ProZipTheme.accentDeep
                        : nil
                ) {
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.80)) {
                        session.isMiniMode = false
                    }
                }
                .onHover { isExpandHovered = $0 }
            }

            Spacer(minLength: 6)

            // Contextual Primary Flow Button when entry is selected (matching OnboardingMiniWindow.png)
            if let rec = currentFlowRecommendation {
                ProZipFlowOrbitButton(
                    title: rec.title,
                    icon: rec.systemIcon,
                    shortcut: nil,
                    isEnabled: rec.isEnabled,
                    mode: .accentOrbit
                ) {
                    appViewModel.executeFlowAction(rec, in: session)
                }
                .help(rec.unavailableReason ?? rec.title)
                .transition(.scale(scale: 0.92).combined(with: .opacity))
            }

            // Right Frosted Glass Capsule Bar: "预览 空格" + "全部解压 ⏎"
            HStack(spacing: 1) {
                miniCapsuleButton(
                    title: "预览",
                    icon: "eye",
                    shortcut: "空格",
                    width: 100,
                    isEnabled: !session.selectedEntryIDs.isEmpty
                ) {
                    appViewModel.previewSelected(in: session)
                }
                .help("使用快速查看预览所选文件 (空格)")

                miniCapsuleButton(
                    title: "全部解压",
                    icon: "arrow.up.square",
                    shortcut: "⏎",
                    width: 108,
                    isEnabled: session.phase.canExtractAll
                ) {
                    appViewModel.extractAll(in: session)
                }
                .help("解压全部文件 (回车)")
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(
                        colorScheme == .dark
                            ? Color.white.opacity(0.12)
                            : Color.white.opacity(0.58)
                    )
                    .shadow(
                        color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.10),
                        radius: 4,
                        x: 0,
                        y: 1
                    )
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.36 : 0.90),
                                Color.white.opacity(colorScheme == .dark ? 0.12 : 0.45)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.0
                    )
            )
        }
    }

    @ViewBuilder
    private func miniCapsuleButton(
        title: String,
        icon: String,
        shortcut: String,
        width: CGFloat,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(shortcut)
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.16) : Color.white.opacity(0.72))
                    )
            }
            .frame(width: width, height: 27)
            .foregroundStyle(isEnabled ? Color.primary.opacity(0.86) : Color.secondary.opacity(0.45))
            .contentShape(Capsule())
        }
        .buttonStyle(ProZipPressScaleStyle(hoverScale: 1.02, pressedScale: 0.96))
        .disabled(!isEnabled)
    }

    // MARK: - Encryption Info Popover

    private var encryptionInfoPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(red: 0.96, green: 0.66, blue: 0.13))
                Text("此压缩包受密码保护")
                    .font(.system(size: 15, weight: .bold))
            }

            Text("可浏览文件列表；预览或解压需要密码。点击锁定按钮输入密码。")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)

            HStack {
                Spacer()
                Button {
                    UserDefaults.standard.set(true, forKey: "archiveEncryption.noticeSuppressed.v1")
                    isEncryptionPopoverPresented = false
                } label: {
                    Text("不再提示")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(13)
        .frame(width: 296)
    }

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

    /// Formats entry sizes to match `data/screenshots/mini.png` ("—", "200 KB", "13 字节")
    private func formattedMiniSize(for entry: ArchiveEntry) -> String {
        if entry.isDirectory {
            return "—"
        }
        let bytes = entry.uncompressedSize
        if bytes < 1024 {
            return "\(bytes) 字节"
        }
        let kb = Double(bytes) / 1024.0
        if kb < 1024.0 {
            if abs(kb.rounded() - kb) < 0.05 {
                return "\(Int(kb.rounded())) KB"
            }
            return String(format: "%.1f KB", kb)
        }
        let mb = kb / 1024.0
        if mb < 1024.0 {
            if abs(mb.rounded() - mb) < 0.05 {
                return "\(Int(mb.rounded())) MB"
            }
            return String(format: "%.1f MB", mb)
        }
        let gb = mb / 1024.0
        return String(format: "%.2f GB", gb)
    }

    /// Returns authentic macOS file/folder icon matching `data/screenshots/mini.png`
    private func miniEntryIcon(for entry: ArchiveEntry) -> NSImage {
        if entry.isDirectory {
            return ProZipResourceLoader.systemFileIcon(for: entry.name, isDirectory: true)
        }
        let ext = entry.fileExtension.lowercased()
        if ext == "bin" {
            // In mini.png, blob.bin uses the archive/zipper document icon
            return NSWorkspace.shared.icon(for: .zip)
        }
        return ProZipResourceLoader.systemFileIcon(for: entry.name, isDirectory: false)
    }

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"
        return df
    }()
}

// MARK: - Visual Effect View Helper for Liquid Glass

public struct VisualEffectView: NSViewRepresentable {
    public let material: NSVisualEffectView.Material
    public let blendingMode: NSVisualEffectView.BlendingMode

    public init(
        material: NSVisualEffectView.Material = .hudWindow,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    ) {
        self.material = material
        self.blendingMode = blendingMode
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
