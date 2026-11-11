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
            // Full macOS Menu Bar commands matching doc/01 section 3 & doc/13
            CommandGroup(replacing: .appSettings) {
                Button("设置…") {
                    ProZipAppDelegate.shared?.openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(replacing: .appInfo) {
                Button("关于 ProZip") {
                    appViewModel.settingsSelectedTab = .about
                    appDelegate.openSettings()
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
                .disabled(appViewModel.activeSession?.selectedEntries.isEmpty != false)

                Button("删除所选项目") {
                    if let s = appViewModel.activeSession {
                        s.removeSelectedDraftEntries()
                    }
                }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(appViewModel.activeSession?.selectedEntries.isEmpty != false || appViewModel.activeSession?.safeDescriptor.editingEligibility.allowed != true)

                Divider()

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

                Button("切换到 Mini 窗口") {
                    if let s = appViewModel.activeSession {
                        s.isMiniMode.toggle()
                    }
                }
                .keyboardShortcut("m", modifiers: [.option, .command])
                .disabled(appViewModel.activeSession?.initialSourceStat == nil)
            }

            CommandGroup(after: .windowList) {
                Button("ProZip 暂存盒") {
                    appDelegate.showShelf()
                }

                Button("任务队列…") {
                    appDelegate.showActiveWindow()
                    appDelegate.openProgressWindow()
                }

                if ProcessInfo.processInfo.environment["PROZIP_UI_GALLERY"] == "1" {
                    Divider()
                    Button("界面与弹窗全览…") {
                        appDelegate.showActiveWindow()
                        appViewModel.isDialogGalleryPresented = true
                    }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                }
            }

            CommandGroup(replacing: .help) {
                Button("更新概览") {
                    appDelegate.showActiveWindow()
                    appViewModel.isReleaseOverviewPresented = true
                }

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
                FirstLaunchOnboardingView()
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

/// Borderless main window: ArcZip has no system titlebar; it draws 16pt
/// traffic lights itself. NSWindow needs canBecomeKey overridden for that.
final class ArcZipWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func performClose(_ sender: Any?) {
        guard delegate?.windowShouldClose?(self) ?? true else { return }
        close()
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

// MARK: - Root Container Switcher (Workspace vs Mini)

struct RootArchiveContainerView: View {
    let sessionID: UUID?
    @EnvironmentObject var appViewModel: ProZipAppViewModel

    var body: some View {
        if let sessionID {
            if let session = appViewModel.sessions.first(where: { $0.id == sessionID }) {
                SessionRootView(session: session)
                    .environmentObject(appViewModel)
            }
        } else {
            ProZipLandingView()
                .environmentObject(appViewModel)
                .frame(width: 560, height: 390)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .background(WindowAccessor(
                    isAlwaysOnTop: false,
                    hidesNativeTrafficLights: true,
                    contentSize: CGSize(width: 560, height: 390),
                    minContentSize: CGSize(width: 560, height: 390),
                    windowTitle: "ProZip",
                    windowIdentifier: "ProZip.MainWindow",
                    isResizable: false
                ))

        }
    }
}

/// Observes the session directly so `isMiniMode` / `isAlwaysOnTop` toggles re-render
/// the window immediately (ArcZip switches Workspace ↔ Mini in place).
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
            hidesNativeTrafficLights: true,
            contentSize: session.isMiniMode ? CGSize(width: 560, height: 422) : CGSize(width: 900, height: 600),
            minContentSize: session.isMiniMode ? CGSize(width: 560, height: 422) : CGSize(width: 880, height: 600),
            windowTitle: session.archiveName,
            windowIdentifier: "\(session.isMiniMode ? "Mini" : "Workspace").\(session.id.uuidString)",
            isResizable: !session.isMiniMode
        ))
        .onAppear { session.showsAuxiliaryEntries = preferences.showsAuxiliaryEntries }
        .onChange(of: preferences.showsAuxiliaryEntries) { _, value in session.showsAuxiliaryEntries = value }
    }
}

/// ArcZip landing (560×390): brand lockup on top, centered welcome copy,
/// outline "open" capsule + filled "create" capsule, gear at top-right.
struct ProZipLandingView: View {
    @EnvironmentObject var appViewModel: ProZipAppViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var isDropTargeted = false

    var body: some View {
        ZStack {
            ProZipTheme.landingGradient(for: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Spacer()
                    ProZipBrandIcon(size: 30, showAppSquircle: true)
                    Text("ProZip")
                        .font(.system(size: 18, weight: .bold))
                    Spacer()
                }
                .overlay(alignment: .trailing) {
                    Button {
                        ProZipAppDelegate.shared?.openSettings()
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 15, weight: .medium))
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(Color.white.opacity(0.7)))
                    }
                    .buttonStyle(.plain)
                    .help("设置")
                }
                .padding(.horizontal, 11)
                .padding(.top, 17)

                Spacer(minLength: 0)

                Text("拖入压缩包进行预览或解压")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.primary)
                    .offset(y: 47)

                Spacer(minLength: 0)

                HStack(spacing: 14) {
                    Button {
                        ProZipAppDelegate.shared?.promptOpenArchive()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "folder")
                                .font(.system(size: 14, weight: .semibold))
                            Text("打开压缩包")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .frame(width: 146, height: 40)
                        .background(Capsule().fill(Color.white))
                        .overlay(Capsule().stroke(Color.primary.opacity(0.10), lineWidth: 1))
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
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
                        .frame(width: 142, height: 40)
                        .background(Capsule().fill(ProZipTheme.accent))
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .help("创建压缩包")
                }
                .padding(.bottom, 91)
            }
            .ignoresSafeArea(.container, edges: .top)
        }
        .overlay(alignment: .topLeading) {
            MainWindowTrafficLightsView(
                onClose: { NSApp.keyWindow?.close() },
                onMinimize: { NSApp.keyWindow?.miniaturize(nil) },
                onZoom: { NSApp.keyWindow?.zoom(nil) }
            )
            .padding(.leading, 19)
            .padding(.top, 24)
        }
        .overlay(alignment: .topLeading) {
            WindowDragArea()
                .frame(width: 430, height: 44)
                .offset(x: 80, y: 0)
        }
        .overlay {
            if isDropTargeted { ProZipTheme.accent.opacity(0.10).allowsHitTesting(false) }
        }
        .animation(.easeInOut(duration: 0.15), value: isDropTargeted)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            guard providers.contains(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else { return false }
            Task { @MainActor in
                let urls = await FileURLDrop.loadURLs(from: providers)
                ProZipAppDelegate.shared?.importFiles(urls, replacingLanding: true)
            }
            return true
        }
    }
}

// MARK: - AppKit Window Accessor for Always-On-Top

struct WindowAccessor: NSViewRepresentable {
    var isAlwaysOnTop: Bool
    var hidesNativeTrafficLights: Bool = false
    var contentSize: CGSize? = nil
    var minContentSize: CGSize? = nil
    var windowTitle: String? = nil
    var windowIdentifier: String? = nil
    var isResizable: Bool = true

    final class Coordinator {
        var lastAppliedSize: CGSize?
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
        let level: NSWindow.Level = isAlwaysOnTop ? .floating : .normal
        if window.level != level { window.level = level }
        var style = window.styleMask.union([.closable, .miniaturizable])
        if isResizable { style.insert(.resizable) } else { style.remove(.resizable) }
        let styleChanged = window.styleMask != style
        if styleChanged { window.styleMask = style }
        if hidesNativeTrafficLights {
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
        }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.acceptsMouseMovedEvents = true
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

        if isResizable {
            window.contentMaxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }
        if let contentSize, context.coordinator.lastAppliedSize != contentSize {
            context.coordinator.lastAppliedSize = contentSize
            window.contentMinSize = .zero
            window.minSize = .zero
            window.setContentSize(contentSize)
            window.center()
        }
        if let minContentSize {
            window.contentMinSize = minContentSize
        }
        if !isResizable, let contentSize {
            window.contentMaxSize = contentSize
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

        Task { @MainActor in
            if !ProZipPreferences.shared.onboardingCompleted {
                ProZipAppViewModel.shared.isOnboardingPresented = true
            }
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
    }

    private func createArchiveWindow(for session: ArchiveBrowsingSession?) -> ArcZipWindow {
        let size = session.map { $0.isMiniMode ? NSSize(width: 560, height: 422) : NSSize(width: 900, height: 600) }
            ?? NSSize(width: 560, height: 390)
        let hosting = NSHostingView(rootView: AppRootView(sessionID: session?.id).environmentObject(ProZipAppViewModel.shared))
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        hosting.sizingOptions = [.minSize]

        let window = ArcZipWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: session?.isMiniMode == false ? [.borderless, .closable, .miniaturizable, .resizable] : [.borderless, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.delegate = self
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.contentMinSize = session?.isMiniMode == false ? NSSize(width: 880, height: 600) : size
        if session?.isMiniMode != false { window.contentMaxSize = size }
        window.collectionBehavior = [.fullScreenPrimary]
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
                button.image = logo
            } else {
                button.image = NSImage(systemSymbolName: "tray.full", accessibilityDescription: "ProZip 文件盒")
                button.image?.isTemplate = true
            }
            button.target = self
            button.action = #selector(toggleShelfPanel(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "ProZip 文件盒"
        }
        shelfStatusItem = item

        NotificationCenter.default.addObserver(
            forName: .proZipCloseShelf,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.hideShelfPanel() }
        }

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
        let defaults = UserDefaults.standard
        let keepOnTop = defaults.object(forKey: "progressWindow.keepOnTop.v1") as? Bool ?? true
        progressWindow?.level = keepOnTop ? .floating : .normal
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
    func openSettings() {
        if let existing = settingsWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let root = ProZipSettingsView(initialTab: ProZipAppViewModel.shared.settingsSelectedTab)
            .environmentObject(ProZipAppViewModel.shared)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            )
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: 900, height: 712)
        hosting.autoresizingMask = [.width, .height]
        hosting.sizingOptions = [.minSize]

        let window = ArcZipWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 712),
            styleMask: [.borderless, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.acceptsMouseMovedEvents = true
        window.minSize = NSSize(width: 900, height: 712)
        window.title = "设置"
        window.identifier = NSUserInterfaceItemIdentifier("ProZip.SettingsWindow")
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
