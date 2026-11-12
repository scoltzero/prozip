import AppKit
import ProZipCore
import ProZipShared
import ServiceManagement
import SwiftUI

// MARK: - ArcZipDialogSurface (Unified Glass & Specular Rim Modal Container)

public struct ArcZipDialogSurface<Content: View>: View {
    public var width: CGFloat
    public var height: CGFloat?
    @ViewBuilder public var content: () -> Content
    @Environment(\.colorScheme) private var colorScheme

    public init(
        width: CGFloat = 460,
        height: CGFloat? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.width = width
        self.height = height
        self.content = content
    }

    public var body: some View {
        content()
            .frame(width: width, height: height)
            .background(
                ZStack {
                    Color(NSColor.windowBackgroundColor)
                    LinearGradient(
                        colors: [
                            ProZipTheme.accent.opacity(colorScheme == .dark ? 0.06 : 0.04),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.18 : 0.65),
                                Color.primary.opacity(0.08)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
    }
}

// MARK: - 1. FirstLaunchOnboardingView (v3 · 8-Step Onboarding · ArcZip 1.2.3 geometry)

public typealias OnboardingView = FirstLaunchOnboardingView

/// Palette / metrics shared by the onboarding pages (ArcZip 1.2.3 replicate).
private enum OnboardingSkin {
    /// Violet used by ArcZip for CTA pills, switches and the completion badge.
    static let violet = ProZipTheme.accent
    static let violetDeep = ProZipTheme.accentDeep
    static let violetSoft = ProZipTheme.accentSoft

    /// Light grey card sitting on the white onboarding page.
    static let cardFill = Color.primary.opacity(0.05)
    static let hairline = Color.primary.opacity(0.10)
    static let inactiveDot = Color.primary.opacity(0.16)
    static let pageFill = Color(NSColor.controlBackgroundColor)

    static let headerHeight: CGFloat = 46
    static let footerHeight: CGFloat = 64
    static let contentTopPadding: CGFloat = 20
    static let horizontalPadding: CGFloat = 24
    static let artworkCorner: CGFloat = 12
}

public struct FirstLaunchOnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject public var preferences = ProZipPreferences.shared
    public var dismissesSheetOnFinish: Bool = false
    @State private var currentPage: Int = 0
    @State private var associatedFormats: Set<String> = []
    @State private var initialAssociationGroups: Set<String> = []
    @State private var associationChoicesLoaded = false
    @State private var isApplyingAssociations = false
    @State private var associationError: String?

    private static let lastPage = 7
    private static let dotCount = 7

    public init(
        initialStep: Int = 0,
        preferences: ProZipPreferences = .shared,
        dismissesSheetOnFinish: Bool = false
    ) {
        self.preferences = preferences
        self.dismissesSheetOnFinish = dismissesSheetOnFinish
        _currentPage = State(initialValue: min(max(0, initialStep), FirstLaunchOnboardingView.lastPage))
    }

    public var body: some View {
        ArcZipDialogSurface(width: 704, height: 582) {
            VStack(spacing: 0) {
                // Brand header — every page except the welcome screen.
                if currentPage > 0 {
                    OnboardingBrandHeader()
                }

                Group {
                    if currentPage == 0 {
                        stepWelcome
                    } else {
                        pageContent
                            .padding(.horizontal, OnboardingSkin.horizontalPadding)
                            .padding(.top, OnboardingSkin.contentTopPadding)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                if currentPage > 0 {
                    navFooter
                }
            }
            .frame(width: 704, height: 582)
            .background(OnboardingSkin.pageFill)
        }
    }

    // MARK: Page routing (0 welcome · 1 Mini · 2 file box · 3 formats · 4 Finder · 5 file access · 6 Pro · 7 ready)

    @ViewBuilder
    private var pageContent: some View {
        switch currentPage {
        case 1: stepMini
        case 2: stepFileBox
        case 3: stepFileAssociations
        case 4: stepFinderMenu
        case 5: stepFileAccess
        case 6: stepProTeaser
        case 7: stepCompletion
        default: stepWelcome
        }
    }

    // MARK: Step 0 · Welcome (no header, no footer)

    private var stepWelcome: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            ProZipBrandIcon(size: 128, showAppSquircle: true)

            onboardingPageTitle("欢迎使用 ProZip")
                .padding(.top, 22)

            Text("Mac 解压缩工具新体验")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .padding(.top, 10)

            Button {
                goTo(1)
            } label: {
                Text("开始设置")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 144, height: 44)
                    .background(Capsule().fill(ProZipTheme.accent))
            }
            .buttonStyle(ProZipPressScaleStyle(hoverScale: 1.02, pressedScale: 0.97))
            .keyboardShortcut(.defaultAction)
            .padding(.top, 24)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(y: 40)
        .background(
            RadialGradient(
                colors: [ProZipTheme.accent.opacity(0.13), Color.clear],
                center: .topLeading,
                startRadius: 12,
                endRadius: 560
            )
        )
    }

    // MARK: Step 1 · ProZip Mini

    private var stepMini: some View {
        VStack(alignment: .leading, spacing: 0) {
            onboardingPageTitle("ProZip Mini")

            Spacer(minLength: 8)

            OnboardingMiniMock()
                .frame(width: 504, height: 284)
                .frame(maxWidth: .infinity, alignment: .center)

            Spacer(minLength: 8)

            OnboardingToggleCard(
                title: "默认用 ProZip Mini 打开压缩包",
                subtitle: "功能齐全，快用快走，减少打扰",
                isOn: $preferences.prefersMiniWindow
            )
        }
    }

    // MARK: Step 2 · ProZip 文件盒

    private var stepFileBox: some View {
        VStack(alignment: .leading, spacing: 0) {
            onboardingPageTitle("ProZip 文件盒")

            Spacer(minLength: 10)

            HStack(alignment: .center, spacing: 4) {
                ZStack(alignment: .top) {
                    OnboardingArtwork(imageName: "OnboardingBoxDesktop", fallbackSymbol: "tray.full.fill")
                        .frame(width: 480, height: 300)

                    OnboardingMenuBarStripMock()
                        .frame(width: 480, height: 24)

                    OnboardingShelfMock()
                        .frame(width: 268, height: 260)
                        .padding(.top, 28)
                }
                .frame(width: 480, height: 300)
                .clipShape(RoundedRectangle(cornerRadius: OnboardingSkin.artworkCorner, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: OnboardingSkin.artworkCorner, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: 18) {
                    OnboardingFeatureBullet(icon: "tray.and.arrow.down.fill", text: "自动弹出，随手收集")
                    OnboardingFeatureBullet(icon: "bolt.fill", text: "快速压缩/解压")
                    OnboardingFeatureBullet(icon: "eye.fill", text: "轻松预览")
                    Text("部分功能需要 ProZip Pro")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 160, alignment: .leading)

                Spacer(minLength: 0)
            }
            .padding(.leading, 9)

            Spacer(minLength: 10)

            OnboardingToggleCard(
                title: "启用文件盒并显示菜单栏图标",
                subtitle: "轻巧待命，需要时再展开",
                isOn: $preferences.boxEnabled
            )
        }
    }

    // MARK: Step 3 · 关联文件格式

    private var stepFileAssociations: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 0) {
                onboardingPageTitle("关联文件格式")

                Text("不确定应该选哪些？用推荐设置即可")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)

                OnboardingVioletPillButton(title: "使用推荐设置", icon: "checkmark.circle") {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        associatedFormats.formUnion(FileAssociationGroup.provisionalRecommendedIDs.intersection(OnboardingArchiveFormat.recommendedIDs))
                    }
                }
                .padding(.top, 18)
            }
            .frame(width: 268, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                VStack(spacing: 0) {
                    ForEach(Array(OnboardingArchiveFormat.recommended.enumerated()), id: \.element.id) { index, format in
                        OnboardingFormatRow(
                            name: format.name,
                            extensions: format.extensions,
                            isOn: Binding(
                                get: { associatedFormats.contains(format.id) },
                                set: { isOn in
                                    if isOn {
                                        associatedFormats.insert(format.id)
                                    } else {
                                        associatedFormats.remove(format.id)
                                    }
                                }
                            )
                        )

                        if index < OnboardingArchiveFormat.recommended.count - 1 {
                            Rectangle()
                                .fill(OnboardingSkin.hairline)
                                .frame(height: 1)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(width: 368, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(OnboardingSkin.pageFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(OnboardingSkin.hairline, lineWidth: 1)
                )

                Text("以后可在设置中调整；PKG 仍由系统安装器打开。")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let associationError {
                    Text(associationError).font(.system(size: 11)).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: 368, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .disabled(isApplyingAssociations || !associationChoicesLoaded)
        .task {
            guard !associationChoicesLoaded else { return }
            isApplyingAssociations = true
            defer { isApplyingAssociations = false }
            do {
                try await preferences.refreshFileAssociations()
                let statuses = preferences.fileAssociationStatuses
                associatedFormats = Set(OnboardingArchiveFormat.recommendedIDs.filter { statuses[$0]?.isFullyAssociated == true })
                initialAssociationGroups = associatedFormats
                associationChoicesLoaded = true
                associationError = nil
            } catch { associationError = error.localizedDescription }
        }
    }

    // MARK: Step 4 · 开启访达菜单项

    private var stepFinderMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 24) {
                OnboardingFinderContextMenuMock()
                    .frame(width: 376, height: 330)

                VStack(alignment: .leading, spacing: 0) {
                    onboardingPageTitle("开启访达菜单项")

                    Text("在右键菜单中快速调用 ProZip")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)

                    OnboardingVioletPillButton(title: "打开系统设置", icon: "gearshape.fill") {
                        openFinderExtensionSettings()
                    }
                    .padding(.top, 16)

                    VStack(alignment: .leading, spacing: 12) {
                        OnboardingNumberedStep(index: 1, text: "点击“打开系统设置”按钮")
                        OnboardingNumberedStep(index: 2, text: "在弹出的页面中开启“文件提供程序”")
                    }
                    .padding(.top, 18)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 12)

            OnboardingToggleCard(
                title: "在移动存储中开启右键菜单",
                subtitle: "为外接硬盘、U 盘等移动存储中的文件提供访达右键菜单",
                isOn: $preferences.monitorsExternalVolumes
            )
            .frame(width: 376)
        }
    }

    // MARK: Step 5 · 让 ProZip 能够顺畅访问你的文件

    private var stepFileAccess: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            onboardingPageTitle("让 ProZip 能够顺畅访问你的文件")

            Text("开启完全磁盘访问权限，以便 ProZip 能从更多位置获取文件，例如微信")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            VStack(alignment: .leading, spacing: 14) {
                OnboardingNumberedStep(index: 1, text: "点击右下角的“打开设置”按钮")
                OnboardingNumberedStep(index: 2, text: "将引导栏里的 ProZip 图标拖到应用列表，也可以点“＋”添加。")
                OnboardingNumberedStep(index: 3, text: "打开 ProZip 的开关；如果系统要求重新打开，流程会从这一页继续。")
            }
            .padding(.top, 20)

            Text("这是可选设置，普通压缩包的打开与解压可以直接使用。")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 20)

            Spacer(minLength: 0)
        }
    }

    // MARK: Step 6 · ProZip Pro

    private var stepProTeaser: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("ProZip")
                    .font(.system(size: 34, weight: .bold))
                Text("Pro")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(OnboardingSkin.violet)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)

            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 0) {
                    proCapabilityCell(
                        icon: "bolt.fill",
                        heading: "全部 Flow 功能",
                        detail: "安装应用与字体，或将文件交给其他应用，一步接上后续操作。"
                    )
                    proColumnDivider
                    proCapabilityCell(
                        icon: "magnifyingglass",
                        heading: "文件搜索",
                        detail: "按名称或路径查找文件，无需逐层翻找。"
                    )
                    proColumnDivider
                    proCapabilityCell(
                        icon: "eye.fill",
                        heading: "悬浮预览",
                        detail: "鼠标悬停即可查看图片与文档，不必逐个打开。"
                    )
                }
                .frame(height: 108)

                Rectangle()
                    .fill(OnboardingSkin.hairline)
                    .frame(height: 1)

                HStack(alignment: .top, spacing: 0) {
                    proCapabilityCell(
                        icon: "slider.horizontal.3",
                        heading: "更多压缩选项",
                        detail: "按用途压缩，使用加密、分卷与更多格式。"
                    )
                    proColumnDivider
                    proCapabilityCell(
                        icon: "square.and.pencil",
                        heading: "编辑已有压缩包",
                        detail: "添加、删除、替换、重命名内部文件，以及保存该修改。"
                    )
                    proColumnDivider
                    proCapabilityCell(
                        icon: "archivebox",
                        heading: "完整的文件盒功能",
                        detail: "快速压缩、解压、打开压缩包或快捷分享。"
                    )
                }
                .frame(height: 108)
            }
            .padding(.top, 24)

            Spacer(minLength: 12)

            Button {
                goTo(FirstLaunchOnboardingView.lastPage)
            } label: {
                Text("全部功能已解锁 · 100% 开源免费")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 30)
                    .frame(height: 52)
                    .background(Capsule().fill(OnboardingSkin.violet))
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Step 7 · 一切就绪

    private var stepCompletion: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            ZStack {
                Circle()
                    .strokeBorder(OnboardingSkin.violet, lineWidth: 3)
                    .frame(width: 64, height: 64)
                Image(systemName: "checkmark")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(OnboardingSkin.violet)
            }

            onboardingPageTitle("一切就绪")
                .padding(.top, 24)

            OnboardingToggleCard(
                title: "开机自动启动 ProZip",
                subtitle: nil,
                isOn: Binding(
                    get: { preferences.launchAtLogin },
                    set: { enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                            preferences.launchAtLogin = enabled
                        } catch {
                            preferences.launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                )
            )
            .frame(width: 320)
            .padding(.top, 26)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Footer navigation (back · 7 dots · primary action)

    private var navFooter: some View {
        ZStack {
            OnboardingDotsIndicator(count: FirstLaunchOnboardingView.dotCount, current: currentPage) { page in
                goTo(page)
            }

            HStack(spacing: 12) {
                Button {
                    goTo(currentPage - 1)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text("返回")
                            .font(.system(size: 13))
                    }
                    .foregroundStyle(.primary)
                    .frame(width: 88, height: 32, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(ProZipPressScaleStyle(hoverScale: 1.02, pressedScale: 0.97))

                Spacer(minLength: 0)

                trailingAction
            }
        }
        .padding(.horizontal, OnboardingSkin.horizontalPadding)
        .frame(maxWidth: .infinity)
        .frame(height: OnboardingSkin.footerHeight)
    }

    @ViewBuilder
    private var trailingAction: some View {
        if currentPage >= FirstLaunchOnboardingView.lastPage {
            OnboardingCapsuleButton(title: "开始使用") {
                finish()
            }
        } else if currentPage == 3 {
            OnboardingCapsuleButton(title: isApplyingAssociations ? "正在应用…" : "应用所选并继续") {
                applyAssociationChoices()
            }
            .disabled(isApplyingAssociations || !associationChoicesLoaded)
        } else if currentPage == 5 {
            HStack(spacing: 10) {
                Button {
                    goTo(currentPage + 1)
                } label: {
                    Text("跳过")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                OnboardingCapsuleButton(title: "打开设置") {
                    openFullDiskAccessSettings()
                }
            }
        } else {
            OnboardingCapsuleButton(title: "下一步") {
                goTo(currentPage + 1)
            }
        }
    }

    // MARK: Shared page pieces

    private func onboardingPageTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 34, weight: .bold))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func proCapabilityCell(icon: String, heading: String, detail: String) -> some View {
        let caption: Text = Text(heading).font(.system(size: 14, weight: .bold))
            + Text("  " + detail).font(.system(size: 14)).foregroundColor(.secondary)

        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(ProZipTheme.accent)
                .frame(width: 20, alignment: .center)
                .padding(.top, 1)

            caption
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var proColumnDivider: some View {
        Rectangle()
            .fill(OnboardingSkin.hairline)
            .frame(width: 1)
            .frame(maxHeight: .infinity)
    }

    // MARK: State + system integration

    private func applyAssociationChoices() {
        guard !isApplyingAssociations else { return }
        var changes: [String: Bool] = [:]
        for id in associatedFormats.subtracting(initialAssociationGroups) { changes[id] = true }
        for id in initialAssociationGroups.subtracting(associatedFormats) { changes[id] = false }
        isApplyingAssociations = true
        associationError = nil
        Task { @MainActor in
            defer { isApplyingAssociations = false }
            do {
                if !changes.isEmpty { try await preferences.applyFileAssociationChanges(changes) }
                initialAssociationGroups = associatedFormats
                goTo(4)
            } catch { associationError = error.localizedDescription }
        }
    }

    private func goTo(_ page: Int) {
        let clamped = min(max(page, 0), FirstLaunchOnboardingView.lastPage)
        guard clamped != currentPage else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
            currentPage = clamped
        }
    }

    private func finish() {
        preferences.onboardingCompleted = true
        ProZipAppViewModel.shared.isOnboardingPresented = false
        if dismissesSheetOnFinish {
            dismiss()
        }
    }

    private func openFinderExtensionSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Onboarding Subviews (private to the onboarding flow)

private struct OnboardingBrandHeader: View {
    var body: some View {
        HStack(spacing: 8) {
            ProZipBrandIcon(size: 28, showAppSquircle: true)
            Text("ProZip")
                .font(.system(size: 16, weight: .bold))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, OnboardingSkin.horizontalPadding)
        .padding(.top, 14)
        .padding(.bottom, 4)
        .frame(height: OnboardingSkin.headerHeight)
    }
}

/// Light grey rounded switch card: 16pt semibold title + 13pt caption, trailing switch.
private struct OnboardingToggleCard: View {
    var title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)

            OnboardingSwitch(isOn: $isOn)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(OnboardingSkin.cardFill)
        )
    }
}

private struct OnboardingSwitch: View {
    @Binding var isOn: Bool
    var compact: Bool = false

    private var trackWidth: CGFloat { compact ? 44 : 54 }
    private var trackHeight: CGFloat { compact ? 26 : 32 }
    private var knobSize: CGFloat { compact ? 20 : 26 }

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                isOn.toggle()
            }
        } label: {
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(isOn ? OnboardingSkin.violet : OnboardingSkin.inactiveDot)

                Circle()
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.16), radius: 1.5, x: 0, y: 0.6)
                    .frame(width: knobSize, height: knobSize)
                    .offset(x: isOn ? (trackWidth - knobSize - 3) : 3)
            }
            .frame(width: trackWidth, height: trackHeight)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
    }
}

/// Bundled onboarding artwork, rounded 12 with a hairline rim and a grey fallback plate.
private struct OnboardingArtwork: View {
    var imageName: String
    var fallbackSymbol: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: OnboardingSkin.artworkCorner, style: .continuous)
                .fill(Color.primary.opacity(0.05))

            if let nsImage = ProZipResourceLoader.image(named: imageName) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: fallbackSymbol)
                    .font(.system(size: 54))
                    .foregroundStyle(ProZipTheme.accent)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: OnboardingSkin.artworkCorner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: OnboardingSkin.artworkCorner, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct OnboardingFeatureBullet: View {
    var icon: String
    var text: String

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ProZipTheme.accent)
                .frame(width: 18)

            Text(text)
                .font(.system(size: 14, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct OnboardingFormatRow: View {
    var name: String
    var extensions: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.system(size: 16, weight: .semibold))
                Text(extensions)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            OnboardingSwitch(isOn: $isOn, compact: true)
        }
        .frame(height: 46)
    }
}

private struct OnboardingNumberedStep: View {
    var index: Int
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(OnboardingSkin.violet)
                .frame(width: 24, height: 24)
                .background(Circle().fill(OnboardingSkin.violetSoft))

            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(.primary.opacity(0.88))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 3)

            Spacer(minLength: 0)
        }
    }
}

private struct OnboardingVioletPillButton: View {
    var title: String
    var icon: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(height: 40)
            .background(
                Capsule().fill(
                    LinearGradient(
                        colors: [OnboardingSkin.violet, OnboardingSkin.violetDeep],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            )
        }
        .buttonStyle(.plain)
    }
}

/// 112 × 36 accent capsule used by the footer (下一步 / 开始使用 / 打开设置).
private struct OnboardingCapsuleButton: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 112, height: 36)
                .background(Capsule().fill(ProZipTheme.accent))
        }
        .buttonStyle(ProZipPressScaleStyle(hoverScale: 1.02, pressedScale: 0.97))
        .keyboardShortcut(.defaultAction)
    }
}

private struct OnboardingDotsIndicator: View {
    var count: Int
    var current: Int
    var onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...count, id: \.self) { index in
                Button {
                    onSelect(index)
                } label: {
                    Circle()
                        .fill(index == current ? ProZipTheme.accent : OnboardingSkin.inactiveDot)
                        .frame(width: 8, height: 8)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Archive formats listed on the association page.
private struct OnboardingArchiveFormat: Identifiable {
    let id: String
    let name: String
    let extensions: String

    static let recommended: [OnboardingArchiveFormat] = [
        OnboardingArchiveFormat(id: "zip", name: "ZIP", extensions: ".zip   .zipx   .z01–.z99"),
        OnboardingArchiveFormat(id: "7z", name: "7Z", extensions: ".7z"),
        OnboardingArchiveFormat(id: "split", name: "分卷压缩包", extensions: ".001–.999"),
        OnboardingArchiveFormat(id: "rar", name: "RAR", extensions: ".rar   .r00–.r99"),
        OnboardingArchiveFormat(id: "cbr", name: "Comic RAR", extensions: ".cbr"),
        OnboardingArchiveFormat(id: "tar", name: "TAR", extensions: ".tar   .tgz   .tbz   .tbz2   .txz"),
        OnboardingArchiveFormat(id: "gzip", name: "Gzip / TAR.GZ", extensions: ".gz   .gzip"),
        OnboardingArchiveFormat(id: "bzip2", name: "Bzip2 / TAR.BZ2", extensions: ".bz2   .bzip2")
    ]

    static let recommendedIDs = Set(recommended.map(\.id))
}

// MARK: - 2. ReleaseOverviewWindowView (更新概览 ReleaseOverviewWindow · W-07)

public struct ReleaseOverviewWindowView: View {
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        ArcZipDialogSurface(width: 620, height: 540) {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    ProZipBrandIcon(size: 48, showAppSquircle: true)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text("ProZip 1.2.3 更新概览")
                                .font(.system(size: 18, weight: .bold))
                            Text("Build 366 · Open Source")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(ProZipTheme.darkInk)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(ProZipTheme.accentBright, in: Capsule())
                        }
                        Text("清洁室架构重构 · 全功能免费解锁 · 4 大引擎与 SQLite 双表极速索引")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        releaseHighlightCard(
                            icon: "macwindow.on.rectangle",
                            title: "双模式工作区与 ProZip Mini 窗口",
                            description: "支持 1040×740 三视图完整工作台与 560×422 磨砂 Mini 窗口一键切换（⌥⌘M），内置黄绿立体口袋检查器与彩色控制圆钮。",
                            imageName: nil
                        )

                        releaseHighlightCard(
                            icon: "point.bottomleft.forward.to.point.topright.scurvepath",
                            title: "Flow 智能动作流全解锁",
                            description: "8 步上下文决策引擎自动推荐「安装到应用程序」、「安装字体」、「运行安装器」或 32 种白名单格式安全直开，带环轨高光动效。",
                            imageName: nil
                        )

                        releaseHighlightCard(
                            icon: "tray.full.fill",
                            title: "菜单栏暂存盒闪电批处理",
                            description: "支持拖放收集散落文件、内联展开浏览目录与归档内容（ShelfFolderBrowser），以及直接压缩、配置压缩、原位解压、合并解压 4 大快捷动作。",
                            imageName: nil
                        )

                        releaseHighlightCard(
                            icon: "cylinder.split.1x2.fill",
                            title: "SQLite 双表极速索引与四引擎架构",
                            description: "L1 NativeZipEngine 零拷贝直读 + L2 7-Zip LZMA2 + L3 libarchive + L4 hdiutil 磁盘映像，配合 archive_publications 事务级回滚保护。",
                            imageName: nil
                        )

                        releaseHighlightCard(
                            icon: "key.fill",
                            title: "AES-GCM 密码本自动匹配解密",
                            description: "支持按最近使用顺序与分组自动尝试解密、创建压缩包一键填充预设密码，以及主密码 HKDF 保护与 Touch ID 解锁。",
                            imageName: nil
                        )
                    }
                    .padding(20)
                }

                Divider()

                HStack {
                    Text("感谢使用开源版 ProZip · 无任何商业门控或联网追踪")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    Spacer()
                    ArcZipDialogButton("知道了", role: .primary, size: .regular) {
                        UserDefaults.standard.set("1.2.3", forKey: "releaseOverview.presentedVersion.v1.stable")
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
        }
    }

    private func releaseHighlightCard(icon: String, title: String, description: String, imageName: String?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(ProZipTheme.accentSoft)
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ProZipTheme.accent)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(.primary)

                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let imageName, let nsImg = ProZipResourceLoader.image(named: imageName) {
                    Image(nsImage: nsImg)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 110)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
                )
        )
    }
}

// MARK: - 3. AboutProZipView & CheckForUpdatesDialogView (W-08)

public struct AboutProZipView: View {
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        ArcZipDialogSurface(width: 420) {
            VStack(spacing: 16) {
                ProZipBrandIcon(size: 76, showAppSquircle: true)
                    .padding(.top, 8)

                VStack(spacing: 4) {
                    Text("ProZip")
                        .font(.system(size: 22, weight: .bold))
                    Text("版本 1.2.3 (Build 366) · Open Source Edition")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Text("基于清洁室规范实现的 macOS 高性能解压缩与归档工作台。\n内置 NativeZipEngine、7-Zip、libarchive 与 hdiutil 四层引擎。")
                    .font(.system(size: 12))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)

                HStack(spacing: 10) {
                    ArcZipSettingsNativeGlassButton("更新概览…", icon: "sparkles") {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            ProZipAppViewModel.shared.isReleaseOverviewPresented = true
                        }
                    }
                    ArcZipSettingsNativeGlassButton("检查更新…", icon: "arrow.triangle.2.circlepath") {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            ProZipAppViewModel.shared.isCheckForUpdatesPresented = true
                        }
                    }
                    ArcZipSettingsNativeGlassButton("弹窗全览…", icon: "macwindow.on.rectangle") {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            ProZipAppViewModel.shared.isDialogGalleryPresented = true
                        }
                    }
                }

                Divider()

                HStack {
                    Text("MIT / GPL v3 开源许可 · 全功能永久解锁")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    ArcZipDialogButton("关闭", role: .primary, size: .compact) {
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(22)
        }
    }
}

public struct CheckForUpdatesDialogView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("updates.autoCheck.v1") private var autoCheckUpdates: Bool = true
    @State private var isChecking: Bool = false

    public init() {}

    public var body: some View {
        ArcZipDialogSurface(width: 420) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    ProZipBrandIcon(size: 52, showAppSquircle: true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(isChecking ? "正在检查更新…" : "ProZip 1.2.3 已是最新版本")
                            .font(.system(size: 15, weight: .bold))
                        Text("当前安装的 ProZip 1.2.3 (Build 366) Open Source 是目前已发布的最新版本。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if isChecking {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(ProZipTheme.accent)
                }

                Toggle("自动检查更新（每天检查一次，安装前征求确认）", isOn: $autoCheckUpdates)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
                    .tint(ProZipTheme.accent)

                Divider()

                HStack {
                    ArcZipSettingsNativeGlassButton("查看更新概览…", icon: "doc.richtext") {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            ProZipAppViewModel.shared.isReleaseOverviewPresented = true
                        }
                    }

                    Spacer()

                    ArcZipDialogButton("重新检查", role: .secondary, size: .regular) {
                        isChecking = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                            isChecking = false
                        }
                    }

                    ArcZipDialogButton("好", role: .primary, size: .regular) {
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(22)
        }
    }
}

// MARK: - 4. PasswordPromptSheetView (D-02 ArcZipNativePasswordAlertPresentation)

public struct PasswordPromptSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject public var appViewModel = ProZipAppViewModel.shared

    @State private var password: String = ""
    @State private var isRevealed: Bool = ProZipPreferences.shared.revealsPasswordByDefault
    @State private var showNonASCIINotice: Bool = false
    @State private var errorFeedback: String?
    @FocusState private var isPasswordFieldFocused: Bool

    public init() {}

    private var hasNonASCII: Bool {
        password.unicodeScalars.contains { !$0.isASCII }
    }

    private func evaluateInputSourceNotice() {
        let suppressed = UserDefaults.standard.bool(forKey: "archivePassword.inputNoticeSuppressed.v1")
        guard !suppressed, !isRevealed else {
            showNonASCIINotice = false
            return
        }
        if ProZipKeyboardInputMonitor.isCurrentInputSourceNonASCII() {
            showNonASCIINotice = true
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProZipBrandIcon(size: 68, showAppSquircle: true)

            Text("解压加密文件")
                .font(.system(size: 15, weight: .bold))
                .padding(.top, 15)

            Text(appViewModel.passwordPromptTitle.isEmpty ? "加密压缩包" : appViewModel.passwordPromptTitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary.opacity(0.88))
                .padding(.top, 8)

            Text(appViewModel.passwordPromptMessage.isEmpty ? "此压缩包受密码保护，输入密码以继续。" : appViewModel.passwordPromptMessage)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.top, 3)

            HStack(spacing: 6) {
                Group {
                    if isRevealed {
                        TextField("密码", text: $password)
                            .focused($isPasswordFieldFocused)
                    } else {
                        SecureField("密码", text: $password)
                            .focused($isPasswordFieldFocused)
                    }
                }
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .onChange(of: password) { _, newVal in
                    errorFeedback = nil
                    let suppressed = UserDefaults.standard.bool(forKey: "archivePassword.inputNoticeSuppressed.v1")
                    if !suppressed && !isRevealed && newVal.unicodeScalars.contains(where: { !$0.isASCII }) {
                        showNonASCIINotice = true
                    }
                }
                .onChange(of: isPasswordFieldFocused) { _, focused in
                    if focused {
                        evaluateInputSourceNotice()
                    }
                }
                .onChange(of: isRevealed) { _, revealed in
                    if revealed {
                        showNonASCIINotice = false
                    } else {
                        evaluateInputSourceNotice()
                    }
                }

                Button {
                    isRevealed.toggle()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showNonASCIINotice, arrowEdge: .top) {
                    ArcZipPasswordInputNoticePopover(
                        format: .sevenZip,
                        onRevealPassword: {
                            isRevealed = true
                            showNonASCIINotice = false
                        },
                        onDismiss: {
                            showNonASCIINotice = false
                        }
                    )
                }
                .help(isRevealed ? "隐藏密码" : "显示密码")
            }
            .padding(.horizontal, 10)
            .frame(width: 210, height: 40)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(NSColor.textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(errorFeedback != nil ? Color.red : ProZipTheme.accent, lineWidth: 1.5)
                    )
            )
            .padding(.top, 10)
            .onAppear {
                isPasswordFieldFocused = true
                evaluateInputSourceNotice()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSTextInputContext.keyboardSelectionDidChangeNotification)) { _ in
                evaluateInputSourceNotice()
            }

            if let err = errorFeedback {
                Text(err)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.red)
                    .padding(.top, 5)
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Button {
                    appViewModel.submitPassword(nil)
                    dismiss()
                } label: {
                    Text("取消")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 112, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                        )
                }
                .buttonStyle(ProZipPressScaleStyle(hoverScale: 1.02, pressedScale: 0.97))
                .keyboardShortcut(.cancelAction)

                Button {
                    let entered = password
                    appViewModel.submitPassword(entered)
                    dismiss()
                } label: {
                    Text("继续")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(password.isEmpty ? Color.secondary.opacity(0.55) : Color.primary)
                        .frame(width: 112, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(password.isEmpty ? Color.primary.opacity(0.04) : ProZipTheme.accent.opacity(0.20))
                        )
                }
                .buttonStyle(ProZipPressScaleStyle(hoverScale: 1.02, pressedScale: 0.97))
                .disabled(password.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
        .padding(16)
        .frame(width: 260, height: 275)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
    }

}

// MARK: - 5. PasswordBookProtectionDialogView (D-05 ArcZipPasswordBookProtectionDialog)

public struct PasswordBookProtectionDialogView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject public var passwordBook = PasswordBook.shared
    @State private var masterPassword: String = ""
    @State private var confirmPassword: String = ""
    @State private var enableTouchID: Bool = false
    @State private var errorMessage: String?
    @State private var isConfirmingReset: Bool = false

    public init() {}

    public var body: some View {
        ArcZipDialogSurface(width: 430) {
            VStack(alignment: .leading, spacing: 14) {
                ProZipModalHeader(
                    title: passwordBook.isLocked ? "解锁密码本" : (passwordBook.hasMasterPassword ? "管理密码本主密码保护" : "设置密码本主密码保护"),
                    subtitle: "为密码本设置独立主密码，解锁后可查看和使用保存的密码。",
                    icon: "lock.shield.fill",
                    onClose: { dismiss() }
                )

                Divider()

                if passwordBook.isLocked {
                    if passwordBook.hasMasterPassword {
                    SecureField("输入密码本主密码", text: $masterPassword)
                        .textFieldStyle(.roundedBorder)

                    if passwordBook.canUseBiometrics() {
                        ArcZipSettingsNativeGlassButton("使用 Touch ID 生物识别快速解锁", icon: "touchid") {
                            Task {
                                if await passwordBook.authenticateWithBiometrics() { dismiss() }
                                else { errorMessage = passwordBook.lastError ?? "快捷解锁未完成，请使用主密码。" }
                            }
                        }
                    }
                    } else {
                        Text(passwordBook.lastError ?? "无法读取密码本，原文件已保留。请检查钥匙串访问权限，或确认后重置密码本。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    SecureField("设置新主密码", text: $masterPassword)
                        .textFieldStyle(.roundedBorder)

                    SecureField("再次输入主密码确认", text: $confirmPassword)
                        .textFieldStyle(.roundedBorder)

                    Toggle("允许使用 Touch ID 快速解锁密码本", isOn: $enableTouchID)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))
                        .tint(ProZipTheme.accent)
                }

                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .padding(.top, 2)
                    Text("请牢记此密码；忘记主密码且无法使用快捷解锁时，只能重置并清空密码本。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                if let err = errorMessage {
                    Text(err)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.red)
                }

                Divider()

                HStack {
                    if passwordBook.hasMasterPassword || passwordBook.isLocked {
                        ArcZipDialogButton(isConfirmingReset ? "确认清空并重置" : "重置密码本…", role: .destructive, size: .compact) {
                            if isConfirmingReset {
                                passwordBook.resetAndClearAll()
                                if let error = passwordBook.lastError { errorMessage = error }
                                else { dismiss() }
                            } else {
                                isConfirmingReset = true
                            }
                        }
                    }

                    Spacer()

                    ArcZipDialogButton("取消", role: .secondary, size: .regular) {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)

                    if passwordBook.isLocked {
                        if passwordBook.hasMasterPassword {
                        ArcZipDialogButton("解锁密码本", role: .primary, size: .regular) {
                            if passwordBook.unlock(withMasterPassword: masterPassword) {
                                dismiss()
                            } else {
                                errorMessage = passwordBook.lastError ?? "主密码错误，请重试。"
                            }
                        }
                        .keyboardShortcut(.defaultAction)
                        }
                    } else {
                        if passwordBook.hasMasterPassword {
                            ArcZipDialogButton("关闭保护", role: .secondary, size: .regular) {
                                passwordBook.removeMasterPassword()
                                if let error = passwordBook.lastError { errorMessage = error }
                                else { dismiss() }
                            }
                        }

                        ArcZipDialogButton("开启保护", role: .primary, size: .regular) {
                            guard !masterPassword.isEmpty else {
                                errorMessage = "请设置主密码。"
                                return
                            }
                            guard masterPassword == confirmPassword else {
                                errorMessage = "两次输入的密码不一致。"
                                return
                            }
                            passwordBook.setMasterPassword(masterPassword, allowQuickUnlock: enableTouchID)
                            if let error = passwordBook.lastError { errorMessage = error }
                            else { dismiss() }
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                }
            }
            .padding(22)
        }
        .onAppear { enableTouchID = passwordBook.isQuickUnlockEnabled }
    }
}

// MARK: - 6. RenameEntrySheetView (重命名项目)

public struct RenameEntrySheetView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject public var appViewModel = ProZipAppViewModel.shared
    @State private var errorMessage: String?

    public init() {}

    public var body: some View {
        ArcZipDialogSurface(width: 360) {
            VStack(alignment: .leading, spacing: 14) {
                ProZipModalHeader(
                    title: "重命名项目",
                    subtitle: "仅更改归档内部条目名称，保存后生效",
                    icon: "pencil.line"
                )

                TextField("输入新名称", text: $appViewModel.renameInput)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: appViewModel.renameInput) { _, _ in
                        errorMessage = nil
                    }

                if let err = errorMessage {
                    Text(err)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.red)
                }

                HStack {
                    ArcZipDialogButton("取消", role: .secondary, size: .regular) {
                        appViewModel.isRenameSheetPresented = false
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)

                    Spacer()

                    ArcZipDialogButton("确定", role: .primary, size: .regular) {
                        do {
                            try appViewModel.commitEntryRename()
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
    }
}

// MARK: - 7. ConflictResolutionDialogView (D-06 同名文件冲突处理)

public struct ConflictResolutionDialogView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject public var appViewModel = ProZipAppViewModel.shared
    @State private var applyToAll: Bool = true
    public var onResolve: ((ConflictResolution, Bool) -> Void)?

    public init(onResolve: ((ConflictResolution, Bool) -> Void)? = nil) {
        self.onResolve = onResolve
    }

    public var body: some View {
        let item = appViewModel.activeConflictItem
        VStack(alignment: .leading, spacing: 0) {
            ProZipBrandIcon(size: 68, showAppSquircle: true)

            Text("替换现有压缩包？")
                .font(.system(size: 15, weight: .bold))
                .padding(.top, 16)

            Text(item.fileName)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .padding(.top, 10)

            Text("替换会覆盖现有版本；同时保留会以新名称创建。")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            Spacer(minLength: 0)

            VStack(spacing: 8) {
                Button {
                    onResolve?(.keepBoth, true)
                    appViewModel.resolvePendingCreationConflict(.keepBoth)
                    dismiss()
                } label: {
                    Text("同时保留")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 230, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.07))
                        )
                }
                .buttonStyle(ProZipPressScaleStyle(hoverScale: 1.01, pressedScale: 0.97))

                Button {
                    onResolve?(.replace, true)
                    appViewModel.resolvePendingCreationConflict(.replace)
                    dismiss()
                } label: {
                    Text("替换")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(red: 0.95, green: 0.32, blue: 0.31))
                        .frame(width: 230, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.07))
                        )
                }
                .buttonStyle(ProZipPressScaleStyle(hoverScale: 1.01, pressedScale: 0.97))
                .keyboardShortcut(.defaultAction)

                Button {
                    onResolve?(.skip, false)
                    appViewModel.resolvePendingCreationConflict(.skip)
                    dismiss()
                } label: {
                    Text("取消")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 230, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.07))
                        )
                }
                .buttonStyle(ProZipPressScaleStyle(hoverScale: 1.01, pressedScale: 0.97))
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 20)
        .frame(width: 260, height: 325)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
    }

    private func conflictVersionRow(badge: String, fileName: String, sizeBytes: Int64, modifiedAt: Date, isIncoming: Bool) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: ProZipResourceLoader.systemFileIcon(for: fileName))
                .resizable()
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(badge)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(isIncoming ? ProZipTheme.accentDeep : .secondary)
                    if isIncoming {
                        Text("较新")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(ProZipTheme.darkInk)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(ProZipTheme.accentBright, in: Capsule())
                    }
                }
                Text("\(ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)) · 修改于 \(modifiedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isIncoming ? ProZipTheme.accentSoft.opacity(0.6) : Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(isIncoming ? ProZipTheme.accent.opacity(0.45) : Color.primary.opacity(0.07), lineWidth: 1)
                )
        )
    }
}

// MARK: - 8. SaveChangesConfirmationDialogView (D-07 保存对压缩包的更改？)

public struct SaveChangesConfirmationDialogView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject public var appViewModel = ProZipAppViewModel.shared

    public init() {}

    public var body: some View {
        let isConflict = appViewModel.saveChangesIsSourceModifiedConflict
        ArcZipDialogSurface(width: 450) {
            VStack(alignment: .leading, spacing: 14) {
                ProZipModalHeader(
                    title: isConflict ? "源压缩包在编辑期间已发生变化" : "是否保存对「\(appViewModel.saveChangesArchiveName)」的更改？",
                    subtitle: isConflict
                        ? "原压缩包未被覆盖。你可以尝试将当前草稿更改合并到最新文件中，或重新载入最新文件。"
                        : "如果不保存，你在当前会话中添加、删除或重命名的归档草稿更改将会丢失。",
                    icon: isConflict ? "exclamationmark.arrow.triangle.2.circlepath" : "externaldrive.badge.checkmark"
                )

                Divider()

                HStack(spacing: 10) {
                    if isConflict {
                        ArcZipDialogButton("放弃更改并重载", role: .destructive, size: .regular) {
                            appViewModel.discardSaveChanges(reload: true)
                            dismiss()
                        }
                        Spacer()
                        ArcZipDialogButton("取消", role: .secondary, size: .regular) {
                            appViewModel.cancelSaveChanges()
                            dismiss()
                        }
                        .keyboardShortcut(.cancelAction)
                        ArcZipDialogButton("合并更改并保存", role: .primary, size: .regular) {
                            appViewModel.confirmSaveChanges(merge: true)
                            dismiss()
                        }
                        .keyboardShortcut(.defaultAction)
                    } else {
                        ArcZipDialogButton("不保存", role: .destructive, size: .regular) {
                            appViewModel.discardSaveChanges()
                            dismiss()
                        }
                        Spacer()
                        ArcZipDialogButton("取消", role: .secondary, size: .regular) {
                            appViewModel.cancelSaveChanges()
                            dismiss()
                        }
                        .keyboardShortcut(.cancelAction)
                        ArcZipDialogButton("保存更改", role: .primary, size: .regular) {
                            appViewModel.confirmSaveChanges()
                            dismiss()
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                }
            }
            .padding(22)
        }
    }
}

// MARK: - 9. DeleteConfirmationDialogView (确认删除所选项目？)

public struct DeleteConfirmationDialogView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject public var appViewModel = ProZipAppViewModel.shared

    public init() {}

    public var body: some View {
        ArcZipDialogSurface(width: 410) {
            VStack(alignment: .leading, spacing: 14) {
                ProZipModalHeader(
                    title: "确认从压缩包中删除所选项目？",
                    subtitle: "删除操作将记录在当前编辑草稿中，点击「保存」并完成事务提交前不会改动原压缩包。",
                    icon: "trash.fill"
                )

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(appViewModel.deleteTargetNames, id: \.self) { name in
                        HStack(spacing: 6) {
                            Image(systemName: name.hasSuffix("/") ? "folder.fill" : "doc.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text(name)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Divider()

                HStack {
                    ArcZipDialogButton("取消", role: .secondary, size: .regular) {
                        appViewModel.isDeleteConfirmationPresented = false
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)

                    Spacer()

                    ArcZipDialogButton("删除", icon: "trash", role: .destructive, size: .regular) {
                        appViewModel.activeSession?.removeSelectedDraftEntries()
                        appViewModel.isDeleteConfirmationPresented = false
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(22)
        }
    }
}

// MARK: - 10. TrashConfirmationDialogView (D-08 解压完成后将原压缩包移到废纸篓？)

public struct TrashConfirmationDialogView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject public var appViewModel = ProZipAppViewModel.shared

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            ProZipBrandIcon(size: 68, showAppSquircle: true)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 16)

            Text("解压完成")
                .font(.system(size: 15, weight: .bold))
                .padding(.top, 14)

            Text("是否将原压缩包移入废纸篓？")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.top, 8)
                .multilineTextAlignment(.center)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Button {
                    appViewModel.resolveExtractionCompletion(moveToTrash: false)
                    dismiss()
                } label: {
                    Text("保留压缩包")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 112, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                        )
                }
                .buttonStyle(ProZipPressScaleStyle(hoverScale: 1.02, pressedScale: 0.97))
                .keyboardShortcut(.cancelAction)

                Button {
                    appViewModel.resolveExtractionCompletion(moveToTrash: true)
                    dismiss()
                } label: {
                    Text("移入废纸篓")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(red: 0.95, green: 0.35, blue: 0.34))
                        .frame(width: 112, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                        )
                }
                .buttonStyle(ProZipPressScaleStyle(hoverScale: 1.02, pressedScale: 0.97))
            }
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 16)
        .frame(width: 260, height: 202)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
    }
}

// MARK: - 11. FilenameRepairDialogView (D-09 ArcZipFilenameRepairDialog)

public struct FilenameRepairDialogView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject public var appViewModel = ProZipAppViewModel.shared

    public init() {}

    public var body: some View {
        ArcZipDialogSurface(width: 560, height: 420) {
            VStack(alignment: .leading, spacing: 12) {
                ProZipModalHeader(
                    title: "修正不兼容的 Windows 文件名",
                    subtitle: "检测到含有 Windows 非法字符 (\\ / : * ? \" < > |)、保留设备名或末尾句点的项目",
                    icon: "wrench.and.screwdriver.fill",
                    onClose: { dismiss() }
                )

                HStack {
                    Label("仅修改压缩包内部的归档路径，磁盘上的源文件保持不变。", systemImage: "checkmark.shield.fill")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(ProZipTheme.accentDeep)

                    Spacer()

                    ArcZipSettingsNativeGlassButton("一键恢复推荐修复名", icon: "wand.and.stars") {
                        for idx in appViewModel.activeFilenameRepairItems.indices {
                            appViewModel.activeFilenameRepairItems[idx].editedName = appViewModel.activeFilenameRepairItems[idx].suggestedName
                        }
                    }
                }

                ScrollView {
                    VStack(spacing: 8) {
                        ForEach($appViewModel.activeFilenameRepairItems) { $item in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(item.originalPath)
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(.orange)
                                    Spacer()
                                    Text(item.issueReason)
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(.secondary)
                                }

                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.turn.down.right")
                                        .font(.system(size: 11))
                                        .foregroundStyle(ProZipTheme.accent)
                                    Text("归档内新名称：")
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(.secondary)
                                    TextField("修复后名称", text: $item.editedName)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 12, design: .monospaced))
                                }
                            }
                            .padding(10)
                            .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }

                Divider()

                HStack {
                    ArcZipDialogButton("取消", role: .secondary, size: .regular) {
                        appViewModel.isFilenameRepairPresented = false
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)

                    Spacer()

                    ArcZipDialogButton("应用修复并继续", icon: "checkmark", role: .primary, size: .regular) {
                        appViewModel.isFilenameRepairPresented = false
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(22)
        }
    }
}

// MARK: - 12. EntryIndexIssueDialogView (D-10 ArcZipEntryIndexIssueDialog)

public struct EntryIndexIssueDialogView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject public var appViewModel = ProZipAppViewModel.shared

    public init() {}

    public var body: some View {
        ArcZipDialogSurface(width: 540, height: 420) {
            VStack(alignment: .leading, spacing: 12) {
                ProZipModalHeader(
                    title: "发现无法安全处理的项目",
                    subtitle: "以下项目包含特殊设备文件、越界符号链接或缺少读取权限。跳过它们即可继续操作。",
                    icon: "exclamationmark.shield.fill",
                    onClose: { dismiss() }
                )

                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(appViewModel.activeEntryIndexIssues) { issue in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: issue.icon)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.orange)
                                    .frame(width: 22)
                                    .padding(.top, 2)

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(issue.path)
                                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        Text(issue.category)
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(.orange)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 1.5)
                                            .background(Color.orange.opacity(0.14), in: Capsule())
                                    }
                                    Text(issue.detail)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                            }
                            .padding(10)
                            .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }

                Divider()

                HStack {
                    ArcZipDialogButton("取消", role: .secondary, size: .regular) {
                        appViewModel.isEntryIndexIssuePresented = false
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)

                    Spacer()

                    ArcZipDialogButton("跳过问题项并继续", icon: "arrow.right.circle.fill", role: .primary, size: .regular) {
                        appViewModel.isEntryIndexIssuePresented = false
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(22)
        }
    }
}

// MARK: - 13. DiskImageLicenseDialogView (D-11 ArcZipDiskImageLicenseDialog)

public struct DiskImageLicenseDialogView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject public var appViewModel = ProZipAppViewModel.shared
    @State private var selectedLanguage: String = "简体中文"

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("磁盘映像使用许可协议")
                    .font(.system(size: 18, weight: .bold))
            }

            Text(appViewModel.diskImageName)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            ScrollView {
                Text(appViewModel.diskImageLicenseText.isEmpty
                     ? """
                       ProZip Test License Agreement

                       This synthetic agreement is only for UI replication testing.
                       You may mount this image locally. No warranty is provided.
                       """
                     : appViewModel.diskImageLicenseText)
                .font(.system(size: 13))
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(NSColor.textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .frame(height: 148)
            .padding(.top, 12)

            Text("你的选择仅用于本次打开；ProZip 不会替你自动接受或保存协议选择。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.top, 10)

            HStack(spacing: 12) {
                Button {
                    appViewModel.isDiskImageLicensePresented = false
                    dismiss()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                        Text("不同意")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(width: 190, height: 40)
                    .background(Capsule().fill(Color(red: 0.92, green: 0.26, blue: 0.23)))
                }
                .buttonStyle(ProZipPressScaleStyle(hoverScale: 1.02, pressedScale: 0.97))
                .keyboardShortcut(.cancelAction)

                Button {
                    appViewModel.acceptDiskImageLicense()
                    dismiss()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                        Text("同意并打开")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(width: 190, height: 40)
                    .background(Capsule().fill(ProZipTheme.accent))
                }
                .buttonStyle(ProZipPressScaleStyle(hoverScale: 1.02, pressedScale: 0.97))
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 14)
        }
        .padding(16)
        .frame(width: 413, height: 305)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
    }
}

// MARK: - 14. SourceAccessAlertDialogView (D-12 ArcZipSourceAccessAlertContent)

public struct SourceAccessAlertDialogView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject public var appViewModel = ProZipAppViewModel.shared

    public init() {}

    public var body: some View {
        ArcZipDialogSurface(width: 460) {
            VStack(alignment: .leading, spacing: 14) {
                ProZipModalHeader(
                    title: "需要文件夹访问授权",
                    subtitle: "ProZip 需要读取来源文件夹中的文件，才能完成浏览、暂存、压缩或解压。",
                    icon: "folder.badge.person.crop"
                )

                HStack(spacing: 10) {
                    Image(nsImage: NSWorkspace.shared.icon(for: .folder))
                        .resizable()
                        .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("受系统隐私保护的来源路径")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                        Text(appViewModel.sourceAccessTargetFolder)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text("这不会更改你的来源文件。若文件位于微信或其他第三方应用的容器目录中，你也可以在「系统设置 → 隐私与安全性 → 完全磁盘访问权限」中启用 ProZip。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                HStack {
                    ArcZipSettingsNativeGlassButton("前往系统隐私设置…", icon: "gearshape") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
                            NSWorkspace.shared.open(url)
                        }
                    }

                    Spacer()

                    ArcZipDialogButton("取消", role: .secondary, size: .regular) {
                        appViewModel.isSourceAccessAlertPresented = false
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)

                    ArcZipDialogButton("授权访问…", icon: "folder.badge.checkmark", role: .primary, size: .regular) {
                        let panel = NSOpenPanel()
                        panel.title = "授权 ProZip 访问文件夹"
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.prompt = "授权访问"
                        _ = panel.runModal()
                        appViewModel.isSourceAccessAlertPresented = false
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(22)
        }
    }
}

// MARK: - 15. ArchiveErrorDetailDialogView (D-13 ArcZipMessageDialog 5-Part Error Dialog)

public struct ArchiveErrorDetailDialogView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject public var appViewModel = ProZipAppViewModel.shared
    @State private var isDetailsExpanded: Bool = true
    @State private var copiedFeedback: Bool = false

    public init() {}

    public var body: some View {
        let err = appViewModel.activeStructuredError
        ArcZipDialogSurface(width: 520) {
            VStack(alignment: .leading, spacing: 12) {
                // Part 1: Title & Failure Summary
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.red.opacity(0.14))
                            .frame(width: 40, height: 40)
                        Image(systemName: "exclamationmark.octagon.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.red)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(err.title)
                            .font(.system(size: 15, weight: .bold))
                        Text(err.summaryReason)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // Part 2 & 3: Source/Affected Item Path + Safety Guarantee ("源压缩包没有被修改")
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 6) {
                        Text("受影响条目：")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                        Text(err.affectedItemPath)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.primary)
                    }

                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(ProZipTheme.accent)
                            .padding(.top, 1)
                        Text(err.recoverySuggestion)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.88))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                // Part 4 & 5: Error Code + Expandable Technical Diagnostic Details
                DisclosureGroup(isExpanded: $isDetailsExpanded) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("错误码：\(err.errorCode)")
                            Spacer()
                            Text("请求 ID：\(err.requestID)")
                        }
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)

                        Text(err.technicalDetails)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .padding(.top, 6)
                } label: {
                    Text("诊断信息与引擎状态 (\(err.engineName))")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Divider()

                HStack {
                    ArcZipSettingsNativeGlassButton(copiedFeedback ? "已复制诊断信息 ✓" : "复制诊断信息", icon: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("\(err.title)\n\(err.errorCode)\n\(err.technicalDetails)", forType: .string)
                        copiedFeedback = true
                    }

                    Spacer()

                    ArcZipDialogButton("关闭", role: .primary, size: .regular) {
                        appViewModel.isErrorDetailPresented = false
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(22)
        }
    }
}

// MARK: - 16. ArchiveProgressWindowView (W-09 MultiTaskProgressPanel)

public typealias MultiTaskProgressPanel = ArchiveProgressWindowView

public struct ArchiveProgressWindowView: View {
    @ObservedObject public var appViewModel = ProZipAppViewModel.shared
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        ArcZipDialogSurface(width: 380, height: 260) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "gauge.with.dots.needle.67percent")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(ProZipTheme.accent)
                        Text("归档任务队列")
                            .font(.system(size: 14, weight: .bold))
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        badgeView(title: "\(appViewModel.activeTasksCount) 进行中", color: ProZipTheme.accent)
                        if appViewModel.waitingTasksCount > 0 {
                            badgeView(title: "\(appViewModel.waitingTasksCount) 等待", color: .orange)
                        }
                        if appViewModel.failedTasksCount > 0 {
                            badgeView(title: "\(appViewModel.failedTasksCount) 失败", color: .red)
                        }
                        badgeView(title: "\(appViewModel.completedTasksCount) 已完成", color: .secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .overlay { WindowDragArea() }

                Divider()

                if appViewModel.tasks.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                        Text("当前无进行中的后台归档任务")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(appViewModel.tasks) { task in
                                TaskRowItemView(task: task)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                    }
                }

                Divider()

                HStack {
                    ArcZipSettingsNativeGlassButton("清理已完成记录", icon: "broom") {
                        appViewModel.tasks.removeAll { $0.phase == .completed || $0.phase == .cancelled }
                    }

                    Spacer()

                    ArcZipDialogButton("关闭", role: .secondary, size: .compact) {
                        appViewModel.isTaskProgressPresented = false
                        dismiss()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
    }

    private func badgeView(title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
    }
}

public struct TaskRowItemView: View {
    @ObservedObject public var task: ArchiveTaskRecord

    public init(task: ArchiveTaskRecord) {
        self.task = task
    }

    private var speedAndETAText: String {
        let speedStr = ByteCountFormatter.string(fromByteCount: task.speedBytesPerSec, countStyle: .file) + "/s"
        if task.phase == .completed {
            return task.speedBytesPerSec > 0 ? "已完成 · 平均 \(speedStr)" : "已完成"
        }
        guard task.speedBytesPerSec > 0 else { return task.phase.rawValue }
        let remainingBytes = max(0, task.totalBytes - task.completedBytes)
        let etaSec = task.speedBytesPerSec > 0 ? max(1, Int(remainingBytes / task.speedBytesPerSec)) : 1
        return "\(speedStr) · 剩余约 \(etaSec) 秒"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(task.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)

                Spacer()

                Text(speedAndETAText)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)

                if task.phase != .completed && task.phase != .failed && task.phase != .cancelled {
                    Button {
                        task.cancel()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("取消任务并安全回滚临时文件")
                } else if let resultURL = task.outputResultURL {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([resultURL])
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11))
                            .foregroundStyle(ProZipTheme.accent)
                    }
                    .buttonStyle(.plain)
                    .help("在访达中显示输出文件")
                }
            }

            ProgressView(value: task.fractionCompleted)
                .progressViewStyle(LinearProgressViewStyle(tint: ProZipTheme.accent))

            HStack {
                Text(task.currentItem ?? task.phase.rawValue)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text("\(Int(task.fractionCompleted * 100))%")
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(task.phase == .completed ? ProZipTheme.accentDeep : .secondary)
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - 17. ProZipUIDialogGalleryView (界面与弹窗全览 · ⌘⇧D Interactive Showcase)

public enum GalleryShowcaseItem: String, CaseIterable, Identifiable {
    case creationDialog = "D-01 创建压缩包面板"
    case menuBarShelf = "W-05 菜单栏暂存盒 (Shelf)"
    case onboarding = "W-06 首次启动引导 (8步)"
    case releaseOverview = "W-07 更新概览窗口"
    case aboutAndUpdates = "W-08 关于与检查更新"
    case progressQueue = "W-09 多任务进度队列"
    case passwordPrompt = "D-02 密码解锁与非英文提示"
    case passwordBookProtection = "D-05 密码本主密码与 Touch ID"
    case conflictResolution = "D-06 同名文件冲突确认"
    case saveChanges = "D-07 保存修改与并发冲突"
    case deleteAndTrash = "D-08 删除条目与移至废纸篓"
    case filenameRepair = "D-09 Windows 非法文件名修复"
    case entryIndexIssue = "D-10 问题项目跳过确认"
    case diskImageSLA = "D-11 DMG 软件许可协议 (SLA)"
    case sourceAccessTCC = "D-12 TCC 文件夹访问授权"
    case structuredError = "D-13 五段式错误诊断弹窗"
    case buttonAndComponentLab = "UI 组件与按钮动效实验室"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .creationDialog: return "archivebox.fill"
        case .menuBarShelf: return "tray.full.fill"
        case .onboarding: return "sparkles"
        case .releaseOverview: return "newspaper.fill"
        case .aboutAndUpdates: return "info.circle.fill"
        case .progressQueue: return "gauge.with.dots.needle.67percent"
        case .passwordPrompt: return "key.fill"
        case .passwordBookProtection: return "lock.shield.fill"
        case .conflictResolution: return "doc.on.doc.fill"
        case .saveChanges: return "externaldrive.badge.checkmark"
        case .deleteAndTrash: return "trash.fill"
        case .filenameRepair: return "wrench.and.screwdriver.fill"
        case .entryIndexIssue: return "exclamationmark.shield.fill"
        case .diskImageSLA: return "opticaldiscdrive.fill"
        case .sourceAccessTCC: return "folder.badge.person.crop"
        case .structuredError: return "exclamationmark.octagon.fill"
        case .buttonAndComponentLab: return "cursorarrow.click.2"
        }
    }
}

public struct ProZipUIDialogGalleryView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject public var appViewModel = ProZipAppViewModel.shared
    @State private var selectedItem: GalleryShowcaseItem = .creationDialog
    @State private var demoPinState: Bool = true
    @State private var demoStrength: CreationProfile.Strength = .balanced

    public init(initialItem: GalleryShowcaseItem = .creationDialog) {
        _selectedItem = State(initialValue: initialItem)
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Left Sidebar of all 17 Dialogs, Popups & Component Showcases
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    ProZipBrandIcon(size: 26, showAppSquircle: true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("界面与弹窗全览")
                            .font(.system(size: 13.5, weight: .bold))
                        Text("16+ 模态框与组件实时预览 (⌘⇧D)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(14)

                Divider()

                ScrollView {
                    VStack(spacing: 3) {
                        ForEach(GalleryShowcaseItem.allCases) { item in
                            let isSelected = selectedItem == item
                            Button {
                                withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                                    selectedItem = item
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: item.icon)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(isSelected ? ProZipTheme.accent : .secondary)
                                        .frame(width: 18)
                                    Text(item.rawValue)
                                        .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                                        .foregroundStyle(isSelected ? .primary : .secondary)
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(isSelected ? ProZipTheme.accentSoft : Color.clear)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                }

                Divider()

                HStack {
                    ArcZipDialogButton("关闭画廊", role: .secondary, size: .compact, isFullWidth: true) {
                        appViewModel.isDialogGalleryPresented = false
                        dismiss()
                    }
                }
                .padding(10)
            }
            .frame(width: 235)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))

            Divider()

            // Right Live Interactive Preview Stage
            VStack(spacing: 0) {
                HStack {
                    Text(selectedItem.rawValue)
                        .font(.system(size: 14, weight: .bold))
                    Spacer()
                    Text("实时交互预览 · 点击组件可直接测试状态切换")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(0.02))

                Divider()

                ScrollView([.horizontal, .vertical]) {
                    VStack {
                        previewContent(for: selectedItem)
                    }
                    .padding(24)
                    .frame(minWidth: 680, minHeight: 620)
                }
            }
        }
        .frame(width: 960, height: 700)
        .background(Color(NSColor.windowBackgroundColor))
    }

    @ViewBuilder
    private func previewContent(for item: GalleryShowcaseItem) -> some View {
        switch item {
        case .creationDialog:
            ArchiveCreationDialogView(defaultName: "季度产品交付包")
        case .menuBarShelf:
            MenuBarShelfView(model: appViewModel.shelfModel)
                .onAppear {
                    if appViewModel.shelfModel.collectedFiles.isEmpty {
                        appViewModel.shelfModel.populateDemoStagedItems()
                    }
                }
        case .onboarding:
            FirstLaunchOnboardingView()
        case .releaseOverview:
            ReleaseOverviewWindowView()
        case .aboutAndUpdates:
            VStack(spacing: 18) {
                AboutProZipView()
                CheckForUpdatesDialogView()
            }
        case .progressQueue:
            ArchiveProgressWindowView()
        case .passwordPrompt:
            VStack(spacing: 16) {
                PasswordPromptSheetView()
                HStack(spacing: 16) {
                    ArcZipPasswordInputNoticePopover(format: .zip)
                        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                    ArchiveEncryptionNoticePopover()
                        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        case .passwordBookProtection:
            PasswordBookProtectionDialogView()
        case .conflictResolution:
            ConflictResolutionDialogView()
        case .saveChanges:
            SaveChangesConfirmationDialogView()
        case .deleteAndTrash:
            VStack(spacing: 18) {
                DeleteConfirmationDialogView()
                TrashConfirmationDialogView()
            }
        case .filenameRepair:
            FilenameRepairDialogView()
        case .entryIndexIssue:
            EntryIndexIssueDialogView()
        case .diskImageSLA:
            DiskImageLicenseDialogView()
        case .sourceAccessTCC:
            SourceAccessAlertDialogView()
        case .structuredError:
            ArchiveErrorDetailDialogView()
        case .buttonAndComponentLab:
            componentShowcaseLab
        }
    }

    private var componentShowcaseLab: some View {
        ArcZipDialogSurface(width: 620) {
            VStack(alignment: .leading, spacing: 18) {
                Text("ArcZip 1.2.3 / ProZip 原生交互组件实验室")
                    .font(.system(size: 16, weight: .bold))

                Group {
                    Text("1. FlowOrbitControl (环轨流光主动作按钮)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 14) {
                        FlowOrbitControl("全部解压", systemImage: "arrow.up.square", shortcutBadge: "⏎", mode: .accentOrbit) {}
                        FlowOrbitControl("安装到“应用程序”", systemImage: "arrow.down.app", shortcutBadge: "⏎", mode: .accentOrbit) {}
                        FlowOrbitControl("预览", systemImage: "eye", shortcutBadge: "空格", mode: .glassPrimary) {}
                    }
                }

                Divider()

                Group {
                    Text("2. FoldspaceButton & ArcZipDialogButton")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        FoldspaceButton("添加文件", systemImage: "plus", role: .primary) {}
                        FoldspaceButton("保存修改", systemImage: "square.and.arrow.down", shortcutBadge: "⌘S", role: .glass) {}
                        ArcZipDialogButton("确认动作", icon: "checkmark", role: .primary) {}
                        ArcZipDialogButton("危险删除", icon: "trash", role: .destructive) {}
                    }
                }

                Divider()

                Group {
                    Text("3. Mini 圆形控制按钮 & 交通灯 & 5 档强度滑杆")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 16) {
                        MainWindowTrafficLightsHoverView()
                        ArcZipMiniRoundActionButton(icon: "xmark", tooltip: "关闭", tintColor: .red) {}
                        Button {
                            demoPinState.toggle()
                        } label: {
                            Image(systemName: "pin.fill")
                        }
                        .buttonStyle(ArcZipMiniPinButtonStyle(isPinned: demoPinState))
                        ArcZipMiniRoundActionButton(icon: "arrow.up.left.and.arrow.down.right", tooltip: "展开为完整工作区", tintColor: ProZipTheme.accent) {}
                        ArcZipSettingsNativeGlassButton("设置原生玻璃按钮", icon: "sparkles") {}
                    }

                    ProZipStrengthSlider(strength: $demoStrength)
                        .padding(.top, 6)
                }
            }
            .padding(24)
        }
    }
}

// MARK: - Generic native-style warning (260×202, matching ArcZip NSAlert)

public struct ProZipAlertDialogView: View {
    @ObservedObject public var appViewModel = ProZipAppViewModel.shared
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            ProZipBrandIcon(size: 68, showAppSquircle: true)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 16)

            Text(appViewModel.alertTitle)
                .font(.system(size: 15, weight: .bold))
                .padding(.top, 14)

            Text(appViewModel.alertMessage)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 16)
                .padding(.top, 8)

            Spacer(minLength: 0)

            Button {
                appViewModel.isAlertPresented = false
                dismiss()
            } label: {
                Text("好")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 230, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(ProZipTheme.accent)
                    )
            }
            .buttonStyle(ProZipPressScaleStyle(hoverScale: 1.02, pressedScale: 0.97))
            .keyboardShortcut(.defaultAction)
            .padding(.bottom, 16)
        }
        .frame(width: 260, height: appViewModel.alertMessage.count > 30 ? 267 : 202)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
    }
}

// MARK: - Onboarding shelf artwork overlay (drawn over OnboardingBoxDesktop.png)

private struct OnboardingShelfMock: View {
    private let files: [(String, String, Color)] = [
        ("photo", "Photo.jpg", Color(red: 0.55, green: 0.72, blue: 0.95)),
        ("photo", "Design.png", Color(red: 0.55, green: 0.72, blue: 0.95)),
        ("doc.richtext", "Notes.pdf", Color(red: 0.92, green: 0.32, blue: 0.32)),
        ("doc.zipper", "Archive.zip", Color(red: 0.62, green: 0.66, blue: 0.72))
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ProZipBrandIcon(size: 22, showAppSquircle: true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("ProZip")
                        .font(.system(size: 11, weight: .bold))
                    Text("文件盒")
                        .font(.system(size: 8.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "pin")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.white.opacity(0.75)))
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.white.opacity(0.75)))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 16) {
                ForEach(Array(files.enumerated()), id: \.offset) { _, file in
                    VStack(spacing: 4) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white)
                                .frame(width: 34, height: 34)
                            Image(systemName: file.0)
                                .font(.system(size: 17))
                                .foregroundStyle(file.2)
                        }
                        Text(file.1)
                            .font(.system(size: 8.5, weight: .medium))
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(ProZipTheme.accent))
                Text("4 个文件 ⌃")
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 10)
                    .frame(height: 22)
                    .background(Capsule().fill(Color.white.opacity(0.92)))
                Spacer()
                Image(systemName: "trash")
                    .font(.system(size: 9, weight: .medium))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.white.opacity(0.92)))
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(colors: [Color.white.opacity(0.92), Color(red: 0.91, green: 0.97, blue: 0.80).opacity(0.92)], startPoint: .top, endPoint: .bottom)
                )
                .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.8), lineWidth: 1)
        )
    }
}

// MARK: - Onboarding Menu Bar Cover (Page 3 · ProZip 文件盒)

private struct OnboardingMenuBarStripMock: View {
    var body: some View {
        HStack(spacing: 11) {
            Spacer(minLength: 0)

            ProZipBrandIcon(size: 14, showAppSquircle: true)

            Image(systemName: "wifi")
                .font(.system(size: 10, weight: .semibold))
            Image(systemName: "battery.100")
                .font(.system(size: 10.5, weight: .medium))
            Image(systemName: "magnifyingglass")
                .font(.system(size: 9.5, weight: .semibold))
            Image(systemName: "switch.2")
                .font(.system(size: 9.5, weight: .semibold))

            Text("10月11日 周日 23:59")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(.white.opacity(0.95))
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.24, blue: 0.39).opacity(0.97),
                    Color(red: 0.24, green: 0.45, blue: 0.63).opacity(0.97),
                    Color(red: 0.14, green: 0.36, blue: 0.54).opacity(0.97)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }
}

// MARK: - Onboarding Vector ProZip Mini Mock (Page 2 · 504×284, Zero Residual Brand Text)

private struct OnboardingMiniMock: View {
    @Environment(\.colorScheme) private var colorScheme

    private let entries: [(String, String, Color, Bool)] = [
        ("IMG_0079.jpeg", "4 MB", Color(red: 0.85, green: 0.42, blue: 0.22), false),
        ("IMG_0667.jpeg", "5.1 MB", Color(red: 0.32, green: 0.48, blue: 0.72), false),
        ("IMG_0927.jpeg", "1.9 MB", Color(red: 0.36, green: 0.69, blue: 0.28), true),
        ("IMG_1207.jpeg", "2.2 MB", Color(red: 0.25, green: 0.60, blue: 0.78), false),
        ("IMG_1216.jpeg", "2.8 MB", Color(red: 0.44, green: 0.56, blue: 0.40), false),
        ("IMG_1606.jpeg", "1.5 MB", Color(red: 0.35, green: 0.52, blue: 0.68), false)
    ]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: OnboardingSkin.artworkCorner, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color(red: 0.953, green: 0.957, blue: 0.961))

            // Dashed callout curves
            Canvas { context, _ in
                let stroke = StrokeStyle(lineWidth: 1.1, lineCap: .round, dash: [3, 2.5])
                let ink = colorScheme == .dark ? Color.white.opacity(0.45) : Color.black.opacity(0.42)

                // 1. Selected row -> "拖动进行解压"
                var dragCurve = Path()
                dragCurve.move(to: CGPoint(x: 118, y: 132))
                dragCurve.addQuadCurve(to: CGPoint(x: 68, y: 126), control: CGPoint(x: 92, y: 108))
                context.stroke(dragCurve, with: .color(ink), style: stroke)

                // 2. Expand circle -> "随时切换到完整界面"
                var expandCurve = Path()
                expandCurve.move(to: CGPoint(x: 155, y: 235))
                expandCurve.addQuadCurve(to: CGPoint(x: 84, y: 212), control: CGPoint(x: 118, y: 262))
                context.stroke(expandCurve, with: .color(ink), style: stroke)

                // 3. Preview button -> "轻松预览"
                var previewCurve = Path()
                previewCurve.move(to: CGPoint(x: 306, y: 235))
                previewCurve.addQuadCurve(to: CGPoint(x: 410, y: 236), control: CGPoint(x: 358, y: 264))
                context.stroke(previewCurve, with: .color(ink), style: stroke)
            }
            .allowsHitTesting(false)

            // Callout labels
            Text("拖动进行解压")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.primary.opacity(0.75))
                .position(x: 58, y: 138)

            Text("随时切换到完整界面")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.primary.opacity(0.75))
                .position(x: 68, y: 198)

            Text("轻松预览")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.primary.opacity(0.75))
                .position(x: 422, y: 224)

            // Center ProZip Mini card (272×194)
            miniCard
                .frame(width: 272, height: 194)
        }
        .clipShape(RoundedRectangle(cornerRadius: OnboardingSkin.artworkCorner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: OnboardingSkin.artworkCorner, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var miniCard: some View {
        let selectionBlue = Color(red: 0.0, green: 0.396, blue: 0.898)
        return VStack(spacing: 0) {
            // Header
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(0.88))
                    .frame(width: 18, height: 20)
                    .overlay(
                        Image(systemName: "doc.zipper")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text("照片集.zip")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("ZIP 压缩包 · 26 个项目")
                        .font(.system(size: 7))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                HStack(spacing: 4) {
                    ProZipBrandIcon(size: 17, showAppSquircle: true)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("ProZip")
                            .font(.system(size: 8.5, weight: .bold))
                        Text("Mini")
                            .font(.system(size: 6, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 0.5)
                            .background(Capsule().fill(Color.black.opacity(0.06)))
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 7)
            .padding(.bottom, 5)

            // Breadcrumb bar
            HStack(spacing: 5) {
                Image(systemName: "chevron.left").font(.system(size: 6.5, weight: .semibold)).foregroundStyle(.secondary)
                Image(systemName: "chevron.up").font(.system(size: 6.5, weight: .semibold)).foregroundStyle(.secondary)
                Text("照片集 / 照片 / 城市")
                    .font(.system(size: 7.5, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.78))
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: 18)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.62))
            )
            .padding(.horizontal, 8)
            .padding(.bottom, 4)

            // File rows
            VStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(item.2.gradient)
                            .frame(width: 9, height: 7)
                            .overlay(
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.55), lineWidth: 0.4)
                            )

                        Text(item.0)
                            .font(.system(size: 7.8, weight: item.3 ? .semibold : .regular))
                            .foregroundStyle(item.3 ? Color.white : Color.primary.opacity(0.88))

                        Spacer()

                        Text(item.1)
                            .font(.system(size: 7.2, design: .monospaced))
                            .foregroundStyle(item.3 ? Color.white.opacity(0.92) : Color.secondary)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 17.5)
                    .background(item.3 ? selectionBlue : Color.clear)
                }
            }

            Spacer(minLength: 0)

            // Bottom floating bar
            HStack(spacing: 5) {
                HStack(spacing: 4) {
                    miniCircleControl("xmark")
                    miniCircleControl("pin")
                    miniCircleControl("arrow.up.left.and.arrow.down.right")
                }

                Spacer(minLength: 4)

                HStack(spacing: 3) {
                    Image(systemName: "bolt.fill").font(.system(size: 6.5, weight: .bold))
                    Text("解压").font(.system(size: 7.5, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .frame(height: 16)
                .background(Capsule().fill(ProZipTheme.accent))

                HStack(spacing: 4) {
                    HStack(spacing: 2) {
                        Image(systemName: "eye").font(.system(size: 6.5))
                        Text("预览").font(.system(size: 6.8, weight: .medium))
                        Text("空格")
                            .font(.system(size: 5.5))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 2.5)
                            .padding(.vertical, 0.5)
                            .background(RoundedRectangle(cornerRadius: 2).strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
                    }
                    Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 0.6, height: 9)
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.up.square").font(.system(size: 6.5))
                        Text("全部解压").font(.system(size: 6.8, weight: .medium))
                        Text("⏎").font(.system(size: 5.8)).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 6)
                .frame(height: 16)
                .background(Capsule().fill(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.86)))
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 7)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color(red: 0.16, green: 0.18, blue: 0.22), Color(red: 0.13, green: 0.16, blue: 0.20)]
                            : [Color(red: 0.965, green: 0.969, blue: 0.961), Color(red: 0.855, green: 0.945, blue: 0.992), Color(red: 0.812, green: 0.925, blue: 0.988)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.20 : 0.86), lineWidth: 1)
        )
    }

    private func miniCircleControl(_ icon: String) -> some View {
        Circle()
            .fill(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.78))
            .frame(width: 14, height: 14)
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: 6, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.82))
            )
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }
}

// MARK: - Onboarding Vector Finder Context Menu Mock (Page 5 · 376×330, Zero Residual Brand Text)

private struct OnboardingFinderContextMenuMock: View {
    private let sidebarItems: [(String, String)] = [
        ("app.badge", "应用程序"),
        ("menubar.dock.rectangle", "桌面"),
        ("doc", "文稿"),
        ("arrow.down.circle", "下载"),
        ("folder", "进行中项目"),
        ("photo", "图片")
    ]

    private let tagColors: [Color] = [
        Color(red: 0.98, green: 0.36, blue: 0.34),
        Color(red: 0.98, green: 0.62, blue: 0.20),
        Color(red: 0.98, green: 0.82, blue: 0.22),
        Color(red: 0.28, green: 0.80, blue: 0.38),
        Color(red: 0.22, green: 0.58, blue: 0.98),
        Color(red: 0.68, green: 0.42, blue: 0.92),
        Color(white: 0.62)
    ]

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Coastal twilight ocean backdrop
            LinearGradient(
                colors: [
                    Color(red: 0.44, green: 0.50, blue: 0.60),
                    Color(red: 0.62, green: 0.58, blue: 0.56),
                    Color(red: 0.24, green: 0.34, blue: 0.44),
                    Color(red: 0.13, green: 0.20, blue: 0.27)
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )

            // Finder Window Mock (316×174)
            finderWindowMock
                .frame(width: 316, height: 174)
                .offset(x: 10, y: 10)

            // macOS Frosted Context Menu Mock (132×194)
            contextMenuCard
                .frame(width: 132)
                .offset(x: 226, y: 122)
        }
        .frame(width: 376, height: 330)
        .clipShape(RoundedRectangle(cornerRadius: OnboardingSkin.artworkCorner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: OnboardingSkin.artworkCorner, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var finderWindowMock: some View {
        HStack(spacing: 0) {
            // Sidebar
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.34)).frame(width: 6, height: 6)
                    Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18)).frame(width: 6, height: 6)
                    Circle().fill(Color(red: 0.16, green: 0.78, blue: 0.25)).frame(width: 6, height: 6)
                }
                .padding(.bottom, 4)

                Text("个人收藏")
                    .font(.system(size: 5.5, weight: .semibold))
                    .foregroundStyle(.secondary)

                ForEach(sidebarItems, id: \.1) { item in
                    HStack(spacing: 4) {
                        Image(systemName: item.0)
                            .font(.system(size: 6.5))
                            .foregroundStyle(Color(red: 0.16, green: 0.52, blue: 0.96))
                            .frame(width: 8)
                        Text(item.1)
                            .font(.system(size: 6.5))
                            .foregroundStyle(Color.black.opacity(0.80))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(width: 72)
            .background(Color(red: 0.945, green: 0.949, blue: 0.957))

            // Main Canvas
            VStack(spacing: 0) {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left").font(.system(size: 6.5)).foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.system(size: 6.5)).foregroundStyle(.secondary.opacity(0.5))
                    Text("ProZip 演示")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.85))
                    Spacer()
                    Image(systemName: "square.grid.2x2").font(.system(size: 6.5)).foregroundStyle(.secondary)
                    Image(systemName: "square.and.arrow.up").font(.system(size: 6.5)).foregroundStyle(.secondary)
                    Image(systemName: "magnifyingglass").font(.system(size: 6.5)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(Color(white: 0.98))

                Rectangle().fill(Color.black.opacity(0.06)).frame(height: 0.6)

                ZStack(alignment: .topLeading) {
                    Color.white

                    HStack(alignment: .top, spacing: 22) {
                        finderDesktopItem(icon: "externaldrive", tint: .gray, name: "App.dmg", selected: false)
                        finderDesktopItem(icon: "doc.zipper", tint: .secondary, name: "Flow.zip", selected: false)
                        finderDesktopItem(icon: "folder.fill", tint: Color(red: 0.33, green: 0.71, blue: 0.98), name: "照片集", selected: false)
                    }
                    .padding(.leading, 18)
                    .padding(.top, 14)

                    finderDesktopItem(icon: "doc.zipper", tint: .secondary, name: "照片集.zip", selected: true)
                        .offset(x: 186, y: 86)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Rectangle().fill(Color.black.opacity(0.06)).frame(height: 0.6)

                HStack(spacing: 3) {
                    Text("Macintosh HD ▸ 用户 ▸ Demo ▸ ProZip 演示 ▸ 照片集.zip")
                        .font(.system(size: 5.5))
                        .foregroundStyle(Color.black.opacity(0.55))
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 6)
                .frame(height: 14)
                .background(Color(white: 0.98))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.24), radius: 8, y: 3)
    }

    private func finderDesktopItem(icon: String, tint: Color, name: String, selected: Bool) -> some View {
        VStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(selected ? Color.black.opacity(0.08) : Color.clear)
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundStyle(tint)
                )
            Text(name)
                .font(.system(size: 6, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.white : Color.black.opacity(0.82))
                .padding(.horizontal, 3)
                .padding(.vertical, 0.8)
                .background(
                    Capsule().fill(selected ? Color(red: 0.0, green: 0.40, blue: 0.90) : Color.clear)
                )
        }
    }

    private var contextMenuCard: some View {
        VStack(alignment: .leading, spacing: 2.5) {
            menuRow("打开")
            menuRow("打开方式", hasSubmenu: true)
            menuDivider
            menuRow("移到废纸篓", sfSymbol: "trash")
            menuDivider
            menuRow("显示简介")
            menuRow("快速查看“照片集.zip”")
            menuDivider

            HStack(spacing: 4) {
                ForEach(Array(tagColors.enumerated()), id: \.offset) { _, color in
                    Circle()
                        .fill(color)
                        .frame(width: 6.5, height: 6.5)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 2)

            menuRow("标签…", sfSymbol: "tag")
            menuDivider
            menuRow("快速操作", sfSymbol: "gearshape", hasSubmenu: true)
            proZipMenuRow("快速解压到当前目录", highlighted: true)
            proZipMenuRow("快速解压到指定目录…", highlighted: false)
            menuDivider
            proZipMenuRow("压缩为 “照片集 2.zip”", highlighted: false)
            proZipMenuRow("压缩为…", highlighted: false)
            menuDivider
            menuRow("服务", hasSubmenu: true)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(white: 0.95).opacity(0.95))
                .shadow(color: .black.opacity(0.28), radius: 10, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.75), lineWidth: 0.8)
        )
    }

    private var menuDivider: some View {
        Rectangle()
            .fill(Color.black.opacity(0.10))
            .frame(height: 0.6)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
    }

    private func menuRow(_ title: String, sfSymbol: String? = nil, hasSubmenu: Bool = false) -> some View {
        HStack(spacing: 4) {
            if let sfSymbol {
                Image(systemName: sfSymbol)
                    .font(.system(size: 6.5))
                    .foregroundStyle(Color.black.opacity(0.65))
                    .frame(width: 9)
            }
            Text(title)
                .font(.system(size: 6.8))
                .foregroundStyle(Color.black.opacity(0.86))
                .lineLimit(1)
            Spacer(minLength: 2)
            if hasSubmenu {
                Image(systemName: "chevron.right")
                    .font(.system(size: 5.5, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.5))
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 10.5)
    }

    private func proZipMenuRow(_ title: String, highlighted: Bool) -> some View {
        HStack(spacing: 4.5) {
            ProZipBrandIcon(size: 9.5, showAppSquircle: true)
            Text(title)
                .font(.system(size: 6.8, weight: highlighted ? .semibold : .medium))
                .foregroundStyle(highlighted ? Color.white : Color.black.opacity(0.88))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 5)
        .frame(height: 12)
        .background(
            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                .fill(highlighted ? ProZipTheme.accent : Color.clear)
        )
    }
}
