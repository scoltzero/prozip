import SwiftUI
import AppKit
import ServiceManagement
import ProZipShared
import ProZipCore

public enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "通用"
    case compression = "压缩"
    case extraction = "解压"
    case passwordBook = "密码本"
    case flow = "Flow"
    case mini = "ProZip Mini"
    case shelf = "ProZip 文件盒"
    case fileAssociation = "格式关联"
    case advanced = "高级"
    case about = "关于"

    public var id: String { rawValue }

    public var systemIcon: String {
        switch self {
        case .general: return "gearshape"
        case .compression: return "arrow.down.to.line.square"
        case .extraction: return "arrow.up.to.line.square"
        case .passwordBook: return "key"
        case .flow: return "bolt.fill"
        case .mini: return "macwindow"
        case .shelf: return "tray.full"
        case .fileAssociation: return "link"
        case .advanced: return "slider.horizontal.3"
        case .about: return "info.circle"
        }
    }

    public var topBarIcon: String {
        switch self {
        case .general: return "gearshape"
        case .compression: return "archivebox"
        case .extraction: return "tray.and.arrow.up"
        case .flow: return "point.bottomleft.forward.to.point.topright.scurvepath"
        default: return systemIcon
        }
    }
}

public struct ProZipSettingsView: View {
    @ObservedObject public var preferences = ProZipPreferences.shared
    @EnvironmentObject public var appViewModel: ProZipAppViewModel
    @State public var selectedTab: SettingsTab = .general
    @State private var hoveredTab: SettingsTab?
    @State private var isProButtonHovered = false
    @Environment(\.colorScheme) private var colorScheme

    public init(initialTab: SettingsTab = .general) {
        _selectedTab = State(initialValue: initialTab)
    }

    private var selectedIndex: Int {
        SettingsTab.allCases.firstIndex(of: selectedTab) ?? 0
    }

    private var settingsWindowTarget: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == "ProZip.SettingsWindow" } ?? NSApp.keyWindow
    }

    public var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
                .frame(width: SettingsMetrics.sidebarWidth)

            settingsDetailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: SettingsMetrics.windowWidth, idealWidth: SettingsMetrics.windowWidth, maxWidth: .infinity, minHeight: SettingsMetrics.windowMinHeight, idealHeight: SettingsMetrics.windowHeight, maxHeight: .infinity)
        .background(SettingsSkin.contentBackground(colorScheme))
        .ignoresSafeArea(.container, edges: .top)
        .overlay(alignment: .top) {
            WindowDragArea()
                .frame(maxWidth: .infinity)
                .frame(height: 44)
        }
        .overlay(alignment: .topLeading) {
            MainWindowTrafficLightsView(
                onClose: { settingsWindowTarget?.close() },
                onMinimize: { settingsWindowTarget?.miniaturize(nil) },
                onZoom: {
                    guard let win = settingsWindowTarget, win.styleMask.contains(.resizable) else { return }
                    win.zoom(nil)
                }
            )
            .padding(.leading, 12)
            .padding(.top, 13)
        }
        .onAppear {
            if appViewModel.settingsSelectedTab != selectedTab {
                appViewModel.settingsSelectedTab = selectedTab
            }
        }
        .onChange(of: appViewModel.settingsSelectedTab) { _, tab in selectedTab = tab }
        .onChange(of: selectedTab) { _, tab in appViewModel.settingsSelectedTab = tab }
    }

    // MARK: - Left Sidebar (210pt: brand @ y=58, nav @ y=116, Pro card @ y=575)

    private var settingsSidebar: some View {
        VStack(spacing: 0) {
            brandHeader

            navigationList

            Spacer(minLength: 0)

            proCard
                .padding(.horizontal, 14)
                .padding(.bottom, SettingsMetrics.proCardBottomInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SettingsSkin.sidebarBackground(colorScheme))
    }

    private var brandHeader: some View {
        Button { NotificationCenter.default.post(name: .proZipShowWelcome, object: nil) } label: {
        HStack(spacing: 11) {
            ProZipBrandIcon(size: 32, showAppSquircle: true)

            Text("ProZip")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(SettingsSkin.primaryText(colorScheme))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.leading, 22)
        .frame(height: 33)
        .padding(.top, SettingsMetrics.brandTop)
        }
        .buttonStyle(.plain)
        .help(preferences.localizedString("欢迎页面"))
    }

    private var navigationList: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: SettingsMetrics.navCornerRadius, style: .continuous)
                .fill(SettingsSkin.navSelectedFill(colorScheme))
                .frame(width: SettingsMetrics.navWidth, height: SettingsMetrics.navHeight)
                .shadow(color: SettingsSkin.navSelectedShadow(colorScheme), radius: 7, x: 0, y: 2)
                .offset(y: CGFloat(selectedIndex) * SettingsMetrics.navStride)
                .opacity(0.999)

            VStack(spacing: SettingsMetrics.navSpacing) {
                ForEach(SettingsTab.allCases) { tab in
                    navigationButton(tab)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, SettingsMetrics.navTop - SettingsMetrics.brandTop - 33)
    }

    private func navigationButton(_ tab: SettingsTab) -> some View {
        let isSelected = selectedTab == tab
        let isHovered = hoveredTab == tab
        return Button {
            guard selectedTab != tab else { return }
            withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 13) {
                Image(systemName: tab.systemIcon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? ProZipTheme.accent : SettingsSkin.navIcon(colorScheme))
                    .frame(width: 16, height: 16)

                Text(preferences.localizedString(tab.rawValue))
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(SettingsSkin.primaryText(colorScheme))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.leading, 16)
            .padding(.trailing, 12)
            .frame(width: SettingsMetrics.navWidth, height: SettingsMetrics.navHeight, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: SettingsMetrics.navCornerRadius, style: .continuous)
                    .fill(isHovered && !isSelected ? SettingsSkin.hoverFill(colorScheme) : Color.clear)
            }
            .contentShape(RoundedRectangle(cornerRadius: SettingsMetrics.navCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                hoveredTab = hovering ? tab : nil
            }
        }
    }

    // MARK: - Pro card (182x131)

    private var proCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Text("ProZip Pro")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(SettingsSkin.primaryText(colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .layoutPriority(1)

                Text(preferences.localizedString("全功能已解锁"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ProZipTheme.accentDeep)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(ProZipTheme.accentSoft)
                    .clipShape(Capsule())

                Spacer(minLength: 0)
            }

            Text(preferences.localizedString("开源无限制，专业功能全部可用"))
                .font(.system(size: 11))
                .foregroundStyle(SettingsSkin.secondaryText(colorScheme))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            Spacer(minLength: 6)

            Button {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                    selectedTab = .about
                }
            } label: {
                Text(preferences.localizedString("开源许可与概览"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .frame(height: SettingsMetrics.proButtonHeight)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [ProZipTheme.accentBright, ProZipTheme.accentDeep],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .brightness(isProButtonHovered ? 0.04 : 0)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) {
                    isProButtonHovered = hovering
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .frame(width: SettingsMetrics.proCardWidth, height: SettingsMetrics.proCardHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius, style: .continuous)
                .fill(SettingsSkin.proCardGradient(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius, style: .continuous)
                .strokeBorder(SettingsSkin.proCardBorder(colorScheme), lineWidth: 1)
        )
    }

    // MARK: - Right Detail Pane (title @ x=240 y=33, scroll x=240..852)

    private var settingsDetailPane: some View {
        Group {
            if selectedTab == .about {
                AboutSettingsPane()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ZStack(alignment: .top) {
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: SettingsMetrics.groupSpacing) {
                            switch selectedTab {
                            case .general:
                                GeneralSettingsPane(preferences: preferences, selectedTab: $selectedTab)
                            case .compression:
                                CompressionSettingsPane(preferences: preferences, selectedTab: $selectedTab)
                            case .extraction:
                                ExtractionSettingsPane(preferences: preferences, selectedTab: $selectedTab)
                            case .passwordBook:
                                PasswordBookSettingsPane(preferences: preferences)
                            case .flow:
                                FlowSettingsPane(preferences: preferences)
                            case .mini:
                                MiniSettingsPane(preferences: preferences)
                            case .shelf:
                                ShelfSettingsPane(preferences: preferences)
                            case .fileAssociation:
                                FileAssociationSettingsPane()
                            case .advanced:
                                AdvancedSettingsPane(preferences: preferences)
                            case .about:
                                AboutSettingsPane()
                            }
                        }
                        .frame(maxWidth: 800, alignment: .leading)
                        .padding(.top, SettingsMetrics.headerHeight)
                        .padding(.leading, SettingsMetrics.contentLeading)
                        .padding(.trailing, SettingsMetrics.contentTrailing)
                        .padding(.bottom, 34)
                        .frame(maxWidth: .infinity, alignment: .top)
                    }

                    detailHeader
                }
            }
        }
        .background(SettingsSkin.contentBackground(colorScheme))
    }

    private var detailHeader: some View {
        let bg = SettingsSkin.contentBackground(colorScheme)
        return HStack(alignment: .center, spacing: 8) {
            Text(preferences.localizedString(selectedTab.rawValue))
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(SettingsSkin.primaryText(colorScheme))
                .lineLimit(1)
                .frame(height: 33, alignment: .center)

            if selectedTab == .flow {
                proUnlockedBadge(text: "Pro 已解锁")
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, SettingsMetrics.contentLeading)
        .padding(.trailing, SettingsMetrics.contentTrailing)
        .padding(.top, SettingsMetrics.titleTop)
        .frame(height: SettingsMetrics.headerHeight, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                ProZipVariableBlurView(
                    direction: .topToBottom,
                    material: colorScheme == .dark ? .hudWindow : .headerView
                )
                LinearGradient(
                    stops: [
                        .init(color: bg.opacity(0.95), location: 0.0),
                        .init(color: bg.opacity(0.86), location: 0.52),
                        .init(color: bg.opacity(0.0), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .allowsHitTesting(false)
        }
    }
}
// MARK: - 1. General Settings Pane (Matching settings.png + Integration & Status Bar)

public struct GeneralSettingsPane: View {
    @ObservedObject public var preferences: ProZipPreferences
    @Binding public var selectedTab: SettingsTab
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("progressWindow.keepOnTop.v1") private var progressWindowKeepOnTop: Bool = true
    @State private var isOnboardingSheetPresented: Bool = false
    @State private var isCheckUpdateSheetPresented: Bool = false
    @State private var loginItemError: String?

    public init(preferences: ProZipPreferences, selectedTab: Binding<SettingsTab> = .constant(.general)) {
        self.preferences = preferences
        self._selectedTab = selectedTab
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // 1. 启动 (Exact match to settings.png)
            settingsCard(title: localized("启动"), minRowHeight: 48) {
                HStack {
                    Text(localized("开机自动启动 ProZip"))
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    settingsSwitch(isOn: Binding(
                        get: { preferences.launchAtLogin },
                        set: { enabled in
                            do {
                                if enabled { try SMAppService.mainApp.register() }
                                else { try SMAppService.mainApp.unregister() }
                                preferences.launchAtLogin = enabled
                                loginItemError = nil
                            } catch { loginItemError = error.localizedDescription }
                        }
                    ))
                }
                
                if let loginItemError {
                    Text(loginItemError).font(.system(size: 12)).foregroundStyle(.red)
                }
            }
            

            // 2. 外观 (Exact match to settings.png using AppearanceLight.png / AppearanceDark.png / AppearanceAutomatic.png)
            settingsCard(title: localized("外观")) {
                HStack(spacing: 16) {
                    appearanceOptionCard(mode: .light, title: "浅色", imageName: "AppearanceLight")
                        .frame(maxWidth: .infinity)
                    appearanceOptionCard(mode: .dark, title: "深色", imageName: "AppearanceDark")
                        .frame(maxWidth: .infinity)
                    appearanceOptionCard(mode: .automatic, title: "自动", imageName: "AppearanceAutomatic")
                        .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 12)
            }

            // 3. 语言 (Exact match to settings.png)
            settingsCard(title: localized("语言")) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(localized("应用语言"))
                            .font(.system(size: 13, weight: .semibold))
                        Text(localized("跟随系统语言，或为 ProZip 单独指定语言。"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    SettingsPopoverPicker(
                        title: localized("应用语言"),
                        selection: $preferences.preferredLanguage,
                        options: [
                            ("system", localized("跟随系统")),
                            ("zh-Hans", "简体中文"),
                            ("en", "English"),
                            ("zh-Hant", "繁體中文")
                        ]
                    )
                }

                if preferences.isLanguageRestartRequired {
                    SettingsSeparator()
                    HStack(spacing: 12) {
                        Text(localized("重新启动 ProZip 后，语言设置将生效。请先保存修改。"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button {
                            preferences.requestLanguageRestart()
                        } label: {
                            Label(localized("重新启动 ProZip"), systemImage: "arrow.clockwise")
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 14)
                                .frame(height: 30)
                                .background(Capsule().fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.white))
                                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                    }
                }
            }
            


            // 4. 进度窗口
            settingsCard(title: localized("进度窗口"), minRowHeight: 48) {
                HStack {
                    Text(localized("保持置顶"))
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    settingsSwitch(isOn: $progressWindowKeepOnTop)
                }
            }
            


            // 5. 浏览 (Exact match to settings.png)
            settingsCard(title: localized("浏览")) {
                SettingsRowLayout {
                    HStack {
                        Text(localized("默认浏览方式"))
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        // Custom 3-item segmented pill with icons (图标 / 列表 / 分栏)
                        HStack(spacing: 2) {
                            ForEach(WorkspaceViewMode.allCases, id: \.self) { mode in
                                let isSelected = preferences.workspaceViewMode == mode
                                Button {
                                    preferences.workspaceViewMode = mode
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: mode.sfSymbol)
                                            .font(.system(size: 11, weight: .semibold))
                                        Text(localized(mode.title))
                                            .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                                    }
                                    .foregroundStyle(isSelected ? ProZipTheme.accentDeep : Color.primary.opacity(0.75))
                                    .frame(width: 88, height: 30)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                                            .fill(isSelected ? (colorScheme == .dark ? Color.white.opacity(0.14) : Color.white) : Color.clear)
                                    )
                                    .shadow(color: isSelected ? Color.black.opacity(0.06) : .clear, radius: 2, y: 1)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(3)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                        )
                    }

                    SettingsSeparator()

                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(localized("显示辅助项目"))
                                .font(.system(size: 13, weight: .semibold))
                            Text(localized("显示通常隐藏的系统辅助文件"))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        settingsSwitch(isOn: $preferences.showsAuxiliaryEntries)
                    }
                }
            }

            // 5. 悬浮预览 (Pro unlocked — all 4 sub-controls enabled when hoverPreviewEnabled is ON)
            settingsCard(title: localized("悬浮预览"), badge: localized("Pro 已解锁")) {
                SettingsRowLayout {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(localized("开启悬浮预览"))
                                .font(.system(size: 13, weight: .medium))
                            Text(localized("鼠标停留时显示文件预览"))
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        settingsSwitch(isOn: $preferences.hoverPreviewEnabled)
                    }

                    if preferences.hoverPreviewEnabled {
                        SettingsRowLayout {
                            SettingsSeparator()

                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(localized("在悬浮预览中播放视频"))
                                        .font(.system(size: 13, weight: .medium))
                                    Text(localized("支持 MP4、MOV、M4V 等格式，部分编码或文件无法预览"))
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                settingsSwitch(isOn: $preferences.hoverVideoEnabled)
                            }

                            SettingsSeparator()

                            HoverMediaLimitSliderRow(limitMB: $preferences.hoverVideoLimitMB)
                                .padding(.vertical, 12)

                            SettingsSeparator()

                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(localized("视频默认静音"))
                                        .font(.system(size: 13, weight: .medium))
                                    Text(localized("默认静音，关闭后播放视频声音"))
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                settingsSwitch(isOn: $preferences.hoverVideoMuted)
                            }

                            SettingsSeparator()

                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(localized("自动播放音频"))
                                        .font(.system(size: 13, weight: .medium))
                                    Text(localized("悬停后自动播放音频，关闭后点击播放按钮开始试听"))
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                settingsSwitch(isOn: $preferences.hoverAudioAutoplay)
                            }
                        }
                    }
                }
            }

            settingsCard(title: localized("密码输入")) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(localized("默认显示密码")).font(.system(size: 13, weight: .semibold))
                        Text(localized("可随时点击眼睛按钮隐藏")).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    settingsSwitch(isOn: $preferences.revealsPasswordByDefault)
                }
            }

            settingsCard(title: localized("处理器使用"), minRowHeight: 48) {
                HStack {
                    Text(localized("最大可用核心数")).font(.system(size: 13, weight: .semibold))
                    Spacer()
                    SettingsPopoverPicker(
                        title: localized("最大可用核心数"),
                        selection: $preferences.processorCount,
                        options: [(0, preferences.localizedString("全部可用（%ld）", ProcessInfo.processInfo.activeProcessorCount))]
                            + (1...max(1, ProcessInfo.processInfo.activeProcessorCount)).map { ($0, String($0)) }
                    )
                }
            }

            settingsCard(title: localized("访达扩展")) {
                SettingsRowLayout {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(localized("在移动存储中开启右键菜单")).font(.system(size: 13, weight: .semibold))
                            Text(localized("为外接硬盘、U盘等移动存储中的文件提供访达右键菜单")).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        settingsSwitch(isOn: $preferences.monitorsExternalVolumes)
                    }
                    SettingsSeparator()
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(localized("访达右键菜单")).font(.system(size: 13, weight: .semibold))
                            Text(localized("如果访达右键菜单中没有 ProZip，可以尝试修复。")).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        glassActionButton(localized("修复访达菜单项")) { NSUpdateDynamicServices() }
                    }
                }
            }

            settingsCard(title: localized("欢迎页面")) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(localized("重新显示欢迎页面")).font(.system(size: 13, weight: .semibold))
                        Text(localized("重新浏览介绍，不会重置设置")).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    glassActionButton(localized("重新显示")) { isOnboardingSheetPresented = true }
                }
            }
        }
        .onAppear {
            if Bundle.main.bundleURL.pathExtension == "app" {
                preferences.launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
        .sheet(isPresented: $isOnboardingSheetPresented) {
            FirstLaunchOnboardingView(dismissesSheetOnFinish: true)
        }
        .sheet(isPresented: $isCheckUpdateSheetPresented) {
            CheckForUpdatesDialogView()
        }
    }

    private func appearanceOptionCard(mode: AppearancePreference, title: String, imageName: String) -> some View {
        let isSelected = preferences.appearance == mode
        return Button {
            preferences.appearance = mode
        } label: {
            VStack(spacing: 0) {
                AppearanceWorkspaceMiniPreview(mode: mode)
                    .frame(maxWidth: .infinity)
                    .frame(height: 82)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(6)

                HStack(spacing: 5) {
                    Text(localized(title))
                        .font(.system(size: 12, weight: isSelected ? .bold : .semibold))
                        .foregroundStyle(.primary)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(ProZipTheme.accent)
                    }
                }
                .padding(.bottom, 10)
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(colorScheme == .dark ? Color(white: 0.15) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? ProZipTheme.accent : Color.primary.opacity(0.10), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func localized(_ key: String) -> String { preferences.localizedString(key) }
}

private struct AppearanceWorkspaceMiniPreview: View {
    let mode: AppearancePreference

    var body: some View {
        switch mode {
        case .light:
            singleCanvas(isDark: false, title: "浅色.zip")
        case .dark:
            singleCanvas(isDark: true, title: "深色.zip")
        case .automatic:
            GeometryReader { geo in
                let half = geo.size.width * 0.5
                ZStack(alignment: .leading) {
                    singleCanvas(isDark: true, title: "自动.zip")
                        .frame(width: geo.size.width, height: geo.size.height)

                    singleCanvas(isDark: false, title: "自动.zip")
                        .frame(width: geo.size.width, height: geo.size.height)
                        .mask(alignment: .leading) {
                            Rectangle()
                                .frame(width: half, height: geo.size.height)
                        }

                    Rectangle()
                        .fill(Color.primary.opacity(0.16))
                        .frame(width: 0.75, height: geo.size.height)
                        .offset(x: half)
                }
            }
        }
    }

    private func singleCanvas(isDark: Bool, title: String) -> some View {
        let outerPlate = isDark ? Color(red: 0.12, green: 0.13, blue: 0.15) : Color(red: 0.94, green: 0.95, blue: 0.96)
        let windowBg = isDark ? Color(red: 0.16, green: 0.17, blue: 0.19) : Color.white
        let ink = isDark ? Color.white.opacity(0.88) : Color.black.opacity(0.82)
        let muted = isDark ? Color.white.opacity(0.42) : Color.black.opacity(0.38)
        let stripe = isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.032)

        return ZStack(alignment: .topLeading) {
            outerPlate

            VStack(spacing: 0) {
                HStack(spacing: 3.5) {
                    Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.34)).frame(width: 4.5, height: 4.5)
                    Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18)).frame(width: 4.5, height: 4.5)
                    Circle().fill(Color(red: 0.16, green: 0.78, blue: 0.25)).frame(width: 4.5, height: 4.5)

                    Text(title)
                        .font(.system(size: 6.5, weight: .semibold))
                        .foregroundStyle(ink)
                        .padding(.leading, 3)

                    Spacer(minLength: 4)

                    HStack(spacing: 3) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 5))
                            .foregroundStyle(muted)
                        Image(systemName: "list.bullet")
                            .font(.system(size: 5, weight: .bold))
                            .foregroundStyle(ProZipTheme.accent)
                        Image(systemName: "rectangle.split.3x1")
                            .font(.system(size: 5))
                            .foregroundStyle(muted)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(isDark ? Color.white.opacity(0.07) : Color.black.opacity(0.045))
                    )

                    Circle()
                        .fill(ProZipTheme.accent)
                        .frame(width: 8, height: 8)
                        .overlay(
                            Image(systemName: "arrow.down.doc.fill")
                                .font(.system(size: 4.2, weight: .bold))
                                .foregroundStyle(.white)
                        )
                }
                .padding(.horizontal, 7)
                .frame(height: 16)

                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 4.5)).foregroundStyle(muted)
                    Image(systemName: "chevron.right").font(.system(size: 4.5)).foregroundStyle(muted)
                    Image(systemName: "folder.fill")
                        .font(.system(size: 5))
                        .foregroundStyle(Color(red: 0.35, green: 0.68, blue: 0.96))
                    Text("归档")
                        .font(.system(size: 5.5, weight: .medium))
                        .foregroundStyle(muted)
                    Spacer()
                }
                .padding(.horizontal, 7)
                .frame(height: 11)
                .background(isDark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))

                ZStack(alignment: .bottom) {
                    VStack(spacing: 5) {
                        Rectangle().fill(stripe).frame(height: 7)
                        Rectangle().fill(stripe).frame(height: 7)
                        Rectangle().fill(stripe).frame(height: 7)
                    }
                    .padding(.top, 5)

                    VStack(spacing: 2) {
                        Image(systemName: "plus.square.on.square")
                            .font(.system(size: 7.5, weight: .medium))
                            .foregroundStyle(ink.opacity(0.72))
                        Text("添加文件到压缩包")
                            .font(.system(size: 5, weight: .semibold))
                            .foregroundStyle(ink.opacity(0.75))
                    }
                    .frame(width: 88, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(isDark ? Color(red: 0.20, green: 0.21, blue: 0.24) : Color.white)
                            .shadow(color: .black.opacity(isDark ? 0.25 : 0.06), radius: 2, y: 1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(
                                isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.10),
                                style: StrokeStyle(lineWidth: 0.6, dash: [2, 1.5])
                            )
                    )
                    .padding(.bottom, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(windowBg)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 0.7)
            )
            .shadow(color: .black.opacity(isDark ? 0.28 : 0.06), radius: 3, y: 1)
            .padding(.leading, 6)
            .padding(.top, 6)
            .padding(.trailing, 6)
            .padding(.bottom, 4)
        }
    }
}

private struct HoverMediaLimitSliderRow: View {
    @Binding var limitMB: Int
    @Environment(\.colorScheme) private var colorScheme

    private let stopsMB: [Int] = [10, 50, 100, 500, 1024, 2048]
    private let labels: [String] = ["10 MB", "50 MB", "100 MB", "500 MB", "1 GB", "2 GB"]

    private var activeStopIndex: Int {
        stopsMB.enumerated().min(by: { abs($0.element - limitMB) < abs($1.element - limitMB) })?.offset ?? 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("可预览音视频大小上限")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text(labels[activeStopIndex])
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                let thumbDiameter: CGFloat = 22
                let trackHeight: CGFloat = 14
                let usableWidth = max(1, geo.size.width - thumbDiameter)
                let fraction = CGFloat(activeStopIndex) / CGFloat(stopsMB.count - 1)
                let thumbCenterX = (thumbDiameter / 2.0) + usableWidth * fraction

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(
                            colorScheme == .dark
                                ? Color.white.opacity(0.12)
                                : Color(red: 230.0 / 255.0, green: 231.0 / 255.0, blue: 234.0 / 255.0)
                        )
                        .frame(height: trackHeight)

                    Capsule()
                        .fill(ProZipTheme.accent)
                        .frame(width: max(trackHeight, thumbCenterX + 2), height: trackHeight)

                    HStack(spacing: 0) {
                        ForEach(0..<stopsMB.count, id: \.self) { idx in
                            Circle()
                                .fill(idx <= activeStopIndex ? Color.white.opacity(0.92) : Color.secondary.opacity(0.45))
                                .frame(width: 3, height: 3)
                            if idx < stopsMB.count - 1 {
                                Spacer()
                            }
                        }
                    }
                    .padding(.horizontal, thumbDiameter / 2.0)

                    Circle()
                        .fill(Color.white)
                        .frame(width: thumbDiameter, height: thumbDiameter)
                        .shadow(color: .black.opacity(0.16), radius: 3, y: 1)
                        .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 0.5))
                        .offset(x: thumbCenterX - (thumbDiameter / 2.0))
                }
                .frame(height: thumbDiameter)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let clamped = min(max(0, value.location.x - thumbDiameter / 2.0), usableWidth)
                            let step = Int(((clamped / usableWidth) * CGFloat(stopsMB.count - 1)).rounded())
                            withAnimation(.spring(response: 0.20, dampingFraction: 0.80)) {
                                limitMB = stopsMB[min(stopsMB.count - 1, max(0, step))]
                            }
                        }
                )
            }
            .frame(height: 22)

            HStack {
                ForEach(Array(labels.enumerated()), id: \.offset) { idx, label in
                    Text(label)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    if idx < labels.count - 1 {
                        Spacer()
                    }
                }
            }
        }
    }
}

private struct SettingsPopoverPicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [(value: Value, title: String)]
    @State private var isPresented = false
    @State private var isButtonHovered = false
    @State private var hoveredValue: Value?
    @Environment(\.colorScheme) private var colorScheme

    private var selectedTitle: String {
        options.first(where: { $0.value == selection })?.title ?? String(describing: selection)
    }

    var body: some View {
        Button { isPresented.toggle() } label: {
            HStack {
                Text(selectedTitle)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: isPresented ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(width: 190, height: 36)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        colorScheme == .dark
                            ? Color.white.opacity(isButtonHovered ? 0.12 : 0.08)
                            : (isButtonHovered
                                ? Color(red: 234.0 / 255.0, green: 236.0 / 255.0, blue: 239.0 / 255.0)
                                : Color(red: 242.0 / 255.0, green: 243.0 / 255.0, blue: 245.0 / 255.0))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isPresented ? ProZipTheme.accent : Color.primary.opacity(0.08),
                        lineWidth: isPresented ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isButtonHovered = $0 }
        .accessibilityLabel(title)
        .accessibilityValue(selectedTitle)
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(options.indices, id: \.self) { index in
                        let option = options[index]
                        let isSelected = selection == option.value
                        Button {
                            selection = option.value
                            isPresented = false
                        } label: {
                            HStack(spacing: 8) {
                                Text(option.title)
                                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                                    .foregroundStyle(isSelected ? ProZipTheme.accentDeep : .primary)
                                Spacer(minLength: 4)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11.5, weight: .bold))
                                    .foregroundStyle(ProZipTheme.accentDeep)
                                    .opacity(isSelected ? 1 : 0)
                            }
                            .padding(.horizontal, 10)
                            .frame(maxWidth: .infinity, minHeight: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(
                                    isSelected ? ProZipTheme.accent.opacity(0.14)
                                        : hoveredValue == option.value ? Color.primary.opacity(0.06) : .clear
                                )
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .onHover { hoveredValue = $0 ? option.value : nil }
                    }
                }
                .padding(6)
            }
            .frame(width: 196, height: min(CGFloat(options.count) * 34 + 12, 300))
        }
    }
}

// MARK: - 2. Compression Settings Pane (Matching compression.png + Output & Security)

public struct CompressionSettingsPane: View {
    @ObservedObject public var preferences: ProZipPreferences
    @Binding public var selectedTab: SettingsTab
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedPurpose: CreationProfile.Purpose
    @State private var hoveredPurpose: CreationProfile.Purpose?
    public init(preferences: ProZipPreferences, selectedTab: Binding<SettingsTab> = .constant(.compression)) {
        self.preferences = preferences
        self._selectedTab = selectedTab
        self._selectedPurpose = State(initialValue: preferences.defaultPurpose)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // 1. 默认用途、格式与压缩强度 (Exact match to compression.png)
            settingsCard(title: "默认用途、格式与压缩强度", minRowHeight: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    // 5 Purpose Cards
                    HStack(spacing: 9) {
                        ForEach(CreationProfile.Purpose.allCases, id: \.self) { purpose in
                            purposeOptionCard(purpose)
                        }
                    }
                    .padding(.top, 14)

                    // 默认压缩格式
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("默认压缩格式")
                                .font(.system(size: 13, weight: .semibold))
                            Text("修改仅应用于当前选中的用途")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()

                        let curFmt = preferences.defaultFormat(for: selectedPurpose)
                        HStack(spacing: 2) {
                            ForEach([ArchiveFormat.zip, .sevenZip, .tar], id: \.self) { fmt in
                                let isAllowed = selectedPurpose.allowedFormats.contains(fmt)
                                let isSelected = curFmt == fmt
                                Button {
                                    if isAllowed {
                                        preferences.setDefaultFormat(fmt, for: selectedPurpose)
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(fmt.rawValue.uppercased())
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(isSelected ? ProZipTheme.accentDeep : (isAllowed ? Color.primary.opacity(0.75) : Color.secondary.opacity(0.4)))
                                        if fmt != .zip {
                                            Text("Pro")
                                                .font(.system(size: 9, weight: .semibold))
                                                .foregroundStyle(ProZipTheme.accentDeep)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(ProZipTheme.accentSoft)
                                                .clipShape(Capsule())
                                        }
                                    }
                                    .frame(width: 90, height: 29)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                                            .fill(isSelected ? (colorScheme == .dark ? Color.white.opacity(0.14) : Color.white) : Color.clear)
                                    )
                                    .shadow(color: isSelected ? Color.black.opacity(0.06) : .clear, radius: 2, y: 1)
                                }
                                .buttonStyle(.plain)
                                .disabled(!isAllowed)
                            }
                        }
                        .padding(3)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                        )
                    }
                    .padding(.top, 28)
                    .padding(.bottom, 26)

                    SettingsSeparator()

                    // 默认压缩强度
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text("默认压缩强度")
                                        .font(.system(size: 13, weight: .semibold))
                                    proUnlockedBadge(text: "Pro")
                                }
                                Text("修改仅应用于当前选中的用途")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(selectedPurpose.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(ProZipTheme.accentDeep)
                        }

                        let curStrength = preferences.defaultStrength(for: selectedPurpose)
                        ProZipStrengthSlider(
                            strength: Binding(
                                get: { curStrength },
                                set: { preferences.setDefaultStrength($0, for: selectedPurpose) }
                            ),
                            isDisabled: selectedPurpose == .smallest || preferences.defaultFormat(for: selectedPurpose) == .tar,
                            thumbDiameter: 28,
                            trackHeight: 20,
                            rowSpacing: 5,
                            subtitleFontSize: 11.5
                        )
                        .padding(.horizontal, 4)
                    }
                    .padding(.top, 15.5)
                    .padding(.bottom, 12)
                }
            }

            // 2. 分卷压缩 (Exact match to compression.png)
            settingsCard(title: "分卷压缩", minRowHeight: 58) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("默认创建分卷压缩包")
                            .font(.system(size: 13, weight: .semibold))
                        Text("新建压缩包时自动启用分卷")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    settingsSwitch(isOn: $preferences.defaultCreatesSplitVolumes)
                }
            }

            // Reset Defaults Button (Exact match to compression.png bottom-right pill)
            HStack {
                Spacer()
                Button {
                    preferences.resetCompressionDefaults()
                    selectedPurpose = .general
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 12, weight: .semibold))
                        Text("恢复默认压缩设置")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white)
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.04), radius: 2, y: 1)
                }
                .buttonStyle(ProZipPressScaleStyle(hoverScale: 1.02, pressedScale: 0.97))
            }
        }
        .onAppear {
            selectedPurpose = preferences.defaultPurpose
        }
        .onChange(of: preferences.defaultPurpose) { _, newValue in
            selectedPurpose = newValue
        }
    }

    private func purposeOptionCard(_ purpose: CreationProfile.Purpose) -> some View {
        let isSelected = selectedPurpose == purpose
        let isHovered = hoveredPurpose == purpose
        return Button {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                selectedPurpose = purpose
                preferences.defaultPurpose = purpose
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 6) {
                    Image(systemName: purpose.sfSymbol)
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .frame(height: 24)

                    Text(purpose.title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(isSelected ? Color.white : Color.primary)

                    Text(purpose.subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Color.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, minHeight: 102, maxHeight: 102)
                .background {
                    RoundedRectangle(cornerRadius: isSelected ? 12.5 : 14, style: .continuous)
                        .fill(
                            isSelected
                                ? ProZipTheme.accent
                                : (colorScheme == .dark
                                    ? Color.white.opacity(isHovered ? 0.09 : 0.05)
                                    : (isHovered ? Color(white: 0.975) : Color.white))
                        )
                        .padding(isSelected ? 1.5 : 0)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            isSelected
                                ? ProZipTheme.accent.opacity(0.42)
                                : Color.primary.opacity(isHovered ? 0.18 : 0.10),
                            lineWidth: 1
                        )
                )

                if purpose != .general {
                    Text("Pro")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(isSelected ? Color.white : ProZipTheme.accentDeep)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.white.opacity(0.22) : ProZipTheme.accentSoft)
                        )
                        .padding(6)
                }
            }
        }
        .buttonStyle(ProZipPressScaleStyle(hoverScale: 1.01, pressedScale: 0.97))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                hoveredPurpose = hovering ? purpose : (hoveredPurpose == purpose ? nil : hoveredPurpose)
            }
        }
    }
}

// MARK: - 3. Extraction Settings Pane (Matching extraction.png + Folder Strategy & Password Book)

public struct ExtractionSettingsPane: View {
    @ObservedObject public var preferences: ProZipPreferences
    @Binding public var selectedTab: SettingsTab
    public init(preferences: ProZipPreferences, selectedTab: Binding<SettingsTab> = .constant(.extraction)) {
        self.preferences = preferences
        self._selectedTab = selectedTab
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // 1. 打开压缩包 (Exact match to extraction.png / arczip-settings-extraction)
            settingsCard(title: "打开压缩包", minRowHeight: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("双击时快速解压")
                                .font(.system(size: 13, weight: .semibold))
                            Text("开启此选项后，双击压缩包会将它立刻解压到所在文件夹，跳过浏览步骤。")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        settingsSwitch(isOn: $preferences.directExtractOnDoubleClick)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .center, spacing: 9.5) {
                            Circle()
                                .fill(Color.secondary.opacity(0.75))
                                .frame(width: 3, height: 3)
                                .padding(.leading, 1.5)
                            Text("按住 Shift 键，再双击压缩包，即可临时快速解压到所在文件夹。")
                        }
                        HStack(alignment: .center, spacing: 9.5) {
                            Circle()
                                .fill(Color.secondary.opacity(0.75))
                                .frame(width: 3, height: 3)
                                .padding(.leading, 1.5)
                            Text("DMG、ISO 等格式不受此设置影响，始终以浏览方式打开。")
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }
                .padding(.top, 12.5)
                .padding(.bottom, 11.5)
            }

            // 2. 解压完成后 (Exact match to extraction.png)
            settingsCard(title: "解压完成后", minRowHeight: 59) {
                SettingsRowLayout(minRowHeight: 59) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("自动选中解压结果")
                                .font(.system(size: 13, weight: .semibold))
                            Text("解压完成后在访达中显示输出位置，并选中解压结果。")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        settingsSwitch(isOn: $preferences.automaticallySelectsResults)
                    }

                    SettingsSeparator()

                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("如何处理压缩包")
                                .font(.system(size: 13, weight: .semibold))
                            Text("全部解压完成后，选择保留或移入废纸篓")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        SettingsPopoverPicker(
                            title: "如何处理压缩包",
                            selection: $preferences.extractionCompletionAction,
                            options: ArchiveCompletionAction.allCases.map { ($0, $0.title) }
                        )
                    }

                    SettingsSeparator()

                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("自动关闭压缩包")
                                .font(.system(size: 13, weight: .semibold))
                            Text("全部解压完成并保留压缩包后，自动关闭窗口")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        settingsSwitch(isOn: $preferences.automaticallyClosesArchive)
                    }
                }
            }

            // 3. 内容过滤 (Exact match to extraction.png)
            VStack(alignment: .leading, spacing: 8) {
                settingsCard(title: "内容过滤", minRowHeight: 58) {
                    SettingsRowLayout(minRowHeight: 58) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("自动排除系统辅助文件")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("过滤 macOS、Windows 生成的辅助文件")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            settingsSwitch(isOn: $preferences.filtersSystemAuxiliaryFiles)
                        }

                        SettingsSeparator()

                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("自动过滤 DMG 安装辅助文件")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("过滤隐藏布局文件与 Applications 替身")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            settingsSwitch(isOn: $preferences.filtersDMGInstallerArtifacts)
                        }
                    }
                }

                Text("明确选中的项目、用户隐藏文件和应用包内容都会保留。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }

        }
    }
}

// MARK: - 4. Password Book Settings Pane

public struct PasswordBookSettingsPane: View {
    @ObservedObject public var preferences: ProZipPreferences
    @ObservedObject public var passwordBook = PasswordBook.shared
    @State private var newTitle: String = ""
    @State private var newPassword: String = ""
    @State private var newNotes: String = ""
    @State private var isNewPreset: Bool = false
    @State private var isAddSheetPresented: Bool = false
    @State private var isProtectionDialogPresented: Bool = false
    @State private var searchKeyword: String = ""
    @State private var revealedEntryIDs: Set<UUID> = []

    public var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let error = passwordBook.lastError {
                Text(error).font(.system(size: 11)).foregroundStyle(.red)
            }
            settingsCard(title: "密码自动化与输入") {
                SettingsRowLayout {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("自动保存成功解压的密码")
                                .font(.system(size: 13, weight: .semibold))
                            Text("成功解锁或创建加密压缩包后，自动保存所用密码。")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        settingsSwitch(isOn: $preferences.passwordBookAutoSave)
                    }

                    SettingsSeparator()

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("打开加密包时自动尝试密码本解锁")
                                .font(.system(size: 13, weight: .semibold))
                            Text("打开加密压缩包时，自动尝试已保存的密码。")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        settingsSwitch(isOn: $preferences.passwordBookAutoUnlock)
                    }

                    SettingsSeparator()

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("默认显示密码")
                                .font(.system(size: 13, weight: .semibold))
                            Text("方便输入中文、日文等非英文密码及使用输入法候选；仍可点击眼睛按钮临时隐藏。")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        settingsSwitch(isOn: $preferences.revealsPasswordByDefault)
                    }
                }
            }

            settingsCard(title: "安全") {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("使用密码保护密码本")
                                .font(.system(size: 13, weight: .semibold))
                            Text(passwordBook.hasMasterPassword ? "已开启保护" : "未开启")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(passwordBook.hasMasterPassword ? ProZipTheme.accentDeep : .secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(passwordBook.hasMasterPassword ? ProZipTheme.accentSoft : Color.secondary.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        Text("使用独立密码保护密码本，支持时可用 Touch ID 或 Apple Watch 快速解锁。")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        if passwordBook.hasMasterPassword && !passwordBook.isLocked {
                            glassActionButton("立即锁定", icon: "lock.fill") {
                                passwordBook.lock()
                            }
                        }
                        glassActionButton(passwordBook.hasMasterPassword ? "修改密码…" : "开启保护…", icon: "lock.shield") {
                            isProtectionDialogPresented = true
                        }
                    }
                }
            }

            settingsCard(title: "已保存的密码") {
                SettingsRowLayout {
                    HStack {
                        Text("共 \(passwordBook.entries.count) 个密码")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)

                        Spacer()

                        TextField("搜索名称或密码", text: $searchKeyword)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 160)

                        glassActionButton("添加密码…", icon: "plus") {
                            isAddSheetPresented = true
                        }
                    }

                    if passwordBook.isLocked {
                        HStack(spacing: 10) {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(ProZipTheme.accent)
                            Text("密码本已锁定。请先解锁密码本以查看或编辑已保存记录。")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Spacer()
                            glassActionButton("解锁密码本…", icon: "key.fill") {
                                isProtectionDialogPresented = true
                            }
                        }
                        .padding(.vertical, 12)
                    } else if passwordBook.entries.isEmpty {
                        Text("尚未保存密码。保存常用密码，方便解锁或创建压缩包。")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 16)
                    } else {
                        let filtered = passwordBook.entries.filter {
                            searchKeyword.isEmpty ||
                            $0.title.localizedCaseInsensitiveContains(searchKeyword) ||
                            $0.note.localizedCaseInsensitiveContains(searchKeyword) ||
                            $0.password.localizedCaseInsensitiveContains(searchKeyword)
                        }
                        ForEach(filtered) { entry in
                            let isRevealed = revealedEntryIDs.contains(entry.id)
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(entry.title)
                                            .font(.system(size: 13, weight: .semibold))
                                        if entry.isPreset {
                                            Text("预设")
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundStyle(ProZipTheme.accentDeep)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1)
                                                .background(ProZipTheme.accentSoft)
                                                .clipShape(Capsule())
                                        }
                                    }
                                    Text(isRevealed ? entry.password : String(repeating: "•", count: max(6, entry.password.count)))
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    if isRevealed {
                                        revealedEntryIDs.remove(entry.id)
                                    } else {
                                        revealedEntryIDs.insert(entry.id)
                                    }
                                } label: {
                                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("显示或隐藏密码")

                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(entry.password, forType: .string)
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("复制密码")

                                Button {
                                    passwordBook.deleteEntry(id: entry.id)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("删除")
                            }
                            Divider()
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $isAddSheetPresented) {
            VStack(alignment: .leading, spacing: 14) {
                Text("添加密码到密码本")
                    .font(.system(size: 13, weight: .bold))

                TextField("名称（可选，如：团队素材包）", text: $newTitle)
                    .textFieldStyle(.roundedBorder)

                TextField("密码内容", text: $newPassword)
                    .textFieldStyle(.roundedBorder)

                TextField("备注信息（可选）", text: $newNotes)
                    .textFieldStyle(.roundedBorder)

                Toggle("设为压缩创建预设密码", isOn: $isNewPreset)
                    .toggleStyle(SwitchToggleStyle(tint: ProZipTheme.accent))

                if let error = passwordBook.lastError {
                    Text(error).font(.system(size: 11)).foregroundStyle(.red)
                }
                HStack {
                    Button("取消") {
                        isAddSheetPresented = false
                    }
                    Spacer()
                    Button("保存") {
                        if !newPassword.isEmpty {
                            let finalTitle = newTitle.trimmingCharacters(in: .whitespaces).isEmpty
                                ? "密码 \(passwordBook.entries.count + 1)"
                                : newTitle
                            passwordBook.addEntry(title: finalTitle, password: newPassword, notes: newNotes, isPreset: isNewPreset)
                            guard passwordBook.lastError == nil else { return }
                            newTitle = ""
                            newPassword = ""
                            newNotes = ""
                            isAddSheetPresented = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ProZipTheme.accent)
                    .disabled(newPassword.isEmpty)
                }
            }
            .padding(24)
            .frame(width: 380)
        }
        .sheet(isPresented: $isProtectionDialogPresented) {
            PasswordBookProtectionDialogView()
        }
    }
}

// MARK: - 5. Flow Settings Pane (Application Installation & Allowed Open Formats)

public struct FlowSettingsPane: View {
    @ObservedObject public var preferences: ProZipPreferences

    public init(preferences: ProZipPreferences) {
        self.preferences = preferences
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // 1. 应用安装 (Exact match to flow.png)
            settingsCard(title: "应用安装") {
                SettingsRowLayout {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("快捷安装")
                                .font(.system(size: 13, weight: .semibold))
                            Text("安装时移除下载来源标记，可能减少 macOS 的安全提示。仅在信任应用来源时开启。")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        settingsSwitch(isOn: $preferences.quickInstallApplication)
                    }

                    SettingsSeparator()

                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("如何处理压缩包")
                                .font(.system(size: 13, weight: .semibold))
                            Text("应用安装完成后，选择保留或移入废纸篓")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        SettingsPopoverPicker(
                            title: "如何处理压缩包",
                            selection: $preferences.installCompletionAction,
                            options: ArchiveCompletionAction.allCases.map { ($0, $0.title) }
                        )
                    }

                    SettingsSeparator()

                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("自动关闭压缩包")
                                .font(.system(size: 13, weight: .semibold))
                            Text("应用安装完成并保留压缩包后，自动关闭窗口")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        settingsSwitch(isOn: $preferences.installAutomaticallyClosesArchive)
                    }
                }
            }

            // 2. 打开文件 (Exact match to flow.png 32 formats whitelist)
            settingsCard(title: "打开文件") {
                SettingsRowLayout {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("允许打开的文件格式")
                                .font(.system(size: 13, weight: .semibold))
                            Text("为所选格式提供“打开文件”操作")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(preferences.allowedOpenFormats.count) / 32")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 16) {
                        Button("选择全部") {
                            preferences.allowedOpenFormats = AllowedOpenFormat.defaultAllowedIDs
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)

                        Button("全部取消") {
                            preferences.allowedOpenFormats.removeAll()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    }

                    ForEach(OpenFileCategory.allCases, id: \.self) { cat in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(cat.rawValue)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)

                            let formats = AllowedOpenFormat.exact32.filter { $0.category == cat }
                            LazyVGrid(columns: [
                                GridItem(.flexible(), alignment: .leading),
                                GridItem(.flexible(), alignment: .leading),
                                GridItem(.flexible(), alignment: .leading),
                                GridItem(.flexible(), alignment: .leading)
                            ], spacing: 10) {
                                ForEach(formats) { fmt in
                                    let isChecked = preferences.allowedOpenFormats.contains(fmt.id)
                                    Button {
                                        if isChecked {
                                            preferences.allowedOpenFormats.remove(fmt.id)
                                        } else {
                                            preferences.allowedOpenFormats.insert(fmt.id)
                                        }
                                    } label: {
                                        HStack(spacing: 6) {
                                            ZStack {
                                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                                    .fill(isChecked ? ProZipTheme.accent : Color.primary.opacity(0.08))
                                                    .frame(width: 16, height: 16)
                                                if isChecked {
                                                    Image(systemName: "checkmark")
                                                        .font(.system(size: 10, weight: .bold))
                                                        .foregroundStyle(.white)
                                                }
                                            }
                                            Text(fmt.displayName)
                                                .font(.system(size: 12))
                                                .foregroundStyle(.primary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.top, 4)
                        .padding(.bottom, cat == OpenFileCategory.allCases.last ? 16 : 0)
                    }
                }
            }


        }
    }

}

// MARK: - 6. ProZip Mini Settings Pane

public struct MiniSettingsPane: View {
    @ObservedObject public var preferences: ProZipPreferences
    @ObservedObject private var spacebarMonitor = FinderSpacebarMonitor.shared

    public var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            settingsCard(title: "打开方式与外观") {
                SettingsRowLayout {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("默认用 ProZip Mini 打开")
                                .font(.system(size: 13, weight: .semibold))
                            Text("从 Finder 打开压缩包时优先使用 Mini")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        settingsSwitch(isOn: $preferences.prefersMiniWindow)
                    }

                    SettingsSeparator()

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("使用 Liquid Glass 材质")
                                .font(.system(size: 13, weight: .semibold))
                            Text("关闭后使用经典毛玻璃材质，即时应用于 Mini 窗口")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        settingsSwitch(isOn: $preferences.miniUsesLiquidGlass)
                    }

                    SettingsSeparator()

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("使用彩色窗口控制按钮")
                                .font(.system(size: 13, weight: .semibold))
                            Text("关闭后按钮恢复未着色外观，置顶时仍保留淡蓝色按钮和圆环")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        settingsSwitch(isOn: $preferences.miniUsesColoredControlButtons)
                    }
                }
            }

            settingsCard(title: "访达空格键直接打开 Mini（系统授权）") {
                SettingsRowLayout {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("在访达中按空格键打开 ProZip Mini")
                                .font(.system(size: 13, weight: .semibold))
                            Text("选中压缩包并按下空格键时，直接弹出可浏览的 Mini 窗格，不修改任何系统文件")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        settingsSwitch(isOn: $preferences.finderSpacebarPreviewEnabled)
                    }

                    SettingsSeparator()

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("接管范围")
                                .font(.system(size: 13, weight: .semibold))
                            Text("决定哪些压缩包在访达按空格时直接弹出 Mini")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        SettingsPopoverPicker(
                            title: "接管范围",
                            selection: $preferences.finderSpacebarPreviewScope,
                            options: FinderSpacebarPreviewScope.allCases.map { ($0, $0.title) }
                        )
                    }

                    SettingsSeparator()

                    HStack(spacing: 12) {
                        Circle()
                            .fill(spacebarMonitor.isAccessibilityGranted ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("辅助功能权限")
                                .font(.system(size: 13, weight: .semibold))
                            Text(spacebarMonitor.isAccessibilityGranted ? "已授权，可安全拦截访达中的空格键事件" : "用于捕获访达空格键，并在文本重命名/搜索时自动放行")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if spacebarMonitor.isAccessibilityGranted {
                            Text("已授权")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(.green)
                        } else {
                            glassActionButton("授权辅助功能") {
                                spacebarMonitor.requestAccessibilityAuthorization()
                            }
                        }
                    }

                    SettingsSeparator()

                    HStack(spacing: 12) {
                        Circle()
                            .fill(spacebarMonitor.automationStatus == .granted ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("自动化权限（控制访达）")
                                .font(.system(size: 13, weight: .semibold))
                            Text("用于在桌面、图标视图等场景读取当前选中的单个压缩包路径")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        switch spacebarMonitor.automationStatus {
                        case .granted:
                            Text("已授权")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(.green)
                        case .denied:
                            glassActionButton("打开系统设置") {
                                spacebarMonitor.openAutomationSettings()
                            }
                        case .notDetermined, .finderNotRunning:
                            glassActionButton("授权控制访达") {
                                spacebarMonitor.requestAutomationAuthorization()
                            }
                        }
                    }

                    SettingsSeparator()

                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(spacebarStatusSummary)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(spacebarMonitor.isTapActive && spacebarMonitor.isFullyAuthorized ? Color.green : .secondary)
                            if let note = spacebarMonitor.lastStatusNote {
                                Text(note)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.orange)
                            }
                        }
                        Spacer()
                        glassActionButton("刷新状态", icon: "arrow.clockwise") {
                            spacebarMonitor.refreshPermissions(attemptTapSync: true)
                        }
                        if !spacebarMonitor.isFullyAuthorized {
                            Button("一键授权") {
                                spacebarMonitor.requestAllAuthorizations()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(ProZipTheme.accent)
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
        .onAppear {
            spacebarMonitor.refreshPermissions(attemptTapSync: true)
        }
    }

    private var spacebarStatusSummary: String {
        if !preferences.finderSpacebarPreviewEnabled {
            return "已关闭访达空格键监听"
        }
        if spacebarMonitor.isTapActive && spacebarMonitor.isFullyAuthorized {
            return "状态：已就绪（在访达选中已接管压缩包按空格即可弹出 Mini）"
        }
        if spacebarMonitor.isTapActive {
            return "状态：部分就绪（建议同时授予“自动化 → 控制访达”权限以覆盖所有视图）"
        }
        return "状态：等待授权后激活（无需重启 ProZip，开启权限后自动生效）"
    }
}

// MARK: - 7. Shelf Settings Pane (ProZip 文件盒)

public struct ShelfSettingsPane: View {
    @ObservedObject public var preferences: ProZipPreferences
    @State private var previewModel = MenuBarShelfModel()
    private let colors = ["chartreuse", "blue", "pink", "red", "orange", "yellow", "green", "gray"]

    public init(preferences: ProZipPreferences) { self.preferences = preferences }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            MenuBarShelfView(model: previewModel, isInteractive: false)
                .offset(x: -221, y: -25)
                .frame(width: 260, height: 267, alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .allowsHitTesting(false)
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isImage)
                .allowsHitTesting(false)
                .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .accessibilityLabel("ProZip 文件盒外观预览")

            settingsCard(title: "外观", minRowHeight: 0) {
                SettingsRowLayout {
                    HStack {
                        Text("颜色").font(.system(size: 13, weight: .semibold))
                        Spacer()
                        HStack(spacing: 18) {
                            ForEach(colors, id: \.self) { color in
                                let swatch = colorForName(color)
                                Button { preferences.boxColor = color } label: {
                                    Circle()
                                        .fill(swatch)
                                        .frame(width: 28, height: 28)
                                        .overlay {
                                            if preferences.boxColor == color {
                                                Circle().strokeBorder(Color.white, lineWidth: 2).padding(-2.5)
                                                Circle().strokeBorder(swatch, lineWidth: 2).padding(-5)
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(colorName(color))
                            }
                        }.padding(.trailing, 4)
                    }
                    .padding(.vertical, 14)
                    SettingsSeparator()
                    VStack(spacing: 12) {
                        HStack {
                            Text("色彩浓度").font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Text("\(Int(preferences.boxShellColorOpacity * 100))%").font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                        SettingsCapsuleSlider(
                            value: $preferences.boxShellColorOpacity,
                            in: 0...1,
                            showsFill: false,
                            gradientTint: colorForName(preferences.boxColor)
                        )
                            .accessibilityLabel("色彩浓度")
                            .accessibilityValue("\(Int(preferences.boxShellColorOpacity * 100))%")
                        HStack {
                            Text("0%")
                            Spacer()
                            Text("100%")
                        }.font(.system(size: 11)).foregroundStyle(.secondary)
                    }.frame(height: 110)
                }
            }

            settingsCard(title: "使用方式", minRowHeight: 0) {
                SettingsRowLayout {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("启用 ProZip 文件盒").font(.system(size: 13, weight: .semibold))
                            Text("显示菜单栏图标，并允许向文件盒拖入文件。").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        settingsSwitch(isOn: $preferences.boxEnabled)
                    }
                    .padding(.vertical, 13)
                    SettingsSeparator()
                    VStack(spacing: 12) {
                        HStack {
                            Text("闲置后自动收起").font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Text("\(preferences.boxIdleDelaySeconds) 秒").font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                        SettingsCapsuleSlider(value: Binding(get: { Double(preferences.boxIdleDelaySeconds) }, set: { preferences.boxIdleDelaySeconds = Int($0) }), in: 1...6, step: 1)
                            .accessibilityLabel("闲置后自动收起")
                            .accessibilityValue("\(preferences.boxIdleDelaySeconds) 秒")
                        HStack { Text("1 秒"); Spacer(); Text("6 秒") }.font(.system(size: 11)).foregroundStyle(.secondary)
                        Text("使用图钉可让文件盒保持显示；拖放和处理文件时会暂停计时。").font(.system(size: 11)).foregroundStyle(.secondary)
                    }.padding(.vertical, 12)
                }
            }
        }
    }

    private func colorName(_ name: String) -> String {
        switch name {
        case "chartreuse": return "黄绿"
        case "lavender": return "薰衣草紫"
        case "blue": return "蓝色"
        case "pink": return "粉色"
        case "red": return "红色"
        case "orange": return "橙色"
        case "yellow": return "黄色"
        case "green": return "绿色"
        default: return "灰色"
        }
    }

    private func colorForName(_ name: String) -> Color {
        switch name {
        case "chartreuse": return ProZipTheme.accent
        case "lavender": return Color(red: 0.56, green: 0.50, blue: 0.85)
        case "blue": return Color(red: 0.25, green: 0.49, blue: 0.90)
        case "pink": return Color(red: 0.86, green: 0.30, blue: 0.58)
        case "red": return Color(red: 0.84, green: 0.28, blue: 0.27)
        case "orange": return Color(red: 0.89, green: 0.53, blue: 0.23)
        case "yellow": return Color(red: 0.93, green: 0.76, blue: 0.31)
        case "green": return Color(red: 0.39, green: 0.67, blue: 0.35)
        default: return Color(red: 0.52, green: 0.53, blue: 0.55)
        }
    }
}

// MARK: - 8. File Association Settings Pane

public struct FileAssociationSettingsPane: View {
    @ObservedObject private var preferences: ProZipPreferences
    @State private var associationError: String?
    @State private var isWorking = false
    @State private var isRecommendationPresented = false

    public init(preferences: ProZipPreferences = .shared) { self.preferences = preferences }

    public var body: some View {
        let statuses = preferences.fileAssociationStatuses
        let associated = statuses.values.filter(\.isFullyAssociated).count
        VStack(alignment: .leading, spacing: SettingsMetrics.groupSpacing) {
            settingsCard(title: "关联状态", minRowHeight: 54) {
                HStack {
                    HStack(spacing: 6) {
                        Circle().fill(preferences.fileAssociationsLoaded ? Color.green : Color.secondary)
                            .frame(width: 6, height: 6)
                        Text(preferences.fileAssociationsLoaded ? "已关联 \(associated) / 23" : "正在读取关联状态…")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 30)
                    .background(Capsule().fill(Color.primary.opacity(0.055)))
                    Spacer()
                    glassActionButton("刷新", icon: "arrow.clockwise") {
                        run { try await preferences.refreshFileAssociations() }
                    }
                    Button {
                        run {
                            try await preferences.refreshFileAssociations()
                            isRecommendationPresented = true
                        }
                    } label: {
                        Label("使用推荐设置", systemImage: "checkmark.circle")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 15)
                            .frame(height: 30)
                            .background(Capsule().fill(ProZipTheme.accent))
                    }
                    .buttonStyle(.plain)
                }
                .disabled(isWorking)
            }
            ForEach(FileAssociationSection.allCases, id: \.self) { section in
                let groups = FileAssociationGroup.all.filter { $0.section == section }
                settingsCard(title: section.rawValue, minRowHeight: 57) {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                        if index > 0 { SettingsSeparator() }
                        associationRow(group, status: statuses[group.id]!)
                    }
                }
            }
            if let associationError {
                Text(associationError).font(.system(size: 12)).foregroundStyle(.red)
            }
        }
        .task { run { try await preferences.refreshFileAssociations() } }
        .sheet(isPresented: $isRecommendationPresented) { recommendationReview }
    }

    private func associationRow(_ group: FileAssociationGroup, status: FileAssociationGroupStatus) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text(group.title).font(.system(size: 13.5, weight: .semibold))
                    Text(group.extensionSummary)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Text(group.description).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            settingsSwitch(isOn: Binding(
                get: { status.isFullyAssociated },
                set: { enabled in run { try await preferences.setFileAssociationGroups([group.id], enabled: enabled) } }
            ))
            .accessibilityLabel("用 ProZip 打开 " + group.title)
            .accessibilityValue(status.isPartiallyAssociated ? "部分关联" : status.isFullyAssociated ? "开启" : "关闭")
            .help(status.isPartiallyAssociated ? "部分关联" : group.description)
            .disabled(isWorking || !preferences.fileAssociationsLoaded)
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue(status.isPartiallyAssociated ? "部分关联" : status.isFullyAssociated ? "已关联" : "未关联")
    }

    private var recommendationReview: some View {
        let statuses = preferences.fileAssociationStatuses
        let groups = FileAssociationGroup.all.filter {
            FileAssociationGroup.provisionalRecommendedIDs.contains($0.id) && statuses[$0.id]?.isFullyAssociated != true
        }
        let pending = groups.reduce(0) { $0 + $1.extensions.count - (statuses[$1.id]?.associatedCount ?? 0) }
        let additional = preferences.additionalAssociationImpact(for: FileAssociationGroup.provisionalRecommendedIDs)
        return VStack(alignment: .leading, spacing: 16) {
            Text("确认关联格式").font(.system(size: 20, weight: .bold))
            Text(groups.isEmpty ? "这些常用格式已全部关联，无需更改。" : "将关联以下 \(groups.count) 组，所选组内有 \(pending) 个扩展名需要更改默认打开方式。")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            ForEach(groups) { group in
                HStack {
                    Text(group.title).font(.system(size: 13, weight: .semibold))
                    Text(group.extensionSummary).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(group.extensions.count - (statuses[group.id]?.associatedCount ?? 0)) 项更改")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            if !additional.isEmpty {
                Text("这些格式共享的打开方式还涉及：" + additional.joined(separator: "、"))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if let associationError { Text(associationError).font(.system(size: 12)).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("取消") { isRecommendationPresented = false }
                Button("确认关联") {
                    run {
                        try await preferences.setFileAssociationGroups(FileAssociationGroup.provisionalRecommendedIDs, enabled: true)
                        isRecommendationPresented = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(ProZipTheme.accent)
                .disabled(pending == 0)
            }
            .disabled(isWorking)
        }
        .padding(24)
        .frame(width: 540)
    }

    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !isWorking else { return }
        isWorking = true
        associationError = nil
        Task { @MainActor in
            defer { isWorking = false }
            do { try await operation() }
            catch { associationError = error.localizedDescription }
        }
    }
}

// MARK: - 9. Advanced Settings Pane

public struct AdvancedSettingsPane: View {
    @ObservedObject public var preferences: ProZipPreferences
    @State private var tempBytes: Int64 = 0
    @State private var maintenanceError: String?

    public var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            settingsCard(title: "临时文件") {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("可清理的临时文件").font(.system(size: 13, weight: .semibold))
                        Text(tempBytes == 0 ? "0 KB" : ByteCountFormatter.string(fromByteCount: tempBytes, countStyle: .file))
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    glassActionButton("清理", icon: "trash") {
                        Task {
                            do {
                                _ = try await ManagedTemporaryArtifactRegistry.shared.cleanAllTemporaryFiles()
                                tempBytes = await ManagedTemporaryArtifactRegistry.shared.totalCleanableBytes()
                                maintenanceError = nil
                            } catch { maintenanceError = error.localizedDescription }
                        }
                    }
                    .disabled(tempBytes == 0)
                }
                .help("清理不再使用的临时文件，保留正在使用的文件和你的原文件。")
            }
            settingsCard(title: "维护") {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("恢复所有设置").font(.system(size: 13, weight: .semibold))
                        Text("语言、通用、压缩、解压、Flow 和文件盒将恢复默认值")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    glassActionButton("恢复默认值", icon: "arrow.counterclockwise", danger: true) {
                        let alert = NSAlert()
                        alert.messageText = "恢复所有设置？"
                        alert.informativeText = "语言、通用、压缩、解压、Flow 和文件盒将恢复默认值。访达中的格式关联和密码本记录将保留。"
                        alert.addButton(withTitle: "恢复默认值")
                        alert.addButton(withTitle: "取消")
                        guard alert.runModal() == .alertFirstButtonReturn else { return }
                        do {
                            if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
                                try SMAppService.mainApp.unregister()
                            }
                            preferences.resetAllSettings()
                            maintenanceError = nil
                        } catch { maintenanceError = error.localizedDescription }
                    }
                }
            }
            if let maintenanceError {
                Text(maintenanceError).font(.system(size: 11)).foregroundStyle(.red)
            }
        }
        .task { tempBytes = await ManagedTemporaryArtifactRegistry.shared.totalCleanableBytes() }
    }
}

// MARK: - 10. About Settings Pane

public struct AboutSettingsPane: View {
    @ObservedObject private var appViewModel = ProZipAppViewModel.shared
    @State private var isUpdateDialogPresented: Bool = false
    @State private var isReleaseOverviewPresented: Bool = false
    @State private var isLicenseSheetPresented: Bool = false
    @AppStorage("updates.autoCheck.v1") private var autoCheckUpdates: Bool = true
    @State private var isCheckingForUpdates = false

    public var body: some View {
        VStack(spacing: 0) {
            ProZipBrandIcon(size: 84, showAppSquircle: true)
                .padding(.top, 68)

            Text("ProZip")
                .font(.system(size: 28, weight: .bold))
                .padding(.top, 14)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("当前版本")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text("\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.2") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "2"))")
                        .font(.system(size: 13, weight: .medium))
                    if appViewModel.isUpdateChecking {
                        Text("正在检查更新…")
                            .font(.system(size: 11))
                            .foregroundStyle(ProZipTheme.accent)
                    } else if let lastDate = AppUpdateService.lastCheckDate {
                        Text("上次检查：\(lastDate.formatted(date: .numeric, time: .shortened))")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("尚未检查更新")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    ProZipAppViewModel.shared.checkForUpdates(userInitiated: true)
                } label: {
                    Text(appViewModel.isUpdateChecking ? "正在检查…" : "检查更新")
                        .font(.system(size: 13))
                        .frame(width: 101, height: 29)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
                .disabled(appViewModel.isUpdateChecking)
            }
            .padding(.top, 54)

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("自动检查更新")
                        .font(.system(size: 16, weight: .semibold))
                    Text("每天检查更新，安装前会征求你的确认。")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                settingsSwitch(isOn: $autoCheckUpdates)
            }
            .padding(.top, 28)

            Button {
                isLicenseSheetPresented = true
            } label: {
                Text("查看开源许可")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 127, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 33)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 52)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $isLicenseSheetPresented) {
            VStack(alignment: .leading, spacing: 14) {
                Text("开源许可")
                    .font(.system(size: 16, weight: .bold))
                Text("感谢这些开源项目。以下保留原始版权声明和许可全文：")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                ScrollView {
                    Text("""
                    • ProZip Open Source Engine & UI — MIT / GPL v3 License
                    • 7-Zip (7zz) — GNU LGPL + unRAR restriction (Igor Pavlov)
                    • libarchive — BSD 2-Clause License
                    • zlib — zlib License (Jean-loup Gailly and Mark Adler)
                    • SQLite3 — Public Domain
                    """)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                }
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                HStack {
                    Spacer()
                    Button("关闭") { isLicenseSheetPresented = false }
                        .buttonStyle(.borderedProminent)
                        .tint(ProZipTheme.accent)
                }
            }
            .padding(22)
            .frame(width: 480, height: 320)
        }
    }
}

// MARK: - Shared Layout Metrics, Palette, Card & Control Helpers

private enum SettingsMetrics {
    static let windowWidth: CGFloat = 900
    static let windowHeight: CGFloat = 712
    static let windowMinHeight: CGFloat = 680

    static let sidebarWidth: CGFloat = 210
    static let brandTop: CGFloat = 63
    static let navTop: CGFloat = 116
    static let navWidth: CGFloat = 182
    static let navHeight: CGFloat = 36
    static let navSpacing: CGFloat = 2
    static let navStride: CGFloat = navHeight + navSpacing
    static let navCornerRadius: CGFloat = 10

    static let proCardWidth: CGFloat = 182
    static let proCardHeight: CGFloat = 131
    static let proCardBottomInset: CGFloat = 20
    static let proButtonHeight: CGFloat = 30

    static let headerHeight: CGFloat = 110
    static let titleTop: CGFloat = 34
    static let contentLeading: CGFloat = 32
    static let contentTrailing: CGFloat = 32

    static let groupSpacing: CGFloat = 14
    static let groupTitleSpacing: CGFloat = 10
    static let rowMinHeight: CGFloat = 60
    static let cardRadius: CGFloat = 18
    static let cardPadding: CGFloat = 20
}

private enum SettingsSkin {
    static func sidebarBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.106, green: 0.110, blue: 0.118)
            : Color(red: 242.0 / 255.0, green: 243.0 / 255.0, blue: 244.0 / 255.0) // #F2F3F4
    }

    static func contentBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.071, green: 0.075, blue: 0.078)
            : Color(red: 248.0 / 255.0, green: 248.0 / 255.0, blue: 249.0 / 255.0) // #F8F8F9
    }

    static func headerGradient(_ scheme: ColorScheme) -> LinearGradient {
        let top = scheme == .dark
            ? Color(red: 0.098, green: 0.102, blue: 0.106)
            : Color(red: 0.945, green: 0.945, blue: 0.949)
        let bottom = contentBackground(scheme)
        return LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }

    static func cardBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.137, green: 0.141, blue: 0.149) : Color.white
    }

    static func cardBorder(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.06) : Color.clear
    }

    static func cardShadow(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black.opacity(0.42) : Color.clear
    }

    static func separator(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.06)
    }

    static func primaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.92) : Color(white: 0.13)
    }

    static func secondaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.56) : Color(white: 0.46)
    }

    static func groupTitle(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.60) : Color(white: 0.40)
    }

    static func navIcon(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.72) : Color(white: 0.32)
    }

    static func navSelectedFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.22) : Color.white
    }

    static func navSelectedShadow(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black.opacity(0.45) : Color.black.opacity(0.07)
    }

    static func hoverFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04)
    }

    static func switchOff(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.18) : Color(white: 0.855)
    }

    static func proCardGradient(_ scheme: ColorScheme) -> LinearGradient {
        if scheme == .dark {
            return LinearGradient(
                colors: [Color(red: 0.145, green: 0.184, blue: 0.086), Color(red: 0.110, green: 0.145, blue: 0.063)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [Color(red: 0.949, green: 0.988, blue: 0.902), Color(red: 0.886, green: 0.965, blue: 0.777)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func proCardBorder(_ scheme: ColorScheme) -> Color {
        ProZipTheme.accent.opacity(scheme == .dark ? 0.34 : 0.24)
    }
}

/// Vertical row container: every child gets `minRowHeight` so all settings rows share
/// the 60pt rhythm; hairline separators keep their natural 1pt height.
private struct SettingsRowLayout: Layout {
    var minRowHeight: CGFloat = SettingsMetrics.rowMinHeight

    private func rowHeight(for subview: LayoutSubview, width: CGFloat) -> CGFloat {
        let fitting = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
        if fitting.height <= 0.5 { return 0 }
        if fitting.height < 6 { return fitting.height }
        return max(fitting.height, minRowHeight)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 600
        var height: CGFloat = 0
        for subview in subviews {
            height += rowHeight(for: subview, width: width)
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for subview in subviews {
            let fitting = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            let height = rowHeight(for: subview, width: bounds.width)
            if height <= 0 { continue }
            subview.place(
                at: CGPoint(x: bounds.minX, y: y + (height - fitting.height) / 2),
                proposal: ProposedViewSize(width: bounds.width, height: fitting.height)
            )
            y += height
        }
    }
}

private struct SettingsSeparator: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(SettingsSkin.separator(colorScheme))
            .frame(height: 1)
    }
}

private struct SettingsCapsuleSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double?
    let showsFill: Bool
    var gradientTint: Color?

    init(
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        step: Double? = nil,
        showsFill: Bool = true,
        gradientTint: Color? = nil
    ) {
        _value = value
        self.range = range
        self.step = step
        self.showsFill = showsFill
        self.gradientTint = gradientTint
    }

    private var fraction: Double {
        min(1, max(0, (value - range.lowerBound) / max(0.001, range.upperBound - range.lowerBound)))
    }

    var body: some View {
        GeometryReader { geometry in
            let travel = max(1, geometry.size.width - 24)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.065)).frame(height: 18)
                if let gradientTint {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.95), gradientTint.opacity(0.42)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 12 + travel * fraction, height: 18)
                } else if showsFill {
                    Capsule().fill(ProZipTheme.accent.opacity(0.45)).frame(width: 12 + travel * fraction, height: 18)
                } else {
                    Capsule().fill(LinearGradient(colors: [.white, Color.primary.opacity(0.05)], startPoint: .leading, endPoint: .trailing)).frame(height: 18)
                }
                Circle().fill(.white).frame(width: 24, height: 24)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.7))
                    .shadow(color: .black.opacity(0.14), radius: 2, y: 1)
                    .offset(x: travel * fraction)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                setValue(range.lowerBound + Double(min(1, max(0, (gesture.location.x - 12) / travel))) * (range.upperBound - range.lowerBound))
            })
        }
        .frame(height: 30)
        .accessibilityElement()
        .accessibilityValue(value.formatted())
        .accessibilityAdjustableAction { direction in
            let increment = step ?? (range.upperBound - range.lowerBound) / 100
            setValue(value + (direction == .increment ? increment : -increment))
        }
    }

    private func setValue(_ proposed: Double) {
        let snapped = step.map { ((proposed - range.lowerBound) / $0).rounded() * $0 + range.lowerBound } ?? proposed
        value = min(range.upperBound, max(range.lowerBound, snapped))
    }
}

private struct SettingsSwitch: View {
    @Binding var isOn: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                isOn.toggle()
            }
        } label: {
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(isOn ? ProZipTheme.accent : SettingsSkin.switchOff(colorScheme))

                Capsule()
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.18), radius: 1.6, x: 0, y: 0.6)
                    .frame(width: 32, height: 20)
                    .offset(x: isOn ? 20 : 2)
            }
            .frame(width: 54, height: 24)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isOn ? "开启" : "关闭")
    }
}

private func settingsSwitch(isOn: Binding<Bool>) -> SettingsSwitch {
    SettingsSwitch(isOn: isOn)
}

private func proUnlockedBadge(text: String) -> some View {
    Text(text)
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(ProZipTheme.accentDeep)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(ProZipTheme.accentSoft)
        .clipShape(Capsule())
}

private struct GlassActionButtonStyle: ButtonStyle {
    var danger = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(danger ? Color.white : Color.primary.opacity(isEnabled ? 0.85 : 0.3))
            .padding(.horizontal, 13)
            .frame(height: 30)
            .background(Capsule().fill(danger ? Color(red: 0.95, green: 0.04, blue: 0.28) : colorScheme == .dark ? Color.white.opacity(0.08) : Color.white))
            .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

private func glassActionButton(_ title: String, icon: String? = nil, danger: Bool = false, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        HStack(spacing: 5) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
            }
            Text(title)
                .lineLimit(1)
        }
    }
    .buttonStyle(GlassActionButtonStyle(danger: danger))
}

private struct SettingsCardShell<Content: View>: View {
    let title: String
    let badge: String?
    let minRowHeight: CGFloat
    let content: Content
    @Environment(\.colorScheme) private var colorScheme

    init(title: String, badge: String?, minRowHeight: CGFloat, content: Content) {
        self.title = title
        self.badge = badge
        self.minRowHeight = minRowHeight
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.groupTitleSpacing) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SettingsSkin.groupTitle(colorScheme))
                    .lineLimit(2)

                if let badge = badge {
                    proUnlockedBadge(text: badge)
                }

                Spacer(minLength: 0)
            }
            .padding(.leading, 8)

            SettingsRowLayout(minRowHeight: minRowHeight) {
                content
            }
            .padding(.horizontal, SettingsMetrics.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius, style: .continuous)
                    .fill(SettingsSkin.cardBackground(colorScheme))
                    .shadow(color: SettingsSkin.cardShadow(colorScheme), radius: 8, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius, style: .continuous)
                    .strokeBorder(SettingsSkin.cardBorder(colorScheme), lineWidth: 1)
            )
        }
    }
}

private func settingsCard<Content: View>(
    title: String,
    badge: String? = nil,
    minRowHeight: CGFloat = 60,
    @ViewBuilder content: () -> Content
) -> some View {
    SettingsCardShell(title: title, badge: badge, minRowHeight: minRowHeight, content: content())
}
