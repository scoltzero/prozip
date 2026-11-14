import AppKit
import ApplicationServices
import Combine
import CoreServices
import Foundation
import os
import ProZipShared

public enum AutomationPermissionStatus: String, Equatable, Sendable {
    case granted
    case notDetermined
    case denied
    case finderNotRunning

    public var title: String {
        switch self {
        case .granted: return "已授权"
        case .notDetermined: return "未授权"
        case .denied: return "已拒绝（请在系统设置中开启）"
        case .finderNotRunning: return "访达未运行"
        }
    }
}

public enum FinderSpacebarArchivePolicy {
    private static let textOrControlRoles: Set<String> = [
        kAXTextFieldRole as String,
        kAXTextAreaRole as String,
        "AXSearchField",
        kAXComboBoxRole as String,
        kAXMenuRole as String,
        kAXMenuItemRole as String,
        kAXMenuBarItemRole as String,
        kAXButtonRole as String,
        kAXPopUpButtonRole as String,
        kAXCheckBoxRole as String,
        kAXRadioButtonRole as String,
        kAXSliderRole as String
    ]

    public static func isTextInputOrControlRole(_ role: String?, subrole: String?) -> Bool {
        if let role, textOrControlRoles.contains(role) {
            return true
        }
        if let subrole, subrole == "AXSearchField" || subrole == "AXSecureTextField" {
            return true
        }
        return false
    }

    public static func isDialogOrSheetSubrole(_ subrole: String?) -> Bool {
        guard let subrole else { return false }
        return subrole == (kAXDialogSubrole as String)
            || subrole == (kAXSystemDialogSubrole as String)
            || subrole == "AXSheet"
            || subrole == (kAXFloatingWindowSubrole as String)
            || subrole == (kAXSystemFloatingWindowSubrole as String)
    }

    public static func extractFileURL(from element: AXUIElement) -> URL? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, kAXURLAttribute as CFString, &value)
        guard status == .success, let value else { return nil }
        if let url = value as? URL, url.isFileURL {
            return url
        }
        if let string = value as? String, let url = URL(string: string), url.isFileURL {
            return url
        }
        return nil
    }

    public static func isCandidateArchive(
        url: URL,
        scope: FinderSpacebarPreviewScope,
        cachedAssociatedExtensions: Set<String>,
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "org.prozip.ProZip",
        fileAssociationSystem: any FileAssociationSystem = LaunchServicesFileAssociationSystem()
    ) -> Bool {
        guard url.isFileURL else { return false }
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .isRegularFileKey])
        guard values?.isDirectory != true, values?.isPackage != true else { return false }
        guard FileManager.default.fileExists(atPath: url.path) else { return false }

        let format = ArchiveFormat.detect(from: url)
        guard format != .unknown else { return false }

        switch scope {
        case .allSupported:
            return true
        case .claimedOnly:
            let ext = url.pathExtension.lowercased()
            guard !ext.isEmpty else { return false }
            if cachedAssociatedExtensions.contains(ext) {
                return true
            }
            if let uti = fileAssociationSystem.contentType(forExtension: ext),
               let handler = fileAssociationSystem.defaultHandler(forContentType: uti),
               handler.caseInsensitiveCompare(bundleIdentifier) == .orderedSame {
                return true
            }
            return false
        }
    }
}

@MainActor
public final class FinderSpacebarMonitor: ObservableObject {
    public static let shared = FinderSpacebarMonitor()

    @Published public private(set) var isAccessibilityGranted: Bool = false
    @Published public private(set) var automationStatus: AutomationPermissionStatus = .notDetermined
    @Published public private(set) var isTapActive: Bool = false
    @Published public private(set) var lastInterceptedArchiveName: String?
    @Published public private(set) var lastStatusNote: String?

    public var onOpenArchiveMini: ((URL) -> Void)?

    public var isFullyAuthorized: Bool {
        isAccessibilityGranted && automationStatus == .granted
    }

    private let preferences: ProZipPreferences
    private let tapController: TapController
    private var cancellables: Set<AnyCancellable> = []
    private var trustPollTimer: Timer?
    private var hasStarted = false

    private init(preferences: ProZipPreferences = .shared) {
        self.preferences = preferences
        self.tapController = TapController()
        self.tapController.onOpenArchive = { [weak self] url in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.lastInterceptedArchiveName = url.lastPathComponent
                self.onOpenArchiveMini?(url)
            }
        }
        self.tapController.onAutomationDenied = { [weak self] in
            Task { @MainActor [weak self] in
                self?.automationStatus = .denied
                self?.pushSnapshotToController()
            }
        }
    }

    public func startMonitoringIfConfigured() {
        if !hasStarted {
            hasStarted = true
            observePreferencesAndSystemState()
        }
        refreshPermissions(attemptTapSync: true)
    }

    public func stopMonitoring() {
        trustPollTimer?.invalidate()
        trustPollTimer = nil
        tapController.stop()
        isTapActive = false
    }

    public func refreshPermissions(attemptTapSync: Bool = true) {
        isAccessibilityGranted = AXIsProcessTrusted()
        automationStatus = Self.checkAutomationStatus(promptIfNeeded: false)
        if isAccessibilityGranted {
            trustPollTimer?.invalidate()
            trustPollTimer = nil
        }
        if attemptTapSync {
            syncTapState()
        } else {
            pushSnapshotToController()
        }
    }

    public func requestAccessibilityAuthorization() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        isAccessibilityGranted = trusted
        if trusted {
            syncTapState()
            return
        }
        lastStatusNote = "请在“系统设置 → 隐私与安全性 → 辅助功能”中允许 ProZip"
        startTrustPolling()
        if !NSWorkspace.shared.frontmostApplication.map({ $0.bundleIdentifier == "com.apple.systempreferences" }).selfOrFalse {
            // AXIsProcessTrustedWithOptions(prompt: true) normally opens the dialog;
            // keep polling so the tap starts as soon as the switch is enabled.
        }
    }

    public func requestAutomationAuthorization() {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").isEmpty == false else {
            automationStatus = .finderNotRunning
            lastStatusNote = "请先打开访达（Finder），然后再授权控制访达"
            return
        }
        lastStatusNote = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let status = Self.checkAutomationStatus(promptIfNeeded: true)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.automationStatus = status
                if status == .denied {
                    self.lastStatusNote = "控制访达权限已被拒绝，请在系统设置中勾选访达"
                    self.openAutomationSettings()
                }
                self.syncTapState()
            }
        }
    }

    public func requestAllAuthorizations() {
        refreshPermissions(attemptTapSync: false)
        if !isAccessibilityGranted {
            requestAccessibilityAuthorization()
        }
        if automationStatus == .notDetermined || automationStatus == .finderNotRunning {
            requestAutomationAuthorization()
        } else if automationStatus == .denied {
            openAutomationSettings()
        }
    }

    public func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        startTrustPolling()
    }

    public func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    private func observePreferencesAndSystemState() {
        preferences.$finderSpacebarPreviewEnabled
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncTapState()
            }
            .store(in: &cancellables)

        preferences.$finderSpacebarPreviewScope
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.pushSnapshotToController()
            }
            .store(in: &cancellables)

        preferences.$associatedArchiveFormats
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.pushSnapshotToController()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshPermissions(attemptTapSync: true)
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if !self.isAccessibilityGranted && self.preferences.finderSpacebarPreviewEnabled {
                    self.refreshPermissions(attemptTapSync: true)
                }
            }
            .store(in: &cancellables)

        DistributedNotificationCenter.default().publisher(for: Notification.Name("com.apple.accessibility.api"))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshPermissions(attemptTapSync: true)
            }
            .store(in: &cancellables)
    }

    private func startTrustPolling() {
        trustPollTimer?.invalidate()
        var ticksRemaining = 90
        trustPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self else {
                    timer.invalidate()
                    return
                }
                ticksRemaining -= 1
                self.refreshPermissions(attemptTapSync: true)
                if self.isAccessibilityGranted || ticksRemaining <= 0 {
                    timer.invalidate()
                    self.trustPollTimer = nil
                }
            }
        }
    }

    private func pushSnapshotToController() {
        tapController.updateConfiguration(
            enabled: preferences.finderSpacebarPreviewEnabled,
            scope: preferences.finderSpacebarPreviewScope,
            associatedExtensions: preferences.cachedAssociatedExtensions,
            automationGranted: automationStatus == .granted
        )
    }

    private func syncTapState() {
        pushSnapshotToController()
        guard preferences.finderSpacebarPreviewEnabled else {
            tapController.stop()
            isTapActive = false
            return
        }
        guard isAccessibilityGranted else {
            tapController.stop()
            isTapActive = false
            return
        }
        let started = tapController.startIfNeeded()
        isTapActive = started
        if !started {
            lastStatusNote = "未能启动访达空格监听（请确认已在辅助功能中允许 ProZip）"
        } else {
            lastStatusNote = nil
        }
    }

    private nonisolated static func checkAutomationStatus(promptIfNeeded: Bool) -> AutomationPermissionStatus {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").isEmpty else {
            return .finderNotRunning
        }
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder")
        let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, promptIfNeeded)
        switch status {
        case noErr:
            return .granted
        case OSStatus(errAEEventWouldRequireUserConsent):
            return .notDetermined
        case OSStatus(errAEEventNotPermitted):
            return .denied
        case OSStatus(procNotFound):
            return .finderNotRunning
        default:
            return .notDetermined
        }
    }
}

private extension Optional where Wrapped == Bool {
    var selfOrFalse: Bool { self ?? false }
}

private final class TapController: @unchecked Sendable {
    private struct ConfigState {
        var enabled = false
        var scope: FinderSpacebarPreviewScope = .claimedOnly
        var associatedExtensions: Set<String> = []
        var automationGranted = false
        var swallowNextSpaceKeyUp = false
    }

    private static let spaceKeyCode: Int64 = 49
    private static let syntheticReplayTag: Int64 = 0x505A_5350 // "PZSP"
    private static let finderBundleID = "com.apple.finder"
    private static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "org.prozip.ProZip"

    private let lock = OSAllocatedUnfairLock(initialState: ConfigState())
    private let finderSelectionQueue = DispatchQueue(label: "org.prozip.finder-spacebar-selection", qos: .userInteractive)
    private var finderSelectionScript: NSAppleScript?

    private var machPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var onOpenArchive: ((URL) -> Void)?
    var onAutomationDenied: (() -> Void)?

    func updateConfiguration(
        enabled: Bool,
        scope: FinderSpacebarPreviewScope,
        associatedExtensions: Set<String>,
        automationGranted: Bool
    ) {
        lock.withLock { state in
            state.enabled = enabled
            state.scope = scope
            state.associatedExtensions = associatedExtensions
            state.automationGranted = automationGranted
        }
    }

    func startIfNeeded() -> Bool {
        if let port = machPort {
            CGEvent.tapEnable(tap: port, enable: true)
            return CGEvent.tapIsEnabled(tap: port)
        }

        let mask = CGEventMask((1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue))
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let controller = Unmanaged<TapController>.fromOpaque(refcon).takeUnretainedValue()
                return controller.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: userInfo
        ) else {
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            CFMachPortInvalidate(port)
            return false
        }

        machPort = port
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return CGEvent.tapIsEnabled(tap: port)
    }

    func stop() {
        lock.withLock { state in
            state.swallowNextSpaceKeyUp = false
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        if let port = machPort {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
            machPort = nil
        }
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port = machPort {
                CGEvent.tapEnable(tap: port, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }

        guard event.getIntegerValueField(.keyboardEventKeycode) == Self.spaceKeyCode else {
            return Unmanaged.passUnretained(event)
        }

        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticReplayTag {
            return Unmanaged.passUnretained(event)
        }

        let snapshot = lock.withLock { $0 }
        guard snapshot.enabled else {
            return Unmanaged.passUnretained(event)
        }

        if type == .keyUp {
            let shouldSwallow = lock.withLock { state -> Bool in
                let current = state.swallowNextSpaceKeyUp
                state.swallowNextSpaceKeyUp = false
                return current
            }
            return shouldSwallow ? nil : Unmanaged.passUnretained(event)
        }

        // KeyDown handling
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            return snapshot.swallowNextSpaceKeyUp ? nil : Unmanaged.passUnretained(event)
        }

        let blockingModifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift, .maskSecondaryFn]
        if !event.flags.intersection(blockingModifiers).isEmpty {
            return Unmanaged.passUnretained(event)
        }

        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              frontApp.bundleIdentifier == Self.finderBundleID else {
            return Unmanaged.passUnretained(event)
        }

        if Self.isQuickLookHUDVisible() {
            return Unmanaged.passUnretained(event)
        }

        let finderApp = AXUIElementCreateApplication(frontApp.processIdentifier)
        if Self.isFinderEditingOrModal(finderApp: finderApp) {
            return Unmanaged.passUnretained(event)
        }

        // Fast synchronous AX selection lookup (typically < 2 ms in List/Column/Outline views)
        switch Self.resolveSelectedURLSynchronously(finderApp: finderApp) {
        case .multipleItems:
            return Unmanaged.passUnretained(event)
        case .singleURL(let url):
            let matches = FinderSpacebarArchivePolicy.isCandidateArchive(
                url: url,
                scope: snapshot.scope,
                cachedAssociatedExtensions: snapshot.associatedExtensions,
                bundleIdentifier: Self.bundleIdentifier
            )
            if matches {
                lock.withLock { $0.swallowNextSpaceKeyUp = true }
                onOpenArchive?(url)
                return nil
            }
            return Unmanaged.passUnretained(event)
        case .unavailable:
            guard snapshot.automationGranted else {
                return Unmanaged.passUnretained(event)
            }
            // Swallow this keyDown so Quick Look cannot flicker, then inspect via AppleScript
            // off the tap thread (~10 ms) and replay synthetic Spacebar if not a claimed archive.
            lock.withLock { $0.swallowNextSpaceKeyUp = true }
            finderSelectionQueue.async { [weak self] in
                guard let self else { return }
                switch self.queryFinderSingleSelectionURL() {
                case .url(let url):
                    let current = self.lock.withLock { $0 }
                    if FinderSpacebarArchivePolicy.isCandidateArchive(
                        url: url,
                        scope: current.scope,
                        cachedAssociatedExtensions: current.associatedExtensions,
                        bundleIdentifier: Self.bundleIdentifier
                    ) {
                        self.onOpenArchive?(url)
                        return
                    }
                    Self.postSyntheticSpacebar()
                case .denied:
                    self.lock.withLock { $0.automationGranted = false }
                    self.onAutomationDenied?()
                    Self.postSyntheticSpacebar()
                case .none:
                    Self.postSyntheticSpacebar()
                }
            }
            return nil
        }
    }

    private enum AXSelectionLookup {
        case singleURL(URL)
        case multipleItems
        case unavailable
    }

    private enum ScriptSelectionLookup {
        case url(URL)
        case denied
        case none
    }

    private static func isFinderEditingOrModal(finderApp: AXUIElement) -> Bool {
        var focusedWindowRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(finderApp, kAXFocusedWindowAttribute as CFString, &focusedWindowRef) == .success,
           let focusedWindow = focusedWindowRef {
            let windowElement = focusedWindow as! AXUIElement
            let subrole = copyStringAttribute(windowElement, attribute: kAXSubroleAttribute as CFString)
            if FinderSpacebarArchivePolicy.isDialogOrSheetSubrole(subrole) {
                return true
            }
            var sheetsRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(windowElement, "AXSheets" as CFString, &sheetsRef) == .success,
               let sheets = sheetsRef as? [AXUIElement], !sheets.isEmpty {
                return true
            }
        }

        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(finderApp, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef else {
            return false
        }
        let element = focused as! AXUIElement
        let role = copyStringAttribute(element, attribute: kAXRoleAttribute as CFString)
        let subrole = copyStringAttribute(element, attribute: kAXSubroleAttribute as CFString)
        return FinderSpacebarArchivePolicy.isTextInputOrControlRole(role, subrole: subrole)
    }

    private static func resolveSelectedURLSynchronously(finderApp: AXUIElement) -> AXSelectionLookup {
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(finderApp, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef else {
            return .unavailable
        }
        let element = focused as! AXUIElement

        var selectedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedChildrenAttribute as CFString, &selectedRef) == .success,
           let selected = selectedRef as? [AXUIElement], !selected.isEmpty {
            if selected.count > 1 { return .multipleItems }
            if let url = FinderSpacebarArchivePolicy.extractFileURL(from: selected[0]) {
                return .singleURL(url)
            }
        }

        if let url = FinderSpacebarArchivePolicy.extractFileURL(from: element) {
            return .singleURL(url)
        }
        return .unavailable
    }

    private func queryFinderSingleSelectionURL() -> ScriptSelectionLookup {
        if finderSelectionScript == nil {
            let source = """
            tell application "Finder"
                set sel to selection
                if (count of sel) is not 1 then return ""
                return POSIX path of ((item 1 of sel) as alias)
            end tell
            """
            let script = NSAppleScript(source: source)
            script?.compileAndReturnError(nil)
            finderSelectionScript = script
        }

        guard let script = finderSelectionScript else { return .none }
        var errorDict: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorDict)
        if let errorDict {
            if let code = errorDict[NSAppleScript.errorNumber] as? Int, code == Int(errAEEventNotPermitted) {
                return .denied
            }
            return .none
        }
        guard let path = descriptor.stringValue, !path.isEmpty else {
            return .none
        }
        return .url(URL(fileURLWithPath: path))
    }

    private static func postSyntheticSpacebar() {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(spaceKeyCode), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(spaceKeyCode), keyDown: false) else {
            return
        }
        keyDown.setIntegerValueField(.eventSourceUserData, value: syntheticReplayTag)
        keyUp.setIntegerValueField(.eventSourceUserData, value: syntheticReplayTag)
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
    }

    private static func isQuickLookHUDVisible() -> Bool {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        for info in windowList {
            guard let owner = info[kCGWindowOwnerName as String] as? String,
                  owner == "QuickLookUIService" else {
                continue
            }
            let alpha = (info[kCGWindowAlpha as String] as? Double) ?? 1.0
            if alpha > 0.01 {
                return true
            }
        }
        return false
    }

    private static func copyStringAttribute(_ element: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? String
    }
}
