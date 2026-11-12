import AppKit
import Combine
import ProZipCore
import ProZipEngines
import ProZipShared
import ProZipUI
import SwiftUI
import UniformTypeIdentifiers

@main
struct ProZipApplication: App {
    @NSApplicationDelegateAdaptor(ProZipAppDelegate.self) var appDelegate
    @StateObject private var appViewModel = ProZipAppViewModel.shared
    @ObservedObject private var preferences = ProZipPreferences.shared

    var body: some Scene {
        Settings { EmptyView() }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("设置…") {
                    appDelegate.openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(replacing: .appInfo) {
                Button("关于 ProZip") {
                    appDelegate.openSettings(tab: .about)
                }

                Button("检查更新…") {
                    appViewModel.checkForUpdates()
                }
            }

            CommandGroup(replacing: .newItem) {
                Button("创建压缩包") {
                    appDelegate.showActiveWindow()
                    appDelegate.createNewArchive()
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(appViewModel.isTerminationRequested)

                Button("打开压缩包…") {
                    appDelegate.promptOpenArchive()
                }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(appViewModel.isTerminationRequested)

                Menu("最近打开") {
                    if preferences.recentArchives.isEmpty {
                        Text("无最近打开的压缩包")
                    } else {
                        ForEach(preferences.recentArchives) { record in
                            Button(record.url.lastPathComponent) {
                                appDelegate.importFiles([record.url], replacingLanding: NSApp.keyWindow === appDelegate.landingWindow)
                            }
                        }
                        Divider()
                        Button("清除菜单") { preferences.recentArchives = [] }
                    }
                }
            }

            CommandGroup(replacing: .undoRedo) {
                Button(appViewModel.activeSession?.undoActionTitle.map { "撤销\($0)" } ?? "撤销") {
                    Task { await appViewModel.activeSession?.undo() }
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(appViewModel.activeSession?.canUndo != true)
                Button(appViewModel.activeSession?.redoActionTitle.map { "重做\($0)" } ?? "重做") {
                    Task { await appViewModel.activeSession?.redo() }
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(appViewModel.activeSession?.canRedo != true)
            }

            CommandMenu("压缩包") {
                Button("预览所选项目") {
                    if let s = appViewModel.activeSession {
                        appViewModel.previewSelected(in: s)
                    }
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(appViewModel.activeSession?.selectedEntries.isEmpty != false)

                Button("解压所选项目…") {
                    if let s = appViewModel.activeSession {
                        appViewModel.extractSelection(s.selectedEntries, in: s)
                    }
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(appViewModel.activeSession?.selectedEntries.isEmpty != false)

                Divider()

                Button("删除所选项目") {
                    if let s = appViewModel.activeSession {
                        s.removeSelectedDraftEntries()
                    }
                }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(appViewModel.activeSession?.selectedEntries.isEmpty != false || appViewModel.activeSession?.safeDescriptor.editingEligibility.allowed != true)

                Button("保存") {
                    if let s = appViewModel.activeSession {
                        Task {
                            appViewModel.saveChanges(for: s)
                        }
                    }
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(appViewModel.activeSession?.hasUnsavedChanges != true)
            }

            CommandMenu("显示") {
                Button("图标") {
                    appViewModel.activeSession?.viewMode = .icons
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("列表") {
                    appViewModel.activeSession?.viewMode = .list
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("分栏") {
                    appViewModel.activeSession?.viewMode = .columns
                }
                .keyboardShortcut("3", modifiers: .command)

                Divider()

                Button("切换到 Mini") {
                    if let s = appViewModel.activeSession {
                        s.isMiniMode.toggle()
                    }
                }
                .disabled(appViewModel.activeSession?.initialSourceStat == nil)
            }

            CommandGroup(after: .windowArrangement) {
                Button("ProZip 文件盒") {
                    appDelegate.showShelf()
                }

                if ProcessInfo.processInfo.environment["PROZIP_UI_GALLERY"] == "1" {
                    Button("界面与弹窗全览…") {
                        appDelegate.showActiveWindow()
                        appViewModel.presentDialog(\.isDialogGalleryPresented, for: appViewModel.activeSessionID)
                    }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                }
            }

            CommandGroup(replacing: .help) {
                Button("更新概览") {
                    appDelegate.showActiveWindow()
                    appViewModel.presentDialog(\.isReleaseOverviewPresented, for: appViewModel.activeSessionID)
                }
                .disabled(true)

                Button("ProZip 帮助") {
                    if let url = URL(string: "https://github.com/prozip/prozip") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }
}


// MARK: - App Root (hosted in the custom borderless window)

struct AppRootView: View {
    let sessionID: UUID?
    @EnvironmentObject var appViewModel: ProZipAppViewModel

    private func presentation(_ keyPath: ReferenceWritableKeyPath<ProZipAppViewModel, Bool>) -> Binding<Bool> {
        Binding(
            get: { appViewModel[keyPath: keyPath] && appViewModel.ownsPresentation(keyPath, sessionID: sessionID) },
            set: { value in
                // Dismissing a sheet after focus moved must not dismiss the new host's sheet.
                guard appViewModel.ownsPresentation(keyPath, sessionID: sessionID) else { return }
                appViewModel[keyPath: keyPath] = value
            }
        )
    }

    var body: some View {
        RootArchiveContainerView(sessionID: sessionID)
            .environmentObject(appViewModel)
            .sheet(isPresented: presentation(\.isOnboardingPresented)) {
                FirstLaunchOnboardingView(dismissesSheetOnFinish: true)
            }
            .sheet(isPresented: presentation(\.isCreationDialogPresented), onDismiss: {
                appViewModel.creationDialogDidDismiss()
            }) {
                ArchiveCreationDialogView(defaultName: appViewModel.sessions.first(where: { $0.id == sessionID })?.url.deletingPathExtension().lastPathComponent ?? "归档")
                    .environmentObject(appViewModel)
            }
            .sheet(isPresented: presentation(\.isPasswordPromptPresented), onDismiss: {
                appViewModel.passwordPromptDidDismiss()
            }) {
                PasswordPromptSheetView()
                    .environmentObject(appViewModel)
            }
            .sheet(isPresented: presentation(\.isAboutPresented)) {
                AboutProZipView()
            }
            .sheet(isPresented: presentation(\.isCheckForUpdatesPresented)) {
                CheckForUpdatesDialogView()
            }
            .sheet(isPresented: presentation(\.isReleaseOverviewPresented)) {
                ReleaseOverviewWindowView()
            }
            .sheet(isPresented: presentation(\.isDialogGalleryPresented)) {
                ProZipUIDialogGalleryView()
            }
            .sheet(isPresented: presentation(\.isPasswordBookProtectionPresented)) {
                PasswordBookProtectionDialogView()
            }
            .sheet(isPresented: presentation(\.isConflictResolutionPresented), onDismiss: {
                appViewModel.conflictDialogDidDismiss()
            }) {
                ConflictResolutionDialogView()
            }
            .sheet(isPresented: presentation(\.isDeleteConfirmationPresented)) {
                DeleteConfirmationDialogView()
            }
            .sheet(isPresented: presentation(\.isTrashConfirmationPresented), onDismiss: {
                appViewModel.extractionCompletionDidDismiss()
            }) {
                TrashConfirmationDialogView()
            }
            .sheet(isPresented: presentation(\.isFilenameRepairPresented)) {
                FilenameRepairDialogView()
            }
            .sheet(isPresented: presentation(\.isEntryIndexIssuePresented)) {
                EntryIndexIssueDialogView()
            }
            .sheet(isPresented: presentation(\.isDiskImageLicensePresented)) {
                DiskImageLicenseDialogView()
            }
            .sheet(isPresented: presentation(\.isSourceAccessAlertPresented)) {
                SourceAccessAlertDialogView()
            }
            .sheet(isPresented: presentation(\.isErrorDetailPresented)) {
                ArchiveErrorDetailDialogView()
            }
    }
}

/// Custom AppKit traffic-lights group container that positions genuine AppKit
/// `standardWindowButton`s at `(19, 24)`, `(39, 24)`, `(59, 24)` (`16×16`) while
/// preserving native `_mouseInGroup:` cluster rollover, `⌥+Green` zoom, and tiling menus.
final class MainWindowTrafficLightsContainerView: NSView {
    private var isHoveringGroup = false
    private var trackingAreaRef: NSTrackingArea?
    private var flagsMonitor: Any?

    @objc(_mouseInGroup:)
    func _mouseInGroup(_ button: NSButton) -> Bool {
        isHoveringGroup
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef { removeTrackingArea(trackingAreaRef) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        setHovering(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        setHovering(false)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { setHovering(false) }
        super.viewWillMove(toWindow: newWindow)
    }

    deinit {
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
    }

    private func setHovering(_ hovering: Bool) {
        guard isHoveringGroup != hovering else { return }
        isHoveringGroup = hovering
        if hovering {
            if flagsMonitor == nil {
                flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
                    self?.refreshButtons()
                    return event
                }
            }
        } else if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
            flagsMonitor = nil
        }
        refreshButtons()
    }

    func refreshButtons() {
        for case let button as NSButton in subviews {
            button.needsDisplay = true
        }
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        (window as? ArcZipWindow)?.enforceTrafficLightButtonFramesInContainer()
    }
}

/// Main application window using `.titled` + `.fullSizeContentView` so native FullScreen
/// (`toggleFullScreen`), `⌥+Green` zoom (`zoom`), and `⌘W` (`performClose:`) all work natively.
final class ArcZipWindow: NSWindow {
    struct TrafficLightRecord {
        weak var button: NSButton?
        weak var originalParent: NSView?
        var originalFrame: NSRect
        var originalMask: NSView.AutoresizingMask
    }

    var savedWorkspaceContentSize = NSSize(width: 1040, height: 740)
    var usesPositionedTrafficLights = false
    var hidesTrafficLights = false
    var isTransitioningFullScreen = false
    var minFrameWidth: CGFloat?
    var minFrameHeight: CGFloat?
    private var isApplyingTrafficLights = false
    private var hasPendingDeferredTrafficPass = false
    private var trafficLightRecords: [NSWindow.ButtonType: TrafficLightRecord] = [:]
    private var trafficLightsContainer: MainWindowTrafficLightsContainerView?
    private var trafficLightObservers: [NSObjectProtocol] = []
    private var observedButtons: Set<ObjectIdentifier> = []
    private weak var observedThemeFrame: NSView?

    deinit {
        for token in trafficLightObservers {
            NotificationCenter.default.removeObserver(token)
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func performClose(_ sender: Any?) {
        guard delegate?.windowShouldClose?(self) ?? true else { return }
        close()
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var adjusted = frameRect
        if !styleMask.contains(.fullScreen) {
            if let minW = minFrameWidth, adjusted.size.width < minW {
                adjusted.size.width = minW
            }
            if let minH = minFrameHeight, adjusted.size.height < minH {
                adjusted.origin.y += (adjusted.size.height - minH)
                adjusted.size.height = minH
            }
        }
        super.setFrame(adjusted, display: flag)
        repositionTrafficLightsContainerIfNeeded()
    }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        super.makeKeyAndOrderFront(sender)
        applyTrafficLightsLayout()
        scheduleDeferredTrafficLightsPass()
    }

    override func orderFront(_ sender: Any?) {
        super.orderFront(sender)
        applyTrafficLightsLayout()
        scheduleDeferredTrafficLightsPass()
    }

    override func orderFrontRegardless() {
        super.orderFrontRegardless()
        applyTrafficLightsLayout()
        scheduleDeferredTrafficLightsPass()
    }

    func scheduleDeferredTrafficLightsPass() {
        guard !hasPendingDeferredTrafficPass else { return }
        hasPendingDeferredTrafficPass = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.hasPendingDeferredTrafficPass = false
            guard !self.isTransitioningFullScreen, !self.styleMask.contains(.fullScreen) else { return }
            self.applyTrafficLightsLayout()
        }
    }

    func prepareForFullScreenEntry() {
        isTransitioningFullScreen = true
        isApplyingTrafficLights = true
        defer { isApplyingTrafficLights = false }
        restoreTrafficLightsToOriginalParents(hidden: false)
        trafficLightsContainer?.isHidden = true
    }

    func enforceTrafficLightButtonFramesInContainer() {
        guard !isApplyingTrafficLights, usesPositionedTrafficLights, !hidesTrafficLights,
              !isTransitioningFullScreen, !styleMask.contains(.fullScreen),
              let container = trafficLightsContainer, !container.isHidden else { return }
        isApplyingTrafficLights = true
        defer { isApplyingTrafficLights = false }
        layoutButtons(inside: container)
    }

    func applyTrafficLightsLayout() {
        guard styleMask.contains(.titled) else { return }
        if styleMask.contains(.fullScreen) || isTransitioningFullScreen {
            if styleMask.contains(.fullScreen) {
                isApplyingTrafficLights = true
                restoreTrafficLightsToOriginalParents(hidden: false)
                trafficLightsContainer?.isHidden = true
                isApplyingTrafficLights = false
            }
            return
        }
        guard !isApplyingTrafficLights else { return }
        isApplyingTrafficLights = true
        defer { isApplyingTrafficLights = false }

        captureTrafficLightRecordsIfNeeded()

        if usesPositionedTrafficLights, let themeFrame = contentView?.superview {
            observeThemeFrameIfNeeded(themeFrame)
            let container: MainWindowTrafficLightsContainerView
            let targetFrame = targetContainerFrame(in: themeFrame)
            if let existing = trafficLightsContainer {
                container = existing
            } else {
                let created = MainWindowTrafficLightsContainerView(frame: targetFrame)
                created.autoresizingMask = [.maxXMargin, .minYMargin]
                trafficLightsContainer = created
                container = created
            }
            if container.superview !== themeFrame {
                themeFrame.addSubview(container, positioned: .above, relativeTo: nil)
            }
            if abs(container.frame.origin.x - targetFrame.origin.x) > 0.5
                || abs(container.frame.origin.y - targetFrame.origin.y) > 0.5
                || abs(container.frame.size.width - targetFrame.size.width) > 0.5
                || abs(container.frame.size.height - targetFrame.size.height) > 0.5 {
                container.frame = targetFrame
            }

            if hidesTrafficLights {
                if !container.isHidden { container.isHidden = true }
                for type: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
                    if let button = standardWindowButton(type) ?? trafficLightRecords[type]?.button {
                        if button.superview !== container {
                            button.removeFromSuperview()
                            container.addSubview(button)
                        }
                        if !button.isHidden { button.isHidden = true }
                    }
                }
                return
            }

            if container.isHidden { container.isHidden = false }
            layoutButtons(inside: container)
        } else if hidesTrafficLights {
            trafficLightsContainer?.isHidden = true
            for type: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
                if let button = standardWindowButton(type) ?? trafficLightRecords[type]?.button {
                    if !button.isHidden { button.isHidden = true }
                }
            }
        } else {
            trafficLightsContainer?.isHidden = true
            restoreTrafficLightsToOriginalParents(hidden: false)
        }
    }

    private func targetContainerFrame(in themeFrame: NSView) -> NSRect {
        let windowRect = NSRect(x: 19, y: max(0, frame.height - 40), width: 56, height: 16)
        return themeFrame.convert(windowRect, from: nil)
    }

    private func layoutButtons(inside container: MainWindowTrafficLightsContainerView) {
        let types: [(NSWindow.ButtonType, CGFloat)] = [(.closeButton, 0), (.miniaturizeButton, 20), (.zoomButton, 40)]
        let resizable = styleMask.contains(.resizable)
        for (type, xOffset) in types {
            guard let button = standardWindowButton(type) ?? trafficLightRecords[type]?.button else { continue }
            if button.superview !== container {
                button.removeFromSuperview()
                container.addSubview(button)
            }
            if !button.autoresizingMask.isEmpty {
                button.autoresizingMask = []
            }
            let actualSize = button.frame.size
            let targetOrigin = NSPoint(
                x: xOffset + floor((16 - actualSize.width) * 0.5),
                y: floor((16 - actualSize.height) * 0.5)
            )
            if abs(button.frame.origin.x - targetOrigin.x) > 0.5 || abs(button.frame.origin.y - targetOrigin.y) > 0.5 {
                button.setFrameOrigin(targetOrigin)
            }
            if button.isHidden { button.isHidden = false }
            let shouldEnable = (type == .zoomButton) ? resizable : true
            if button.isEnabled != shouldEnable { button.isEnabled = shouldEnable }
        }
    }

    private func repositionTrafficLightsContainerIfNeeded() {
        guard !isApplyingTrafficLights, usesPositionedTrafficLights, !isTransitioningFullScreen,
              !styleMask.contains(.fullScreen),
              let container = trafficLightsContainer,
              let themeFrame = contentView?.superview else { return }
        isApplyingTrafficLights = true
        defer { isApplyingTrafficLights = false }
        let targetFrame = targetContainerFrame(in: themeFrame)
        if abs(container.frame.origin.x - targetFrame.origin.x) > 0.5
            || abs(container.frame.origin.y - targetFrame.origin.y) > 0.5
            || abs(container.frame.size.width - targetFrame.size.width) > 0.5
            || abs(container.frame.size.height - targetFrame.size.height) > 0.5 {
            container.frame = targetFrame
        }
        if !hidesTrafficLights {
            layoutButtons(inside: container)
        }
    }

    private func observeThemeFrameIfNeeded(_ themeFrame: NSView) {
        guard observedThemeFrame !== themeFrame else { return }
        observedThemeFrame = themeFrame
        themeFrame.postsFrameChangedNotifications = true
        let token = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: themeFrame,
            queue: nil
        ) { [weak self] _ in
            self?.repositionTrafficLightsContainerIfNeeded()
        }
        trafficLightObservers.append(token)
    }

    private func captureTrafficLightRecordsIfNeeded() {
        for type: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = standardWindowButton(type) else { continue }
            if let superview = button.superview, superview !== trafficLightsContainer, trafficLightRecords[type] == nil {
                trafficLightRecords[type] = TrafficLightRecord(
                    button: button,
                    originalParent: superview,
                    originalFrame: button.frame,
                    originalMask: button.autoresizingMask
                )
            } else if trafficLightRecords[type]?.button == nil {
                trafficLightRecords[type]?.button = button
            }

            let buttonID = ObjectIdentifier(button)
            if !observedButtons.contains(buttonID) {
                observedButtons.insert(buttonID)
                button.postsFrameChangedNotifications = true
                let token = NotificationCenter.default.addObserver(
                    forName: NSView.frameDidChangeNotification,
                    object: button,
                    queue: nil
                ) { [weak self] _ in
                    guard let self, !self.isApplyingTrafficLights,
                          (self.usesPositionedTrafficLights || self.hidesTrafficLights),
                          !self.isTransitioningFullScreen,
                          !self.styleMask.contains(.fullScreen) else { return }
                    self.scheduleDeferredTrafficLightsPass()
                }
                trafficLightObservers.append(token)
            }
        }
    }

    private func restoreTrafficLightsToOriginalParents(hidden: Bool) {
        let resizable = styleMask.contains(.resizable)
        for type: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            guard let record = trafficLightRecords[type],
                  let button = standardWindowButton(type) ?? record.button else {
                if let button = standardWindowButton(type) {
                    if button.isHidden != hidden { button.isHidden = hidden }
                    let shouldEnable = (type == .zoomButton) ? resizable : true
                    if button.isEnabled != shouldEnable { button.isEnabled = shouldEnable }
                }
                continue
            }
            if let originalParent = record.originalParent, button.superview !== originalParent {
                button.removeFromSuperview()
                originalParent.addSubview(button)
                button.autoresizingMask = record.originalMask
                button.frame = record.originalFrame
            }
            if button.isHidden != hidden { button.isHidden = hidden }
            let shouldEnable = (type == .zoomButton) ? resizable : true
            if button.isEnabled != shouldEnable { button.isEnabled = shouldEnable }
        }
    }
}

final class ShelfPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { orderOut(sender) }
}

final class TaskProgressPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { ProZipAppViewModel.shared.isTaskProgressPresented = false }
    override func performClose(_ sender: Any?) { ProZipAppViewModel.shared.isTaskProgressPresented = false }
}

// MARK: - Root Container Switcher (Onboarding vs Landing vs Workspace vs Mini)

struct RootArchiveContainerView: View {
    let sessionID: UUID?
    @EnvironmentObject var appViewModel: ProZipAppViewModel
    @ObservedObject private var preferences = ProZipPreferences.shared

    var body: some View {
        if let sessionID {
            if let session = appViewModel.sessions.first(where: { $0.id == sessionID }) {
                SessionRootView(session: session)
                    .environmentObject(appViewModel)
            }
        } else {
            let isOnboarding = !preferences.onboardingCompleted
            let targetSize = isOnboarding ? CGSize(width: 704, height: 582) : CGSize(width: 560, height: 390)
            Group {
                if isOnboarding {
                    FirstLaunchOnboardingView()
                        .environmentObject(appViewModel)
                        .frame(width: 704, height: 582)
                } else {
                    ProZipLandingView()
                        .environmentObject(appViewModel)
                        .frame(width: 560, height: 390)
                }
            }
            .background(WindowAccessor(
                isAlwaysOnTop: false,
                hidesNativeTrafficLights: isOnboarding || appViewModel.isOnboardingPresented,
                usesPositionedTrafficLights: true,
                contentSize: targetSize,
                minContentSize: targetSize,
                windowTitle: "ProZip",
                windowIdentifier: "ProZip.MainWindow",
                isResizable: false,
                allowsFullScreen: false,
                centersOnSizeChange: true
            ))
        }
    }
}

/// Observes the session directly so `isMiniMode` / `isAlwaysOnTop` toggles re-render
/// the window immediately (ArcZip switches Workspace ↔ Mini in place, preserving selection
/// and `savedWorkspaceContentSize`).
struct SessionRootView: View {
    @ObservedObject var session: ArchiveBrowsingSession
    @EnvironmentObject var appViewModel: ProZipAppViewModel
    @ObservedObject private var preferences = ProZipPreferences.shared

    var body: some View {
        Group {
            if session.isMiniMode {
                MiniArchiveView(session: session)
                    .environmentObject(appViewModel)
            } else {
                WorkspaceWindowView(session: session)
                    .environmentObject(appViewModel)
            }
        }
        .background(WindowAccessor(
            isAlwaysOnTop: session.isAlwaysOnTop,
            hidesNativeTrafficLights: session.isMiniMode,
            usesPositionedTrafficLights: true,
            contentSize: session.isMiniMode ? CGSize(width: 560, height: 422) : CGSize(width: 1040, height: 740),
            minContentSize: session.isMiniMode ? CGSize(width: 560, height: 422) : CGSize(width: 900, height: 600),
            windowTitle: session.archiveName,
            windowIdentifier: "\(session.isMiniMode ? "Mini" : "Workspace").\(session.id.uuidString)",
            isResizable: !session.isMiniMode,
            allowsFullScreen: !session.isMiniMode,
            restoresSavedWorkspaceSize: !session.isMiniMode
        ))
        .onAppear { session.showsAuxiliaryEntries = preferences.showsAuxiliaryEntries }
        .onChange(of: preferences.showsAuxiliaryEntries) { _, value in session.showsAuxiliaryEntries = value }
    }
}

/// ArcZip landing (`560×390`): `6pt` `#E8E9ED` bezel + `1pt` `#FFFFFF` inner rim around `r=26` card,
/// ambient peach + ProZip green glow, cycling headline, hover/press capsules, gear at `(503, 13)`.
struct ProZipLandingView: View {
    @EnvironmentObject var appViewModel: ProZipAppViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.controlActiveState) private var controlActiveState
    @State private var isDropTargeted = false
    @State private var headlineIndex = 0
    @State private var isHoveringGear = false
    @State private var isHoveringOpen = false
    @State private var isHoveringCreate = false

    private static let headlines = [
        "拖入压缩包进行预览或解压",
        "拖入文件以创建压缩包"
    ]

    private var isWindowActive: Bool {
        controlActiveState != .inactive
    }

    var body: some View {
        let outerShape = RoundedRectangle(cornerRadius: 32, style: .continuous)
        let innerShape = RoundedRectangle(cornerRadius: 26, style: .continuous)

        ZStack {
            outerShape
                .fill(colorScheme == .dark ? Color(red: 0.11, green: 0.114, blue: 0.125) : Color(red: 0.910, green: 0.914, blue: 0.929))

            ZStack {
                landingBackdrop
                    .clipShape(innerShape)

                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Spacer(minLength: 0)
                        ProZipBrandIcon(size: 30, showAppSquircle: true)
                        Text("ProZip")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("ProZip")
                    .accessibilityValue("欢迎页面")
                    .padding(.top, 10)

                    Spacer(minLength: 0)

                    ZStack {
                        Text(Self.headlines[headlineIndex])
                            .id(headlineIndex)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(.primary)
                            .transition(.opacity)
                    }
                    .frame(height: 33)
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("ProZip.LandingHeadline")
                    .accessibilityLabel("欢迎！拖入文件以开始")
                    .padding(.bottom, 47.5)

                    ProZipGlassGroup(spacing: 4) {
                        HStack(spacing: 12) {
                            Button {
                                ProZipAppDelegate.shared?.promptOpenArchive()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "folder")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("打开压缩包")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .frame(width: 146.5, height: 40)
                                .foregroundStyle(.primary)
                            }
                            .buttonStyle(ProZipGlassSegmentButtonStyle(shape: .capsule, hoverDarkOpacity: 0.11, hoverLightOpacity: 0.065))
                            .proZipLiquidGlassCapsule(interactive: true)
                            .onHover { isHoveringOpen = $0 }
                            .accessibilityIdentifier("ProZip.LandingOpen")
                            .accessibilityLabel("打开压缩包")
                            .help("打开压缩包")

                            Button {
                                ProZipAppDelegate.shared?.createNewArchive()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 14, weight: .bold))
                                    Text("创建压缩包")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .frame(width: 142.5, height: 40)
                                .background {
                                    if isWindowActive {
                                        Capsule()
                                            .fill(
                                                LinearGradient(
                                                    colors: [
                                                        isHoveringCreate ? Color(red: 0.56, green: 0.85, blue: 0.12).opacity(0.88) : ProZipTheme.accent.opacity(0.84),
                                                        isHoveringCreate ? ProZipTheme.accent.opacity(0.92) : ProZipTheme.accentDeep.opacity(0.78)
                                                    ],
                                                    startPoint: .top,
                                                    endPoint: .bottom
                                                )
                                            )
                                    }
                                }
                                .foregroundStyle(isWindowActive ? Color.white : Color.secondary)
                            }
                            .buttonStyle(
                                ProZipGlassSegmentButtonStyle(
                                    shape: .capsule,
                                    hoverDarkOpacity: isWindowActive ? 0.10 : 0.08,
                                    hoverLightOpacity: isWindowActive ? 0.05 : 0.05
                                )
                            )
                            .proZipLiquidGlassCapsule(interactive: true, tint: isWindowActive ? ProZipTheme.accent : nil)
                            .onHover { hovering in
                                withAnimation(.easeOut(duration: 0.14)) { isHoveringCreate = hovering }
                            }
                            .accessibilityIdentifier("ProZip.LandingCreate")
                            .accessibilityLabel("创建压缩包")
                            .help("创建压缩包")
                        }
                    }
                    .padding(.bottom, 84.5)
                }
            }
            .clipShape(innerShape)
            .overlay(
                innerShape.strokeBorder(
                    colorScheme == .dark ? Color.white.opacity(0.10) : Color.white,
                    lineWidth: 1
                )
            )
            .padding(6)
        }
        .frame(width: 560, height: 390)
        .clipShape(outerShape)
        .overlay(
            outerShape.strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                .allowsHitTesting(false)
        )
        .overlay(alignment: .topTrailing) {
            Button {
                ProZipAppDelegate.shared?.openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.85))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(ProZipGlassSegmentButtonStyle(shape: .circle, hoverDarkOpacity: 0.10, hoverLightOpacity: 0.055))
            .proZipLiquidGlassCircle(interactive: true)
            .onHover { isHoveringGear = $0 }
            .padding(.top, 13)
            .padding(.trailing, 19)
            .accessibilityIdentifier("ProZip.LandingSettings")
            .accessibilityLabel("设置…")
            .help("设置…")
        }
        .overlay(alignment: .topLeading) {
            MainWindowTrafficLightsView(
                isZoomEnabled: false,
                onClose: { (ProZipAppDelegate.shared?.landingWindow ?? NSApp.keyWindow)?.performClose(nil) },
                onMinimize: { (ProZipAppDelegate.shared?.landingWindow ?? NSApp.keyWindow)?.miniaturize(nil) },
                onZoom: {}
            )
            .padding(.leading, 19)
            .padding(.top, 24)
        }
        .overlay(alignment: .topLeading) {
            WindowDragArea()
                .frame(width: 416, height: 48)
                .offset(x: 82, y: 0)
        }
        .overlay {
            if isDropTargeted {
                innerShape
                    .fill(ProZipTheme.accent.opacity(0.10))
                    .overlay(innerShape.strokeBorder(ProZipTheme.accent.opacity(0.45), lineWidth: 1.5))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("文件投放区")
        .animation(.easeInOut(duration: 0.15), value: isDropTargeted)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3.6))
                guard !Task.isCancelled else { break }
                withAnimation(.easeInOut(duration: 0.45)) {
                    headlineIndex = (headlineIndex + 1) % Self.headlines.count
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            guard providers.contains(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else { return false }
            Task { @MainActor in
                let urls = await FileURLDrop.loadURLs(from: providers)
                ProZipAppDelegate.shared?.importFiles(urls, replacingLanding: true)
            }
            return true
        }
    }

    @ViewBuilder
    private var landingBackdrop: some View {
        if colorScheme == .dark {
            ZStack {
                Color(red: 0.118, green: 0.122, blue: 0.133)
                RadialGradient(
                    colors: [Color(red: 0.24, green: 0.16, blue: 0.16).opacity(0.42), .clear],
                    center: UnitPoint(x: 0.24, y: 0.30),
                    startRadius: 12,
                    endRadius: 240
                )
                RadialGradient(
                    colors: [ProZipTheme.accent.opacity(0.14), .clear],
                    center: UnitPoint(x: 0.80, y: 0.84),
                    startRadius: 16,
                    endRadius: 230
                )
            }
        } else {
            ZStack {
                Color(red: 0.996, green: 0.988, blue: 0.986)
                RadialGradient(
                    colors: [Color(red: 0.996, green: 0.910, blue: 0.902).opacity(0.85), .clear],
                    center: UnitPoint(x: 0.26, y: 0.32),
                    startRadius: 10,
                    endRadius: 245
                )
                RadialGradient(
                    colors: [ProZipTheme.accent.opacity(0.12), .clear],
                    center: UnitPoint(x: 0.80, y: 0.84),
                    startRadius: 12,
                    endRadius: 240
                )
            }
        }
    }
}

private struct LandingScaleButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

// MARK: - AppKit Window Accessor

struct WindowAccessor: NSViewRepresentable {
    var isAlwaysOnTop: Bool
    var hidesNativeTrafficLights: Bool = false
    var usesPositionedTrafficLights: Bool = false
    var contentSize: CGSize? = nil
    var minContentSize: CGSize? = nil
    var windowTitle: String? = nil
    var windowIdentifier: String? = nil
    var isResizable: Bool = true
    var allowsFullScreen: Bool = false
    var restoresSavedWorkspaceSize: Bool = false
    var centersOnSizeChange: Bool = false

    final class Coordinator {
        var lastAppliedModeKey: String?
        var wasResizable: Bool?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            self.updateWindow(view.window, context: context)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            self.updateWindow(nsView.window, context: context)
        }
    }

    private func updateWindow(_ window: NSWindow?, context: Context) {
        guard let window else { return }
        let arcWindow = window as? ArcZipWindow
        let isFullScreen = window.styleMask.contains(.fullScreen)

        if !allowsFullScreen && isFullScreen {
            window.toggleFullScreen(nil)
            return
        }

        let level: NSWindow.Level = isAlwaysOnTop ? .floating : .normal
        if window.level != level { window.level = level }

        if context.coordinator.wasResizable == true && !isResizable && !isFullScreen, let arcWindow {
            let current = window.contentView?.bounds.size ?? window.frame.size
            if current.width >= 900 && current.height >= 600 {
                arcWindow.savedWorkspaceContentSize = current
            }
        }
        context.coordinator.wasResizable = isResizable

        var styleChanged = false
        if !isFullScreen {
            var style = window.styleMask.union([.titled, .fullSizeContentView, .closable, .miniaturizable])
            style.remove(.borderless)
            if isResizable { style.insert(.resizable) } else { style.remove(.resizable) }
            if window.styleMask != style {
                window.styleMask = style
                styleChanged = true
            }
        }

        let targetCollection: NSWindow.CollectionBehavior = allowsFullScreen ? [.fullScreenPrimary] : []
        if !isFullScreen && window.collectionBehavior != targetCollection {
            window.collectionBehavior = targetCollection
        }

        if !window.titlebarAppearsTransparent { window.titlebarAppearsTransparent = true }
        if window.titleVisibility != .hidden { window.titleVisibility = .hidden }
        if window.titlebarSeparatorStyle != .none { window.titlebarSeparatorStyle = .none }
        if !window.isMovableByWindowBackground { window.isMovableByWindowBackground = true }
        if !window.acceptsMouseMovedEvents { window.acceptsMouseMovedEvents = true }

        if let windowTitle, window.title != windowTitle {
            window.title = windowTitle
            NSApp.changeWindowsItem(window, title: windowTitle, filename: false)
        }
        if let windowIdentifier {
            let identifier = NSUserInterfaceItemIdentifier(windowIdentifier)
            if styleChanged || window.identifier != identifier {
                window.identifier = identifier
                window.setAccessibilityIdentifier(windowIdentifier)
            }
        }

        let modeKey = "\(windowIdentifier ?? ""):\(isResizable):\(Int(contentSize?.width ?? 0))x\(Int(contentSize?.height ?? 0))"
        if !isFullScreen, let contentSize, context.coordinator.lastAppliedModeKey != modeKey {
            let previousKey = context.coordinator.lastAppliedModeKey
            context.coordinator.lastAppliedModeKey = modeKey
            let resolvedSize: NSSize
            if restoresSavedWorkspaceSize, let saved = arcWindow?.savedWorkspaceContentSize {
                resolvedSize = NSSize(width: max(900, saved.width), height: max(600, saved.height))
            } else {
                resolvedSize = contentSize
            }
            window.contentMinSize = .zero
            window.minSize = .zero
            window.contentMaxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            window.setContentSize(resolvedSize)
            if previousKey == nil || centersOnSizeChange {
                window.center()
            }
            if previousKey != nil, windowIdentifier == "ProZip.MainWindow", ProZipAppViewModel.shared.activeSessionID == nil, !window.isVisible {
                window.makeKeyAndOrderFront(nil)
            }
        }

        if !isFullScreen {
            if let minContentSize {
                if window.contentMinSize != minContentSize { window.contentMinSize = minContentSize }
                if window.minSize != minContentSize { window.minSize = minContentSize }
            }
            let maxTarget = isResizable
                ? NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
                : (contentSize ?? window.frame.size)
            if window.contentMaxSize != maxTarget { window.contentMaxSize = maxTarget }
            if window.maxSize != maxTarget { window.maxSize = maxTarget }
        }

        if let arcWindow {
            arcWindow.hidesTrafficLights = hidesNativeTrafficLights
            arcWindow.usesPositionedTrafficLights = usesPositionedTrafficLights
            arcWindow.applyTrafficLightsLayout()
        } else if hidesNativeTrafficLights {
            for type: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
                if let btn = window.standardWindowButton(type), !btn.isHidden { btn.isHidden = true }
            }
        }
    }
}

// MARK: - ProZip App Delegate

@MainActor
final class ProZipAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static weak var shared: ProZipAppDelegate?
    var landingWindow: ArcZipWindow?
    private(set) var sessionWindows: [UUID: ArcZipWindow] = [:]
    private var isSynchronizingSessionWindows = false
    var settingsWindow: ArcZipWindow?
    var alertWindow: NSWindow?
    private var progressWindow: TaskProgressPanel?
    private var saveAlert: NSAlert?
    private var isWaitingForTermination = false
    private var restartRequested = false
    var shelfStatusItem: NSStatusItem?
    var shelfPanel: NSPanel?
    var shelfEventMonitors: [Any] = []
    private var shelfIdleTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProZipAppDelegate.shared = self
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        // 1. Apply runtime sculpted application icon
        ProZipIconRenderer.applyApplicationIcon()

        // 2. Keep the welcome page separate from each archive's window.
        showActiveWindow()

        setupShelfStatusItem()
        observePreferences()
        ProZipAppViewModel.shared.$sessions
            .map { $0.map(\.id) }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.synchronizeSessionWindows()
                if ProZipAppViewModel.shared.activeSessionID != nil { self?.showActiveWindow() }
            }
            .store(in: &cancellables)
        ProZipAppViewModel.shared.$activeSessionID
            .receive(on: RunLoop.main)
            .sink { [weak self] id in
                guard let id, ProZipAppViewModel.shared.activeSessionID == id else { return }
                self?.showActiveWindow()
            }
            .store(in: &cancellables)

        ProZipAppViewModel.shared.$isSettingsPresented
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] presented in
                guard presented else { return }
                ProZipAppViewModel.shared.isSettingsPresented = false
                self?.openSettings(tab: ProZipAppViewModel.shared.settingsSelectedTab)
            }
            .store(in: &cancellables)

        ProZipAppViewModel.shared.$isPasswordBookManagerPresented
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] presented in
                guard presented else { return }
                ProZipAppViewModel.shared.isPasswordBookManagerPresented = false
                self?.openSettings(tab: .passwordBook)
            }
            .store(in: &cancellables)

        ProZipAppViewModel.shared.$isAlertPresented
            .receive(on: RunLoop.main)
            .sink { [weak self] presented in
                if presented { self?.showAlertWindow() } else { self?.alertWindow?.orderOut(nil); self?.alertWindow = nil }
            }
            .store(in: &cancellables)

        ProZipAppViewModel.shared.$isTaskProgressPresented
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] presented in
                if presented { self?.showProgressWindow() }
                else { self?.progressWindow?.orderOut(nil) }
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateProgressWindowLevel() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .proZipShowWelcome)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.showWelcomeWindow() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .proZipShowMainWindow)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.showActiveWindow() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .proZipRestartRequested)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.restartRequested = true
                NSApp.terminate(nil)
            }
            .store(in: &cancellables)

        ProZipAppViewModel.shared.$isSaveChangesPresented
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] presented in if presented { self?.showSaveConfirmation() } }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .proZipTerminationReady, object: ProZipAppViewModel.shared)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.replyToTermination(allow: true) }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .proZipTerminationCancelled, object: ProZipAppViewModel.shared)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.replyToTermination(allow: false) }
            .store(in: &cancellables)

        // 3. Perform crash recovery for leftover temporary artifacts
        Task {
            _ = try? await ManagedTemporaryArtifactRegistry.shared.performStartupRecovery()
        }

        // 4. Process command line arguments (e.g. open files passed via Terminal)
        let args = CommandLine.arguments
        if args.count > 1 {
            let files = args.dropFirst().filter { !$0.hasPrefix("-") }
                .map { URL(fileURLWithPath: $0) }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
            if !files.isEmpty { importFiles(files, replacingLanding: true, honorMiniPreference: true) }
        }

        // The empty SwiftUI Settings scene can materialize at launch on macOS 27.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            for candidate in NSApp.windows where
                candidate !== self.landingWindow &&
                !self.sessionWindows.values.contains(where: { $0 === candidate }) &&
                candidate !== self.settingsWindow &&
                candidate !== self.alertWindow &&
                candidate.sheetParent == nil && !(candidate is NSPanel) {
                candidate.orderOut(nil)
            }
        }

        // 5. Check for updates in background if needed
        ProZipAppViewModel.shared.checkAutoUpdatesOnLaunchIfNeeded()
    }

    private func createArchiveWindow(for session: ArchiveBrowsingSession?) -> ArcZipWindow {
        let isOnboarding = session == nil && !ProZipPreferences.shared.onboardingCompleted
        let size: NSSize
        if let session {
            size = session.isMiniMode ? NSSize(width: 560, height: 422) : NSSize(width: 1040, height: 740)
        } else {
            size = isOnboarding ? NSSize(width: 704, height: 582) : NSSize(width: 560, height: 390)
        }

        let hosting = NSHostingView(rootView: AppRootView(sessionID: session?.id).environmentObject(ProZipAppViewModel.shared))
        hosting.safeAreaRegions = []
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        hosting.sizingOptions = [.minSize]

        let isWorkspace = (session != nil && session?.isMiniMode == false)
        let styleMask: NSWindow.StyleMask = isWorkspace
            ? [.titled, .fullSizeContentView, .closable, .miniaturizable, .resizable]
            : [.titled, .fullSizeContentView, .closable, .miniaturizable]

        let window = ArcZipWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        window.delegate = self
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        window.acceptsMouseMovedEvents = true
        window.contentMinSize = isWorkspace ? NSSize(width: 900, height: 600) : size
        if !isWorkspace { window.contentMaxSize = size }
        window.collectionBehavior = isWorkspace ? [.fullScreenPrimary] : []
        window.usesPositionedTrafficLights = true
        window.hidesTrafficLights = (session?.isMiniMode == true) || isOnboarding
        window.applyTrafficLightsLayout()
        window.center()
        window.title = session?.archiveName ?? "ProZip"
        let identifier = session.map { "\($0.isMiniMode ? "Mini" : "Workspace").\($0.id.uuidString)" } ?? "ProZip.MainWindow"
        window.identifier = NSUserInterfaceItemIdentifier(identifier)
        window.setAccessibilityIdentifier(identifier)
        NSApp.addWindowsItem(window, title: window.title, filename: false)
        return window
    }

    private func synchronizeSessionWindows() {
        guard !isSynchronizingSessionWindows else { return }
        isSynchronizingSessionWindows = true
        defer { isSynchronizingSessionWindows = false }

        let sessions = ProZipAppViewModel.shared.sessions
        let ids = Set(sessions.map(\.id))
        for id in Array(sessionWindows.keys) where !ids.contains(id) {
            guard let window = sessionWindows.removeValue(forKey: id) else { continue }
            window.delegate = nil
            NSApp.removeWindowsItem(window)
            window.close()
        }
        for session in sessions where sessionWindows[session.id] == nil {
            let window = createArchiveWindow(for: session)
            sessionWindows[session.id] = window
            window.orderFront(nil)
        }
        assert(Set(sessionWindows.keys) == ids)
    }

    func showActiveWindow() {
        if landingWindow == nil {
            landingWindow = createArchiveWindow(for: nil)
            if ProZipAppViewModel.shared.activeSessionID == nil { landingWindow?.orderFront(nil) }
            else if let landingWindow { NSApp.removeWindowsItem(landingWindow) }
        }
        synchronizeSessionWindows()
        let window = ProZipAppViewModel.shared.activeSessionID.flatMap { sessionWindows[$0] } ?? landingWindow
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showWelcomeWindow() {
        ProZipAppViewModel.shared.activeSessionID = nil
        showActiveWindow()
        if let landingWindow { NSApp.addWindowsItem(landingWindow, title: "ProZip", filename: false) }
    }

    func createNewArchive() {
        ProZipAppViewModel.shared.createNewArchiveSession()
        landingWindow?.orderOut(nil)
        if let landingWindow { NSApp.removeWindowsItem(landingWindow) }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let id = sessionWindows.first(where: { $0.value === sender })?.key else { return true }
        ProZipAppViewModel.shared.activeSessionID = id
        ProZipAppViewModel.shared.closeSession(id: id)
        // The session is removed only after its save/discard flow has completed.
        return false
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        (notification.object as? ArcZipWindow)?.prepareForFullScreenEntry()
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        (notification.object as? ArcZipWindow)?.isTransitioningFullScreen = false
    }

    func windowDidFailToEnterFullScreen(_ window: NSWindow) {
        guard let arcWindow = window as? ArcZipWindow else { return }
        arcWindow.isTransitioningFullScreen = false
        arcWindow.applyTrafficLightsLayout()
        arcWindow.scheduleDeferredTrafficLightsPass()
    }

    func windowWillExitFullScreen(_ notification: Notification) {
        (notification.object as? ArcZipWindow)?.isTransitioningFullScreen = true
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        guard let arcWindow = notification.object as? ArcZipWindow else { return }
        arcWindow.isTransitioningFullScreen = false
        arcWindow.applyTrafficLightsLayout()
        arcWindow.scheduleDeferredTrafficLightsPass()
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        if sender === settingsWindow {
            return NSSize(width: max(900, frameSize.width), height: max(680, frameSize.height))
        }
        return frameSize
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? ArcZipWindow,
              window.usesPositionedTrafficLights,
              !window.hidesTrafficLights,
              window.styleMask.contains(.resizable),
              !window.styleMask.contains(.fullScreen) else { return }
        let size = window.contentView?.bounds.size ?? window.frame.size
        if size.width >= 900 && size.height >= 600 {
            window.savedWorkspaceContentSize = size
        }
    }

    func windowDidBecomeKey(_ notification: Notification) { activateSession(for: notification) }
    func windowDidBecomeMain(_ notification: Notification) { activateSession(for: notification) }

    private func activateSession(for notification: Notification) {
        guard !isSynchronizingSessionWindows, let window = notification.object as? NSWindow else { return }
        let id: UUID?
        if window === landingWindow {
            id = nil
        } else if let sessionID = sessionWindows.first(where: { $0.value === window })?.key {
            id = sessionID
        } else {
            return
        }
        if ProZipAppViewModel.shared.activeSessionID != id {
            ProZipAppViewModel.shared.activeSessionID = id
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showActiveWindow()
        }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if ProZipAppViewModel.shared.prepareForTermination() { return .terminateNow }
        isWaitingForTermination = true
        return .terminateLater
    }

    private func replyToTermination(allow: Bool) {
        if !allow { restartRequested = false }
        guard isWaitingForTermination else { return }
        isWaitingForTermination = false
        if allow { ProZipAppViewModel.shared.cancelBackgroundWork() }
        NSApp.reply(toApplicationShouldTerminate: allow)
    }

    func applicationWillTerminate(_ notification: Notification) {
        ProZipAppViewModel.shared.cancelBackgroundWork()
        guard restartRequested else { return }
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        relaunch.arguments = ["-n", Bundle.main.bundleURL.path]
        do { try relaunch.run() }
        catch { NSLog("ProZip could not restart: %@", error.localizedDescription) }
    }

    private func showSaveConfirmation() {
        let vm = ProZipAppViewModel.shared
        guard saveAlert == nil, vm.isSaveChangesPresented else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = vm.saveChangesIsSourceModifiedConflict ? "源压缩包在编辑期间已发生变化" : "是否保存对“\(vm.saveChangesArchiveName)”的修改？"
        alert.informativeText = vm.saveChangesIsSourceModifiedConflict ? "你可以重载源压缩包，或核对后合并待保存的修改。" : "不保存将丢失这些修改。"
        alert.addButton(withTitle: vm.saveChangesIsSourceModifiedConflict ? "合并更改并保存" : "保存")
        alert.addButton(withTitle: vm.saveChangesIsSourceModifiedConflict ? "放弃更改并重载" : "放弃更改")
        alert.addButton(withTitle: "取消").keyEquivalent = "\u{1b}"
        saveAlert = alert
        let response = alert.runModal()
        saveAlert = nil
        if response == .alertFirstButtonReturn { vm.confirmSaveChanges(merge: vm.saveChangesIsSourceModifiedConflict) }
        else if response == .alertSecondButtonReturn { vm.discardSaveChanges(reload: vm.saveChangesIsSourceModifiedConflict) }
        else { vm.cancelSaveChanges() }
        vm.performConfirmedSave()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func observePreferences() {
        let preferences = ProZipPreferences.shared
        preferences.$appearance
            .removeDuplicates()
            .sink { appearance in
                switch appearance {
                case .light: NSApp.appearance = NSAppearance(named: .aqua)
                case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
                case .automatic: NSApp.appearance = nil
                }
            }
            .store(in: &cancellables)
        preferences.$boxEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                self?.shelfStatusItem?.isVisible = enabled
                if !enabled { self?.hideShelfPanel() }
            }
            .store(in: &cancellables)
        ProZipAppViewModel.shared.shelfModel.$isPinned
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.resetShelfIdleTimer() }
            .store(in: &cancellables)
    }

    @MainActor
    private func setupShelfStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            if let path = Bundle.main.path(forResource: "AppIcon-Preview", ofType: "png"),
               let logo = NSImage(contentsOfFile: path) {
                logo.size = NSSize(width: 18, height: 18)
                logo.isTemplate = false
                logo.accessibilityDescription = "ProZip 文件盒"
                button.image = logo
            } else {
                button.image = NSImage(systemSymbolName: "tray.full", accessibilityDescription: "ProZip 文件盒")
                button.image?.isTemplate = true
            }
            button.target = self
            button.action = #selector(toggleShelfPanel(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "ProZip 文件盒"
            button.setAccessibilityLabel("ProZip 文件盒")
            button.setAccessibilityTitle("ProZip 文件盒")
        }
        shelfStatusItem = item

        NotificationCenter.default.publisher(for: .proZipCloseShelf)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.hideShelfPanel() }
            .store(in: &cancellables)

        let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            self?.closeShelfIfUnpinned(event: event)
            return event
        }
        let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.closeShelfIfUnpinned(event: nil) }
        }
        shelfEventMonitors = [local, global].compactMap { $0 }
    }

    @MainActor
    @objc private func toggleShelfPanel(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showShelfStatusMenu()
            return
        }
        if shelfPanel?.isVisible == true {
            hideShelfPanel()
        } else {
            showShelfPanel()
        }
    }

    @MainActor
    private func showShelfStatusMenu() {
        guard let button = shelfStatusItem?.button else { return }
        let menu = NSMenu()

        let openItem = NSMenuItem(title: "打开 ProZip", action: #selector(activateMainWindowFromMenu), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let quitItem = NSMenuItem(title: "退出 ProZip", action: #selector(quitFromMenu), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    @MainActor
    @objc private func activateMainWindowFromMenu() {
        hideShelfPanel()
        showActiveWindow()
    }

    func showShelf() {
        ProZipPreferences.shared.boxEnabled = true
        showShelfPanel()
    }

    @MainActor
    @objc private func quitFromMenu() {
        NSApp.terminate(nil)
    }

    @MainActor
    private func showShelfPanel() {
        if shelfPanel == nil {
            let vm = ProZipAppViewModel.shared
            let root = MenuBarShelfView(model: vm.shelfModel)
                .environmentObject(vm)
            let hosting = NSHostingView(rootView: root)
            hosting.frame = NSRect(x: 0, y: 0, width: 521, height: 497)
            let panel = ShelfPanel(
                contentRect: NSRect(x: 0, y: 0, width: 521, height: 497),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.contentView = hosting
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = .statusBar
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.becomesKeyOnlyIfNeeded = false
            panel.acceptsMouseMovedEvents = true
            panel.title = "ProZip 文件盒"
            panel.identifier = NSUserInterfaceItemIdentifier("ProZip.MenuBarShelf")
            panel.setAccessibilityIdentifier("ProZip.MenuBarShelf")
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            shelfPanel = panel
        }
        guard let panel = shelfPanel else { return }
        if let button = shelfStatusItem?.button, let buttonWindow = button.window {
            let rect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
            var x = rect.midX - 351
            if let screen = buttonWindow.screen ?? NSScreen.main {
                x = min(max(x, screen.visibleFrame.minX + 8), screen.visibleFrame.maxX - 529)
            }
            panel.setFrameOrigin(NSPoint(x: x, y: rect.minY - 497 + 2))
        }
        panel.makeKeyAndOrderFront(nil)
        resetShelfIdleTimer()
    }

    @MainActor
    private func hideShelfPanel() {
        shelfIdleTimer?.invalidate()
        shelfIdleTimer = nil
        shelfPanel?.orderOut(nil)
    }

    private func resetShelfIdleTimer() {
        shelfIdleTimer?.invalidate()
        guard shelfPanel?.isVisible == true else { return }
        let delay = TimeInterval(max(1, ProZipPreferences.shared.boxIdleDelaySeconds))
        shelfIdleTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, let panel = self.shelfPanel, panel.isVisible else { return }
                let model = ProZipAppViewModel.shared
                if model.shelfModel.isPinned { return }
                if NSEvent.pressedMouseButtons != 0 || panel.frame.contains(NSEvent.mouseLocation) || model.activeTasksCount > 0 {
                    self.resetShelfIdleTimer()
                } else {
                    self.hideShelfPanel()
                }
            }
        }
    }

    @MainActor
    private func closeShelfIfUnpinned(event: NSEvent?) {
        guard let panel = shelfPanel, panel.isVisible else { return }
        if ProZipAppViewModel.shared.shelfModel.isPinned { return }
        let location = event?.locationInWindow ?? NSEvent.mouseLocation
        let screenPoint: NSPoint
        if let event, let window = event.window {
            screenPoint = window.convertPoint(toScreen: location)
        } else {
            screenPoint = NSEvent.mouseLocation
        }
        if !panel.frame.contains(screenPoint) {
            hideShelfPanel()
        }
    }

    @MainActor
    private func showProgressWindow() {
        if progressWindow == nil {
            let panel = TaskProgressPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 260), styleMask: [.borderless], backing: .buffered, defer: false)
            panel.contentView = NSHostingView(rootView: ArchiveProgressWindowView().environmentObject(ProZipAppViewModel.shared))
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.isMovableByWindowBackground = true
            panel.title = "归档任务队列"
            panel.identifier = NSUserInterfaceItemIdentifier("ProZip.TaskProgress")
            panel.center()
            NSApp.addWindowsItem(panel, title: panel.title, filename: false)
            progressWindow = panel
        }
        updateProgressWindowLevel()
        progressWindow?.orderFront(nil)
    }

    private func updateProgressWindowLevel() {
        guard let progressWindow else { return }
        let keepOnTop = UserDefaults.standard.object(forKey: "progressWindow.keepOnTop.v1") as? Bool ?? true
        let targetLevel: NSWindow.Level = keepOnTop ? .floating : .normal
        if progressWindow.level != targetLevel {
            progressWindow.level = targetLevel
        }
    }

    func openProgressWindow() {
        ProZipAppViewModel.shared.isTaskProgressPresented = true
        showProgressWindow()
        progressWindow?.makeKeyAndOrderFront(nil)
    }

    private func showAlertWindow() {
        guard alertWindow == nil else { return }
        let vm = ProZipAppViewModel.shared
        let height: CGFloat = vm.alertMessage.count > 30 ? 267 : 202
        let root = ProZipAlertDialogView()
            .environmentObject(vm)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: 260, height: height)
        let window = ArcZipWindow(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        let parent = vm.activeSessionID.flatMap { sessionWindows[$0] } ?? landingWindow
        if let parent {
            let pf = parent.frame
            window.setFrameOrigin(NSPoint(x: pf.midX - 130, y: pf.midY - height / 2))
        } else {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        alertWindow = window
    }

    @MainActor
    func openSettings(tab: SettingsTab? = nil) {
        if let tab, ProZipAppViewModel.shared.settingsSelectedTab != tab {
            ProZipAppViewModel.shared.settingsSelectedTab = tab
        }
        if let existing = settingsWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let root = ProZipSettingsView(initialTab: ProZipAppViewModel.shared.settingsSelectedTab)
            .environmentObject(ProZipAppViewModel.shared)
        let hosting = NSHostingView(rootView: root)
        hosting.safeAreaRegions = []
        hosting.frame = NSRect(x: 0, y: 0, width: 900, height: 712)
        hosting.autoresizingMask = [.width, .height]
        hosting.sizingOptions = [.minSize]

        let window = ArcZipWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 712),
            styleMask: [.titled, .fullSizeContentView, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.delegate = self
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.hasShadow = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = false
        window.acceptsMouseMovedEvents = true
        window.minFrameWidth = 900
        window.minFrameHeight = 680
        window.minSize = NSSize(width: 900, height: 680)
        window.contentMinSize = NSSize(width: 900, height: 680)
        window.collectionBehavior = [.fullScreenNone]
        window.usesPositionedTrafficLights = false
        window.hidesTrafficLights = false
        window.applyTrafficLightsLayout()
        window.title = "设置"
        window.identifier = NSUserInterfaceItemIdentifier("ProZip.SettingsWindow")
        window.setAccessibilityIdentifier("ProZip.SettingsWindow")
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.addWindowsItem(window, title: "设置", filename: false)
        settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor
    func application(_ application: NSApplication, open urls: [URL]) {
        let files = urls.filter(\.isFileURL)
        for url in urls where !url.isFileURL {
            do {
                let request = try FinderActionRequest(url: url)
                try performFinderAction(request.action, urls: request.files)
            } catch {
                let vm = ProZipAppViewModel.shared
                vm.alertTitle = "无法处理访达请求"
                vm.alertMessage = error.localizedDescription
                vm.isAlertPresented = true
            }
        }
        if !files.isEmpty {
            importFiles(files, replacingLanding: ProZipAppViewModel.shared.activeSessionID == nil, honorMiniPreference: true)
        }
    }

    private func pasteboardFileURLs(_ pasteboard: NSPasteboard = .general) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL], !urls.isEmpty { return urls }
        let paths = pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] ?? []
        return paths.map { URL(fileURLWithPath: $0) }
    }

    @objc func performProZipService(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = pasteboardFileURLs(pasteboard)
        guard !urls.isEmpty else { error.pointee = "请选择文件或文件夹"; return }
        guard let userData, let action = FinderAction(rawValue: userData) else {
            error.pointee = "无法识别这项 ProZip 服务"
            return
        }
        do { try performFinderAction(action, urls: urls) }
        catch let failure { error.pointee = failure.localizedDescription as NSString }
    }

    private func performFinderAction(_ action: FinderAction, urls: [URL]) throws {
        let vm = ProZipAppViewModel.shared
        guard !vm.isTerminationRequested else { throw ProZipError.cancelled }
        let urls = try FinderActionRequest(action: action, files: urls).files
        try FileURLDrop.validateSources(urls)
        switch action {
        case .browseArchive:
            for url in urls { vm.openArchive(at: url, honorMiniPreference: true) }
        case .extractHere:
            for url in urls {
                vm.extractAll(in: vm.sessionForExternalExtraction(at: url), to: url.deletingLastPathComponent())
            }
            showActiveWindow()
        case .extractTo:
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.prompt = "解压到此处"
            guard panel.runModal() == .OK, let destination = panel.url else { return }
            for url in urls { vm.extractAll(in: vm.sessionForExternalExtraction(at: url), to: destination) }
            showActiveWindow()
        case .compressDefault:
            quickCompress(urls)
        case .compressConfigured:
            showActiveWindow()
            vm.beginCreation(sources: urls, ownerSessionID: vm.activeSessionID)
        case .sendToProZip:
            importFiles(urls, replacingLanding: true)
        }
    }

    private func quickCompress(_ urls: [URL]) {
        guard let first = urls.first else { return }
        let profile = ProZipPreferences.shared.makeDefaultCreationProfile()
        let isDirectory = (try? first.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        let name = urls.count > 1 ? "压缩包" : (isDirectory ? first.lastPathComponent : first.deletingPathExtension().lastPathComponent)
        let destination = first.deletingLastPathComponent().appendingPathComponent(name).appendingPathExtension(profile.format.defaultExtension)
        showActiveWindow()
        ProZipAppViewModel.shared.createArchive(sources: urls, destinationURL: destination, profile: profile)
    }

    @MainActor
    func quickCompressFromPasteboard() {
        do { try performFinderAction(.compressDefault, urls: pasteboardFileURLs()) }
        catch { reportFinderActionFailure(error) }
    }

    @MainActor
    func quickExtractFromPasteboard() {
        do { try performFinderAction(.extractHere, urls: pasteboardFileURLs()) }
        catch { reportFinderActionFailure(error) }
    }

    private func reportFinderActionFailure(_ error: Error) {
        let vm = ProZipAppViewModel.shared
        vm.alertTitle = "无法处理访达请求"
        vm.alertMessage = error.localizedDescription
        vm.isAlertPresented = true
    }

    @MainActor
    func revealPasteboardSelection() {
        let urls = pasteboardFileURLs()
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func importFiles(_ urls: [URL], replacingLanding: Bool = false, honorMiniPreference: Bool = false) {
        let vm = ProZipAppViewModel.shared
        Task {
            do {
                let imported = try await vm.importFiles(urls, honorMiniPreference: honorMiniPreference)
                if replacingLanding || imported.contains(where: { $0.initialSourceStat == nil }) {
                    landingWindow?.orderOut(nil)
                    if let landingWindow { NSApp.removeWindowsItem(landingWindow) }
                }
            } catch {
                vm.alertTitle = "无法导入文件"
                vm.alertMessage = error.localizedDescription
                vm.isAlertPresented = true
            }
        }
    }

    @MainActor
    func promptOpenArchive() {
        let replacingLanding = NSApp.keyWindow === landingWindow
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "打开"
        if panel.runModal() == .OK { importFiles(panel.urls, replacingLanding: replacingLanding) }
    }
}
