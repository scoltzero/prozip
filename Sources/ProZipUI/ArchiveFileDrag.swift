import AppKit
import Darwin
import SwiftUI
import UniformTypeIdentifiers
import ProZipShared

@MainActor
public enum ArchiveFileDrag {
    public typealias ExportEntry = @MainActor (ArchiveEntry) async throws -> URL
    public typealias ErrorHandler = @MainActor (Error) -> Void

    /// One native promise per top-level selected item; exporting starts only after a receiver accepts it.
    public static func makeProviders(
        entries: [ArchiveEntry],
        exportEntry: @escaping ExportEntry,
        onError: @escaping ErrorHandler
    ) throws -> [NSFilePromiseProvider] {
        let directories = entries.filter(\.isDirectory).map { $0.path + "/" }
        var seen = Set<String>()
        let roots = entries.filter { entry in
            seen.insert(entry.path).inserted && !directories.contains { entry.path.hasPrefix($0) }
        }
        return try roots.map { entry in
            guard !entry.name.isEmpty, entry.name != ".", entry.name != "..",
                  !entry.name.contains("/"), !entry.name.contains("\0") else {
                throw CocoaError(.fileWriteInvalidFileName)
            }
            let type = UTType(filenameExtension: entry.fileExtension) ?? .data
            let fileType = entry.isDirectory ? UTType.folder : type.conforms(to: .data) ? type : .data
            let writer = ArchiveFilePromiseWriter(entry: entry, exportEntry: exportEntry, onError: onError)
            let provider = NSFilePromiseProvider(fileType: fileType.identifier, delegate: writer)
            // NSFilePromiseProvider.delegate is weak; the pasteboard must retain the writer through fulfillment.
            provider.userInfo = writer
            return provider
        }
    }

    public static func cancel(_ providers: [NSFilePromiseProvider]) {
        for provider in providers { (provider.userInfo as? ArchiveFilePromiseWriter)?.cancel() }
    }
}

@MainActor
private final class ArchiveFilePromiseWriter: NSObject, NSFilePromiseProviderDelegate {
    let entry: ArchiveEntry
    let exportEntry: ArchiveFileDrag.ExportEntry
    let onError: ArchiveFileDrag.ErrorHandler
    let progress = Progress(totalUnitCount: 2)
    private var task: Task<Void, Never>?
    private var started = false

    init(entry: ArchiveEntry, exportEntry: @escaping ArchiveFileDrag.ExportEntry, onError: @escaping ArchiveFileDrag.ErrorHandler) {
        self.entry = entry
        self.exportEntry = exportEntry
        self.onError = onError
        super.init()
        progress.cancellationHandler = { [weak self] in
            Task { @MainActor in self?.task?.cancel() }
        }
    }

    func cancel() { progress.cancel(); task?.cancel() }

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String { entry.name }

    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue { .main }

    nonisolated func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        writePromiseTo url: URL,
        completionHandler: @escaping (Error?) -> Void
    ) {
        Task { @MainActor in
            guard !started else {
                let error = CocoaError(.fileWriteUnknown)
                completionHandler(error)
                onError(error)
                return
            }
            started = true
            task = Task {
                defer { task = nil }
                do {
                    if progress.isCancelled { throw CancellationError() }
                    let source = try await exportEntry(entry)
                    try Task.checkCancellation()
                    progress.completedUnitCount = 1
                    let progress = progress
                    let isDirectory = entry.isDirectory
                    let copy = Task.detached(priority: .userInitiated) {
                        try copyArchivePromise(from: source, to: url, isDirectory: isDirectory, progress: progress)
                    }
                    try await withTaskCancellationHandler {
                        try await copy.value
                    } onCancel: {
                        progress.cancel()
                        copy.cancel()
                    }
                    progress.completedUnitCount = 2
                    completionHandler(nil)
                } catch {
                    let cancelled = error is CancellationError || progress.isCancelled
                    completionHandler(cancelled ? CocoaError(.userCancelled) : error)
                    if !cancelled { onError(error) }
                }
            }
        }
    }
}

private func copyArchivePromise(from source: URL, to destination: URL, isDirectory: Bool, progress: Progress) throws {
    guard source.isFileURL, destination.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
    try Task.checkCancellation()
    if progress.isCancelled { throw CancellationError() }
    let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard (values.isDirectory == true && values.isSymbolicLink != true) == isDirectory else {
        throw ProZipError.structureConflict("导出结果与归档项目类型不符。")
    }
    if isDirectory {
        let sourcePath = source.resolvingSymlinksInPath().standardizedFileURL.path
        let targetPath = destination.deletingLastPathComponent().resolvingSymlinksInPath()
            .appendingPathComponent(destination.lastPathComponent).standardizedFileURL.path
        let prefix = sourcePath.hasSuffix("/") ? sourcePath : sourcePath + "/"
        guard targetPath != sourcePath, !targetPath.hasPrefix(prefix) else {
            throw ProZipError.structureConflict("不能将文件夹拖入自身或其子目录。")
        }
    }
    let fm = FileManager.default
    let staging = destination.deletingLastPathComponent().appendingPathComponent(".prozip-drop-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: staging, withIntermediateDirectories: false)
    defer { try? fm.removeItem(at: staging) }
    let payload = staging.appendingPathComponent("payload", isDirectory: isDirectory)
    guard let state = copyfile_state_alloc() else { throw POSIXError(.ENOMEM) }
    defer { copyfile_state_free(state) }
    let callback: copyfile_callback_t = { _, stage, _, _, _, context in
        guard let context else { return COPYFILE_QUIT }
        let progress = Unmanaged<Progress>.fromOpaque(context).takeUnretainedValue()
        return progress.isCancelled || stage == COPYFILE_ERR ? COPYFILE_QUIT : COPYFILE_CONTINUE
    }
    guard copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CB), unsafeBitCast(callback, to: UnsafeRawPointer.self)) == 0,
          copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CTX), Unmanaged.passUnretained(progress).toOpaque()) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    let flags = copyfile_flags_t(COPYFILE_ALL | COPYFILE_RECURSIVE | COPYFILE_EXCL | COPYFILE_NOFOLLOW)
    if copyfile(source.path, payload.path, state, flags) != 0 {
        if progress.isCancelled { throw CancellationError() }
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    try Task.checkCancellation()
    if progress.isCancelled { throw CancellationError() }
    // Same-directory staging permits an atomic publish that cannot overwrite an existing destination.
    if renamex_np(payload.path, destination.path, UInt32(RENAME_EXCL)) != 0 {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}

/// Overlay the draggable name/icon area. Supply its normal click handler; clicks wait until mouse-up,
/// so starting a drag on an already selected item does not collapse a multiple selection.
public struct ArchiveFileDragSource: NSViewRepresentable {
    let entries: @MainActor () -> [ArchiveEntry]
    let exportEntry: ArchiveFileDrag.ExportEntry
    let onClick: @MainActor (Int, NSEvent.ModifierFlags) -> Void
    let onError: ArchiveFileDrag.ErrorHandler
    let onHover: (@MainActor (Bool) -> Void)?

    public init(
        entries: @escaping @MainActor () -> [ArchiveEntry],
        exportEntry: @escaping ArchiveFileDrag.ExportEntry,
        onClick: @escaping @MainActor (Int, NSEvent.ModifierFlags) -> Void,
        onError: @escaping ArchiveFileDrag.ErrorHandler,
        onHover: (@MainActor (Bool) -> Void)? = nil
    ) {
        self.entries = entries
        self.exportEntry = exportEntry
        self.onClick = onClick
        self.onError = onError
        self.onHover = onHover
    }

    public func makeNSView(context: Context) -> NSView {
        let view = ArchiveFileDragView()
        updateNSView(view, context: context)
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ArchiveFileDragView)?.configuration = self
    }

    public static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        (nsView as? ArchiveFileDragView)?.stopHoverTracking()
    }
}

@MainActor
private final class ArchiveFileDragView: NSView, NSDraggingSource {
    var configuration: ArchiveFileDragSource?
    private var mouseDownEvent: NSEvent?
    private var providers: [NSFilePromiseProvider] = []
    private var hoverTrackingArea: NSTrackingArea?
    private var isHovered = false

    // A movable borderless window must deliver row drags here instead of moving its background.
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        hoverTrackingArea = nil
        guard window != nil else { return }
        let area = NSTrackingArea(rect: .zero, options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window { stopHoverTracking() }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { updateTrackingAreas() }
    }

    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }

    func stopHoverTracking() {
        setHovered(false)
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        hoverTrackingArea = nil
    }

    private func setHovered(_ hovered: Bool) {
        guard isHovered != hovered else { return }
        isHovered = hovered
        configuration?.onHover?(hovered)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if let event = NSApp.currentEvent,
           event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control)) {
            return nil
        }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        // A first click can activate the window before its tracking area sends mouseEntered.
        setHovered(true)
    }

    override func mouseUp(with event: NSEvent) {
        guard let down = mouseDownEvent else { return }
        mouseDownEvent = nil
        configuration?.onClick(down.clickCount, down.modifierFlags)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = mouseDownEvent, let configuration else { return }
        guard hypot(event.locationInWindow.x - down.locationInWindow.x, event.locationInWindow.y - down.locationInWindow.y) >= 4 else { return }
        mouseDownEvent = nil
        setHovered(false)
        do {
            let entries = configuration.entries()
            providers = try ArchiveFileDrag.makeProviders(entries: entries, exportEntry: configuration.exportEntry, onError: configuration.onError)
            guard !providers.isEmpty else { return }
            let point = convert(event.locationInWindow, from: nil)
            let items = providers.enumerated().map { index, provider in
                let item = NSDraggingItem(pasteboardWriter: provider)
                let name = (provider.userInfo as? ArchiveFilePromiseWriter)?.entry.name ?? ""
                let image = ProZipResourceLoader.systemFileIcon(for: name, isDirectory: UTType(provider.fileType)?.conforms(to: .directory) == true)
                item.setDraggingFrame(NSRect(x: point.x + CGFloat(index) * 4, y: point.y - 16 - CGFloat(index) * 4, width: 32, height: 32), contents: image)
                return item
            }
            let session = beginDraggingSession(with: items, event: event, source: self)
            session.draggingFormation = .stack
            session.animatesToStartingPositionsOnCancelOrFail = true
        } catch { configuration.onError(error) }
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        setHovered(false)
        if operation.isEmpty { cancelPromises() }
    }

    func cancelPromises() { ArchiveFileDrag.cancel(providers) }
}
