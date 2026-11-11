import Foundation
import Combine
import CoreServices
import UniformTypeIdentifiers

// MARK: - Persistent Preferences (aligned with data/defaults-keys.tsv)

public enum AppearancePreference: String, CaseIterable, Codable, Sendable {
    case light
    case dark
    case automatic

    public var title: String {
        switch self {
        case .light: return "浅色"
        case .dark: return "深色"
        case .automatic: return "自动"
        }
    }
}

public enum WorkspaceViewMode: String, CaseIterable, Codable, Sendable {
    case icons
    case list
    case columns

    public var title: String {
        switch self {
        case .icons: return "图标"
        case .list: return "列表"
        case .columns: return "分栏"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .icons: return "square.grid.2x2"
        case .list: return "list.bullet"
        case .columns: return "rectangle.split.3x1"
        }
    }
}

public struct RecentArchiveRecord: Codable, Hashable, Identifiable, Sendable {
    public var id: String { path }
    public let path: String
    public let openedAt: Double // Apple epoch seconds

    public var url: URL { URL(fileURLWithPath: path) }
    public var openedDate: Date { Date(timeIntervalSinceReferenceDate: openedAt) }

    public init(path: String, openedAt: Double = Date().timeIntervalSinceReferenceDate) {
        self.path = path
        self.openedAt = openedAt
    }
}

public final class ProZipPreferences: ObservableObject, @unchecked Sendable {
    public static let shared = ProZipPreferences()

    private let defaults: UserDefaults
    private let fileAssociationSystem: any FileAssociationSystem
    private let fileAssociationQueue = DispatchQueue(label: "org.prozip.file-associations", qos: .userInitiated)
    private var fileAssociationGeneration = 0
    private var actualAssociatedExtensions: Set<String> = []
    private var associationTypesByExtension: [String: String] = [:]
    public private(set) var fileAssociationsLoaded = false

    // General & Appearance
    @Published public var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: "launchAtLogin") }
    }
    @Published public var appearance: AppearancePreference {
        didSet { defaults.set(appearance.rawValue, forKey: "appearance.preference.v1") }
    }
    @Published public var preferredLanguage: String {
        didSet {
            defaults.set(preferredLanguage, forKey: "localization.preferredLanguage.v1")
            if preferredLanguage == "system" { defaults.removeObject(forKey: "AppleLanguages") }
            else { defaults.set([preferredLanguage], forKey: "AppleLanguages") }
        }
    }
    public let languageAtLaunch: String
    private let localizationBundleAtLaunch: Bundle

    public var isLanguageRestartRequired: Bool { preferredLanguage != languageAtLaunch }

    public func requestLanguageRestart(notificationCenter: NotificationCenter = .default) {
        guard isLanguageRestartRequired else { return }
        notificationCenter.post(name: .proZipRestartRequested, object: self)
    }

    public func localizedString(_ key: String, _ arguments: CVarArg...) -> String {
        let value = localizationBundleAtLaunch.localizedString(forKey: key, value: key, table: nil)
        return arguments.isEmpty ? value : String(format: value, arguments: arguments)
    }

    private static func localizationBundle(for language: String, in bundle: Bundle) -> Bundle {
        let languages = language == "system" ? Locale.preferredLanguages : [language]
        guard let localization = Bundle.preferredLocalizations(from: bundle.localizations, forPreferences: languages).first,
              let path = bundle.path(forResource: localization, ofType: "lproj"),
              let localized = Bundle(path: path) else { return bundle }
        return localized
    }
    @Published public var workspaceViewMode: WorkspaceViewMode {
        didSet { defaults.set(workspaceViewMode.rawValue, forKey: "workspaceViewMode.v1") }
    }
    @Published public var showsAuxiliaryEntries: Bool {
        didSet { defaults.set(showsAuxiliaryEntries, forKey: "showsAuxiliaryEntries.v1") }
    }

    // Hover Preview (Open Source: Unlocked by default)
    @Published public var hoverPreviewEnabled: Bool {
        didSet { defaults.set(hoverPreviewEnabled, forKey: "hoverPreviewEnabled.v1") }
    }
    @Published public var hoverVideoEnabled: Bool {
        didSet { defaults.set(hoverVideoEnabled, forKey: "hoverVideoEnabled.v1") }
    }
    @Published public var hoverAudioAutoplay: Bool {
        didSet { defaults.set(hoverAudioAutoplay, forKey: "hoverAudioAutoplay.v1") }
    }
    @Published public var hoverVideoMuted: Bool {
        didSet { defaults.set(hoverVideoMuted, forKey: "hoverVideoMuted.v1") }
    }
    @Published public var hoverVideoLimitMB: Int {
        didSet { defaults.set(hoverVideoLimitMB, forKey: "hoverVideoLimitMB.v1") }
    }

    // Onboarding
    @Published public var associatedArchiveFormats: [String] {
        didSet { defaults.set(associatedArchiveFormats, forKey: "fileAssociations.enabledExts.v1") }
    }

    @Published public var onboardingCompleted: Bool {
        didSet { defaults.set(onboardingCompleted, forKey: "onboarding.hasCompleted.v1") }
    }
    @Published public var onboardingCurrentPage: Int {
        didSet { defaults.set(onboardingCurrentPage, forKey: "onboarding.currentPage.v2") }
    }

    // Compression
    @Published public var defaultPurpose: CreationProfile.Purpose {
        didSet { defaults.set(defaultPurpose.rawValue, forKey: "archiveCreation.defaultPurpose.v1") }
    }
    @Published public var defaultCreatesSplitVolumes: Bool {
        didSet { defaults.set(defaultCreatesSplitVolumes, forKey: "archiveCreation.defaultCreatesSplitVolumes.v1") }
    }
    @Published public var defaultVolumeSizeBytes: Int64 {
        didSet { defaults.set(defaultVolumeSizeBytes, forKey: "archiveCreation.defaultVolumeSize.v1") }
    }
    @Published public var defaultPreservesMacMetadata: Bool {
        didSet { defaults.set(defaultPreservesMacMetadata, forKey: "archiveCreation.defaultPreservesMacMetadata.v1") }
    }
    @Published public var processorCount: Int {
        didSet { defaults.set(processorCount, forKey: "archiveCreation.processorCount.v1") }
    }
    @Published public var windowsNameRepair: Bool {
        didSet { defaults.set(windowsNameRepair, forKey: "archiveCreation.windowsNameRepair") }
    }

    // Extraction
    @Published public var directExtractOnDoubleClick: Bool {
        didSet { defaults.set(directExtractOnDoubleClick, forKey: "extraction.opening.direct") }
    }
    @Published public var automaticallySelectsResults: Bool {
        didSet {
            defaults.set(automaticallySelectsResults, forKey: "extraction.automaticallySelectsResults.v1")
            defaults.set(automaticallySelectsResults, forKey: "extraction.completion.reveal_results")
        }
    }
    @Published public var extractionCompletionAction: ArchiveCompletionAction {
        didSet { defaults.set(extractionCompletionAction.rawValue, forKey: "extraction.completion.action") }
    }
    @Published public var automaticallyClosesArchive: Bool {
        didSet { defaults.set(automaticallyClosesArchive, forKey: "extraction.automaticallyClosesArchive.v1") }
    }
    @Published public var filtersSystemAuxiliaryFiles: Bool {
        didSet { defaults.set(filtersSystemAuxiliaryFiles, forKey: "extraction.filtersSystemAuxiliaryFiles.v1") }
    }
    @Published public var filtersDMGInstallerArtifacts: Bool {
        didSet { defaults.set(filtersDMGInstallerArtifacts, forKey: "extraction.filtersDMGInstallerArtifacts.v1") }
    }

    // Password
    @Published public var revealsPasswordByDefault: Bool {
        didSet { defaults.set(revealsPasswordByDefault, forKey: "archivePassword.revealsByDefault.v1") }
    }
    @Published public var passwordBookAutoSave: Bool {
        didSet { defaults.set(passwordBookAutoSave, forKey: "passwordBook.autoSave.v1") }
    }
    @Published public var passwordBookAutoUnlock: Bool {
        didSet { defaults.set(passwordBookAutoUnlock, forKey: "passwordBook.autoUnlock.v1") }
    }

    // Flow & Application Installation
    @Published public var quickInstallApplication: Bool {
        didSet { defaults.set(quickInstallApplication, forKey: "applicationInstallation.quickInstall.v1") }
    }
    @Published public var installCompletionAction: ArchiveCompletionAction {
        didSet { defaults.set(installCompletionAction.rawValue, forKey: "applicationInstallation.completedArchiveAction.v1") }
    }
    @Published public var installAutomaticallyClosesArchive: Bool {
        didSet { defaults.set(installAutomaticallyClosesArchive, forKey: "applicationInstallation.automaticallyClosesArchive.v1") }
    }
    @Published public var allowedOpenFormats: Set<String> {
        didSet { defaults.set(Array(allowedOpenFormats).sorted(), forKey: "openFile.allowedFormats.v1") }
    }

    // Mini Window
    @Published public var prefersMiniWindow: Bool {
        didSet { defaults.set(prefersMiniWindow, forKey: "archiveOpening.prefersMiniWindow.v1") }
    }
    @Published public var miniUsesLiquidGlass: Bool {
        didSet { defaults.set(miniUsesLiquidGlass, forKey: "miniWindow.usesLiquidGlass.v1") }
    }
    @Published public var miniUsesColoredControlButtons: Bool {
        didSet { defaults.set(miniUsesColoredControlButtons, forKey: "miniWindow.usesColoredControlButtons.v1") }
    }

    // Box (MenuBar Shelf)
    @Published public var boxEnabled: Bool {
        didSet { defaults.set(boxEnabled, forKey: "box.enabled.v1") }
    }
    @Published public var boxColor: String {
        didSet { defaults.set(boxColor, forKey: "box.color") }
    }
    @Published public var boxShellColorOpacity: Double {
        didSet { defaults.set(boxShellColorOpacity, forKey: "box.shellColorOpacity.v1") }
    }
    @Published public var boxIdleDelaySeconds: Int {
        didSet { defaults.set(boxIdleDelaySeconds, forKey: "box.idleDelay.v1") }
    }

    // Finder & Recent Archives
    @Published public var monitorsExternalVolumes: Bool {
        didSet {
            defaults.set(monitorsExternalVolumes, forKey: "finder.monitorsExternalVolumes.v1")
            if oldValue != monitorsExternalVolumes {
                DistributedNotificationCenter.default().postNotificationName(
                    Notification.Name("org.prozip.ProZip.finderPreferencesChanged"),
                    object: nil, userInfo: nil, deliverImmediately: true
                )
            }
        }
    }
    @Published public var recentArchives: [RecentArchiveRecord] {
        didSet {
            if let data = try? JSONEncoder().encode(recentArchives) {
                defaults.set(data, forKey: "recentArchives.v1")
            }
        }
    }

    public init(defaults: UserDefaults = .standard, resourceBundle: Bundle = .main,
                fileAssociationSystem: any FileAssociationSystem = LaunchServicesFileAssociationSystem()) {
        self.defaults = defaults
        self.fileAssociationSystem = fileAssociationSystem
        let language = defaults.string(forKey: "localization.preferredLanguage.v1") ?? "system"
        self.languageAtLaunch = language
        self.localizationBundleAtLaunch = Self.localizationBundle(for: language, in: resourceBundle)

        self.launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        self.appearance = AppearancePreference(rawValue: defaults.string(forKey: "appearance.preference.v1") ?? "") ?? .automatic
        self.preferredLanguage = language
        self.workspaceViewMode = WorkspaceViewMode(rawValue: defaults.string(forKey: "workspaceViewMode.v1") ?? "") ?? .list
        self.showsAuxiliaryEntries = defaults.bool(forKey: "showsAuxiliaryEntries.v1")

        self.hoverPreviewEnabled = defaults.object(forKey: "hoverPreviewEnabled.v1") as? Bool ?? true
        self.hoverVideoEnabled = defaults.object(forKey: "hoverVideoEnabled.v1") as? Bool ?? true
        self.hoverAudioAutoplay = defaults.object(forKey: "hoverAudioAutoplay.v1") as? Bool ?? true
        self.hoverVideoMuted = defaults.object(forKey: "hoverVideoMuted.v1") as? Bool ?? true
        let limit = defaults.integer(forKey: "hoverVideoLimitMB.v1")
        self.hoverVideoLimitMB = limit > 0 ? limit : 100

        self.onboardingCompleted = defaults.bool(forKey: "onboarding.hasCompleted.v1")
        self.associatedArchiveFormats = defaults.stringArray(forKey: "fileAssociations.enabledExts.v1") ?? []
        self.onboardingCurrentPage = defaults.integer(forKey: "onboarding.currentPage.v2")

        self.defaultPurpose = CreationProfile.Purpose(rawValue: defaults.string(forKey: "archiveCreation.defaultPurpose.v1") ?? "") ?? .general
        self.defaultCreatesSplitVolumes = defaults.bool(forKey: "archiveCreation.defaultCreatesSplitVolumes.v1")
        let volSize = defaults.object(forKey: "archiveCreation.defaultVolumeSize.v1") as? Int64
        self.defaultVolumeSizeBytes = volSize ?? (100 * 1024 * 1024)
        self.defaultPreservesMacMetadata = defaults.object(forKey: "archiveCreation.defaultPreservesMacMetadata.v1") as? Bool ?? true
        self.processorCount = defaults.integer(forKey: "archiveCreation.processorCount.v1")
        self.windowsNameRepair = defaults.object(forKey: "archiveCreation.windowsNameRepair") as? Bool ?? true

        self.directExtractOnDoubleClick = defaults.bool(forKey: "extraction.opening.direct")
        self.automaticallySelectsResults = defaults.object(forKey: "extraction.automaticallySelectsResults.v1") as? Bool ?? true
        self.extractionCompletionAction = ArchiveCompletionAction(rawValue: defaults.string(forKey: "extraction.completion.action") ?? "") ?? .ask
        self.automaticallyClosesArchive = defaults.bool(forKey: "extraction.automaticallyClosesArchive.v1")
        self.filtersSystemAuxiliaryFiles = defaults.object(forKey: "extraction.filtersSystemAuxiliaryFiles.v1") as? Bool ?? true
        self.filtersDMGInstallerArtifacts = defaults.object(forKey: "extraction.filtersDMGInstallerArtifacts.v1") as? Bool ?? true

        self.revealsPasswordByDefault = defaults.bool(forKey: "archivePassword.revealsByDefault.v1")
        self.passwordBookAutoSave = defaults.object(forKey: "passwordBook.autoSave.v1") as? Bool ?? true
        self.passwordBookAutoUnlock = defaults.object(forKey: "passwordBook.autoUnlock.v1") as? Bool ?? true

        self.quickInstallApplication = defaults.object(forKey: "applicationInstallation.quickInstall.v1") as? Bool ?? true
        self.installCompletionAction = ArchiveCompletionAction(rawValue: defaults.string(forKey: "applicationInstallation.completedArchiveAction.v1") ?? "") ?? .ask
        self.installAutomaticallyClosesArchive = defaults.object(forKey: "applicationInstallation.automaticallyClosesArchive.v1") as? Bool ?? true

        if let savedFormats = defaults.stringArray(forKey: "openFile.allowedFormats.v1") {
            self.allowedOpenFormats = Set(savedFormats)
        } else {
            self.allowedOpenFormats = AllowedOpenFormat.defaultAllowedIDs
        }

        self.prefersMiniWindow = defaults.object(forKey: "archiveOpening.prefersMiniWindow.v1") as? Bool ?? false
        self.miniUsesLiquidGlass = defaults.object(forKey: "miniWindow.usesLiquidGlass.v1") as? Bool ?? true
        self.miniUsesColoredControlButtons = defaults.object(forKey: "miniWindow.usesColoredControlButtons.v1") as? Bool ?? true

        self.boxEnabled = defaults.object(forKey: "box.enabled.v1") as? Bool ?? true
        self.boxColor = defaults.string(forKey: "box.color") ?? "chartreuse"
        self.boxShellColorOpacity = defaults.object(forKey: "box.shellColorOpacity.v1") as? Double ?? 0.35
        let idle = defaults.integer(forKey: "box.idleDelay.v1")
        self.boxIdleDelaySeconds = idle > 0 ? idle : 3

        self.monitorsExternalVolumes = defaults.bool(forKey: "finder.monitorsExternalVolumes.v1")

        if let data = defaults.data(forKey: "recentArchives.v1"),
           let decoded = try? JSONDecoder().decode([RecentArchiveRecord].self, from: data) {
            self.recentArchives = decoded
        } else {
            self.recentArchives = []
        }
    }

    @MainActor public var fileAssociationStatuses: [String: FileAssociationGroupStatus] {
        Dictionary(uniqueKeysWithValues: FileAssociationGroup.all.map { group in
            (group.id, FileAssociationGroupStatus(
                associatedCount: group.extensions.filter { actualAssociatedExtensions.contains($0) }.count,
                totalCount: group.extensions.count,
                unresolvedCount: group.extensions.filter { associationTypesByExtension[$0] == nil }.count
            ))
        })
    }

    @MainActor public func additionalAssociationImpact(for groupIDs: Set<String>) -> [String] {
        let types = Set(FileAssociationGroup.all.filter { groupIDs.contains($0.id) }.flatMap(\.extensions)
            .filter { !actualAssociatedExtensions.contains($0) }.compactMap { associationTypesByExtension[$0] })
        return FileAssociationGroup.all.filter { group in
            !groupIDs.contains(group.id) && group.extensions.contains { associationTypesByExtension[$0].map(types.contains) == true }
        }.map(\.title)
    }

    @MainActor public func refreshFileAssociations(for extensions: [String] = FileAssociationGroup.allExtensions) async throws {
        try await runFileAssociationBatch(changes: [:], additionalExtensions: extensions)
    }

    @MainActor public func setFileAssociation(_ ext: String, enabled: Bool) async throws {
        try await runFileAssociationBatch(changes: [ext: enabled], additionalExtensions: [ext])
    }

    @MainActor public func setFileAssociationGroups(_ groupIDs: Set<String>, enabled: Bool) async throws {
        try await applyFileAssociationChanges(Dictionary(uniqueKeysWithValues: groupIDs.map { ($0, enabled) }))
    }

    @MainActor public func applyFileAssociationChanges(_ groups: [String: Bool]) async throws {
        let known = Set(FileAssociationGroup.all.map(\.id))
        guard Set(groups.keys).isSubset(of: known) else { throw Self.associationError("未知的格式关联组。") }
        var changes: [String: Bool] = [:]
        for group in FileAssociationGroup.all {
            if let enabled = groups[group.id] { for ext in group.extensions { changes[ext] = enabled } }
        }
        try await runFileAssociationBatch(changes: changes, additionalExtensions: [])
    }

    private struct AssociationSnapshot: Sendable {
        let associated: Set<String>
        let types: [String: String]
        let errors: [String]
    }

    @MainActor private func runFileAssociationBatch(changes: [String: Bool], additionalExtensions: [String]) async throws {
        fileAssociationGeneration += 1
        let generation = fileAssociationGeneration
        let snapshot: AssociationSnapshot = try await withCheckedThrowingContinuation { continuation in
            fileAssociationQueue.async {
                do { continuation.resume(returning: try self.performFileAssociationBatch(changes: changes, additionalExtensions: additionalExtensions)) }
                catch { continuation.resume(throwing: error) }
            }
        }
        if generation == fileAssociationGeneration {
            actualAssociatedExtensions = snapshot.associated
            associationTypesByExtension = snapshot.types
            fileAssociationsLoaded = true
            associatedArchiveFormats = snapshot.associated.sorted()
        }
        if !snapshot.errors.isEmpty {
            let shown = snapshot.errors.prefix(6).joined(separator: "\n")
            let remaining = snapshot.errors.count > 6 ? "\n另有 \(snapshot.errors.count - 6) 项。" : ""
            throw Self.associationError(shown + remaining)
        }
    }

    private func performFileAssociationBatch(changes: [String: Bool], additionalExtensions: [String]) throws -> AssociationSnapshot {
        let system = fileAssociationSystem
        guard system.isPackagedApplication, let bundleID = system.applicationBundleID else {
            throw Self.associationError("请从已构建的 ProZip 应用程序中查看和设置格式关联。")
        }
        let aliases = Set(FileAssociationGroup.allExtensions + additionalExtensions + Array(changes.keys))
        var types: [String: String] = [:]
        for ext in aliases { types[ext] = system.contentType(forExtension: ext) }
        var requestedTypes: [String: (enabled: Bool, ext: String)] = [:]
        var errors: [String] = []
        for (ext, enabled) in changes {
            guard let type = types[ext] else { errors.append(".\(ext)：无法识别文件类型。"); continue }
            if let previous = requestedTypes[type], previous.enabled != enabled {
                errors.append("部分格式共享打开方式，不能同时启用和还原，请分开设置。")
            }
            requestedTypes[type] = (enabled, ext)
        }
        let backupKey = "fileAssociations.previousHandlers.v1"
        var backups = defaults.dictionary(forKey: backupKey) as? [String: String] ?? [:]
        var attempted: [(type: String, before: String?, after: String)] = []
        if errors.isEmpty {
            do {
                for type in requestedTypes.keys.sorted() {
                    let request = requestedTypes[type]!
                    let current = system.defaultHandler(forContentType: type)
                    let target: String
                    if request.enabled {
                        if Self.sameHandler(current, bundleID) { continue }
                        if let current { backups[type] = current }
                        else { backups.removeValue(forKey: type) }
                        defaults.set(backups, forKey: backupKey)
                        target = bundleID
                    } else {
                        guard Self.sameHandler(current, bundleID) else { continue }
                        guard let previous = backups[type], !Self.sameHandler(previous, bundleID) else {
                            throw Self.associationError(".\(request.ext)：没有可恢复的原默认应用，请在访达“显示简介”中选择打开方式。")
                        }
                        target = previous
                    }
                    attempted.append((type, current, target))
                    try system.setDefaultHandler(target, forContentType: type)
                }
            } catch {
                errors.append(error.localizedDescription)
                var incomplete = false
                for change in attempted.reversed() {
                    let current = system.defaultHandler(forContentType: change.type)
                    if Self.sameHandler(current, change.before) { continue }
                    guard Self.sameHandler(current, change.after), let before = change.before else { incomplete = true; continue }
                    do { try system.setDefaultHandler(before, forContentType: change.type) }
                    catch { incomplete = true }
                }
                if incomplete { errors.append("部分更改无法自动还原，当前关联状态已刷新。") }
            }
        }
        var ours: Set<String> = []
        var handlers: [String: String] = [:]
        for type in Set(types.values) { handlers[type] = system.defaultHandler(forContentType: type) }
        for (ext, type) in types where Self.sameHandler(handlers[type], bundleID) { ours.insert(ext) }
        return AssociationSnapshot(associated: ours, types: types, errors: errors)
    }

    private static func sameHandler(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs, let rhs else { return lhs == nil && rhs == nil }
        return lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }

    private static func associationError(_ message: String) -> NSError {
        NSError(domain: "ProZipFileAssociation", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    // Per-purpose format & strength memory (doc/04 section 2.1 & 7)
    public func defaultFormat(for purpose: CreationProfile.Purpose) -> ArchiveFormat {
        let key = "archiveCreation.defaultFormat.v2.\(purpose.rawValue)"
        if let raw = defaults.string(forKey: key),
           let fmt = ArchiveFormat(rawValue: raw),
           purpose.allowedFormats.contains(fmt) {
            return fmt
        }
        return purpose.defaultFormat
    }

    public func setDefaultFormat(_ format: ArchiveFormat, for purpose: CreationProfile.Purpose) {
        guard purpose.allowedFormats.contains(format) else { return }
        let key = "archiveCreation.defaultFormat.v2.\(purpose.rawValue)"
        defaults.set(format.rawValue, forKey: key)
        objectWillChange.send()
    }

    public func defaultStrength(for purpose: CreationProfile.Purpose) -> CreationProfile.Strength {
        if purpose == .smallest { return .maximum }
        let key = "archiveCreation.defaultStrength.v2.\(purpose.rawValue)"
        if let val = defaults.object(forKey: key) as? Int,
           let strength = CreationProfile.Strength(rawValue: val) {
            return strength
        }
        return purpose.defaultStrength
    }

    public func setDefaultStrength(_ strength: CreationProfile.Strength, for purpose: CreationProfile.Purpose) {
        let key = "archiveCreation.defaultStrength.v2.\(purpose.rawValue)"
        defaults.set(strength.rawValue, forKey: key)
        objectWillChange.send()
    }

    public func resetCompressionDefaults() {
        for purpose in CreationProfile.Purpose.allCases {
            defaults.removeObject(forKey: "archiveCreation.defaultFormat.v2.\(purpose.rawValue)")
            defaults.removeObject(forKey: "archiveCreation.defaultStrength.v2.\(purpose.rawValue)")
        }
        defaultPurpose = .general
        defaultCreatesSplitVolumes = false
        defaultPreservesMacMetadata = true
        objectWillChange.send()
    }

    public func resetAllSettings() {
        resetCompressionDefaults()
        defaultVolumeSizeBytes = 100 * 1024 * 1024
        processorCount = 0
        windowsNameRepair = true
        launchAtLogin = false
        appearance = .automatic
        preferredLanguage = "system"
        workspaceViewMode = .list
        showsAuxiliaryEntries = false
        hoverPreviewEnabled = true
        hoverVideoEnabled = true
        hoverAudioAutoplay = true
        hoverVideoMuted = true
        hoverVideoLimitMB = 100
        directExtractOnDoubleClick = false
        automaticallySelectsResults = true
        extractionCompletionAction = .ask
        automaticallyClosesArchive = false
        filtersSystemAuxiliaryFiles = true
        filtersDMGInstallerArtifacts = true
        revealsPasswordByDefault = false
        passwordBookAutoSave = true
        passwordBookAutoUnlock = true
        quickInstallApplication = true
        installCompletionAction = .ask
        installAutomaticallyClosesArchive = true
        allowedOpenFormats = AllowedOpenFormat.defaultAllowedIDs
        prefersMiniWindow = false
        miniUsesLiquidGlass = true
        miniUsesColoredControlButtons = true
        boxEnabled = true
        boxColor = "chartreuse"
        boxShellColorOpacity = 0.35
        boxIdleDelaySeconds = 3
        monitorsExternalVolumes = false
        for key in ["finder.fixedCompressFormat.v1", "finder.optionKeyQuickSwitch.v1", "updates.autoCheck.v1", "progressWindow.keepOnTop.v1", "archivePassword.inputNoticeSuppressed.v1", "archiveEncryption.noticeSuppressed.v1"] {
            defaults.removeObject(forKey: key)
        }
    }

    public func recordRecentArchive(_ url: URL) {
        var list = recentArchives.filter { $0.path != url.path }
        list.insert(RecentArchiveRecord(path: url.path), at: 0)
        if list.count > 8 {
            list = Array(list.prefix(8))
        }
        recentArchives = list
    }

    public func makeDefaultCreationProfile() -> CreationProfile {
        let purpose = defaultPurpose
        let format = defaultFormat(for: purpose)
        let strength = defaultStrength(for: purpose)
        let cores = processorCount > 0 ? processorCount : ProcessInfo.processInfo.activeProcessorCount
        let split: CreationProfile.SplitPlan? = defaultCreatesSplitVolumes ? .bySize(defaultVolumeSizeBytes) : nil
        return CreationProfile(
            purpose: purpose,
            format: format,
            strength: strength,
            split: split,
            password: nil,
            encryptHeaders: false,
            preserveMacMetadata: purpose == .mac ? true : defaultPreservesMacMetadata,
            processorCount: cores,
            repairWindowsNames: purpose == .windows ? true : windowsNameRepair
        )
    }
}


public extension Notification.Name {
    static let proZipCloseShelf = Notification.Name("ProZipCloseShelf")
    static let proZipRestartRequested = Notification.Name("ProZipRestartRequested")
}
