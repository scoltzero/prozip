import AppKit
import Combine
import UniformTypeIdentifiers
import SwiftUI
import XCTest
import ProZipCore
import ProZipEngines
import ProZipShared
@testable import ProZipUI

@MainActor
final class UIBehaviorTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("prozip-ui-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testExtractAllIgnoresCurrentFolderSearchAndHiddenFiles() async throws {
        let vm = makeTestAppViewModel()
        let session = ArchiveBrowsingSession(url: URL(fileURLWithPath: "/tmp/all-entries.zip"))
        let entries = [
            ArchiveEntry(path: "docs", type: .directory),
            ArchiveEntry(path: "docs/readme.txt", type: .file),
            ArchiveEntry(path: "other.txt", type: .file),
            ArchiveEntry(path: "__MACOSX/._other.txt", type: .file)
        ]
        try await session.loadEntries(entries)
        await session.enterDirectory("docs")
        session.searchQuery = "readme"
        let all = try await vm.extractionEntries(for: nil, in: session)
        XCTAssertEqual(Set(all.map(\.path)), Set(entries.map(\.path)))
        let selected = try await vm.extractionEntries(for: [entries[0]], in: session)
        XCTAssertEqual(Set(selected.map(\.path)), ["docs", "docs/readme.txt"])
    }

    func testArchiveRenameMovesFileAndRefusesExistingDestination() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recent = ProZipPreferences.shared.recentArchives
        defer { ProZipPreferences.shared.recentArchives = recent }
        let source = directory.appendingPathComponent("source.zip")
        let original = Data("archive payload".utf8)
        try original.write(to: source)
        let session = ArchiveBrowsingSession(url: source)
        let vm = makeTestAppViewModel()
        try vm.renameArchive(session, to: "renamed")
        let renamed = directory.appendingPathComponent("renamed.zip")
        XCTAssertEqual(session.url, renamed)
        XCTAssertEqual(try Data(contentsOf: renamed), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        let occupied = directory.appendingPathComponent("occupied.zip")
        try Data("keep".utf8).write(to: occupied)
        XCTAssertThrowsError(try vm.renameArchive(session, to: "occupied.zip"))
        XCTAssertThrowsError(try vm.renameArchive(session, to: "../outside.zip"))
        XCTAssertEqual(session.url, renamed)
        XCTAssertEqual(try Data(contentsOf: renamed), original)
        XCTAssertEqual(try String(contentsOf: occupied), "keep")
    }

    func testShelfCopyKeepsExistingFilesAndRejectsRecursiveDestination() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceDirectory = directory.appendingPathComponent("source", isDirectory: true)
        let destination = directory.appendingPathComponent("output", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let source = sourceDirectory.appendingPathComponent("note.txt")
        let existing = destination.appendingPathComponent("note.txt")
        try Data("new".utf8).write(to: source)
        try Data("keep".utf8).write(to: existing)
        let copied = try ShelfFileActions.copy([source], to: destination)
        XCTAssertEqual(copied.map(\.lastPathComponent), ["note (2).txt"])
        XCTAssertEqual(try String(contentsOf: existing), "keep")
        XCTAssertEqual(try String(contentsOf: copied[0]), "new")
        XCTAssertThrowsError(try ShelfFileActions.copy([sourceDirectory], to: sourceDirectory))
        let inner = sourceDirectory.appendingPathComponent("inner", isDirectory: true)
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        XCTAssertThrowsError(try ShelfFileActions.copy([sourceDirectory], to: inner))
    }

    func testSaveConfirmationWritesChangesBeforeClosingSession() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("note.txt")
        try Data("payload".utf8).write(to: source)
        let archive = directory.appendingPathComponent("source.zip")
        let engine = NativeZipEngine()
        try await engine.create(sources: [source], at: archive, profile: CreationProfile(format: .zip), password: nil, progress: { _ in })
        let entries = try await engine.list(archive, password: nil, progress: { _ in })
        let session = ArchiveBrowsingSession(url: archive)
        try await session.loadEntries(entries)
        try session.renameEntry(entries[0], to: "renamed.txt")
        let vm = makeTestAppViewModel()
        vm.sessions = [session]
        vm.activeSessionID = session.id
        vm.closeSession(id: session.id)
        XCTAssertTrue(vm.isSaveChangesPresented)
        vm.confirmSaveChanges()
        XCTAssertEqual(vm.sessions.count, 1)
        XCTAssertTrue(vm.tasks.isEmpty)
        vm.performConfirmedSave()
        for _ in 0..<200 {
            if vm.sessions.isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(vm.sessions.isEmpty, "The session may close only after publication succeeds")
        let saved = try await engine.list(archive, password: nil, progress: { _ in })
        XCTAssertEqual(saved.map(\.path), ["renamed.txt"])
    }

    func testFailedSaveKeepsSessionAndDraft() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = directory.appendingPathComponent("invalid.zip")
        let payload = Data("deliberately invalid archive".utf8)
        try payload.write(to: archive)
        let entry = ArchiveEntry(path: "note.txt", type: .file)
        let session = ArchiveBrowsingSession(url: archive)
        try await session.loadEntries([entry])
        try session.renameEntry(entry, to: "renamed.txt")
        let vm = makeTestAppViewModel()
        vm.sessions = [session]
        vm.activeSessionID = session.id
        vm.closeSession(id: session.id)
        vm.confirmSaveChanges()
        vm.performConfirmedSave()
        for _ in 0..<200 {
            if vm.tasks.first?.phase == .failed { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(vm.tasks.first?.phase, .failed)
        XCTAssertEqual(vm.sessions.count, 1)
        XCTAssertTrue(session.hasUnsavedChanges)
        XCTAssertEqual(try Data(contentsOf: archive), payload)
    }

    func testNewDraftStagingHonorsRenameDeleteAndRejectsTraversal() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("original.txt")
        try Data("payload".utf8).write(to: source)
        let files = try await ProZipAppViewModel.stageNewArchiveDraft([
            .addFile(sourceURL: source, archivePath: "docs/original.txt"),
            .addFile(sourceURL: source, archivePath: "remove.txt"),
            .renameEntry(oldArchivePath: "docs/original.txt", newArchivePath: "docs/renamed.txt"),
            .deleteEntry(archivePath: "remove.txt")
        ])
        let stagedRoot = try XCTUnwrap(files.first).deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: stagedRoot) }
        XCTAssertEqual(files.map(\.lastPathComponent), ["docs"])
        XCTAssertEqual(try String(contentsOf: stagedRoot.appendingPathComponent("docs/renamed.txt")), "payload")
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagedRoot.appendingPathComponent("remove.txt").path))
        do {
            _ = try await ProZipAppViewModel.stageNewArchiveDraft([.addFile(sourceURL: source, archivePath: "../escape.txt")])
            XCTFail("Traversal must be rejected before copying")
        } catch let error as ProZipError {
            guard case .unsafePath = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testSelectionRangeRetainsAnchorAndKeyboardExtendsLead() async throws {
        let session = ArchiveBrowsingSession(url: URL(fileURLWithPath: "/tmp/selection.zip"))
        let entries = (0..<5).map { ArchiveEntry(path: "file\($0).txt", type: .file) }
        try await session.loadEntries(entries)
        session.selectOnly(entries[1].id)
        session.selectRange(to: entries[3].id, in: entries)
        XCTAssertEqual(session.selectedEntryIDs, Set(entries[1...3].map(\.id)))
        session.moveSelection(by: -1, in: entries, extending: true)
        XCTAssertEqual(session.selectedEntryIDs, Set(entries[1...2].map(\.id)))
        session.moveSelection(by: 1, in: entries)
        XCTAssertEqual(session.selectedEntryIDs, [entries[3].id])
        session.toggleSelection(entries[0].id)
        XCTAssertEqual(session.selectedEntryIDs, [entries[0].id, entries[3].id])
        session.selectAll(entries)
        XCTAssertEqual(session.selectedEntryIDs, Set(entries.map(\.id)))
        XCTAssertEqual(session.moveSelection(by: 1, in: entries), entries[4].id)
    }

    func testEntryRenameStaysWithItsWindowAfterFocusChanges() async throws {
        let entry = ArchiveEntry(path: "same-name.txt", type: .file)
        let first = ArchiveBrowsingSession(url: URL(fileURLWithPath: "/tmp/first.zip"))
        let second = ArchiveBrowsingSession(url: URL(fileURLWithPath: "/tmp/second.zip"))
        try await first.loadEntries([entry])
        try await second.loadEntries([entry])
        let vm = makeTestAppViewModel()
        vm.sessions = [first, second]
        vm.activeSessionID = first.id
        vm.beginRenaming(entry, in: first)
        vm.activeSessionID = second.id
        vm.renameInput = "changed.txt"
        try vm.commitEntryRename()
        XCTAssertEqual(first.pendingMutations, [.renameEntry(oldArchivePath: "same-name.txt", newArchivePath: "changed.txt")])
        XCTAssertTrue(second.pendingMutations.isEmpty)
        vm.activeSessionID = nil
        XCTAssertNil(vm.activeSession)
    }

    func testPasswordRequestsWaitForDismissalAndKeepTheirArchive() {
        let first = ArchiveBrowsingSession(url: URL(fileURLWithPath: "/tmp/password-first.zip"))
        let second = ArchiveBrowsingSession(url: URL(fileURLWithPath: "/tmp/password-second.zip"))
        let vm = makeTestAppViewModel()
        vm.sessions = [first, second]
        vm.activeSessionID = second.id
        vm.requestArchivePassword(for: first)
        vm.requestArchivePassword(for: second)
        XCTAssertEqual(vm.passwordPromptTitle, first.archiveName)
        XCTAssertTrue(vm.ownsPresentation(\.isPasswordPromptPresented, sessionID: first.id))
        var submitted = false
        vm.passwordPromptCompletion = { _ in submitted = true }
        vm.submitPassword("generated-test-password")
        XCTAssertFalse(submitted)
        XCTAssertFalse(vm.isPasswordPromptPresented)
        vm.passwordPromptDidDismiss()
        XCTAssertTrue(submitted)
        XCTAssertEqual(vm.passwordPromptTitle, second.archiveName)
        XCTAssertTrue(vm.ownsPresentation(\.isPasswordPromptPresented, sessionID: second.id))
        vm.submitPassword(nil)
        vm.passwordPromptDidDismiss()
        XCTAssertFalse(vm.isPasswordPromptPresented)
    }

    func testCreationRequestsNeverReplaceInputsOfAnOpenForm() {
        let first = ArchiveBrowsingSession(url: URL(fileURLWithPath: "/tmp/creation-first.zip"))
        let second = ArchiveBrowsingSession(url: URL(fileURLWithPath: "/tmp/creation-second.zip"))
        let one = URL(fileURLWithPath: "/tmp/one.txt")
        let two = URL(fileURLWithPath: "/tmp/two.txt")
        let vm = makeTestAppViewModel()
        vm.sessions = [first, second]
        vm.activeSessionID = first.id
        vm.beginCreation(sources: [one], ownerSessionID: first.id)
        vm.activeSessionID = second.id
        vm.beginCreation(sources: [two], ownerSessionID: second.id)
        XCTAssertEqual(vm.creationSources, [one])
        XCTAssertTrue(vm.ownsPresentation(\.isCreationDialogPresented, sessionID: first.id))
        XCTAssertFalse(vm.ownsPresentation(\.isCreationDialogPresented, sessionID: second.id))
        vm.isCreationDialogPresented = false
        vm.creationDialogDidDismiss()
        XCTAssertEqual(vm.creationSources, [two])
        XCTAssertTrue(vm.ownsPresentation(\.isCreationDialogPresented, sessionID: second.id))
        vm.isCreationDialogPresented = false
        vm.creationDialogDidDismiss()
        XCTAssertTrue(vm.creationSources.isEmpty)
    }

    func testClosingAnotherDirtyWindowQueuesItsOwnConfirmation() async throws {
        let entry = ArchiveEntry(path: "one.txt", type: .file)
        let first = ArchiveBrowsingSession(url: URL(fileURLWithPath: "/tmp/closing-first.zip"))
        let second = ArchiveBrowsingSession(url: URL(fileURLWithPath: "/tmp/closing-second.zip"))
        try await first.loadEntries([entry])
        try await second.loadEntries([entry])
        try first.renameEntry(entry, to: "first.txt")
        try second.renameEntry(entry, to: "second.txt")
        let vm = makeTestAppViewModel()
        vm.sessions = [first, second]
        vm.activeSessionID = first.id
        vm.closeSession(id: first.id)
        vm.activeSessionID = second.id
        vm.closeSession(id: second.id)
        XCTAssertEqual(vm.saveConfirmationSessionID, first.id)
        vm.cancelSaveChanges()
        vm.performConfirmedSave()
        XCTAssertEqual(vm.saveConfirmationSessionID, second.id)
        XCTAssertTrue(vm.ownsPresentation(\.isSaveChangesPresented, sessionID: second.id))
        vm.discardSaveChanges()
        XCTAssertEqual(vm.sessions.map(\.id), [first.id])
        XCTAssertTrue(first.hasUnsavedChanges)
    }

    func testSelectedEntriesRefreshWhenTheirMetadataChanges() async throws {
        let entry = ArchiveEntry(path: "same.txt", type: .file, uncompressedSize: 10, permissions: 0o644)
        let session = ArchiveBrowsingSession(url: URL(fileURLWithPath: "/tmp/selection-cache.zip"))
        try await session.loadEntries([entry])
        session.selectOnly(entry.id)
        XCTAssertEqual(session.selectedEntries.first?.permissions, 0o644)
        let changed = ArchiveEntry(path: "same.txt", type: .file, uncompressedSize: 10, permissions: 0o755)
        session.displayedEntries = [changed]
        XCTAssertEqual(session.selectedEntries.first?.permissions, 0o755)
        session.selectedEntryIDs.removeAll()
        XCTAssertTrue(session.selectedEntries.isEmpty)
    }

    func testDraftPreviewReadsRenamedSourceBeforeArchiveExists() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("original.txt")
        try Data("real source contents".utf8).write(to: source)
        let session = ArchiveBrowsingSession(url: root.appendingPathComponent("not-created.zip"))
        try session.addFiles([source])
        await session.refreshDisplayedEntries()
        let entry = try XCTUnwrap(session.displayedEntries.first)
        try session.renameEntry(entry, to: "renamed.txt")
        await session.refreshDisplayedEntries()
        let renamed = try XCTUnwrap(session.displayedEntries.first)
        let vm = makeTestAppViewModel()
        let preview = try await vm.previewBytes(for: renamed, in: session, maximumCount: 4)
        let materialized = try await vm.materializePreview(renamed, in: session)
        XCTAssertEqual(preview, Data("real".utf8))
        XCTAssertEqual(materialized, source)
        vm.extractAll(in: session)
        XCTAssertTrue(vm.tasks.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: session.url.path))
    }

    func testImportedFilesOpenArchivesOrCreateASourceDraft() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let recent = ProZipPreferences.shared.recentArchives
        defer { ProZipPreferences.shared.recentArchives = recent }
        let file = root.appendingPathComponent("input.txt")
        try Data("fixture".utf8).write(to: file)
        let vm = makeTestAppViewModel()
        let drafts = try await vm.importFiles([file])
        XCTAssertEqual(drafts.count, 1)
        XCTAssertNil(drafts[0].initialSourceStat)
        XCTAssertEqual(drafts[0].pendingMutations, [.addFile(sourceURL: file, archivePath: "input.txt")])
        let archive = root.appendingPathComponent("archive.zip")
        try await NativeZipEngine().create(sources: [file], at: archive, profile: CreationProfile(format: .zip), password: nil, progress: { _ in })
        let sessions = try await vm.importFiles([archive])
        XCTAssertEqual(sessions.map(\.url), [archive])
        XCTAssertNotNil(sessions[0].initialSourceStat)
        let again = try await vm.importFiles([archive])
        XCTAssertEqual(again.map(\.id), sessions.map(\.id))
        for session in Array(vm.sessions) { vm.forceCloseSession(id: session.id) }
    }

    func testFileDropDecodesFileURLsAndRejectsNetworkURLs() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("drop.txt")
        try Data().write(to: file)
        let providers = [
            NSItemProvider(item: file as NSURL, typeIdentifier: UTType.fileURL.identifier),
            NSItemProvider(item: file.dataRepresentation as NSData, typeIdentifier: UTType.fileURL.identifier),
            NSItemProvider(item: URL(string: "https://example.invalid/file")! as NSURL, typeIdentifier: UTType.fileURL.identifier)
        ]
        let urls = await FileURLDrop.loadURLs(from: providers)
        XCTAssertEqual(urls, [file])
    }

    func testReadOnlyArchiveCannotAcquireEditingMutations() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("readonly.rar")
        let input = root.appendingPathComponent("add.txt")
        try Data("reference".utf8).write(to: source)
        try Data("new".utf8).write(to: input)
        let session = ArchiveBrowsingSession(url: source, descriptor: ArchiveDescriptor(url: source, format: .rar))
        let entry = ArchiveEntry(path: "one.txt", type: .file)
        try await session.loadEntries([entry])
        session.selectOnly(entry.id)
        XCTAssertThrowsError(try session.addFiles([input]))
        XCTAssertThrowsError(try session.renameEntry(entry, to: "new.txt"))
        XCTAssertThrowsError(try session.replaceEntry(entry, with: input))
        session.removeSelectedDraftEntries()
        XCTAssertEqual(session.selectedEntryIDs, [entry.id])
        XCTAssertTrue(session.pendingMutations.isEmpty)
    }

    func testClosingActiveWindowRestoresMostRecentlyFocusedArchive() {
        let a = ArchiveBrowsingSession(url: URL(fileURLWithPath: "/tmp/a.zip"))
        let b = ArchiveBrowsingSession(url: URL(fileURLWithPath: "/tmp/b.zip"))
        let c = ArchiveBrowsingSession(url: URL(fileURLWithPath: "/tmp/c.zip"))
        let vm = makeTestAppViewModel()
        vm.sessions = [a, b, c]
        vm.activeSessionID = a.id
        vm.activeSessionID = c.id
        vm.activeSessionID = b.id
        vm.forceCloseSession(id: b.id)
        XCTAssertEqual(vm.activeSessionID, c.id)
        vm.forceCloseSession(id: c.id)
        XCTAssertEqual(vm.activeSessionID, a.id)
    }

    func testMissingArchiveReportsFailureInsteadOfAnEmptyDraft() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let recent = ProZipPreferences.shared.recentArchives
        defer { ProZipPreferences.shared.recentArchives = recent }
        let vm = makeTestAppViewModel()
        let session = vm.openArchive(at: root.appendingPathComponent("missing.zip"))
        for _ in 0..<100 {
            if case .failed = session.phase { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        guard case .failed = session.phase else { return XCTFail("A missing source must not look like an empty archive") }
        XCTAssertTrue(vm.isAlertPresented)
        vm.forceCloseSession(id: session.id)
    }

    func testQuitWaitsForDirtyDraftAndCanBeCancelled() async throws {
        let entry = ArchiveEntry(path: "one.txt", type: .file)
        let session = ArchiveBrowsingSession(url: URL(fileURLWithPath: "/tmp/quit.zip"))
        try await session.loadEntries([entry])
        try session.renameEntry(entry, to: "changed.txt")
        let vm = makeTestAppViewModel()
        vm.sessions = [session]
        vm.activeSessionID = session.id
        XCTAssertFalse(vm.prepareForTermination())
        XCTAssertTrue(vm.isTerminationRequested)
        XCTAssertTrue(vm.isSaveChangesPresented)
        vm.cancelSaveChanges()
        XCTAssertFalse(vm.isTerminationRequested)
        XCTAssertEqual(vm.sessions.count, 1)
        XCTAssertTrue(session.hasUnsavedChanges)
    }

    func testQuitBecomesReadyOnlyAfterExplicitDiscard() async throws {
        let entry = ArchiveEntry(path: "one.txt", type: .file)
        let session = ArchiveBrowsingSession(url: URL(fileURLWithPath: "/tmp/quit-discard.zip"))
        try await session.loadEntries([entry])
        try session.renameEntry(entry, to: "changed.txt")
        let vm = makeTestAppViewModel()
        vm.sessions = [session]
        var ready = false
        let subscription = NotificationCenter.default.publisher(for: .proZipTerminationReady, object: vm).sink { _ in ready = true }
        XCTAssertFalse(vm.prepareForTermination())
        XCTAssertFalse(ready)
        vm.discardSaveChanges()
        XCTAssertTrue(ready)
        XCTAssertTrue(vm.sessions.isEmpty)
        withExtendedLifetime(subscription) {}
    }

    func testCancellingDraftCreationAlsoCancelsPendingQuit() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("input.txt")
        try Data("fixture".utf8).write(to: file)
        let vm = makeTestAppViewModel()
        let draft = vm.createNewArchiveSession()
        try draft.addFiles([file])
        XCTAssertFalse(vm.prepareForTermination())
        vm.confirmSaveChanges()
        vm.performConfirmedSave()
        for _ in 0..<100 {
            if vm.isCreationDialogPresented { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(vm.isCreationDialogPresented)
        vm.isCreationDialogPresented = false
        vm.creationDialogDidDismiss()
        XCTAssertFalse(vm.isTerminationRequested)
        XCTAssertTrue(draft.hasUnsavedChanges)
        vm.forceCloseSession(id: draft.id)
    }

    func testTaskCountersNotifyWhenTaskCompletesWithoutArrayMutation() async throws {
        let vm = makeTestAppViewModel()
        let task = ArchiveTaskRecord(title: "test", archiveURL: URL(fileURLWithPath: "/tmp/result.zip"), phase: .compressing)
        vm.tasks = [task]
        let notification = expectation(description: "Completion updates the parent queue counters")
        let subscription = vm.objectWillChange.sink {
            if vm.completedTasksCount == 1 { notification.fulfill() }
        }
        task.update(progress: OperationProgress(phase: .completed))
        await fulfillment(of: [notification], timeout: 2)
        withExtendedLifetime(subscription) {}
        XCTAssertEqual(vm.activeTasksCount, 0)
        XCTAssertEqual(vm.completedTasksCount, 1)
    }

    func testDeclaredFinderServicesHaveAProviderPort() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: root.appendingPathComponent("Resources/Info.plist")), format: nil) as? [String: Any]
        let services = try XCTUnwrap(plist?["NSServices"] as? [[String: Any]])
        XCTAssertEqual(services.count, 6)
        for service in services {
            XCTAssertEqual(service["NSPortName"] as? String, "ProZip")
            XCTAssertEqual(service["NSMessage"] as? String, "performProZipService")
        }
        XCTAssertEqual(Set(services.compactMap { $0["NSUserData"] as? String }), ["browseArchive", "extractHere", "extractTo", "compressDefault", "compressConfigured", "sendToProZip"])
    }

    func testWorkspaceInspectorTracksWindowRightEdgeAtEverySize() async throws {
        let vm = makeTestAppViewModel()
        let session = ArchiveBrowsingSession(url: URL(fileURLWithPath: "/tmp/layout.zip"))
        try await session.loadEntries([ArchiveEntry(path: "readme.txt", type: .file)])
        for size in [CGSize(width: 880, height: 600), CGSize(width: 1040, height: 740), CGSize(width: 1600, height: 900)] {
            let root = WorkspaceWindowView(session: session)
                .environmentObject(vm)
                .environment(\.colorScheme, .light)
                .frame(width: size.width, height: size.height)
            let hosting = NSHostingView(rootView: root)
            hosting.frame = CGRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: hosting.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = hosting
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(30))
            hosting.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            let scale = CGFloat(bitmap.pixelsWide) / size.width
            let color = try XCTUnwrap(bitmap.colorAt(x: Int((size.width - 265) * scale), y: Int(20 * scale))?.usingColorSpace(.deviceRGB))
            XCTAssertGreaterThan(color.alphaComponent, 0.95, "Inspector absent at \(size)")
            XCTAssertGreaterThan(color.greenComponent - color.redComponent, 0.005, "Inspector no longer follows right edge at \(size)")
            window.contentView = nil
        }
    }
}
