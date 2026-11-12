import Foundation
import Combine
import Darwin
import ProZipShared

// MARK: - Source Archive Stat (doc/07 section 5 & test E5)

public struct SourceArchiveStat: Equatable, Sendable {
    public let mtime: Date
    public let size: Int64
    public let inode: UInt64

    public init(mtime: Date, size: Int64, inode: UInt64) {
        self.mtime = mtime
        self.size = size
        self.inode = inode
    }

    public static func read(from url: URL) -> SourceArchiveStat? {
        var info = stat()
        guard stat(url.path, &info) == 0 else { return nil }
        return SourceArchiveStat(
            mtime: Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec) + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000),
            size: Int64(info.st_size), inode: UInt64(info.st_ino)
        )
    }
}

// MARK: - Archive Browsing Session (doc/02, doc/07, tests A7, A8, E1-E8)

@MainActor
public final class ArchiveBrowsingSession: ObservableObject {
    public let id: UUID

    @Published public var archiveURL: URL? {
        didSet {
            captureSourceStat()
        }
    }
    @Published public var descriptor: ArchiveDescriptor?
    @Published public var phase: IndexPhase = .idle

    @Published public private(set) var currentDirectoryPath: String = ""
    @Published public private(set) var backStack: [String] = []
    @Published public private(set) var forwardStack: [String] = []

    @Published public var displayedEntries: [ArchiveEntry] = [] {
        didSet {
            displayedEntriesRevision &+= 1
            refreshSelectedEntries()
        }
    }
    public private(set) var displayedEntriesRevision: UInt = 0
    @Published public private(set) var auxiliaryEntryCount: Int = 0
    @Published public var selectedEntryIDs: Set<String> = [] {
        didSet { refreshSelectedEntries() }
    }
    private var selectedEntriesCache: [ArchiveEntry] = []
    public private(set) var selectionAnchorID: String?
    public private(set) var selectionLeadID: String?
    private var refreshEntriesTask: Task<Void, Never>?
    @Published public var showsAuxiliaryEntries: Bool = false {
        didSet {
            guard showsAuxiliaryEntries != oldValue else { return }
            scheduleDisplayedEntriesRefresh()
        }
    }
    @Published public var searchQuery: String = "" {
        didSet {
            guard searchQuery != oldValue else { return }
            scheduleDisplayedEntriesRefresh()
        }
    }

    private func scheduleDisplayedEntriesRefresh() {
        refreshEntriesTask?.cancel()
        refreshEntriesTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled else { return }
            await self?.refreshDisplayedEntries()
        }
    }

    @Published public private(set) var pendingMutations: [ArchiveMutation] = []
    @Published public private(set) var redoMutations: [ArchiveMutation] = []

    @Published public var viewMode: WorkspaceViewMode = .list
    @Published public var isMiniMode: Bool = false
    @Published public var isAlwaysOnTop: Bool = false
    @Published public var isSearchExpanded: Bool = false

    public let index: EntryIndex

    public private(set) var initialSourceStat: SourceArchiveStat?

    public init(
        id: UUID = UUID(),
        archiveURL: URL? = nil,
        descriptor: ArchiveDescriptor? = nil,
        index: EntryIndex? = nil,
        isMiniMode: Bool = false,
        viewMode: WorkspaceViewMode = .list
    ) {
        self.id = id
        self.archiveURL = archiveURL
        self.descriptor = descriptor
        self.isMiniMode = isMiniMode
        self.viewMode = viewMode

        if let existingIndex = index {
            self.index = existingIndex
        } else {
            // Default to an in-memory index for immediate and lightweight operation
            self.index = (try? EntryIndex(inMemory: true)) ?? (try! EntryIndex(url: nil))
        }

        if archiveURL != nil {
            captureSourceStat()
        }
    }

    public convenience init(
        url: URL,
        descriptor: ArchiveDescriptor? = nil,
        isMiniMode: Bool = false,
        viewMode: WorkspaceViewMode = .list
    ) {
        self.init(
            archiveURL: url,
            descriptor: descriptor,
            isMiniMode: isMiniMode,
            viewMode: viewMode
        )
    }

    public var archiveName: String {
        archiveURL?.lastPathComponent ?? descriptor?.url.lastPathComponent ?? "归档"
    }

    public var safeDescriptor: ArchiveDescriptor {
        descriptor ?? ArchiveDescriptor(url: url, format: ArchiveFormat.detect(from: url))
    }

    public var selectedEntries: [ArchiveEntry] { selectedEntriesCache }

    private func refreshSelectedEntries() {
        selectedEntriesCache = selectedEntryIDs.isEmpty ? [] : displayedEntries.filter { selectedEntryIDs.contains($0.id) }
    }

    public var currentItems: [ArchiveEntry] {
        displayedEntries
    }

    public var url: URL {
        archiveURL ?? descriptor?.url ?? URL(fileURLWithPath: "/tmp/untitled.zip")
    }

    public var entries: [ArchiveEntry] {
        get { displayedEntries }
        set { displayedEntries = newValue }
    }

    public var isDraftEdited: Bool {
        get { hasUnsavedChanges }
        set {
            if !newValue { acceptSavedChanges() }
        }
    }

    public var historyIndex: Int {
        backStack.count
    }

    public var pathHistory: [String] {
        backStack + [currentDirectoryPath] + forwardStack.reversed()
    }

    public func selectOnly(_ id: String) {
        selectedEntryIDs = [id]
        selectionAnchorID = id
        selectionLeadID = id
    }

    public func toggleSelection(_ id: String) {
        if selectedEntryIDs.contains(id) {
            selectedEntryIDs.remove(id)
        } else {
            selectedEntryIDs.insert(id)
        }
        selectionAnchorID = id
        selectionLeadID = id
    }

    public func selectRange(to id: String, in orderedEntries: [ArchiveEntry], additive: Bool = false) {
        let anchor = selectionAnchorID ?? orderedEntries.first(where: { selectedEntryIDs.contains($0.id) })?.id
        guard let anchor, let start = orderedEntries.firstIndex(where: { $0.id == anchor }),
              let end = orderedEntries.firstIndex(where: { $0.id == id }) else { selectOnly(id); return }
        let range = Set(orderedEntries[min(start, end)...max(start, end)].map(\.id))
        selectedEntryIDs = additive ? selectedEntryIDs.union(range) : range
        selectionAnchorID = anchor
        selectionLeadID = id
    }

    public func selectAll(_ entries: [ArchiveEntry]) {
        selectedEntryIDs = Set(entries.map(\.id))
        selectionAnchorID = entries.first?.id
        selectionLeadID = entries.last?.id
    }

    @discardableResult
    public func moveSelection(by delta: Int, in orderedEntries: [ArchiveEntry], extending: Bool = false) -> String? {
        guard !orderedEntries.isEmpty else { return nil }
        let current = selectedEntryIDs.isEmpty ? nil : orderedEntries.firstIndex(where: { $0.id == selectionLeadID }) ?? orderedEntries.firstIndex(where: { selectedEntryIDs.contains($0.id) })
        let index = min(orderedEntries.count - 1, max(0, (current ?? (delta > 0 ? -1 : orderedEntries.count)) + delta))
        let id = orderedEntries[index].id
        if extending { selectRange(to: id, in: orderedEntries) } else { selectOnly(id) }
        return id
    }

    public func removeSelectedDraftEntries() {
        let selected = selectedEntries
        do {
            try deleteEntries(selected)
            selectedEntryIDs.removeAll()
        } catch { return }
    }

    public func addDraftMutation(_ mutation: ArchiveMutation) {
        pendingMutations.append(mutation)
        redoMutations.removeAll()
        if case .renameEntry(let old, let new) = mutation { synchronizeRename(from: old, to: new) }
        Task { @MainActor in
            await refreshDisplayedEntries()
        }
    }

    // MARK: - Breadcrumbs & Directory Navigation (doc/02 section 4 & tests A7, A8)

    public var breadcrumbs: [(title: String, path: String)] {
        let rootTitle: String
        if let desc = descriptor {
            rootTitle = desc.url.lastPathComponent
        } else if let url = archiveURL {
            rootTitle = url.lastPathComponent
        } else {
            rootTitle = "根目录"
        }

        var crumbs: [(title: String, path: String)] = [(title: rootTitle, path: "")]
        guard !currentDirectoryPath.isEmpty else {
            return crumbs
        }

        let components = currentDirectoryPath.split(separator: "/").map(String.init)
        var cumulativePath = ""
        for comp in components {
            if cumulativePath.isEmpty {
                cumulativePath = comp
            } else {
                cumulativePath = "\(cumulativePath)/\(comp)"
            }
            crumbs.append((title: comp, path: cumulativePath))
        }

        return crumbs
    }

    public var canGoBack: Bool {
        !backStack.isEmpty
    }

    public var canGoForward: Bool {
        !forwardStack.isEmpty
    }

    public var canGoUp: Bool {
        !currentDirectoryPath.isEmpty
    }

    /// Enters a directory inside the archive, pushing current path to backStack and resetting forwardStack.
    public func enterDirectory(_ path: String) async {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard trimmed != currentDirectoryPath else { return }

        backStack.append(currentDirectoryPath)
        forwardStack.removeAll()
        currentDirectoryPath = trimmed
        selectedEntryIDs.removeAll()
        await refreshDisplayedEntries()
    }

    /// Returns to previous directory in history.
    public func goBack() async {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(currentDirectoryPath)
        currentDirectoryPath = previous
        selectedEntryIDs.removeAll()
        await refreshDisplayedEntries()
    }

    /// Advances to forward directory in history.
    public func goForward() async {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(currentDirectoryPath)
        currentDirectoryPath = next
        selectedEntryIDs.removeAll()
        await refreshDisplayedEntries()
    }

    /// Navigates to enclosing parent directory.
    public func goUp() async {
        guard !currentDirectoryPath.isEmpty else { return }
        let parent = (currentDirectoryPath as NSString).deletingLastPathComponent
        let target = (parent == "." || parent == currentDirectoryPath) ? "" : parent
        await enterDirectory(target)
    }

    // MARK: - Draft Editing & Mutations (doc/07 & tests E1-E8)

    public var hasUnsavedChanges: Bool {
        !pendingMutations.isEmpty
    }

    public var canUndo: Bool {
        !pendingMutations.isEmpty
    }

    public var canRedo: Bool {
        !redoMutations.isEmpty
    }

    public var undoActionTitle: String? {
        pendingMutations.last?.actionDescription
    }

    public var redoActionTitle: String? {
        redoMutations.last?.actionDescription
    }

    private func validateEditing() throws {
        guard initialSourceStat != nil else { return }
        let eligibility = safeDescriptor.editingEligibility
        guard eligibility.allowed else { throw ProZipError.editingNotSupported(eligibility.reason ?? "此格式不支持编辑保存") }
    }

    /// Adds external files into the archive draft.
    public func addFiles(_ urls: [URL], toDirectory dirPath: String? = nil) throws {
        try validateEditing()
        let targetDir = dirPath ?? currentDirectoryPath
        let normalizedTarget = targetDir.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        for url in urls {
            guard url.isFileURL, FileManager.default.fileExists(atPath: url.path) || (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil else {
                throw ProZipError.invalidArchive("待添加文件不存在：\(url.path)")
            }

            let name = url.lastPathComponent
            let archivePath = normalizedTarget.isEmpty ? name : "\(normalizedTarget)/\(name)"
            pendingMutations.append(.addFile(sourceURL: url, archivePath: archivePath))
        }

        redoMutations.removeAll()
        Task { @MainActor in
            await refreshDisplayedEntries()
        }
    }

    /// Marks archive entries for deletion in the draft.
    public func deleteEntries(_ entries: [ArchiveEntry]) throws {
        try validateEditing()
        guard !entries.isEmpty else { return }

        for entry in entries {
            pendingMutations.append(.deleteEntry(archivePath: entry.path))
        }

        redoMutations.removeAll()
        Task { @MainActor in
            await refreshDisplayedEntries()
        }
    }

    /// Renames an existing entry in the draft.
    public func renameEntry(_ entry: ArchiveEntry, to newName: String) throws {
        try validateEditing()
        let newArchivePath = try ArchiveEntryRenamePolicy.validateNewName(
            newName,
            currentEntry: entry,
            siblingEntries: displayedEntries
        )

        pendingMutations.append(.renameEntry(oldArchivePath: entry.path, newArchivePath: newArchivePath))
        redoMutations.removeAll()
        synchronizeRename(from: entry.path, to: newArchivePath, renamedEntry: entry)
        Task { @MainActor in
            await refreshDisplayedEntries()
        }
    }

    /// Replaces the content of an entry with a local file.
    public func replaceEntry(_ entry: ArchiveEntry, with fileURL: URL) throws {
        try validateEditing()
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ProZipError.invalidArchive("替换源文件不存在：\(fileURL.path)")
        }

        pendingMutations.append(.replaceEntry(archivePath: entry.path, replacementSourceURL: fileURL))
        redoMutations.removeAll()
        Task { @MainActor in
            await refreshDisplayedEntries()
        }
    }

    /// Undoes the last mutation.
    public func undo() async {
        guard let mutation = pendingMutations.popLast() else { return }
        redoMutations.append(mutation)
        if case .renameEntry(let old, let new) = mutation { synchronizeRename(from: new, to: old) }
        await refreshDisplayedEntries()
    }

    /// Redoes the undone mutation.
    public func redo() async {
        guard let mutation = redoMutations.popLast() else { return }
        pendingMutations.append(mutation)
        if case .renameEntry(let old, let new) = mutation { synchronizeRename(from: old, to: new) }
        await refreshDisplayedEntries()
    }

    /// Discards all draft mutations.
    public func discardChanges() async {
        guard hasUnsavedChanges || canRedo else { return }
        for mutation in pendingMutations.reversed() {
            if case .renameEntry(let old, let new) = mutation { synchronizeRename(from: new, to: old) }
        }
        pendingMutations.removeAll()
        redoMutations.removeAll()
        await restoreBaselineNavigation()
        await refreshDisplayedEntries()
    }

    /// A successful publication keeps the target paths and view until the saved index is reloaded.
    public func acceptSavedChanges() {
        pendingMutations.removeAll()
        redoMutations.removeAll()
    }

    private func synchronizeRename(from old: String, to new: String, renamedEntry: ArchiveEntry? = nil) {
        var idMapping: [String: String] = [:]
        for entry in displayedEntries + (renamedEntry.map { [$0] } ?? []) {
            let path = Self.renamedPath(entry.path, from: old, to: new)
            if path != entry.path { idMapping[entry.id] = Self.entry(entry, at: path).id }
        }
        idMapping[ArchiveEntry.makeID(path: old, type: .directory, crc32: 0, uncompressedSize: 0)] =
            ArchiveEntry.makeID(path: new, type: .directory, crc32: 0, uncompressedSize: 0)
        selectedEntryIDs = Set(selectedEntryIDs.map { idMapping[$0] ?? $0 })
        selectionAnchorID = selectionAnchorID.map { idMapping[$0] ?? $0 }
        selectionLeadID = selectionLeadID.map { idMapping[$0] ?? $0 }
        currentDirectoryPath = Self.renamedPath(currentDirectoryPath, from: old, to: new)
        backStack = backStack.map { Self.renamedPath($0, from: old, to: new) }
        forwardStack = forwardStack.map { Self.renamedPath($0, from: old, to: new) }
        displayedEntries = displayedEntries.map { entry in
            let path = Self.renamedPath(entry.path, from: old, to: new)
            return path == entry.path ? entry : Self.entry(entry, at: path)
        }
    }

    private func restoreBaselineNavigation() async {
        let current = currentDirectoryPath
        let back = backStack
        let forward = forwardStack
        var resolved: [String: String] = ["": ""]
        for path in Set([current] + back + forward) where !path.isEmpty {
            var candidate = path
            while !candidate.isEmpty {
                if let entry = try? await index.entry(forPath: candidate), entry.isDirectory { break }
                candidate = (candidate as NSString).deletingLastPathComponent
            }
            resolved[path] = candidate
        }
        guard pendingMutations.isEmpty, currentDirectoryPath == current, backStack == back, forwardStack == forward else { return }
        let directory = resolved[current] ?? ""
        func history(_ paths: [String]) -> [String] {
            var result: [String] = []
            for path in paths {
                let target = resolved[path] ?? ""
                if result.last != target { result.append(target) }
            }
            while result.last == directory { result.removeLast() }
            return result
        }
        currentDirectoryPath = directory
        backStack = history(back)
        forwardStack = history(forward)
    }

    private nonisolated static func renamedPath(_ path: String, from old: String, to new: String) -> String {
        path == old || path.hasPrefix(old + "/") ? new + path.dropFirst(old.count) : path
    }

    private nonisolated static func entry(_ entry: ArchiveEntry, at path: String) -> ArchiveEntry {
        ArchiveEntry(
            id: ArchiveEntry.makeID(path: path, type: entry.type, crc32: entry.crc32, uncompressedSize: entry.uncompressedSize),
            path: path, type: entry.type,
            uncompressedSize: entry.uncompressedSize, compressedSize: entry.compressedSize,
            modifiedAt: entry.modifiedAt, permissions: entry.permissions, crc32: entry.crc32,
            isEncrypted: entry.isEncrypted, symlinkTarget: entry.symlinkTarget,
            encryptionGroupID: entry.encryptionGroupID
        )
    }

    // MARK: - Source Modification Detection (doc/07 section 5 & test E5)

    /// Captures file mtime, size, and inode to detect concurrent disk modifications.
    public func captureSourceStat() {
        guard let url = archiveURL else {
            initialSourceStat = nil
            return
        }

        initialSourceStat = SourceArchiveStat.read(from: url)
    }

    /// Returns true if the underlying archive file has been modified, moved, or truncated externally.
    public func hasSourceArchiveChangedOnDisk() -> Bool {
        guard let initial = initialSourceStat, let url = archiveURL else { return false }

        var s = stat()
        if stat(url.path, &s) != 0 {
            return true
        }

        let currentMtime = Date(timeIntervalSince1970: TimeInterval(s.st_mtimespec.tv_sec) + TimeInterval(s.st_mtimespec.tv_nsec) / 1_000_000_000.0)
        let currentSize = Int64(s.st_size)
        let currentInode = UInt64(s.st_ino)

        if currentInode != initial.inode || currentSize != initial.size || abs(currentMtime.timeIntervalSince(initial.mtime)) > 0.001 {
            return true
        }

        return false
    }

    // MARK: - Index Population & Display Refresh

    /// Populates the session's entry index and refreshes UI entries.
    public func loadEntries(_ entries: [ArchiveEntry]) async throws {
        phase = .preliminary(loadedCount: entries.count)
        try await index.rebuild(with: entries)
        phase = .ready(totalCount: entries.count)
        await refreshDisplayedEntries()
    }

    /// Fetches directory entries or search results and overlays in-memory pending mutations.
    public func refreshDisplayedEntries() async {
        let directory = currentDirectoryPath
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let mutations = pendingMutations
        let includeAuxiliary = showsAuxiliaryEntries
        do {
            let rawEntries: [ArchiveEntry]
            if !query.isEmpty {
                // shortcut: edited searches replay the full index so renamed ancestors match; index the overlay if large drafts need faster search.
                if mutations.isEmpty {
                    rawEntries = try await index.search(keyword: query, includeAuxiliary: includeAuxiliary)
                } else {
                    rawEntries = try await index.allEntries(includeAuxiliary: true)
                }
            } else {
                rawEntries = try await index.listDirectory(
                    parentPath: Self.pathBeforeRenames(directory, mutations: mutations[...]),
                    includeAuxiliary: includeAuxiliary || !mutations.isEmpty,
                    includeDiskImageBackground: includeAuxiliary || !mutations.isEmpty,
                    includeApplicationsShortcut: includeAuxiliary || !mutations.isEmpty,
                    limit: Int(Int32.max)
                )
            }

            let entries: [ArchiveEntry]
            let auxiliaryCount: Int
            if mutations.isEmpty {
                entries = try await Self.overlay(mutations, on: rawEntries, directory: directory, query: query, includeAuxiliary: includeAuxiliary)
                let allCount = try await index.countDirectory(parentPath: directory, includeAuxiliary: true, includeDiskImageBackground: true, includeApplicationsShortcut: true)
                let visibleCount = try await index.countDirectory(parentPath: directory)
                auxiliaryCount = allCount - visibleCount
            } else {
                let allEntries = try await Self.overlay(mutations, on: rawEntries, directory: directory, query: query, includeAuxiliary: true)
                let visibleEntries = allEntries.filter { !$0.isAuxiliary && !$0.isDiskImageBackground && !$0.isApplicationsShortcut }
                entries = includeAuxiliary ? allEntries : visibleEntries
                auxiliaryCount = allEntries.count - visibleEntries.count
            }
            guard currentDirectoryPath == directory, searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) == query,
                  pendingMutations == mutations, showsAuxiliaryEntries == includeAuxiliary else { return }
            displayedEntries = entries
            auxiliaryEntryCount = auxiliaryCount
            let visibleIDs = Set(entries.map(\.id))
            let selection = selectedEntryIDs.intersection(visibleIDs)
            if selection != selectedEntryIDs { selectedEntryIDs = selection }
            if let anchor = selectionAnchorID, !visibleIDs.contains(anchor) { selectionAnchorID = nil }
            if let lead = selectionLeadID, !visibleIDs.contains(lead) { selectionLeadID = nil }
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            guard currentDirectoryPath == directory, searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) == query,
                  pendingMutations == mutations, showsAuxiliaryEntries == includeAuxiliary else { return }
            displayedEntries = []
            auxiliaryEntryCount = 0
            selectedEntryIDs.removeAll()
            selectionAnchorID = nil
            selectionLeadID = nil
        }
    }

    /// Reads a column without changing the active directory or navigation history.
    public func directoryEntries(at path: String, includeAuxiliary: Bool? = nil) async throws -> [ArchiveEntry] {
        let mutations = pendingMutations
        let includeAuxiliary = includeAuxiliary ?? showsAuxiliaryEntries
        let entries = try await index.listDirectory(
            parentPath: Self.pathBeforeRenames(path, mutations: mutations[...]),
            includeAuxiliary: includeAuxiliary || !mutations.isEmpty,
            includeDiskImageBackground: includeAuxiliary || !mutations.isEmpty,
            includeApplicationsShortcut: includeAuxiliary || !mutations.isEmpty,
            limit: Int(Int32.max)
        )
        return try await Self.overlay(mutations, on: entries, directory: path, query: "", includeAuxiliary: includeAuxiliary)
    }

    public func totalUncompressedSize(inDirectory path: String) async throws -> Int64 {
        var directories = [path]
        var total: Int64 = 0
        while let directory = directories.popLast() {
            try Task.checkCancellation()
            for entry in try await directoryEntries(at: directory, includeAuxiliary: true) {
                if entry.isDirectory { directories.append(entry.path) }
                else {
                    let sum = total.addingReportingOverflow(max(0, entry.uncompressedSize))
                    total = sum.overflow ? .max : sum.partialValue
                }
            }
        }
        return total
    }

    private nonisolated static func pathBeforeRenames(_ path: String, mutations: ArraySlice<ArchiveMutation>) -> String {
        var path = path
        for mutation in mutations.reversed() {
            if case .renameEntry(let old, let new) = mutation { path = renamedPath(path, from: new, to: old) }
        }
        return path
    }

    // Local directory I/O and mutation replay run off the main actor; navigation reads only immediate children.
    private nonisolated static func overlay(_ mutations: [ArchiveMutation], on entries: [ArchiveEntry], directory: String, query: String, includeAuxiliary: Bool) async throws -> [ArchiveEntry] {
        var entries = entries
        for (offset, mutation) in mutations.enumerated() {
            try Task.checkCancellation()
            switch mutation {
            case .deleteEntry(let path):
                entries.removeAll { $0.path == path || $0.path.hasPrefix(path + "/") }
            case .renameEntry(let old, let new):
                entries = entries.map { entry in
                    guard entry.path == old || entry.path.hasPrefix(old + "/") else { return entry }
                    return Self.entry(entry, at: new + entry.path.dropFirst(old.count))
                }
            case .addFile(let source, let path), .replaceEntry(let path, let source):
                let directoryAtAddition = pathBeforeRenames(directory, mutations: mutations.suffix(from: offset + 1))
                let added = try localEntries(at: source, archivePath: path, directory: directoryAtAddition, recursive: !query.isEmpty)
                if case .replaceEntry = mutation {
                    entries.removeAll { $0.path == path || $0.path.hasPrefix(path + "/") }
                } else if added.first?.isDirectory == false {
                    entries.removeAll { $0.path.hasPrefix(path + "/") }
                }
                let addedPaths = Set(added.map(\.path))
                entries.removeAll { addedPaths.contains($0.path) }
                entries.append(contentsOf: added)
            }
        }

        entries.removeAll { entry in
            if !includeAuxiliary && (entry.isAuxiliary || entry.isDiskImageBackground || entry.isApplicationsShortcut) { return true }
            if !query.isEmpty { return !entry.path.localizedCaseInsensitiveContains(query) }
            return entry.parentPath != directory
        }
        entries.sort { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        return entries
    }

    private nonisolated static func localEntry(at url: URL, archivePath: String) throws -> ArchiveEntry {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileType = attributes[.type] as? FileAttributeType
        let type: EntryType = fileType == .typeSymbolicLink ? .symlink : fileType == .typeDirectory ? .directory : .file
        return ArchiveEntry(
            path: archivePath,
            type: type,
            uncompressedSize: (attributes[.size] as? NSNumber)?.int64Value ?? 0,
            modifiedAt: attributes[.modificationDate] as? Date ?? Date(),
            permissions: (attributes[.posixPermissions] as? NSNumber)?.uint16Value,
            symlinkTarget: type == .symlink ? try FileManager.default.destinationOfSymbolicLink(atPath: url.path) : nil
        )
    }

    private nonisolated static func localEntries(at source: URL, archivePath: String, directory: String, recursive: Bool) throws -> [ArchiveEntry] {
        let root = try localEntry(at: source, archivePath: archivePath)
        var entries = [root]
        guard root.isDirectory else { return entries }

        var localDirectory = source
        if !recursive && directory != archivePath {
            guard directory.hasPrefix(archivePath + "/") else { return entries }
            let components = directory.dropFirst(archivePath.count + 1).split(separator: "/", omittingEmptySubsequences: false)
            for component in components {
                guard !component.isEmpty, component != ".", component != "..", !component.contains("\0") else {
                    throw ProZipError.unsafePath(directory)
                }
                localDirectory.appendPathComponent(String(component))
                // Never browse through a source symlink, including a link to a directory.
                do {
                    guard try localEntry(at: localDirectory, archivePath: directory).isDirectory else { return entries }
                } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
                    return entries // A merged archive directory need not exist in this particular source tree.
                }
            }
        }

        var directories = [(localDirectory, recursive ? archivePath : directory)]
        while let (url, path) = directories.popLast() {
            try Task.checkCancellation()
            for child in try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
                try Task.checkCancellation()
                let entry = try localEntry(at: child, archivePath: path + "/" + child.lastPathComponent)
                entries.append(entry)
                if recursive && entry.isDirectory { directories.append((child, entry.path)) }
            }
        }
        return entries
    }
}
