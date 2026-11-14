import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - ProZip Yellow-Green Theme & Brand Visuals

public enum ProZipTheme {
    /// Primary Yellow-Green (Chartreuse / Lime) accent color
    public static let accent = Color(red: 0.49, green: 0.78, blue: 0.08)          // #7DC714
    public static let accentPrimary = Color(red: 0.659, green: 0.878, blue: 0.00) // #A8E000
    public static let accentBright = Color(red: 0.722, green: 0.949, blue: 0.094) // #B8F218
    public static let accentDeep = Color(red: 0.35, green: 0.62, blue: 0.02)      // #599E05
    public static let accentSoft = Color(red: 0.55, green: 0.82, blue: 0.12).opacity(0.16)

    /// Dark ink text color used on bright yellow-green buttons (#141A05)
    public static let darkInk = Color(red: 0.078, green: 0.102, blue: 0.020)

    /// Mini window dark glass surface (#1A1B1E)
    public static let miniDarkSurface = Color(red: 0.102, green: 0.106, blue: 0.118)

    public static let brandGradient = LinearGradient(
        colors: [
            Color(red: 0.75, green: 0.95, blue: 0.24),
            Color(red: 0.52, green: 0.82, blue: 0.09),
            Color(red: 0.34, green: 0.64, blue: 0.04)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let pocketGradient = LinearGradient(
        colors: [
            Color(red: 0.82, green: 0.96, blue: 0.52),
            Color(red: 0.58, green: 0.85, blue: 0.22),
            Color(red: 0.44, green: 0.74, blue: 0.10)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Landing / welcome window ambient gradient (top-left warm peach glow -> neutral -> bottom-right soft ProZip lime glow).
    public static func landingGradient(for scheme: ColorScheme) -> LinearGradient {
        if scheme == .dark {
            return LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.10, blue: 0.10),
                    Color(red: 0.10, green: 0.11, blue: 0.12),
                    Color(red: 0.10, green: 0.13, blue: 0.09)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [
                Color(red: 0.996, green: 0.933, blue: 0.925), // #FEECEB / #FEE8E6 warm peach top-left
                Color(red: 0.996, green: 0.988, blue: 0.988),
                Color(red: 0.945, green: 0.976, blue: 0.910)  // soft #ECF7E0 bottom-right lime glow
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    public static func inspectorBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 32.0 / 255.0, green: 33.0 / 255.0, blue: 37.0 / 255.0)   // #202125
            : Color(red: 235.0 / 255.0, green: 231.0 / 255.0, blue: 241.0 / 255.0) // #EBE7F1
    }

    public static func inspectorCardBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 38.0 / 255.0, green: 39.0 / 255.0, blue: 43.0 / 255.0)   // #26272B
            : Color.white
    }

    public static func zebraRowBackground(index: Int, isSelected: Bool, scheme: ColorScheme) -> Color {
        if isSelected {
            return scheme == .dark ? Color.white.opacity(0.13) : Color.black.opacity(0.13) // #DDDCDD
        }
        if index.isMultiple(of: 2) {
            return Color.clear
        }
        return scheme == .dark
            ? Color.white.opacity(0.035)
            : Color.black.opacity(0.035) // #F4F5F5
    }
}

// MARK: - ProZip Resource Loader (Bundle + Workspace Fallback for Snapshot Tests)

public enum ProZipResourceLoader {
    private static let workspaceResourcesDir = "/Users/luochuhan/repo/prozip/Resources"

    /// Searches Bundle.main and `/Users/luochuhan/repo/prozip/Resources` for PNG/ICNS resources.
    public static func image(named name: String) -> NSImage? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let nsString = trimmed as NSString
        let ext = nsString.pathExtension
        let baseName = ext.isEmpty ? trimmed : nsString.deletingPathExtension

        // 1. Bundle.main.image(forResource:)
        if let img = Bundle.main.image(forResource: NSImage.Name(trimmed)) {
            return img
        }
        if baseName != trimmed, let img = Bundle.main.image(forResource: NSImage.Name(baseName)) {
            return img
        }

        // 2. Bundle.main.url(forResource:withExtension:)
        let resolvedExt = ext.isEmpty ? "png" : ext
        if let url = Bundle.main.url(forResource: baseName, withExtension: resolvedExt),
           let img = NSImage(contentsOf: url) {
            return img
        }
        if let url = Bundle.main.url(forResource: trimmed, withExtension: nil),
           let img = NSImage(contentsOf: url) {
            return img
        }

        // 3. Direct workspace Resources fallback for offscreen snapshot tests & debug runs
        let candidatePaths = [
            "\(workspaceResourcesDir)/\(baseName).\(resolvedExt)",
            "\(workspaceResourcesDir)/\(trimmed)",
            "\(workspaceResourcesDir)/\(baseName).png",
            "\(FileManager.default.currentDirectoryPath)/Resources/\(baseName).\(resolvedExt)",
            "\(FileManager.default.currentDirectoryPath)/Resources/\(trimmed)"
        ]
        for path in candidatePaths {
            if FileManager.default.fileExists(atPath: path),
               let img = NSImage(contentsOfFile: path) {
                return img
            }
        }

        return nil
    }

    public static func swiftUIImage(named name: String) -> Image? {
        guard let nsImage = image(named: name) else { return nil }
        return Image(nsImage: nsImage)
    }

    /// Returns the authentic macOS system icon for a file or folder.
    public static func systemFileIcon(for nameOrPath: String, isDirectory: Bool = false) -> NSImage {
        if isDirectory {
            return NSWorkspace.shared.icon(for: .folder)
        }
        let ext = (nameOrPath as NSString).pathExtension.lowercased()
        if ext == "zip" || ext == "7z" || ext == "rar" || ext == "tar" || ext == "gz" || ext == "xz" || ext == "bz2" {
            return NSWorkspace.shared.icon(for: .zip)
        }
        if !ext.isEmpty, let utType = UTType(filenameExtension: ext) {
            return NSWorkspace.shared.icon(for: utType)
        }
        return NSWorkspace.shared.icon(for: .data)
    }
}

// MARK: - ProZip Brand Icon ("P" replacing original "A" in Yellow-Green)

/// Sculpted 3D ribbon "P" icon matching the aesthetic of the original "A" icon,
/// using a pearlescent white outer P-arch and a vibrant yellow-green inner fold.
public struct ProZipBrandIcon: View {
    public var size: CGFloat
    public var showAppSquircle: Bool

    public init(size: CGFloat = 32, showAppSquircle: Bool = false) {
        self.size = size
        self.showAppSquircle = showAppSquircle
    }

    public var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height

            if showAppSquircle {
                let inset = w * 0.06
                let squircleRect = CGRect(x: inset, y: inset, width: w - inset * 2, height: h - inset * 2)
                let squirclePath = Path(roundedRect: squircleRect, cornerRadius: w * 0.225, style: .continuous)

                context.drawLayer { shadowCtx in
                    shadowCtx.addFilter(.shadow(color: .black.opacity(0.24), radius: w * 0.05, x: 0, y: w * 0.025))
                    shadowCtx.fill(
                        squirclePath,
                        with: .linearGradient(
                            Gradient(colors: [
                                Color(red: 0.97, green: 0.99, blue: 0.94),
                                Color(red: 0.90, green: 0.95, blue: 0.84)
                            ]),
                            startPoint: CGPoint(x: w * 0.2, y: h * 0.08),
                            endPoint: CGPoint(x: w * 0.8, y: h * 0.92)
                        )
                    )
                }

                context.stroke(
                    squirclePath,
                    with: .linearGradient(
                        Gradient(colors: [
                            Color.white.opacity(0.9),
                            Color(red: 0.55, green: 0.82, blue: 0.12).opacity(0.45)
                        ]),
                        startPoint: CGPoint(x: 0, y: 0),
                        endPoint: CGPoint(x: w, y: h)
                    ),
                    lineWidth: max(1, w * 0.015)
                )
            }

            let scale: CGFloat = showAppSquircle ? 0.72 : 0.92
            let offset = (1.0 - scale) * 0.5 * w

            context.drawLayer { layer in
                layer.translateBy(x: offset, y: offset)
                layer.scaleBy(x: scale, y: scale)

                // 1. Back / Inner Yellow-Green Ribbon Fold (the vibrant lower-right fold & inner loop of 'P')
                var greenFold = Path()
                greenFold.move(to: CGPoint(x: w * 0.34, y: h * 0.52))
                greenFold.addCurve(
                    to: CGPoint(x: w * 0.78, y: h * 0.36),
                    control1: CGPoint(x: w * 0.54, y: h * 0.52),
                    control2: CGPoint(x: w * 0.78, y: h * 0.48)
                )
                greenFold.addCurve(
                    to: CGPoint(x: w * 0.82, y: h * 0.62),
                    control1: CGPoint(x: w * 0.84, y: h * 0.44),
                    control2: CGPoint(x: w * 0.86, y: h * 0.55)
                )
                greenFold.addCurve(
                    to: CGPoint(x: w * 0.46, y: h * 0.86),
                    control1: CGPoint(x: w * 0.76, y: h * 0.74),
                    control2: CGPoint(x: w * 0.60, y: h * 0.86)
                )
                greenFold.addCurve(
                    to: CGPoint(x: w * 0.34, y: h * 0.68),
                    control1: CGPoint(x: w * 0.38, y: h * 0.86),
                    control2: CGPoint(x: w * 0.34, y: h * 0.78)
                )
                greenFold.closeSubpath()

                layer.fill(
                    greenFold,
                    with: .linearGradient(
                        Gradient(colors: [
                            Color(red: 0.84, green: 0.98, blue: 0.28), // Bright lime-yellow highlight
                            Color(red: 0.56, green: 0.86, blue: 0.10), // Vivid chartreuse
                            Color(red: 0.30, green: 0.58, blue: 0.02)  // Deep forest-lime shadow
                        ]),
                        startPoint: CGPoint(x: w * 0.36, y: h * 0.36),
                        endPoint: CGPoint(x: w * 0.82, y: h * 0.86)
                    )
                )

                // 2. Secondary Yellow-Green Accent Leaf / Diagonal Fold inside the P bowl
                var innerLeaf = Path()
                innerLeaf.move(to: CGPoint(x: w * 0.36, y: h * 0.30))
                innerLeaf.addCurve(
                    to: CGPoint(x: w * 0.70, y: h * 0.42),
                    control1: CGPoint(x: w * 0.52, y: h * 0.26),
                    control2: CGPoint(x: w * 0.68, y: h * 0.32)
                )
                innerLeaf.addCurve(
                    to: CGPoint(x: w * 0.42, y: h * 0.60),
                    control1: CGPoint(x: w * 0.72, y: h * 0.52),
                    control2: CGPoint(x: w * 0.56, y: h * 0.60)
                )
                innerLeaf.closeSubpath()

                layer.fill(
                    innerLeaf,
                    with: .linearGradient(
                        Gradient(colors: [
                            Color(red: 0.92, green: 1.0, blue: 0.42),
                            Color(red: 0.62, green: 0.89, blue: 0.14)
                        ]),
                        startPoint: CGPoint(x: w * 0.38, y: h * 0.28),
                        endPoint: CGPoint(x: w * 0.68, y: h * 0.58)
                    )
                )

                // 3. Main Pearlescent White 3D "P" Arch Ribbon (replaces original 'A' white arch)
                var pOuter = Path()
                pOuter.move(to: CGPoint(x: w * 0.16, y: h * 0.80))
                pOuter.addLine(to: CGPoint(x: w * 0.16, y: h * 0.34))
                pOuter.addCurve(
                    to: CGPoint(x: w * 0.48, y: h * 0.10),
                    control1: CGPoint(x: w * 0.16, y: h * 0.16),
                    control2: CGPoint(x: w * 0.28, y: h * 0.10)
                )
                pOuter.addCurve(
                    to: CGPoint(x: w * 0.84, y: h * 0.36),
                    control1: CGPoint(x: w * 0.70, y: h * 0.10),
                    control2: CGPoint(x: w * 0.84, y: h * 0.20)
                )
                pOuter.addCurve(
                    to: CGPoint(x: w * 0.48, y: h * 0.60),
                    control1: CGPoint(x: w * 0.84, y: h * 0.51),
                    control2: CGPoint(x: w * 0.70, y: h * 0.60)
                )
                pOuter.addLine(to: CGPoint(x: w * 0.38, y: h * 0.60))
                pOuter.addLine(to: CGPoint(x: w * 0.38, y: h * 0.44))
                pOuter.addLine(to: CGPoint(x: w * 0.47, y: h * 0.44))
                pOuter.addCurve(
                    to: CGPoint(x: w * 0.63, y: h * 0.35),
                    control1: CGPoint(x: w * 0.57, y: h * 0.44),
                    control2: CGPoint(x: w * 0.63, y: h * 0.40)
                )
                pOuter.addCurve(
                    to: CGPoint(x: w * 0.47, y: h * 0.26),
                    control1: CGPoint(x: w * 0.63, y: h * 0.29),
                    control2: CGPoint(x: w * 0.57, y: h * 0.26)
                )
                pOuter.addCurve(
                    to: CGPoint(x: w * 0.37, y: h * 0.36),
                    control1: CGPoint(x: w * 0.40, y: h * 0.26),
                    control2: CGPoint(x: w * 0.37, y: h * 0.30)
                )
                pOuter.addLine(to: CGPoint(x: w * 0.37, y: h * 0.80))
                pOuter.addCurve(
                    to: CGPoint(x: w * 0.16, y: h * 0.80),
                    control1: CGPoint(x: w * 0.37, y: h * 0.90),
                    control2: CGPoint(x: w * 0.16, y: h * 0.90)
                )
                pOuter.closeSubpath()

                layer.drawLayer { pShadow in
                    pShadow.addFilter(.shadow(color: Color.black.opacity(0.18), radius: w * 0.04, x: 0, y: w * 0.02))
                    pShadow.fill(
                        pOuter,
                        with: .linearGradient(
                            Gradient(colors: [
                                Color.white,
                                Color(red: 0.95, green: 0.97, blue: 0.93),
                                Color(red: 0.87, green: 0.90, blue: 0.85)
                            ]),
                            startPoint: CGPoint(x: w * 0.2, y: h * 0.1),
                            endPoint: CGPoint(x: w * 0.8, y: h * 0.88)
                        )
                    )
                }

                layer.stroke(
                    pOuter,
                    with: .color(Color.white.opacity(0.85)),
                    lineWidth: max(0.8, w * 0.014)
                )
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Inspector Archive Pocket Illustration (Yellow-Green version of workspace.png pocket)

public struct ProZipArchivePocketGraphic: View {
    public var size: CGFloat

    public init(size: CGFloat = 112) {
        self.size = size
    }

    public var body: some View {
        ZStack {
            // Back pocket rim
            RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.72, green: 0.91, blue: 0.38).opacity(0.55),
                            Color(red: 0.49, green: 0.78, blue: 0.08).opacity(0.75)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size * 0.82, height: size * 0.68)
                .offset(y: size * 0.04)

            // Left tilted document card inside pocket
            RoundedRectangle(cornerRadius: size * 0.07, style: .continuous)
                .fill(Color.white.opacity(0.92))
                .frame(width: size * 0.34, height: size * 0.42)
                .overlay(
                    Image(systemName: "photo")
                        .font(.system(size: size * 0.13, weight: .semibold))
                        .foregroundStyle(ProZipTheme.accent.opacity(0.7))
                )
                .rotationEffect(.degrees(-10))
                .offset(x: -size * 0.15, y: -size * 0.14)
                .shadow(color: .black.opacity(0.08), radius: 3, y: 1)

            // Right tilted document card inside pocket
            RoundedRectangle(cornerRadius: size * 0.07, style: .continuous)
                .fill(Color.white.opacity(0.92))
                .frame(width: size * 0.34, height: size * 0.42)
                .overlay(
                    Image(systemName: "waveform")
                        .font(.system(size: size * 0.13, weight: .semibold))
                        .foregroundStyle(ProZipTheme.accentDeep.opacity(0.7))
                )
                .rotationEffect(.degrees(10))
                .offset(x: size * 0.15, y: -size * 0.13)
                .shadow(color: .black.opacity(0.08), radius: 3, y: 1)

            // Center front document card with lines
            RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                .fill(Color.white)
                .frame(width: size * 0.38, height: size * 0.46)
                .overlay(
                    VStack(alignment: .leading, spacing: size * 0.045) {
                        ForEach(0..<4, id: \.self) { idx in
                            Capsule()
                                .fill(Color.secondary.opacity(0.32))
                                .frame(width: idx == 3 ? size * 0.16 : size * 0.24, height: size * 0.028)
                        }
                    }
                    .offset(y: -size * 0.04)
                )
                .offset(y: -size * 0.18)
                .shadow(color: .black.opacity(0.10), radius: 4, y: 2)

            // Front translucent frosted yellow-green pocket body
            RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                .fill(ProZipTheme.pocketGradient)
                .frame(width: size * 0.84, height: size * 0.56)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                        .stroke(Color.white.opacity(0.65), lineWidth: 1.5)
                )
                .offset(y: size * 0.10)
                .shadow(color: ProZipTheme.accentDeep.opacity(0.28), radius: 8, y: 5)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Runtime & Build-Time App Icon Renderer

public enum ProZipIconRenderer {
    @MainActor
    public static func makeAppIconImage(size: CGFloat = 512) -> NSImage {
        let view = ProZipBrandIcon(size: size, showAppSquircle: true)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1.0
        return renderer.nsImage ?? NSImage(size: NSSize(width: size, height: size))
    }

    @MainActor
    public static func applyApplicationIcon() {
        let img = makeAppIconImage(size: 512)
        NSApplication.shared.applicationIconImage = img
    }
}

// MARK: - Custom 5-Stop Yellow-Green Compression Strength Slider (matching compression.png)

public struct ProZipStrengthSlider: View {
    @Binding public var strength: CreationProfile.Strength
    public var isDisabled: Bool
    public var thumbDiameter: CGFloat
    public var trackHeight: CGFloat
    public var rowSpacing: CGFloat
    public var subtitleFontSize: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    public init(
        strength: Binding<CreationProfile.Strength>,
        isDisabled: Bool = false,
        thumbDiameter: CGFloat = 22,
        trackHeight: CGFloat = 14,
        rowSpacing: CGFloat = 8,
        subtitleFontSize: CGFloat = 12
    ) {
        self._strength = strength
        self.isDisabled = isDisabled
        self.thumbDiameter = thumbDiameter
        self.trackHeight = trackHeight
        self.rowSpacing = rowSpacing
        self.subtitleFontSize = subtitleFontSize
    }

    /// Maps strength to the 5 visual stops (0..4) matching ArcZip 1.2.3's compression.png
    /// where `.balanced` sits at the exact center stop (stop 2 = 50%).
    private var visualStopIndex: Int {
        switch strength {
        case .store: return 0
        case .fastest: return 1
        case .fast: return 1
        case .balanced: return 2
        case .maximum: return 4
        }
    }

    private func strengthForVisualStop(_ step: Int) -> CreationProfile.Strength {
        switch step {
        case 0: return .store
        case 1: return .fast
        case 2: return .balanced
        case 3: return .balanced
        default: return .maximum
        }
    }

    public var body: some View {
        let dotSize: CGFloat = thumbDiameter >= 26 ? 4 : 3
        VStack(spacing: rowSpacing) {
            GeometryReader { geo in
                let totalWidth = max(1, geo.size.width)
                let usableWidth = max(1, totalWidth - thumbDiameter)
                let fraction = CGFloat(visualStopIndex) / 4.0
                let thumbCenterX = (thumbDiameter / 2.0) + usableWidth * fraction

                ZStack(alignment: .leading) {
                    // Track background (#EDEEF1 light / white 12% dark)
                    Capsule()
                        .fill(
                            colorScheme == .dark
                                ? Color.white.opacity(0.12)
                                : Color(red: 237.0 / 255.0, green: 238.0 / 255.0, blue: 241.0 / 255.0)
                        )
                        .frame(height: trackHeight)

                    // Solid yellow-green active fill track
                    Capsule()
                        .fill(isDisabled ? Color.secondary.opacity(0.35) : ProZipTheme.accent)
                        .frame(width: max(trackHeight, thumbCenterX + 2), height: trackHeight)

                    // 5 stop dots
                    HStack(spacing: 0) {
                        ForEach(0..<5, id: \.self) { idx in
                            Circle()
                                .fill(idx <= visualStopIndex ? Color.white.opacity(0.92) : Color.secondary.opacity(0.45))
                                .frame(width: dotSize, height: dotSize)
                            if idx < 4 {
                                Spacer()
                            }
                        }
                    }
                    .padding(.horizontal, thumbDiameter / 2.0)

                    // White round thumb
                    Circle()
                        .fill(Color.white)
                        .frame(width: thumbDiameter, height: thumbDiameter)
                        .shadow(color: .black.opacity(0.16), radius: 3, y: 1)
                        .overlay(
                            Circle()
                                .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
                        )
                        .offset(x: thumbCenterX - (thumbDiameter / 2.0))
                }
                .frame(height: thumbDiameter)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard !isDisabled else { return }
                            let clamped = min(max(0, value.location.x - thumbDiameter / 2.0), usableWidth)
                            let step = Int(((clamped / usableWidth) * 4.0).rounded())
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.78)) {
                                strength = strengthForVisualStop(step)
                            }
                        }
                )
            }
            .frame(height: thumbDiameter)

            // 3-column labels matching compression.png ("更快" left, active title center, "更小" right)
            ZStack {
                HStack {
                    Text("更快")
                        .font(.system(size: 12, weight: visualStopIndex <= 1 ? .semibold : .regular))
                        .foregroundStyle(visualStopIndex <= 1 ? ProZipTheme.accent : Color.secondary)
                    Spacer()
                    Text("更小")
                        .font(.system(size: 12, weight: visualStopIndex >= 4 ? .semibold : .regular))
                        .foregroundStyle(visualStopIndex >= 4 ? ProZipTheme.accent : Color.secondary)
                }

                Text(strength.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ProZipTheme.accent)
            }

            Text(strength.subtitle)
                .font(.system(size: subtitleFontSize))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .opacity(isDisabled ? 0.55 : 1.0)
    }
}

// MARK: - Keyboard Shortcut Keycap Badge (FoldspaceShortcutKeycap)

public struct FoldspaceShortcutKeycap: View {
    public enum Tone: Sendable {
        case glassLight
        case glassDark
        case onAccent
        case subtle
    }

    public let text: String
    public var tone: Tone

    public init(_ text: String, tone: Tone = .glassLight) {
        self.text = text
        self.tone = tone
    }

    public var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 5.5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .stroke(borderColor, lineWidth: 0.5)
            )
    }

    private var foregroundColor: Color {
        switch tone {
        case .glassLight:
            return Color(red: 0.30, green: 0.30, blue: 0.32)
        case .glassDark:
            return Color.white.opacity(0.88)
        case .onAccent:
            return ProZipTheme.darkInk
        case .subtle:
            return Color.secondary
        }
    }

    private var backgroundColor: Color {
        switch tone {
        case .glassLight:
            return Color.white.opacity(0.92)
        case .glassDark:
            return Color.white.opacity(0.14)
        case .onAccent:
            return ProZipTheme.darkInk.opacity(0.13)
        case .subtle:
            return Color.primary.opacity(0.07)
        }
    }

    private var borderColor: Color {
        switch tone {
        case .glassLight:
            return Color.black.opacity(0.06)
        case .glassDark:
            return Color.white.opacity(0.18)
        case .onAccent:
            return ProZipTheme.darkInk.opacity(0.16)
        case .subtle:
            return Color.primary.opacity(0.10)
        }
    }
}

// MARK: - FoldspaceButton (ArcZip 1.2.3 Interactive Button with Continuous Hover Glow & Spring Press)

public enum FoldspaceButtonRole: Sendable {
    case primary
    case secondary
    case glass
    case subtle
    case destructive
}

public enum FoldspaceButtonSize: Sendable {
    case compact
    case regular
    case large

    public var horizontalPadding: CGFloat {
        switch self {
        case .compact: return 9
        case .regular: return 12
        case .large: return 16
        }
    }

    public var verticalPadding: CGFloat {
        switch self {
        case .compact: return 4.5
        case .regular: return 6.5
        case .large: return 9
        }
    }

    public var fontSize: CGFloat {
        switch self {
        case .compact: return 12
        case .regular: return 13
        case .large: return 14
        }
    }
}

public enum FoldspaceButtonShape: Sendable {
    case capsule
    case rounded(CGFloat)
}

public struct FoldspaceButtonStyle: ButtonStyle {
    public var pressScale: CGFloat

    public init(pressScale: CGFloat = 0.97) {
        self.pressScale = pressScale
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressScale : 1.0)
            .brightness(configuration.isPressed ? -0.02 : 0)
            .animation(.spring(response: 0.22, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

public struct FoldspaceButton: View {
    public let title: String
    public var icon: String?
    public var shortcut: String?
    public var role: FoldspaceButtonRole
    public var size: FoldspaceButtonSize
    public var shape: FoldspaceButtonShape
    public var isDisabled: Bool
    public let action: () -> Void

    @State private var isHovered: Bool = false
    @State private var hoverPoint: CGPoint = .zero
    @Environment(\.colorScheme) private var colorScheme

    public init(
        title: String,
        icon: String? = nil,
        shortcut: String? = nil,
        role: FoldspaceButtonRole = .secondary,
        size: FoldspaceButtonSize = .regular,
        shape: FoldspaceButtonShape = .capsule,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.shortcut = shortcut
        self.role = role
        self.size = size
        self.shape = shape
        self.isDisabled = isDisabled
        self.action = action
    }

    public init(
        _ title: String,
        systemImage: String? = nil,
        shortcutBadge: String? = nil,
        role: FoldspaceButtonRole = .secondary,
        size: FoldspaceButtonSize = .regular,
        shape: FoldspaceButtonShape = .capsule,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.init(
            title: title,
            icon: systemImage,
            shortcut: shortcutBadge,
            role: role,
            size: size,
            shape: shape,
            isDisabled: isDisabled,
            action: action
        )
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: size.fontSize - 0.5, weight: role == .primary ? .semibold : .medium))
                }

                Text(title)
                    .font(.system(size: size.fontSize, weight: role == .primary ? .semibold : .medium))
                    .lineLimit(1)

                if let shortcut {
                    FoldspaceShortcutKeycap(shortcut, tone: keycapTone)
                }
            }
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .foregroundStyle(foregroundStyle)
            .background(backgroundView)
            .overlay(borderView)
            .contentShape(Rectangle())
        }
        .buttonStyle(FoldspaceButtonStyle(pressScale: 0.97))
        .disabled(isDisabled)
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                hoverPoint = location
                if !isHovered {
                    withAnimation(.easeOut(duration: 0.15)) {
                        isHovered = true
                    }
                }
            case .ended:
                withAnimation(.easeOut(duration: 0.18)) {
                    isHovered = false
                }
            }
        }
    }

    private var keycapTone: FoldspaceShortcutKeycap.Tone {
        if role == .primary {
            return .onAccent
        }
        return colorScheme == .dark ? .glassDark : .glassLight
    }

    private var foregroundStyle: Color {
        if isDisabled {
            return colorScheme == .dark
                ? Color.white.opacity(0.36)
                : Color(red: 0.52, green: 0.52, blue: 0.54)
        }
        switch role {
        case .primary:
            return ProZipTheme.darkInk
        case .destructive:
            return Color.red
        case .secondary, .glass, .subtle:
            return colorScheme == .dark ? Color.white.opacity(0.92) : Color(red: 0.11, green: 0.11, blue: 0.12)
        }
    }

    @ViewBuilder
    private var backgroundView: some View {
        let baseFill: Color = {
            switch role {
            case .primary:
                return isDisabled ? Color.secondary.opacity(0.25) : ProZipTheme.accentBright
            case .secondary:
                if colorScheme == .dark {
                    return Color.white.opacity(isHovered ? 0.14 : 0.08)
                } else {
                    return Color.white.opacity(isHovered ? 0.65 : 0.01)
                }
            case .glass:
                if colorScheme == .dark {
                    return Color.white.opacity(isHovered ? 0.16 : 0.10)
                } else {
                    return Color.white.opacity(isHovered ? 0.82 : 0.68)
                }
            case .subtle:
                return isHovered ? Color.primary.opacity(0.08) : Color.clear
            case .destructive:
                return Color.red.opacity(isHovered ? 0.18 : 0.12)
            }
        }()

        ZStack {
            switch shape {
            case .capsule:
                Capsule()
                    .fill(baseFill)
                if isHovered && !isDisabled {
                    Capsule()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.16 : 0.35),
                                    Color.clear
                                ],
                                center: UnitPoint(
                                    x: min(1, max(0, hoverPoint.x / 110.0)),
                                    y: min(1, max(0, hoverPoint.y / 34.0))
                                ),
                                startRadius: 2,
                                endRadius: 56
                            )
                        )
                }
            case .rounded(let radius):
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(baseFill)
                if isHovered && !isDisabled {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.16 : 0.35),
                                    Color.clear
                                ],
                                center: UnitPoint(
                                    x: min(1, max(0, hoverPoint.x / 110.0)),
                                    y: min(1, max(0, hoverPoint.y / 34.0))
                                ),
                                startRadius: 2,
                                endRadius: 56
                            )
                        )
                }
            }
        }
    }

    @ViewBuilder
    private var borderView: some View {
        let strokeColor: Color = {
            guard role == .glass || (isHovered && !isDisabled && role != .subtle) else {
                return Color.clear
            }
            return colorScheme == .dark ? Color.white.opacity(0.18) : Color.white.opacity(0.55)
        }()

        switch shape {
        case .capsule:
            Capsule()
                .stroke(strokeColor, lineWidth: 0.8)
        case .rounded(let radius):
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(strokeColor, lineWidth: 0.8)
        }
    }
}

// MARK: - FlowOrbitControl (Prominent Liquid Glass Primary Action Button)

public typealias ProZipFlowOrbitButton = FlowOrbitControl

public struct FlowOrbitControl: View {
    public enum AppearanceMode: Sendable {
        /// Vibrant ProZip yellow-green Liquid Glass prominent button
        case accentOrbit
        /// Translucent regular Liquid Glass capsule button
        case glassPrimary
    }

    public let title: String
    public var icon: String?
    public var shortcut: String?
    public var isEnabled: Bool
    public var mode: AppearanceMode
    public var minimumSize: CGSize?
    public let action: () -> Void

    @State private var isHovered: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    public init(
        title: String,
        icon: String? = "arrow.up.square",
        shortcut: String? = "⏎",
        isEnabled: Bool = true,
        mode: AppearanceMode = .accentOrbit,
        minimumSize: CGSize? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.shortcut = shortcut
        self.isEnabled = isEnabled
        self.mode = mode
        self.minimumSize = minimumSize
        self.action = action
    }

    public init(
        _ title: String,
        systemImage: String? = "arrow.up.square",
        shortcutBadge: String? = "⏎",
        isEnabled: Bool = true,
        mode: AppearanceMode = .accentOrbit,
        minimumSize: CGSize? = nil,
        action: @escaping () -> Void
    ) {
        self.init(
            title: title,
            icon: systemImage,
            shortcut: shortcutBadge,
            isEnabled: isEnabled,
            mode: mode,
            minimumSize: minimumSize,
            action: action
        )
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                }

                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)

                if let shortcut {
                    FoldspaceShortcutKeycap(
                        shortcut,
                        tone: mode == .accentOrbit ? .onAccent : (colorScheme == .dark ? .glassDark : .glassLight)
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6.5)
            .frame(minWidth: minimumSize?.width, minHeight: minimumSize?.height)
            .foregroundStyle(foregroundColor)
            .background(innerFillCapsule)
            .contentShape(Capsule())
        }
        .buttonStyle(ProZipProminentGlassPressStyle())
        .proZipLiquidGlassCapsule(
            interactive: isEnabled,
            tint: mode == .accentOrbit && isEnabled ? ProZipTheme.accent : nil
        )
        .shadow(
            color: mode == .accentOrbit && isEnabled
                ? ProZipTheme.accentDeep.opacity(isHovered ? 0.30 : 0.18)
                : .clear,
            radius: isHovered ? 8 : 5,
            x: 0,
            y: 2
        )
        .disabled(!isEnabled)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
                isHovered = hovering
            }
        }
    }

    private var foregroundColor: Color {
        if !isEnabled {
            return Color.secondary.opacity(0.55)
        }
        switch mode {
        case .accentOrbit:
            return Color.white
        case .glassPrimary:
            return colorScheme == .dark ? Color.white : Color(red: 0.10, green: 0.10, blue: 0.11)
        }
    }

    @ViewBuilder
    private var innerFillCapsule: some View {
        switch mode {
        case .accentOrbit:
            Capsule()
                .fill(
                    isEnabled
                        ? LinearGradient(
                            colors: [
                                isHovered ? Color(red: 0.56, green: 0.85, blue: 0.12).opacity(0.74) : ProZipTheme.accent.opacity(0.68),
                                isHovered ? ProZipTheme.accent.opacity(0.78) : ProZipTheme.accentDeep.opacity(0.64)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        : LinearGradient(
                            colors: [Color.secondary.opacity(0.22), Color.secondary.opacity(0.18)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                )
                .overlay(
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(isEnabled ? 0.42 : 0.12), Color.white.opacity(0.10)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.8
                        )
                )
                .padding(1.2)
        case .glassPrimary:
            Capsule()
                .fill(
                    isHovered && isEnabled
                        ? (colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06))
                        : Color.clear
                )
        }
    }
}

private struct ProZipProminentGlassPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - ArcZipDialogButton (Roles & Sizes with 8pt Corner Radius & Top Specular Rim)

public enum ArcZipDialogButtonRole: Sendable {
    case primary
    case secondary
    case destructive
    case tertiary

    public static let confirm: Self = .primary
    public static let cancel: Self = .secondary
}

public enum ArcZipDialogButtonSize: Sendable {
    case compact
    case regular
    case large

    public var height: CGFloat {
        switch self {
        case .compact: return 26
        case .regular: return 32
        case .large: return 38
        }
    }

    public var horizontalPadding: CGFloat {
        switch self {
        case .compact: return 12
        case .regular: return 16
        case .large: return 22
        }
    }

    public var fontSize: CGFloat {
        switch self {
        case .compact: return 12
        case .regular: return 13
        case .large: return 14
        }
    }
}

public struct ArcZipDialogButtonStyle: ButtonStyle {
    public var role: ArcZipDialogButtonRole
    public var size: ArcZipDialogButtonSize
    public var isFullWidth: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    public init(
        role: ArcZipDialogButtonRole = .primary,
        size: ArcZipDialogButtonSize = .regular,
        isFullWidth: Bool = false
    ) {
        self.role = role
        self.size = size
        self.isFullWidth = isFullWidth
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size.fontSize, weight: role == .primary ? .semibold : .medium))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, size.horizontalPadding)
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .frame(height: size.height)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(backgroundFill(isPressed: configuration.isPressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(topBorderOpacity),
                                Color.white.opacity(0.04)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.8
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.78), value: configuration.isPressed)
            .opacity(isEnabled ? 1.0 : 0.5)
    }

    private var foregroundColor: Color {
        switch role {
        case .primary:
            return ProZipTheme.darkInk
        case .destructive:
            return Color.white
        case .secondary:
            return colorScheme == .dark ? Color.white.opacity(0.92) : Color.primary
        case .tertiary:
            return Color.secondary
        }
    }

    private func backgroundFill(isPressed: Bool) -> AnyShapeStyle {
        switch role {
        case .primary:
            let top = isPressed ? ProZipTheme.accentPrimary : ProZipTheme.accentBright
            let bot = isPressed ? ProZipTheme.accent : ProZipTheme.accentPrimary
            return AnyShapeStyle(LinearGradient(colors: [top, bot], startPoint: .top, endPoint: .bottom))
        case .destructive:
            let c = isPressed ? Color(red: 0.82, green: 0.20, blue: 0.18) : Color(red: 0.92, green: 0.26, blue: 0.23)
            return AnyShapeStyle(c)
        case .secondary:
            let base = colorScheme == .dark
                ? Color.white.opacity(isPressed ? 0.15 : 0.09)
                : Color.black.opacity(isPressed ? 0.09 : 0.05)
            return AnyShapeStyle(base)
        case .tertiary:
            return AnyShapeStyle(isPressed ? Color.primary.opacity(0.06) : Color.clear)
        }
    }

    private var topBorderOpacity: Double {
        switch role {
        case .primary: return 0.45
        case .destructive: return 0.30
        case .secondary: return colorScheme == .dark ? 0.18 : 0.35
        case .tertiary: return 0.0
        }
    }
}

public struct ArcZipDialogButton: View {
    public typealias Role = ArcZipDialogButtonRole
    public typealias Size = ArcZipDialogButtonSize

    public let title: String
    public var icon: String?
    public var role: ArcZipDialogButtonRole
    public var size: ArcZipDialogButtonSize
    public var isFullWidth: Bool
    public let action: () -> Void

    @State private var isHovered: Bool = false

    public init(
        _ title: String,
        icon: String? = nil,
        role: ArcZipDialogButtonRole = .primary,
        size: ArcZipDialogButtonSize = .regular,
        isFullWidth: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.role = role
        self.size = size
        self.isFullWidth = isFullWidth
        self.action = action
    }

    public init(
        title: String,
        icon: String? = nil,
        role: ArcZipDialogButtonRole = .primary,
        size: ArcZipDialogButtonSize = .regular,
        isFullWidth: Bool = false,
        action: @escaping () -> Void
    ) {
        self.init(title, icon: icon, role: role, size: size, isFullWidth: isFullWidth, action: action)
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: size.fontSize - 1, weight: .semibold))
                }
                Text(title)
            }
        }
        .buttonStyle(ArcZipDialogButtonStyle(role: role, size: size, isFullWidth: isFullWidth))
        .brightness(isHovered ? 0.03 : 0)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - ArcZipMiniRingShape, ArcZipMiniRoundActionButton & ArcZipMiniPinButtonStyle

public struct ArcZipMiniRingShape: InsettableShape {
    public var insetAmount: CGFloat = 0

    public init(insetAmount: CGFloat = 0) {
        self.insetAmount = insetAmount
    }

    public func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        return Path(ellipseIn: insetRect)
    }

    public func inset(by amount: CGFloat) -> ArcZipMiniRingShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

public struct ArcZipMiniRoundActionButton: View {
    public let icon: String
    public var tooltip: String
    public var size: CGFloat
    public var tintColor: Color?
    public var fillTint: Color?
    public let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    public init(
        icon: String,
        tooltip: String = "",
        size: CGFloat = 28,
        tintColor: Color? = nil,
        fillTint: Color? = nil,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.tooltip = tooltip
        self.size = size
        self.tintColor = tintColor
        self.fillTint = fillTint
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.40, weight: .semibold))
                .foregroundStyle(
                    tintColor ?? (colorScheme == .dark ? Color.white.opacity(0.90) : Color(red: 0.11, green: 0.12, blue: 0.14))
                )
                .frame(width: size, height: size)
        }
        .buttonStyle(ProZipGlassSegmentButtonStyle(shape: .circle, baseTint: fillTint))
        .proZipLiquidGlassCircle(interactive: true, tint: fillTint?.opacity(0.18))
        .help(tooltip)
        .accessibilityIdentifier(icon)
        .accessibilityLabel(tooltip.isEmpty ? icon : tooltip)
    }
}

public struct ArcZipMiniPinButtonStyle: ButtonStyle {
    public var isPinned: Bool
    public var size: CGFloat
    public var isColored: Bool

    @State private var isHovered: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    private static let skyBlue = Color(red: 0.31, green: 0.67, blue: 0.98)

    public init(isPinned: Bool, size: CGFloat = 28, isColored: Bool = false) {
        self.isPinned = isPinned
        self.size = size
        self.isColored = isColored
    }

    public func makeBody(configuration: Configuration) -> some View {
        ZStack {
            Circle()
                .fill(innerHoverOrStateFill(isPressed: configuration.isPressed))
                .frame(width: size, height: size)

            configuration.label
                .font(.system(size: size * 0.40, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: size, height: size)
        }
        .contentShape(Circle())
        .proZipLiquidGlassCircle(
            interactive: true,
            tint: isPinned ? Self.skyBlue.opacity(0.55) : (isColored ? Self.skyBlue.opacity(0.18) : nil)
        )
        .overlay {
            if isPinned {
                Circle()
                    .strokeBorder(Self.skyBlue.opacity(0.82), lineWidth: 1.5)
                    .frame(width: size + 5, height: size + 5)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
        .animation(.spring(response: 0.24, dampingFraction: 0.78), value: isPinned)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
                isHovered = hovering
            }
        }
    }

    private func innerHoverOrStateFill(isPressed: Bool) -> Color {
        if isPinned {
            return Self.skyBlue.opacity(isPressed ? 0.88 : (isHovered ? 0.82 : 0.74))
        }
        if isColored {
            return Self.skyBlue.opacity(isPressed ? 0.28 : (isHovered ? 0.22 : 0.12))
        }
        if colorScheme == .dark {
            return Color.white.opacity(isPressed ? 0.16 : (isHovered ? 0.10 : 0.0))
        }
        return Color.black.opacity(isPressed ? 0.12 : (isHovered ? 0.075 : 0.0))
    }

    private var iconColor: Color {
        if isPinned {
            return .white
        }
        if isColored {
            return Self.skyBlue
        }
        return colorScheme == .dark ? Color.white.opacity(0.90) : Color(red: 0.11, green: 0.12, blue: 0.14)
    }
}

public struct ArcZipMiniPinButton: View {
    @Binding public var isPinned: Bool
    public var size: CGFloat
    public var isColored: Bool
    public var tooltip: String?

    public init(isPinned: Binding<Bool>, size: CGFloat = 34, isColored: Bool = false, tooltip: String? = nil) {
        self._isPinned = isPinned
        self.size = size
        self.isColored = isColored
        self.tooltip = tooltip
    }

    public var body: some View {
        let resolvedTooltip = tooltip ?? (isPinned ? "取消窗口置顶" : "窗口置顶")
        Button {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.72)) {
                isPinned.toggle()
            }
        } label: {
            Image(systemName: isPinned ? "pin.fill" : "pin")
        }
        .buttonStyle(ArcZipMiniPinButtonStyle(isPinned: isPinned, size: size, isColored: isColored))
        .help(resolvedTooltip)
        .accessibilityLabel(resolvedTooltip)
    }
}

// MARK: - ArcZipSettingsNativeGlassButton (Settings Row Glass Button, height: 26, cornerRadius: 6)

public struct ArcZipSettingsNativeGlassButtonStyle: ButtonStyle {
    @State private var isHovered: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        let fillOpacity: Double = {
            if configuration.isPressed { return 0.16 }
            return isHovered ? 0.13 : 0.08
        }()

        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.92) : Color.primary)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        colorScheme == .dark
                            ? Color.white.opacity(fillOpacity)
                            : Color.black.opacity(isHovered ? 0.08 : 0.045)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        colorScheme == .dark
                            ? Color.white.opacity(0.14)
                            : Color.black.opacity(0.12),
                        lineWidth: 0.8
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.20, dampingFraction: 0.78), value: configuration.isPressed)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.14)) {
                    isHovered = hovering
                }
            }
    }
}

public struct ArcZipSettingsNativeGlassButton: View {
    public let title: String
    public var icon: String?
    public let action: () -> Void

    public init(_ title: String, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    public init(title: String, icon: String? = nil, action: @escaping () -> Void) {
        self.init(title, icon: icon, action: action)
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .medium))
                }
                Text(title)
            }
        }
        .buttonStyle(ArcZipSettingsNativeGlassButtonStyle())
    }
}

// MARK: - MainWindowTrafficLightsHoverView (#FF5F57, #FEBC2E, #28C840, 12x12pt, spacing 8pt)

public struct MainWindowTrafficLightsHoverView: View {
    public var onClose: (() -> Void)?
    public var onMinimize: (() -> Void)?
    public var onZoom: (() -> Void)?

    @State private var isHovered: Bool = false

    public init(
        onClose: (() -> Void)? = nil,
        onMinimize: (() -> Void)? = nil,
        onZoom: (() -> Void)? = nil
    ) {
        self.onClose = onClose
        self.onMinimize = onMinimize
        self.onZoom = onZoom
    }

    public var body: some View {
        HStack(spacing: 8) {
            dotButton(
                color: Color(red: 1.0, green: 0.373, blue: 0.341),   // #FF5F57
                border: Color(red: 0.88, green: 0.27, blue: 0.25),
                symbol: "xmark"
            ) {
                if let onClose {
                    onClose()
                } else {
                    NSApp.keyWindow?.performClose(nil)
                }
            }

            dotButton(
                color: Color(red: 0.996, green: 0.737, blue: 0.180), // #FEBC2E
                border: Color(red: 0.87, green: 0.62, blue: 0.10),
                symbol: "minus"
            ) {
                if let onMinimize {
                    onMinimize()
                } else {
                    NSApp.keyWindow?.performMiniaturize(nil)
                }
            }

            dotButton(
                color: Color(red: 0.157, green: 0.784, blue: 0.251), // #28C840
                border: Color(red: 0.11, green: 0.66, blue: 0.18),
                symbol: "plus"
            ) {
                if let onZoom {
                    onZoom()
                } else {
                    NSApp.keyWindow?.performZoom(nil)
                }
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }

    private func dotButton(
        color: Color,
        border: Color,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .stroke(border.opacity(0.65), lineWidth: 0.5)
                    )

                if isHovered {
                    Image(systemName: symbol)
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.68))
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Compatibility Button Styles & Modal Header

public struct ProZipPrimaryButtonStyle: ButtonStyle {
    public var isCompact: Bool

    public init(isCompact: Bool = false) {
        self.isCompact = isCompact
    }

    public func makeBody(configuration: Configuration) -> some View {
        ArcZipDialogButtonStyle(
            role: .primary,
            size: isCompact ? .compact : .regular
        )
        .makeBody(configuration: configuration)
    }
}

public struct ProZipSecondaryButtonStyle: ButtonStyle {
    public var isCompact: Bool

    public init(isCompact: Bool = false) {
        self.isCompact = isCompact
    }

    public func makeBody(configuration: Configuration) -> some View {
        ArcZipDialogButtonStyle(
            role: .secondary,
            size: isCompact ? .compact : .regular
        )
        .makeBody(configuration: configuration)
    }
}

public struct ProZipModalHeader: View {
    public let title: String
    public var subtitle: String?
    public var icon: String?
    public var onClose: (() -> Void)?

    public init(
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        onClose: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.onClose = onClose
    }

    public var body: some View {
        HStack(spacing: 12) {
            if let icon {
                ZStack {
                    Circle()
                        .fill(ProZipTheme.accentSoft)
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(ProZipTheme.accent)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Shared Liquid Glass & Progressive Variable Blur Coatings

public struct ProZipGlassMaterialView: NSViewRepresentable {
    public var material: NSVisualEffectView.Material
    public var blendingMode: NSVisualEffectView.BlendingMode
    public var state: NSVisualEffectView.State
    public var isEmphasized: Bool

    public init(
        material: NSVisualEffectView.Material = .hudWindow,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        state: NSVisualEffectView.State = .active,
        isEmphasized: Bool = false
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
        self.isEmphasized = isEmphasized
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = PassThroughVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.isEmphasized = isEmphasized
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        if nsView.material != material { nsView.material = material }
        if nsView.blendingMode != blendingMode { nsView.blendingMode = blendingMode }
        if nsView.state != state { nsView.state = state }
        if nsView.isEmphasized != isEmphasized { nsView.isEmphasized = isEmphasized }
    }
}

private final class PassThroughVisualEffectView: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Progressive variable backdrop blur (`withinWindow`) feathered smoothly via `CAGradientLayer` mask.
public struct ProZipVariableBlurView: NSViewRepresentable {
    public enum Direction: Sendable {
        case topToBottom
        case bottomToTop
    }

    public var direction: Direction
    public var material: NSVisualEffectView.Material

    public init(
        direction: Direction = .topToBottom,
        material: NSVisualEffectView.Material = .headerView
    ) {
        self.direction = direction
        self.material = material
    }

    public func makeNSView(context: Context) -> NSView {
        let view = VariableBlurBackdropNSView()
        view.configure(direction: direction, material: material)
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? VariableBlurBackdropNSView)?.configure(direction: direction, material: material)
    }
}

private final class VariableBlurBackdropNSView: NSView {
    private let effectView = NSVisualEffectView()
    private let maskGradient = CAGradientLayer()
    private var currentDirection: ProZipVariableBlurView.Direction = .topToBottom

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        effectView.blendingMode = .withinWindow
        effectView.state = .active
        effectView.autoresizingMask = [.width, .height]
        addSubview(effectView)
        layer?.mask = maskGradient
        applyStops()
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(direction: ProZipVariableBlurView.Direction, material: NSVisualEffectView.Material) {
        if effectView.material != material {
            effectView.material = material
        }
        if currentDirection != direction {
            currentDirection = direction
            applyStops()
        }
    }

    private func applyStops() {
        let solid = NSColor.white.cgColor
        let high = NSColor.white.withAlphaComponent(0.88).cgColor
        let mid = NSColor.white.withAlphaComponent(0.38).cgColor
        let clear = NSColor.clear.cgColor
        maskGradient.colors = [solid, high, mid, clear]
        maskGradient.locations = [0.0, 0.46, 0.78, 1.0]
        // AppKit layer-backed coordinates have y=0 at bottom, y=1 at top unless flipped.
        switch currentDirection {
        case .topToBottom:
            maskGradient.startPoint = CGPoint(x: 0.5, y: 1.0)
            maskGradient.endPoint = CGPoint(x: 0.5, y: 0.0)
        case .bottomToTop:
            maskGradient.startPoint = CGPoint(x: 0.5, y: 0.0)
            maskGradient.endPoint = CGPoint(x: 0.5, y: 1.0)
        }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        effectView.frame = bounds
        maskGradient.frame = bounds
        CATransaction.commit()
    }
}

private struct ProZipGlassCoatingModifier: ViewModifier {
    var cornerRadius: CGFloat
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    var tint: Color?
    var rimOpacity: Double

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                ZStack {
                    ProZipGlassMaterialView(material: material, blendingMode: blendingMode)
                    if let tint {
                        tint
                    } else {
                        Color.white.opacity(colorScheme == .dark ? 0.05 : 0.42)
                    }
                }
                .clipShape(shape)
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity((colorScheme == .dark ? 0.24 : 0.68) * rimOpacity),
                            Color.primary.opacity(0.08 * rimOpacity)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            }
    }
}

public extension View {
    func proZipGlassCoating(
        cornerRadius: CGFloat = 16,
        material: NSVisualEffectView.Material = .hudWindow,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        tint: Color? = nil,
        rimOpacity: Double = 1.0
    ) -> some View {
        modifier(
            ProZipGlassCoatingModifier(
                cornerRadius: cornerRadius,
                material: material,
                blendingMode: blendingMode,
                tint: tint,
                rimOpacity: rimOpacity
            )
        )
    }
}

/// AppKit-backed drag strip: uses `NSWindow.performDrag` for normal windows and drags
/// the owning root window when hosted inside an attached macOS sheet.
public struct WindowDragArea: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> NSView { DragStripView() }
    public func updateNSView(_ nsView: NSView, context: Context) {}

    public static func resolveRootWindow(from window: NSWindow?) -> NSWindow? {
        var current = window
        while let parent = current?.sheetParent {
            current = parent
        }
        return current
    }
}

private final class DragStripView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        if window.sheetParent == nil {
            window.performDrag(with: event)
            return
        }
        guard let target = WindowDragArea.resolveRootWindow(from: window) else { return }
        let startMouseLocation = NSEvent.mouseLocation
        let startOrigin = target.frame.origin
        window.trackEvents(
            matching: [.leftMouseDragged, .leftMouseUp],
            timeout: NSEvent.foreverDuration,
            mode: .eventTracking
        ) { trackedEvent, stop in
            guard let trackedEvent else {
                stop.pointee = true
                return
            }
            if trackedEvent.type == .leftMouseDragged {
                let currentLocation = NSEvent.mouseLocation
                target.setFrameOrigin(NSPoint(
                    x: startOrigin.x + (currentLocation.x - startMouseLocation.x),
                    y: startOrigin.y + (currentLocation.y - startMouseLocation.y)
                ))
            } else if trackedEvent.type == .leftMouseUp {
                stop.pointee = true
            }
        }
    }
}

// MARK: - Native macOS 26+ Liquid Glass Helpers & Segment Button Style

public enum ProZipGlassHighlightShape: Sendable {
    case circle
    case capsule
}

/// Segment / icon button style for controls hosted inside or wrapped by macOS 26+ Liquid Glass:
/// renders a smooth inner hover/press highlight without scale jitter, letting native `Glass.interactive()`
/// drive the directional liquid-lens press response.
public struct ProZipGlassSegmentButtonStyle: ButtonStyle {
    public var shape: ProZipGlassHighlightShape
    public var baseTint: Color?
    public var hoverDarkOpacity: Double
    public var hoverLightOpacity: Double

    public init(
        shape: ProZipGlassHighlightShape = .capsule,
        baseTint: Color? = nil,
        hoverDarkOpacity: Double = 0.10,
        hoverLightOpacity: Double = 0.065
    ) {
        self.shape = shape
        self.baseTint = baseTint
        self.hoverDarkOpacity = hoverDarkOpacity
        self.hoverLightOpacity = hoverLightOpacity
    }

    public func makeBody(configuration: Configuration) -> some View {
        SegmentBody(
            configuration: configuration,
            shape: shape,
            baseTint: baseTint,
            hoverDarkOpacity: hoverDarkOpacity,
            hoverLightOpacity: hoverLightOpacity
        )
    }

    private struct SegmentBody: View {
        let configuration: Configuration
        let shape: ProZipGlassHighlightShape
        let baseTint: Color?
        let hoverDarkOpacity: Double
        let hoverLightOpacity: Double

        @State private var isHovered = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            configuration.label
                .background {
                    switch shape {
                    case .circle:
                        Circle().fill(highlightFill)
                    case .capsule:
                        Capsule().fill(highlightFill)
                    }
                }
                .contentShape(
                    shape == .circle ? AnyShape(Circle()) : AnyShape(Capsule())
                )
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.14)) {
                        isHovered = hovering
                    }
                }
        }

        private var highlightFill: Color {
            if let baseTint {
                guard isEnabled else { return baseTint.opacity(0.08) }
                if configuration.isPressed { return baseTint.opacity(0.28) }
                if isHovered { return baseTint.opacity(0.20) }
                return baseTint.opacity(0.11)
            }
            guard isEnabled else { return .clear }
            if colorScheme == .dark {
                if configuration.isPressed { return Color.white.opacity(hoverDarkOpacity + 0.06) }
                return isHovered ? Color.white.opacity(hoverDarkOpacity) : .clear
            } else {
                if configuration.isPressed { return Color.black.opacity(hoverLightOpacity + 0.045) }
                return isHovered ? Color.black.opacity(hoverLightOpacity) : .clear
            }
        }
    }
}

/// Groups nearby Liquid Glass controls into a shared backdrop sampling pass on macOS 26+.
public struct ProZipGlassGroup<Content: View>: View {
    public var spacing: CGFloat?
    @ViewBuilder public let content: Content

    public init(spacing: CGFloat? = 4, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}

private struct ProZipLiquidGlassCapsuleModifier: ViewModifier {
    var interactive: Bool
    var tint: Color?
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            let base: Glass = tint.map { Glass.regular.tint($0) } ?? .regular
            content.glassEffect(interactive ? base.interactive() : base, in: .capsule)
        } else {
            content
                .background {
                    ZStack {
                        Capsule().fill(.ultraThinMaterial)
                        if let tint {
                            Capsule().fill(tint.opacity(0.75))
                        } else {
                            Capsule().fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.72))
                        }
                    }
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.07), radius: 6, x: 0, y: 2)
                }
                .overlay {
                    Capsule()
                        .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.22 : 0.65), lineWidth: 0.8)
                        .allowsHitTesting(false)
                }
        }
    }
}

private struct ProZipLiquidGlassCircleModifier: ViewModifier {
    var interactive: Bool
    var tint: Color?
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            let base: Glass = tint.map { Glass.regular.tint($0) } ?? .regular
            content.glassEffect(interactive ? base.interactive() : base, in: .circle)
        } else {
            content
                .background {
                    ZStack {
                        Circle().fill(.ultraThinMaterial)
                        if let tint {
                            Circle().fill(tint.opacity(0.75))
                        } else {
                            Circle().fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.72))
                        }
                    }
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.07), radius: 4, x: 0, y: 1.5)
                }
                .overlay {
                    Circle()
                        .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.22 : 0.65), lineWidth: 0.8)
                        .allowsHitTesting(false)
                }
        }
    }
}

private struct ProZipLiquidGlassRoundedRectModifier: ViewModifier {
    var cornerRadius: CGFloat
    var interactive: Bool
    var tint: Color?
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            let base: Glass = tint.map { Glass.regular.tint($0) } ?? .regular
            content.glassEffect(interactive ? base.interactive() : base, in: shape)
        } else {
            content
                .background {
                    ZStack {
                        ProZipGlassMaterialView(material: .hudWindow, blendingMode: .behindWindow)
                        if let tint {
                            tint
                        } else {
                            Color.white.opacity(colorScheme == .dark ? 0.08 : 0.45)
                        }
                    }
                    .clipShape(shape)
                }
        }
    }
}

public extension View {
    func proZipLiquidGlassCapsule(interactive: Bool = false, tint: Color? = nil) -> some View {
        modifier(ProZipLiquidGlassCapsuleModifier(interactive: interactive, tint: tint))
    }

    func proZipLiquidGlassCircle(interactive: Bool = false, tint: Color? = nil) -> some View {
        modifier(ProZipLiquidGlassCircleModifier(interactive: interactive, tint: tint))
    }

    func proZipLiquidGlassRoundedRect(cornerRadius: CGFloat, interactive: Bool = false, tint: Color? = nil) -> some View {
        modifier(ProZipLiquidGlassRoundedRectModifier(cornerRadius: cornerRadius, interactive: interactive, tint: tint))
    }
}
