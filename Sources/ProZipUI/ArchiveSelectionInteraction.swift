import AppKit
import SwiftUI
import ProZipCore
import ProZipShared

@MainActor
enum ArchiveSelectionInteraction {
    static func click(_ entry: ArchiveEntry, in session: ArchiveBrowsingSession, orderedEntries: [ArchiveEntry], modifiers: NSEvent.ModifierFlags? = nil) {
        focus(session)
        let modifiers = modifiers ?? NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
        if modifiers.contains(.shift) {
            session.selectRange(to: entry.id, in: orderedEntries, additive: modifiers.contains(.command))
        } else if modifiers.contains(.command) {
            session.toggleSelection(entry.id)
        } else {
            session.selectOnly(entry.id)
        }
    }

    static func focus(_ session: ArchiveBrowsingSession) {
        NotificationCenter.default.post(name: .proZipFocusArchiveBrowser, object: session.id)
    }
}

private extension Notification.Name {
    static let proZipFocusArchiveBrowser = Notification.Name("ProZipFocusArchiveBrowser")
}

struct ArchiveFileDragHitArea: View {
    let entry: ArchiveEntry
    @ObservedObject var session: ArchiveBrowsingSession
    let orderedEntries: [ArchiveEntry]
    var onClick: ((Int, NSEvent.ModifierFlags) -> Void)?
    var onHover: ((Bool) -> Void)?
    @EnvironmentObject private var appViewModel: ProZipAppViewModel

    var body: some View {
        ArchiveFileDragSource(
            entries: { session.selectedEntryIDs.contains(entry.id) ? session.selectedEntries : [entry] },
            exportEntry: { try await appViewModel.exportEntry($0, in: session) },
            onClick: { count, modifiers in
                ArchiveSelectionInteraction.focus(session)
                if let onClick { onClick(count, modifiers) }
                else if count >= 2 {
                    if entry.isDirectory { Task { await session.enterDirectory(entry.path) } }
                    else { appViewModel.openEntryExternally(entry, in: session) }
                } else {
                    ArchiveSelectionInteraction.click(entry, in: session, orderedEntries: orderedEntries, modifiers: modifiers)
                }
            },
            onError: { error in
                appViewModel.alertTitle = "无法拖出文件"
                appViewModel.alertMessage = error.localizedDescription
                appViewModel.isAlertPresented = true
            },
            onHover: onHover
        )
        .accessibilityHidden(true)
    }
}

struct ArchiveKeyboardNavigation: ViewModifier {
    @ObservedObject var session: ArchiveBrowsingSession
    let entries: [ArchiveEntry]
    var columnCount: Int = 1
    var opensFoldersWithRightArrow = false
    var handlesHorizontalSelection = false
    @EnvironmentObject private var appViewModel: ProZipAppViewModel
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        ScrollViewReader { scroll in
            content
                .focusable()
                .focusEffectDisabled()
                .focused($isFocused)
                .simultaneousGesture(TapGesture().onEnded { isFocused = true })
                .onAppear { isFocused = true }
                .onReceive(NotificationCenter.default.publisher(for: .proZipFocusArchiveBrowser)) { event in
                    if event.object as? UUID == session.id { isFocused = true }
                }
                .onKeyPress(.upArrow, phases: [.down, .repeat]) { press in
                    if press.modifiers.contains(.command) { Task { await session.goUp() } }
                    else { move(-max(1, columnCount), extending: press.modifiers.contains(.shift), scroll: scroll) }
                    return .handled
                }
                .onKeyPress(.downArrow, phases: [.down, .repeat]) { press in
                    if press.modifiers.contains(.command) { openSelectedDirectory() }
                    else { move(max(1, columnCount), extending: press.modifiers.contains(.shift), scroll: scroll) }
                    return .handled
                }
                .onKeyPress(.rightArrow, phases: [.down, .repeat]) { press in
                    if opensFoldersWithRightArrow { openSelectedDirectory() }
                    else if handlesHorizontalSelection { move(1, extending: press.modifiers.contains(.shift), scroll: scroll) }
                    else { return .ignored }
                    return .handled
                }
                .onKeyPress(.leftArrow, phases: [.down, .repeat]) { press in
                    if opensFoldersWithRightArrow { Task { await session.goUp() } }
                    else if handlesHorizontalSelection { move(-1, extending: press.modifiers.contains(.shift), scroll: scroll) }
                    else { return .ignored }
                    return .handled
                }
                .onKeyPress("a", phases: .down) { press in
                    guard press.modifiers.contains(.command) else { return .ignored }
                    session.selectAll(entries)
                    return .handled
                }
                .onKeyPress("f", phases: .down) { press in
                    guard press.modifiers.contains(.command), session.phase.canSearch else { return .ignored }
                    session.isSearchExpanded = true
                    return .handled
                }
                .onKeyPress(.space) {
                    guard session.phase.canPreview else { return .ignored }
                    appViewModel.previewSelected(in: session)
                    return .handled
                }
                .onKeyPress(KeyEquivalent("\r")) {
                    guard session.initialSourceStat != nil else { return .ignored }
                    appViewModel.extractAll(in: session)
                    return .handled
                }
        }
    }

    private func move(_ delta: Int, extending: Bool, scroll: ScrollViewProxy) {
        if let id = session.moveSelection(by: delta, in: entries, extending: extending) {
            scroll.scrollTo(id)
        }
    }

    private func openSelectedDirectory() {
        guard let entry = session.selectedEntries.first else { return }
        if entry.isDirectory { Task { await session.enterDirectory(entry.path) } }
        else { appViewModel.openEntryExternally(entry, in: session) }
    }
}
