import AppKit
import Carbon.HIToolbox
import ProZipCore
import ProZipShared
import SwiftUI

// MARK: - ProZipKeyboardInputMonitor (Non-ASCII / CJK IME Detection for NSSecureTextField)

public enum ProZipKeyboardInputMonitor {
    @MainActor
    public static func isCurrentInputSourceNonASCII() -> Bool {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return false
        }
        if let asciiPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsASCIICapable) {
            let isASCII = Unmanaged<CFBoolean>.fromOpaque(asciiPtr).takeUnretainedValue()
            if !CFBooleanGetValue(isASCII) {
                return true
            }
        }
        if let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
            let sourceID = (Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String).lowercased()
            if sourceID.contains("inputmethod.scim")
                || sourceID.contains("inputmethod.tcim")
                || sourceID.contains("sogou")
                || sourceID.contains("rime")
                || sourceID.contains("wetype")
                || sourceID.contains("baidu")
                || sourceID.contains("pinyin")
                || sourceID.contains("shuangpin")
                || sourceID.contains("wubi") {
                return true
            }
        }
        return false
    }
}

// MARK: - ArchiveCreationExpansionScrollState (doc/04 & doc/13 D-01)

public struct ArchiveCreationExpansionScrollState: Equatable, Sendable {
    public var isAdvancedExpanded: Bool
    public var isPasswordEnabled: Bool
    public var isSplitEnabled: Bool

    public init(
        isAdvancedExpanded: Bool = true,
        isPasswordEnabled: Bool = false,
        isSplitEnabled: Bool = false
    ) {
        self.isAdvancedExpanded = isAdvancedExpanded
        self.isPasswordEnabled = isPasswordEnabled
        self.isSplitEnabled = isSplitEnabled
    }
}

// MARK: - ArcZipPasswordInputNoticePopover (D-03 Non-ASCII Input Method Popover)

public struct ArcZipPasswordInputNoticePopover: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("archivePassword.inputNoticeSuppressed.v1") private var noticeSuppressed: Bool = false
    public var format: ArchiveFormat
    public var onSwitchTo7Z: (() -> Void)?
    public var onRevealPassword: (() -> Void)?
    public var onDismiss: (() -> Void)?

    public init(
        format: ArchiveFormat = .zip,
        onSwitchTo7Z: (() -> Void)? = nil,
        onRevealPassword: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.format = format
        self.onSwitchTo7Z = onSwitchTo7Z
        self.onRevealPassword = onRevealPassword
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "eye")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ProZipTheme.accent)
                Text("输入非英文密码")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
            }

            Text("输入中文或其他语言的密码时，请先点击眼睛按钮显示内容，再进行输入；也可以直接粘贴。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            if format == .zip && onSwitchTo7Z != nil {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .padding(.top, 1)
                    Text("ZIP 密码字符编码没有统一标准；为保证跨平台可解压，创建 ZIP 时密码仅支持 ASCII。中文密码请使用 7Z。")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }

            HStack(spacing: 8) {
                if format == .zip, let onSwitchTo7Z {
                    Button("切换为 7Z 格式") {
                        onSwitchTo7Z()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(ProZipTheme.accent)
                }

                Spacer()

                Button {
                    noticeSuppressed = true
                    if let onDismiss {
                        onDismiss()
                    } else {
                        dismiss()
                    }
                } label: {
                    Text("不再提示")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.primary.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(width: 296)
    }
}

// MARK: - ArchiveEncryptionNoticePopover (D-04 Encryption Info Popover)

public struct ArchiveEncryptionNoticePopover: View {
    @AppStorage("archiveEncryption.noticeSuppressed.v1") private var noticeSuppressed: Bool = false

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(ProZipTheme.accent)
                Text("归档加密机制说明")
                    .font(.system(size: 13, weight: .bold))
            }

            VStack(alignment: .leading, spacing: 6) {
                Label("7Z 格式：采用 AES-256 强加密，支持 Unicode 中文密码及「加密文件名」（隐藏目录结构）。", systemImage: "checkmark.shield.fill")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)

                Label("ZIP 格式：采用跨平台兼容加密，仅限 ASCII 半角字符密码，默认不隐藏文件名列表。", systemImage: "info.circle.fill")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Toggle("不再自动提示", isOn: $noticeSuppressed)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 290)
    }
}

// MARK: - ArchiveCreationDialogView (D-01 Compression Creation Dialog)

public struct ArchiveCreationDialogView: View {
    @ObservedObject private var appViewModel: ProZipAppViewModel
    @ObservedObject private var preferences = ProZipPreferences.shared
    @ObservedObject private var passwordBook: PasswordBook
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private let explicitInitialPurpose: CreationProfile.Purpose?
    @State private var selectedPurpose: CreationProfile.Purpose = .general
    @State private var hoveredPurpose: CreationProfile.Purpose?
    @State private var archiveName: String = "归档"
    @State private var format: ArchiveFormat = .zip
    @State private var strength: CreationProfile.Strength = .balanced
    @State private var outputDestinationMode: String = "same"
    @State private var outputDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")

    @State private var expansionState = ArchiveCreationExpansionScrollState(isAdvancedExpanded: true)
    @State private var password: String = ""
    @State private var confirmationPassword: String = ""
    @State private var isConfirmationVisible: Bool = ProZipPreferences.shared.revealsPasswordByDefault
    @State private var isPasswordVisible: Bool = ProZipPreferences.shared.revealsPasswordByDefault
    @State private var showNonASCIINoticePopover: Bool = false
    @State private var showEncryptionInfoPopover: Bool = false
    @State private var savePasswordToBook: Bool = ProZipPreferences.shared.passwordBookAutoSave
    @State private var encryptHeaderNames: Bool = false

    @State private var splitModeByCount: Bool = false
    @State private var splitSizeValue: String = "100"
    @State private var splitSizeUnit: String = "MB"
    @State private var splitTotalParts: Int = 3

    @State private var excludeMacJunk: Bool = true
    @State private var windowsCompatibleNames: Bool = true
    @State private var moveSourcesToTrash: Bool = false
    @State private var keepParentDirectory: Bool = true
    @State private var validationErrorMessage: String?
    @FocusState private var isNameFieldFocused: Bool

    @MainActor
    public init(initialPurpose: CreationProfile.Purpose? = nil, defaultName: String = "归档", appViewModel: ProZipAppViewModel? = nil) {
        let appViewModel = appViewModel ?? .shared
        self.appViewModel = appViewModel
        self.passwordBook = appViewModel.passwordBook
        self.explicitInitialPurpose = initialPurpose
        _archiveName = State(initialValue: defaultName)
        if let initialPurpose {
            _selectedPurpose = State(initialValue: initialPurpose)
        }
    }

    private var hasNonASCIICharactersInPassword: Bool {
        password.unicodeScalars.contains { !$0.isASCII }
    }

    private var passwordStrengthInfo: (label: String, score: Int, color: Color) {
        guard !password.isEmpty else {
            return ("未输入", 0, Color.secondary.opacity(0.35))
        }
        var score = 1
        if password.count >= 8 { score += 1 }
        if password.count >= 12 { score += 1 }
        let hasUpper = password.rangeOfCharacter(from: .uppercaseLetters) != nil
        let hasDigit = password.rangeOfCharacter(from: .decimalDigits) != nil
        let hasSymbol = password.rangeOfCharacter(from: .punctuationCharacters.union(.symbols)) != nil
        if (hasUpper && hasDigit) || hasSymbol { score += 1 }
        switch score {
        case 1: return ("弱", 1, .orange)
        case 2: return ("中等", 2, .yellow)
        case 3: return ("较强", 3, ProZipTheme.accent)
        default: return ("极强", 4, ProZipTheme.accentBright)
        }
    }

    private var selectedSourceItems: [URL] {
        appViewModel.creationSources
    }

    private var sourceSummaryText: String {
        let urls = selectedSourceItems
        let count = urls.count
        var bytes: Int64 = 0
        for url in urls {
            if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap({ Int64($0) }) {
                bytes += size
            }
        }
        let sizeText = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        return "已选 \(count) 个项目 · 共 \(sizeText)"
    }

    private var formatDescriptionText: String {
        switch format {
        case .zip:
            return "跨平台兼容性最好，支持 Windows 文件名兼容修复与分卷"
        case .sevenZip:
            return "极限 LZMA2 压缩率（4 GB 固实块），支持 AES-256 加密与加密文件名"
        case .tar:
            return "保留完整 POSIX 权限与 Unix 目录结构，适合 Linux 与服务器部署"
        default:
            return "标准归档格式"
        }
    }

    private var canAdjustStrength: Bool {
        if format == .tar { return false }
        if selectedPurpose == .smallest { return false }
        return true
    }

    public var body: some View {
        VStack(spacing: 0) {
            brandHeader

            ZStack(alignment: .bottom) {
                ScrollViewReader { scrollProxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 0) {
                            nameAndDestinationRow
                                .padding(.top, 6)

                            purposeSection
                                .padding(.top, 14)

                            settingsAndOverviewRow
                                .padding(.top, 16)

                            advancedOptionsSection
                                .id("advanced-options-anchor")
                                .padding(.top, 16)
                        }
                        .padding(.horizontal, 44)
                        .padding(.bottom, validationErrorMessage == nil ? 90 : 126)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: expansionState) { _, newState in
                        if newState.isAdvancedExpanded {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                scrollProxy.scrollTo("advanced-options-anchor", anchor: .bottom)
                            }
                        }
                    }
                }

                VStack(spacing: 0) {
                    if let errorMsg = validationErrorMessage {
                        validationBanner(errorMsg)
                    }

                    footerBar
                }
            }
        }
        .frame(width: 900, height: 600)
        .background {
            ZStack {
                creationSheetBackground
                WindowDragArea()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(creationCardBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.36 : 0.18), radius: 28, y: 14)
        .onAppear {
            let initialP = explicitInitialPurpose ?? preferences.defaultPurpose
            selectedPurpose = initialP
            format = preferences.defaultFormat(for: initialP)
            strength = preferences.defaultStrength(for: initialP)
            expansionState.isSplitEnabled = preferences.defaultCreatesSplitVolumes
            let defaultBytes = preferences.defaultVolumeSizeBytes
            if defaultBytes > 0 {
                let gb: Int64 = 1024 * 1024 * 1024
                let mb: Int64 = 1024 * 1024
                if defaultBytes % gb == 0 {
                    splitSizeValue = String(defaultBytes / gb)
                    splitSizeUnit = "GB"
                } else {
                    splitSizeValue = String(max(1, defaultBytes / mb))
                    splitSizeUnit = "MB"
                }
            }
            excludeMacJunk = !preferences.defaultPreservesMacMetadata
            windowsCompatibleNames = preferences.windowsNameRepair
            isPasswordVisible = preferences.revealsPasswordByDefault
            isConfirmationVisible = preferences.revealsPasswordByDefault
            savePasswordToBook = preferences.passwordBookAutoSave

            if let firstSource = appViewModel.creationOriginalSources?.first ?? selectedSourceItems.first {
                outputDirectory = firstSource.deletingLastPathComponent()
                if archiveName == "归档" || archiveName == "项目归档" {
                    archiveName = firstSource.deletingPathExtension().lastPathComponent
                }
            }
        }
    }

    // MARK: - Brand Header (32pt icon + 24pt title, no window chrome)

    private var brandHeader: some View {
        HStack(spacing: 12) {
            ProZipBrandIcon(size: 32, showAppSquircle: true)
                .frame(width: 32, height: 32)

            Text("创建压缩包")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(creationInk)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 44)
        .padding(.top, 20)
        .padding(.bottom, 18)
        .contentShape(Rectangle())
        .overlay {
            WindowDragArea()
        }
    }

    // MARK: - Name & Destination Row (two columns, 399pt each)

    private var nameAndDestinationRow: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                columnLabel("名称")

                HStack(spacing: 10) {
                    archivePreviewSwatch

                    TextField("输入压缩包名称", text: $archiveName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(creationInk)
                        .focused($isNameFieldFocused)

                    Text(".\(format.defaultExtension)")
                        .font(.system(size: 15, weight: .regular, design: .monospaced))
                        .foregroundStyle(creationMutedInk)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(creationFieldFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            isNameFieldFocused ? ProZipTheme.accent : creationCardBorder,
                            lineWidth: isNameFieldFocused ? 1.6 : 1
                        )
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    isNameFieldFocused = true
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 7) {
                columnLabel("存储位置")

                Menu {
                    Button {
                        setDestinationMode("same")
                    } label: {
                        Label("与原文件同目录", systemImage: "arrow.turn.down.right")
                    }

                    Button {
                        setDestinationMode("desktop")
                    } label: {
                        Label("桌面 (Desktop)", systemImage: "menubar.dock.rectangle")
                    }

                    Button {
                        chooseOutputDirectory()
                    } label: {
                        Label("自定义目录…", systemImage: "folder")
                    }

                    Divider()

                    Button {
                        chooseOutputDirectory()
                    } label: {
                        Label("选择文件夹…", systemImage: "folder.badge.gearshape")
                    }
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(ProZipTheme.accent)

                        Text(destinationDisplayName)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(creationInk)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(creationMutedInk)
                    }
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(creationFieldFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(creationCardBorder, lineWidth: 1)
                    )
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 40)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var archivePreviewSwatch: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [ProZipTheme.accentBright, ProZipTheme.accent],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 32, height: 32)
            .overlay(
                Image(systemName: "archivebox.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ProZipTheme.darkInk.opacity(0.78))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.55), lineWidth: 1)
            )
    }

    private func columnLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(creationMutedInk)
    }

    // MARK: - Purpose Section (5 cards, 152×106)

    private var purposeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("这个压缩包将用于什么？")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(creationInk)

            HStack(spacing: 9) {
                ForEach(CreationProfile.Purpose.allCases, id: \.self) { purpose in
                    purposeCard(purpose)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func purposeCard(_ purpose: CreationProfile.Purpose) -> some View {
        let isSelected = selectedPurpose == purpose
        let isHovered = hoveredPurpose == purpose
        return Button {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                applyPurpose(purpose)
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: purpose.sfSymbol)
                    .font(.system(size: 24, weight: .medium))
                    .frame(height: 28)

                Text(purpose.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Text(purpose.subtitle)
                    .font(.system(size: 10.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .opacity(isSelected ? 0.95 : 0.62)
            }
            .foregroundStyle(isSelected ? Color.white : creationInk)
            .frame(width: 152, height: 106)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        isSelected
                            ? ProZipTheme.accent
                            : (isHovered
                                ? (colorScheme == .dark ? Color.white.opacity(0.08) : Color(white: 0.978))
                                : creationCardFill)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? ProZipTheme.accentDeep.opacity(0.35)
                            : (isHovered ? ProZipTheme.accent.opacity(0.42) : creationCardBorder),
                        lineWidth: 1
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? ProZipTheme.accent.opacity(0.30) : Color.clear, lineWidth: 2.5)
                    .padding(-2)
            )
            .overlay(alignment: .topTrailing) {
                if purpose != .general {
                    proBadge(onAccent: isSelected)
                        .padding(8)
                }
            }
            .shadow(
                color: isSelected
                    ? ProZipTheme.accent.opacity(0.28)
                    : (isHovered ? Color.black.opacity(colorScheme == .dark ? 0.22 : 0.06) : .clear),
                radius: isSelected ? 7 : 4,
                y: isSelected ? 3 : 2
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(ProZipPressScaleStyle(hoverScale: 1.01, pressedScale: 0.97))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                hoveredPurpose = hovering ? purpose : (hoveredPurpose == purpose ? nil : hoveredPurpose)
            }
        }
    }

    private func proBadge(onAccent: Bool = false) -> some View {
        Text("Pro")
            .font(.system(size: 9.5, weight: .bold))
            .foregroundStyle(ProZipTheme.accentDeep)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(onAccent ? Color.white.opacity(0.92) : ProZipTheme.accentSoft)
            )
            .overlay(
                Capsule()
                    .strokeBorder(ProZipTheme.accent.opacity(0.45), lineWidth: 0.8)
            )
    }

    // MARK: - Lower Section (压缩设置 + 压缩包概览)

    private var settingsAndOverviewRow: some View {
        HStack(alignment: .top, spacing: 14) {
            compressionSettingsCard
            archiveOverviewCard
        }
    }

    private var compressionSettingsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("压缩设置")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(creationInk)

            Text("压缩格式")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(creationMutedInk)
                .padding(.top, 14)

            formatSegmentedControl
                .padding(.top, 10)

            HStack(spacing: 6) {
                Text("压缩强度")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(creationMutedInk)

                proBadge()

                Spacer(minLength: 0)

                Text(effectiveStrength.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ProZipTheme.accentDeep)
            }
            .padding(.top, 6)

            ProZipStrengthSlider(
                strength: Binding(
                    get: { selectedPurpose == .smallest ? .maximum : strength },
                    set: { newVal in
                        strength = newVal
                        preferences.setDefaultStrength(newVal, for: selectedPurpose)
                    }
                ),
                isDisabled: !canAdjustStrength
            )
            .frame(height: 70)
            .padding(.top, 16)

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 214, maxHeight: 214, alignment: .topLeading)
        .background(creationCardSurface)
    }

    private var formatSegmentedControl: some View {
        HStack(spacing: 3) {
            ForEach([ArchiveFormat.zip, .sevenZip, .tar], id: \.self) { candidate in
                formatSegment(candidate)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(creationFieldFill)
        )
    }

    private func formatSegment(_ candidate: ArchiveFormat) -> some View {
        let isAllowed = selectedPurpose.allowedFormats.contains(candidate)
        let isSelected = format == candidate
        return Button {
            selectFormat(candidate)
        } label: {
            HStack(spacing: 4) {
                Text(candidate.rawValue.uppercased())
                    .font(.system(size: 12.5, weight: .semibold))

                if candidate != .zip {
                    Text("Pro")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(ProZipTheme.accentDeep)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(ProZipTheme.accentSoft, in: Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(ProZipTheme.accent.opacity(0.35), lineWidth: 0.7)
                        )
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .foregroundStyle(
                isSelected
                    ? ProZipTheme.accentDeep
                    : (isAllowed ? creationInk.opacity(0.8) : creationMutedInk.opacity(0.5))
            )
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? creationCardFill : Color.clear)
            )
            .shadow(color: isSelected ? Color.black.opacity(0.08) : .clear, radius: 2, y: 1)
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isAllowed)
        .opacity(isAllowed ? 1.0 : 0.4)
    }

    private var archiveOverviewCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("压缩包概览")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(creationInk)

            VStack(spacing: 7) {
                overviewRow("格式", overviewFormatLabel)
                overviewRow("压缩强度", effectiveStrength.title)
                overviewRow("用途", selectedPurpose.title)
            }
            .padding(.top, 14)

            Rectangle()
                .fill(creationCardBorder)
                .frame(height: 1)
                .padding(.vertical, 14)

            VStack(alignment: .leading, spacing: 9) {
                overviewCheckRow("清理 macOS 辅助文件", isOn: excludeMacJunk)
                overviewCheckRow("采用通用 ZIP 设置", isOn: windowsCompatibleNames)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 214, maxHeight: 214, alignment: .topLeading)
        .background(creationCardSurface)
    }

    private func overviewRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(creationMutedInk)

            Spacer(minLength: 0)

            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(creationInk)
                .lineLimit(1)
        }
    }

    private func overviewCheckRow(_ text: String, isOn: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isOn ? ProZipTheme.accentDeep : creationMutedInk.opacity(0.35))

            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(creationInk.opacity(0.85))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
    }

    private var creationCardSurface: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(creationCardFill)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(creationCardBorder, lineWidth: 1)
            )
    }

    // MARK: - Collapsible Advanced Options Section (ArchiveCreationExpansionScrollState)

    private var advancedOptionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                    expansionState.isAdvancedExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: expansionState.isAdvancedExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(ProZipTheme.accent)
                        .frame(width: 14)

                    Text("高级选项")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text("密码保护 · 密码本预设 · 7Z 加密文件名 · 分卷压缩 · 兼容与清理")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Spacer()
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expansionState.isAdvancedExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    passwordProtectionBlock

                    splitVolumeBlock

                    compatibilityAndCleanupBlock
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Password Protection Block (with Non-ASCII Popover, Eye Toggle & Password Book Menu)

    private var passwordProtectionBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Toggle(isOn: Binding(
                    get: { expansionState.isPasswordEnabled },
                    set: { val in
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                            expansionState.isPasswordEnabled = val
                            validationErrorMessage = nil
                        }
                    }
                )) {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(ProZipTheme.accent)
                        Text(format == .sevenZip ? "密码保护 (AES-256)" : "密码保护")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.primary)

                        Button {
                            showEncryptionInfoPopover.toggle()
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showEncryptionInfoPopover, arrowEdge: .bottom) {
                            ArchiveEncryptionNoticePopover()
                        }
                    }
                }
                .toggleStyle(.switch)
                .tint(ProZipTheme.accent)
                .disabled(format == .tar)

                Spacer()

                if expansionState.isPasswordEnabled {
                    Menu {
                        let presets = passwordBook.presets
                        let allEntries = passwordBook.entries
                        if !presets.isEmpty {
                            Section("预设密码") {
                                ForEach(presets) { entry in
                                    Button("填充：\(entry.title)") {
                                        password = entry.password
                                        confirmationPassword = entry.password
                                        passwordBook.recordUsage(id: entry.id)
                                    }
                                }
                            }
                        }
                        if !allEntries.isEmpty {
                            Section("全部已保存密码") {
                                ForEach(allEntries) { entry in
                                    Button("\(entry.title) (\(entry.password.prefix(2))•••)") {
                                        password = entry.password
                                        confirmationPassword = entry.password
                                        passwordBook.recordUsage(id: entry.id)
                                    }
                                }
                            }
                        } else {
                            Text("密码本暂无记录")
                        }
                        Divider()
                        Button("打开密码本设置…") {
                            appViewModel.settingsSelectedTab = .passwordBook
                            appViewModel.isPasswordBookManagerPresented = true
                        }
                    } label: {
                        Label("从密码本选择预设密码", systemImage: "key.fill")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(ProZipTheme.accentDeep)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }

            if expansionState.isPasswordEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) {
                    HStack(spacing: 8) {
                        Group {
                            if isPasswordVisible {
                                TextField("输入密码", text: $password)
                            } else {
                                SecureField("输入密码", text: $password)
                            }
                        }
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(.primary)
                        .onChange(of: password) { _, newValue in
                            validationErrorMessage = nil
                            let suppressed = UserDefaults.standard.bool(forKey: "archivePassword.inputNoticeSuppressed.v1")
                            if !suppressed && newValue.unicodeScalars.contains(where: { !$0.isASCII }) {
                                showNonASCIINoticePopover = true
                            }
                        }
                        .onReceive(NotificationCenter.default.publisher(for: NSTextInputContext.keyboardSelectionDidChangeNotification)) { _ in
                            let suppressed = UserDefaults.standard.bool(forKey: "archivePassword.inputNoticeSuppressed.v1")
                            if !suppressed && !isPasswordVisible && ProZipKeyboardInputMonitor.isCurrentInputSourceNonASCII() {
                                showNonASCIINoticePopover = true
                            }
                        }

                        // Non-ASCII Input Method Notice Button & Popover (ArcZipPasswordInputNoticePopover)
                        Button {
                            showNonASCIINoticePopover.toggle()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: hasNonASCIICharactersInPassword ? "exclamationmark.triangle.fill" : "globe")
                                    .font(.system(size: 11))
                                if hasNonASCIICharactersInPassword {
                                    Text("非 ASCII 字符")
                                        .font(.system(size: 10, weight: .bold))
                                }
                            }
                            .foregroundStyle(hasNonASCIICharactersInPassword ? Color.orange : Color.secondary)
                            .padding(.horizontal, hasNonASCIICharactersInPassword ? 6 : 4)
                            .padding(.vertical, 2.5)
                            .background(
                                hasNonASCIICharactersInPassword ? Color.orange.opacity(0.15) : Color.clear,
                                in: Capsule()
                            )
                        }
                        .buttonStyle(.plain)
                        .help("检查密码输入法与跨平台编码兼容性")
                        .popover(isPresented: $showNonASCIINoticePopover, arrowEdge: .bottom) {
                            ArcZipPasswordInputNoticePopover(
                                format: format,
                                onSwitchTo7Z: {
                                    format = .sevenZip
                                    showNonASCIINoticePopover = false
                                },
                                onRevealPassword: {
                                    isPasswordVisible = true
                                    showNonASCIINoticePopover = false
                                },
                                onDismiss: {
                                    showNonASCIINoticePopover = false
                                }
                            )
                        }

                        Button {
                            isPasswordVisible.toggle()
                        } label: {
                            Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(isPasswordVisible ? "隐藏密码" : "显示明文密码")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(creationCardFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(
                                        hasNonASCIICharactersInPassword && format == .zip
                                            ? Color.orange
                                            : Color.primary.opacity(0.14),
                                        lineWidth: 1
                                    )
                            )
                    )

                        HStack(spacing: 8) {
                            Group {
                                if isConfirmationVisible { TextField("再次输入密码", text: $confirmationPassword) }
                                else { SecureField("再次输入密码", text: $confirmationPassword) }
                            }
                            .textFieldStyle(.plain)
                            .font(.system(size: 12.5, design: .monospaced))
                            .foregroundStyle(.primary)
                            Button { isConfirmationVisible.toggle() } label: {
                                Image(systemName: isConfirmationVisible ? "eye.slash" : "eye")
                                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                            }.buttonStyle(.plain).help(isConfirmationVisible ? "隐藏确认密码" : "显示确认密码")
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8).fill(creationCardFill))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.14), lineWidth: 1))
                    }

                    if hasNonASCIICharactersInPassword && format == .zip {
                        HStack(spacing: 6) {
                            Image(systemName: "globe")
                                .font(.system(size: 11))
                                .foregroundStyle(.orange)
                            Text("为保证跨平台可解压，创建 ZIP 时密码仅支持 ASCII。中文密码请切换为 7Z 格式。")
                                .font(.system(size: 11))
                                .foregroundStyle(.orange)
                        }
                    }

                    // Password Strength Bar + Save to Password Book + 7Z Encrypt Filenames
                    HStack(spacing: 10) {
                        Text("强度：\(passwordStrengthInfo.label)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(passwordStrengthInfo.color)

                        HStack(spacing: 3) {
                            ForEach(1...4, id: \.self) { idx in
                                Capsule()
                                    .fill(idx <= passwordStrengthInfo.score ? passwordStrengthInfo.color : Color.primary.opacity(0.10))
                                    .frame(width: 18, height: 4)
                            }
                        }

                        Spacer()

                        Toggle("保存到密码本", isOn: $savePasswordToBook)
                            .toggleStyle(.checkbox)
                            .font(.system(size: 11.5))
                            .tint(ProZipTheme.accent)

                        Toggle("加密文件名（仅 7Z）", isOn: $encryptHeaderNames)
                            .toggleStyle(.checkbox)
                            .font(.system(size: 11.5))
                            .tint(ProZipTheme.accent)
                            .disabled(format != .sevenZip)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.black.opacity(0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
                )
        )
    }

    // MARK: - Split Volume Block (doc/04 section 2.3)

    private var splitVolumeBlock: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Toggle(isOn: Binding(
                    get: { expansionState.isSplitEnabled },
                    set: { val in
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                            expansionState.isSplitEnabled = val
                        }
                    }
                )) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.split.2x1.fill")
                            .foregroundStyle(ProZipTheme.accent)
                        Text("分卷压缩（仅支持 ZIP 与 7Z）")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
                .toggleStyle(.switch)
                .tint(ProZipTheme.accent)
                .disabled(!format.supportsSplitVolumes)

                Spacer()

                if expansionState.isSplitEnabled {
                    Picker("", selection: $splitModeByCount) {
                        Text("按每卷大小").tag(false)
                        Text("按分卷总数").tag(true)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                }
            }

            if expansionState.isSplitEnabled {
                if !splitModeByCount {
                    HStack(spacing: 8) {
                        Text("每卷大小")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)

                        TextField("100", text: $splitSizeValue)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .frame(width: 72)

                        Picker("", selection: $splitSizeUnit) {
                            Text("MB").tag("MB")
                            Text("GB").tag("GB")
                        }
                        .labelsHidden()
                        .frame(width: 68)

                        Menu("常用大小预设") {
                            Button("100 MB（邮件/即时通讯附件）") {
                                splitSizeValue = "100"
                                splitSizeUnit = "MB"
                            }
                            Button("700 MB (CD-R)") {
                                splitSizeValue = "700"
                                splitSizeUnit = "MB"
                            }
                            Button("2048 MB（网盘单文件限制）") {
                                splitSizeValue = "2048"
                                splitSizeUnit = "MB"
                            }
                            Button("4096 MB (FAT32 上限)") {
                                splitSizeValue = "4096"
                                splitSizeUnit = "MB"
                            }
                        }
                        .font(.system(size: 11))

                        Spacer()
                    }
                } else {
                    Stepper("均分为 \(splitTotalParts) 卷（支持 2–999 卷，命名 .001 … .\(String(format: "%03d", splitTotalParts))）", value: $splitTotalParts, in: 2...999)
                        .font(.system(size: 11.5))
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.black.opacity(0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
                )
        )
    }

    // MARK: - Compatibility & Cleanup Options Block

    private var compatibilityAndCleanupBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("排除 macOS 辅助文件 (.DS_Store, __MACOSX, ._资源分叉)", isOn: $excludeMacJunk)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11.5))
                    .tint(ProZipTheme.accent)
                Spacer()
            }

            HStack {
                Toggle("Windows 文件名兼容修复（自动替换 \\ / : * ? \" < > | 等非法字符）", isOn: $windowsCompatibleNames)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11.5))
                    .tint(ProZipTheme.accent)

                Spacer()

                Button("预览修复列表…") {
                    appViewModel.isFilenameRepairPresented = true
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ProZipTheme.accentDeep)
            }

            HStack(spacing: 24) {
                Toggle("保持原始目录顶层结构", isOn: $keepParentDirectory)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11.5))
                    .tint(ProZipTheme.accent)

                Toggle("压缩完成后将源文件移至废纸篓", isOn: $moveSourcesToTrash)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11.5))
                    .tint(ProZipTheme.accent)

                Spacer()
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.black.opacity(0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
                )
        )
    }

    // MARK: - Validation Banner

    private func validationBanner(_ message: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))

            Text(message)
                .font(.system(size: 11.5, weight: .medium))

            Spacer(minLength: 0)
        }
        .foregroundStyle(Color(red: 0.78, green: 0.22, blue: 0.16))
        .padding(.horizontal, 44)
        .padding(.vertical, 7)
        .background(Color(red: 0.92, green: 0.26, blue: 0.23).opacity(0.08))
    }

    // MARK: - Footer Bar (44pt tall pill buttons, right aligned)

    private var footerBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(creationCardBorder)
                .frame(height: 1)

            HStack(spacing: 22) {
                Spacer(minLength: 0)

                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                        Text("取消")
                    }
                }
                .buttonStyle(
                    CreationFooterButtonStyle(
                        fill: Color(red: 0.92, green: 0.26, blue: 0.23),
                        foreground: .white
                    )
                )
                .keyboardShortcut(.cancelAction)

                Button {
                    submitCreation()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "archivebox.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("创建压缩包")
                    }
                }
                .buttonStyle(
                    CreationFooterButtonStyle(
                        fill: ProZipTheme.accent,
                        foreground: .white
                    )
                )
                .keyboardShortcut(.defaultAction)
                .disabled(archiveName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 44)
            .padding(.top, 12)
            .padding(.bottom, 14)
        }
        .background {
            ZStack {
                ZStack {
                    ProZipVariableBlurView(
                        direction: .bottomToTop,
                        material: colorScheme == .dark ? .hudWindow : .headerView
                    )
                    creationSheetBackground.opacity(0.84)
                }
                .allowsHitTesting(false)

                WindowDragArea()
            }
        }
    }

    // MARK: - Creation Layout Helpers

    private var creationSheetBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.110, green: 0.114, blue: 0.125)
            : Color.white
    }

    private var creationCardFill: Color {
        colorScheme == .dark
            ? Color(red: 0.157, green: 0.161, blue: 0.176)
            : Color.white
    }

    private var creationCardBorder: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.08)
    }

    private var creationInk: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.92)
            : Color(red: 0.07, green: 0.07, blue: 0.09)
    }

    private var creationMutedInk: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.56)
            : Color(red: 0.42, green: 0.42, blue: 0.46)
    }

    private var creationFieldFill: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.07)
            : Color(red: 0.949, green: 0.953, blue: 0.965)
    }

    private var effectiveStrength: CreationProfile.Strength {
        selectedPurpose == .smallest ? .maximum : strength
    }

    private var overviewFormatLabel: String {
        format.rawValue.uppercased()
    }

    private var destinationDisplayName: String {
        let last = outputDirectory.lastPathComponent
        return last.isEmpty ? outputDirectory.path : last
    }

    private func setDestinationMode(_ mode: String) {
        withAnimation(.easeInOut(duration: 0.16)) {
            outputDestinationMode = mode
            if mode == "desktop" {
                outputDirectory = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Desktop")
            } else if mode == "same", let first = selectedSourceItems.first {
                outputDirectory = first.deletingLastPathComponent()
            }
        }
    }

    private func selectFormat(_ candidate: ArchiveFormat) {
        guard selectedPurpose.allowedFormats.contains(candidate) else { return }
        withAnimation(.easeInOut(duration: 0.16)) {
            format = candidate
            preferences.setDefaultFormat(candidate, for: selectedPurpose)
            if candidate != .sevenZip {
                encryptHeaderNames = false
            }
            if candidate == .tar {
                expansionState.isPasswordEnabled = false
                expansionState.isSplitEnabled = false
            }
            validationErrorMessage = nil
        }
    }

    // MARK: - Helpers

    private func applyPurpose(_ purpose: CreationProfile.Purpose) {
        selectedPurpose = purpose
        preferences.defaultPurpose = purpose
        format = preferences.defaultFormat(for: purpose)
        strength = preferences.defaultStrength(for: purpose)

        switch purpose {
        case .general:
            excludeMacJunk = true
            windowsCompatibleNames = true
        case .windows:
            excludeMacJunk = true
            windowsCompatibleNames = true
        case .mac:
            excludeMacJunk = false
            windowsCompatibleNames = false
        case .unix:
            excludeMacJunk = true
            windowsCompatibleNames = false
            expansionState.isPasswordEnabled = false
            expansionState.isSplitEnabled = false
        case .smallest:
            excludeMacJunk = true
            windowsCompatibleNames = true
            strength = .maximum
        }
        validationErrorMessage = nil
    }

    private func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择压缩包保存位置"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            outputDirectory = url
            outputDestinationMode = "custom"
        }
    }

    private func submitCreation() {
        let sanitizedName = archiveName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitizedName.isEmpty, sanitizedName != ".", sanitizedName != "..", !sanitizedName.contains("/"), !sanitizedName.contains("\0") else {
            validationErrorMessage = "请输入有效的压缩包名称。"
            return
        }
        if expansionState.isPasswordEnabled, password != confirmationPassword {
            validationErrorMessage = "两次输入的密码不一致。"
            return
        }
        if expansionState.isPasswordEnabled && password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            validationErrorMessage = "请设置密码，或关闭密码保护。"
            return
        }

        var splitPlan: CreationProfile.SplitPlan?
        if expansionState.isSplitEnabled && format.supportsSplitVolumes {
            if splitModeByCount {
                splitPlan = .byCount(splitTotalParts)
            } else {
                let trimmedSplit = splitSizeValue.trimmingCharacters(in: .whitespacesAndNewlines)
                let mult: Double = splitSizeUnit == "GB" ? (1024 * 1024 * 1024) : (1024 * 1024)
                guard let numericSize = Double(trimmedSplit),
                      numericSize.isFinite,
                      numericSize > 0,
                      numericSize * mult <= Double(Int64.max) else {
                    validationErrorMessage = "请输入有效的每卷大小（大于 0 的数字）。"
                    return
                }
                let bytes = Int64((numericSize * mult).rounded())
                guard bytes >= 1024 * 1024 else {
                    validationErrorMessage = "每卷大小至少为 1 MB。"
                    return
                }
                splitPlan = .bySize(bytes)
            }
        }

        let profile = CreationProfile(
            purpose: selectedPurpose,
            format: format,
            strength: selectedPurpose == .smallest ? .maximum : strength,
            split: splitPlan,
            password: expansionState.isPasswordEnabled && !password.isEmpty ? password : nil,
            encryptHeaders: expansionState.isPasswordEnabled && format == .sevenZip && encryptHeaderNames,
            preserveMacMetadata: !excludeMacJunk,
            processorCount: preferences.processorCount > 0 ? preferences.processorCount : ProcessInfo.processInfo.activeProcessorCount,
            repairWindowsNames: windowsCompatibleNames
        )

        do {
            try profile.validate()
        } catch {
            validationErrorMessage = error.localizedDescription
            return
        }

        let targetURL = outputDirectory.appendingPathComponent("\(sanitizedName).\(format.defaultExtension)")

        var sources = selectedSourceItems
        if sources.isEmpty {
            let panel = NSOpenPanel()
            panel.title = "选择要压缩的文件或文件夹"
            panel.canChooseFiles = true
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = true
            if panel.runModal() == .OK {
                sources = panel.urls
            }
        }

        guard !sources.isEmpty else { return }
        let originalSources = appViewModel.creationOriginalSources ?? sources
        if !keepParentDirectory, sources.count == 1,
           (try? sources[0].resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])).map({ $0.isDirectory == true && $0.isSymbolicLink != true }) == true {
            do { sources = try FileManager.default.contentsOfDirectory(at: sources[0], includingPropertiesForKeys: nil) }
            catch { validationErrorMessage = error.localizedDescription; return }
        }
        let completion = appViewModel.creationCompletion
        appViewModel.creationCompletion = nil
        dismiss()
        appViewModel.createArchive(
            sources: sources,
            destinationURL: targetURL,
            profile: profile,
            moveSourcesToTrash: moveSourcesToTrash,
            savePasswordToBook: expansionState.isPasswordEnabled && savePasswordToBook,
            sourcesToTrash: originalSources,
            completion: completion
        )
    }
}

// MARK: - Creation Footer Button Style (hover brighten + press scale 0.97)

private struct CreationFooterButtonStyle: ButtonStyle {
    var fill: Color
    var foreground: Color

    func makeBody(configuration: Configuration) -> some View {
        CreationFooterButtonBody(
            configuration: configuration,
            fill: fill,
            foreground: foreground
        )
    }
}

private struct CreationFooterButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let fill: Color
    let foreground: Color

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(width: 212, height: 44)
            .background(
                Capsule(style: .continuous)
                    .fill(fill)
                    .overlay(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(isHovered ? 0.10 : 0))
                    )
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.8)
            )
            .shadow(color: fill.opacity(isHovered ? 0.30 : 0.16), radius: isHovered ? 10 : 6, y: 3)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(isEnabled ? 1.0 : 0.5)
            .animation(.spring(response: 0.24, dampingFraction: 0.78), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) {
                    isHovered = hovering
                }
            }
    }
}
