import AppKit
import Combine
import UniformTypeIdentifiers
import SwiftUI
import XCTest
import zlib
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
        for size in [CGSize(width: 900, height: 600), CGSize(width: 1040, height: 740), CGSize(width: 1600, height: 900)] {
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
            XCTAssertLessThan(color.redComponent, 0.97, "Inspector no longer follows right edge at \(size)")
            XCTAssertGreaterThan(color.blueComponent, color.greenComponent, "Inspector must use neutral #EBE7F1 surface rather than green tint at \(size)")
            window.contentView = nil
        }
    }

    func testSynthesizedVirtualDirectoryUsesDistantPastTimestamp() async throws {
        let session = ArchiveBrowsingSession(url: URL(fileURLWithPath: "/tmp/aux-virtual.zip"))
        session.showsAuxiliaryEntries = true
        try await session.loadEntries([
            ArchiveEntry(path: "__MACOSX/._readme.txt", type: .file, uncompressedSize: 82)
        ])
        await session.refreshDisplayedEntries()
        let macosx = try XCTUnwrap(session.displayedEntries.first(where: { $0.path == "__MACOSX" }))
        XCTAssertTrue(macosx.isDirectory)
        XCTAssertEqual(macosx.modifiedAt, Date.distantPast)
    }

    func testEmptyDraftWorkspaceFitsMinimumSizeWithoutClipping() async throws {
        let vm = makeTestAppViewModel()
        let session = ArchiveBrowsingSession(url: URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString)-未命名压缩包.zip"))
        XCTAssertNil(session.initialSourceStat)
        let idealHosting = NSHostingView(
            rootView: WorkspaceWindowView(session: session)
                .environmentObject(vm)
        )
        idealHosting.safeAreaRegions = []
        idealHosting.layoutSubtreeIfNeeded()
        XCTAssertEqual(idealHosting.fittingSize.width, 1040, accuracy: 1, "Ideal width must stay 1040")
        XCTAssertEqual(idealHosting.fittingSize.height, 740, accuracy: 1, "Empty draft skeleton must not overflow 740 ideal height")

        let hosting = NSHostingView(
            rootView: WorkspaceWindowView(session: session)
                .environmentObject(vm)
        )
        hosting.safeAreaRegions = []
        hosting.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
        hosting.sizingOptions = [.minSize]
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.titled, .fullSizeContentView, .resizable], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(20))
        hosting.layoutSubtreeIfNeeded()
        XCTAssertEqual(window.contentMinSize.width, 900, accuracy: 1, "Workspace minimum width must be 900")
        XCTAssertEqual(window.contentMinSize.height, 600, accuracy: 1, "Workspace minimum height must be 600")
        window.contentView = nil
    }

    func testWorkspaceFlowCapsuleHitTestReachesHostingViewWithoutInterception() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("prozip-capsule-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let archiveURL = tempDir.appendingPathComponent("sample.zip")
        try Data([0x50, 0x4B, 0x05, 0x06] + Array(repeating: UInt8(0), count: 18)).write(to: archiveURL)

        let vm = makeTestAppViewModel()
        let session = ArchiveBrowsingSession(url: archiveURL)
        try await session.loadEntries([ArchiveEntry(path: "hello.txt", type: .file, uncompressedSize: 5)])
        XCTAssertNotNil(session.initialSourceStat)

        let size = CGSize(width: 1040, height: 740)
        let hosting = NSHostingView(
            rootView: WorkspaceWindowView(session: session)
                .environmentObject(vm)
                .frame(width: size.width, height: size.height)
        )
        hosting.safeAreaRegions = []
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(30))
        hosting.layoutSubtreeIfNeeded()

        // Centers of 切换到 Mini (23,681,34,34), 全部解压 (58,681,129,34), 预览 (188,681,118,34) in bottom-up coords:
        for point in [NSPoint(x: 40, y: 42), NSPoint(x: 122, y: 42), NSPoint(x: 247, y: 42)] {
            let hitView = try XCTUnwrap(hosting.hitTest(point))
            XCTAssertTrue(hitView === hosting, "AppKit subview \(type(of: hitView)) intercepted hitTest at \(point)")
        }
        window.contentView = nil
    }

    func testManagedTempCleanupPreservesCreationDraftAndAppInstallDirs() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("prozip-reg-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let registry = try ManagedTemporaryArtifactRegistry(fileURL: tempRoot.appendingPathComponent("registry.sqlite"))
        let previewDir = try await registry.createManagedTemporaryDirectory(purpose: "quicklook")
        addTeardownBlock { try? FileManager.default.removeItem(at: previewDir) }
        try Data(repeating: 0xAA, count: 1024).write(to: previewDir.appendingPathComponent("thumb.png"))

        let draftDir = try await registry.createManagedTemporaryDirectory(purpose: "creation-draft")
        addTeardownBlock { try? FileManager.default.removeItem(at: draftDir) }
        try Data(repeating: 0xBB, count: 2048).write(to: draftDir.appendingPathComponent("staged.txt"))

        let installDir = try await registry.createManagedTemporaryDirectory(purpose: "application-installation")
        addTeardownBlock { try? FileManager.default.removeItem(at: installDir) }
        try Data(repeating: 0xCC, count: 4096).write(to: installDir.appendingPathComponent("App.app"))

        let cleanable = await registry.totalCleanableBytes()
        XCTAssertEqual(cleanable, 1024)

        let freed = try await registry.cleanAllTemporaryFiles()
        XCTAssertEqual(freed, 1024)
        XCTAssertFalse(FileManager.default.fileExists(atPath: previewDir.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: draftDir.path), "creation-draft must survive active-PID temp cleanup")
        XCTAssertTrue(FileManager.default.fileExists(atPath: installDir.path), "application-installation must survive active-PID temp cleanup")
    }

    func testNativeZipCreationEmitsSmoothIntermediateProgress() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        // Single 4 MiB compressible file to exercise both preparing and 512 KiB slice-level Deflate progress
        let source = root.appendingPathComponent("payload.txt")
        let pattern = Data("ProZip smooth progress verification line 0123456789ABCDEF\n".utf8)
        var payload = Data()
        payload.reserveCapacity(4 * 1024 * 1024)
        while payload.count < 4 * 1024 * 1024 {
            payload.append(pattern)
        }
        try payload.write(to: source)

        let archive = root.appendingPathComponent("smooth.zip")
        final class ProgressCollector: @unchecked Sendable {
            let lock = NSLock()
            var snapshots: [OperationProgress] = []
            func append(_ p: OperationProgress) {
                lock.lock()
                snapshots.append(p)
                lock.unlock()
            }
        }
        let collector = ProgressCollector()

        try await NativeZipEngine().create(
            sources: [source],
            at: archive,
            profile: CreationProfile(format: .zip),
            password: nil
        ) { progress in
            collector.append(progress)
        }

        let snapshots = collector.snapshots
        let fractions = snapshots.map(\.fractionCompleted)
        XCTAssertGreaterThanOrEqual(fractions.count, 5, "Expected multiple progress ticks rather than 0 -> 1 jump")
        XCTAssertTrue(fractions.contains { $0 > 0.01 && $0 < 0.25 }, "Expected early preparing/starting progress: \(fractions)")
        XCTAssertTrue(fractions.contains { $0 >= 0.25 && $0 <= 0.96 }, "Expected mid-compression Deflate progress: \(fractions)")
        XCTAssertEqual(fractions.last, 1.0)

        for index in 1..<fractions.count {
            XCTAssertGreaterThanOrEqual(
                fractions[index] + 1e-9,
                fractions[index - 1],
                "Progress must be monotonically non-decreasing: \(fractions)"
            )
        }
    }

    func testSevenZipProgressSnapshotParserHandlesBackspaceStreams() {
        let sample = Data("  0%\u{08}\u{08}\u{08}\u{08}    \u{08}\u{08}\u{08}\u{08} 49% + big.bin\u{08}\u{08}\u{08}\u{08}".utf8)
        let parsed = SevenZipEngine.parseProgressSnapshot(from: sample)
        XCTAssertEqual(parsed?.percent, 49)
        XCTAssertEqual(parsed?.currentItem, "big.bin")

        let finalSample = Data("100% 1 + folder/archive item.pdf\u{08}\u{08}".utf8)
        let finalParsed = SevenZipEngine.parseProgressSnapshot(from: finalSample)
        XCTAssertEqual(finalParsed?.percent, 100)
        XCTAssertEqual(finalParsed?.currentItem, "folder/archive item.pdf")

        let nonProgress = Data("Creating archive: /tmp/foo%20bar.7z\n".utf8)
        XCTAssertNil(SevenZipEngine.parseProgressSnapshot(from: nonProgress))
    }

    func testTaskQueueSupportsSingleDeleteClearFinishedIncludingFailedAndClearAll() {
        let vm = makeTestAppViewModel()
        var activeCancelled = false
        let activeTask = ArchiveTaskRecord(
            title: "Active",
            archiveURL: URL(fileURLWithPath: "/tmp/active.zip"),
            phase: .compressing,
            completedBytes: 50_000,
            totalBytes: 100_000,
            cancelAction: { activeCancelled = true }
        )
        let failedTask = ArchiveTaskRecord(
            title: "Failed",
            archiveURL: URL(fileURLWithPath: "/tmp/failed.zip"),
            phase: .failed
        )
        failedTask.errorMessage = "密码仅支持 ASCII"
        let completedTask = ArchiveTaskRecord(
            title: "Completed",
            archiveURL: URL(fileURLWithPath: "/tmp/completed.zip"),
            phase: .completed
        )
        let cancelledTask = ArchiveTaskRecord(
            title: "Cancelled",
            archiveURL: URL(fileURLWithPath: "/tmp/cancelled.zip"),
            phase: .cancelled
        )

        vm.tasks = [activeTask, failedTask, completedTask, cancelledTask]
        XCTAssertEqual(vm.activeTasksCount, 1)
        XCTAssertEqual(vm.failedTasksCount, 1)
        XCTAssertEqual(vm.completedTasksCount, 1)
        XCTAssertEqual(vm.finishedTasksCount, 3)

        // 1. Dismiss a single record (e.g. cancelled row)
        vm.removeTask(id: cancelledTask.id)
        XCTAssertEqual(vm.tasks.map(\.id), [activeTask.id, failedTask.id, completedTask.id])

        // 2. Clear finished records must remove BOTH completed AND failed records while keeping active task
        vm.clearFinishedTasks()
        XCTAssertEqual(vm.tasks.map(\.id), [activeTask.id])
        XCTAssertFalse(activeCancelled)

        // 3. Re-add a failed record and test Clear All (cancels active task + empties queue)
        let secondFailed = ArchiveTaskRecord(
            title: "Failed 2",
            archiveURL: URL(fileURLWithPath: "/tmp/failed2.zip"),
            phase: .failed
        )
        vm.tasks.append(secondFailed)
        vm.clearAllTasks()
        XCTAssertTrue(activeCancelled, "clearAllTasks must safely cancel in-progress tasks before removing")
        XCTAssertTrue(vm.tasks.isEmpty)

        // 4. Verify ArchiveProgressWindowView lays out cleanly at 380x260 with mixed rows
        vm.tasks = [completedTask, failedTask]
        let hosting = NSHostingView(
            rootView: ArchiveProgressWindowView(appViewModel: vm)
                .environmentObject(vm)
                .frame(width: 380, height: 260)
        )
        hosting.frame = NSRect(x: 0, y: 0, width: 380, height: 260)
        hosting.layoutSubtreeIfNeeded()
        XCTAssertLessThanOrEqual(hosting.fittingSize.width, 380)
    }

    func testTaskRecordPreservesMonotonicProgressAcrossZeroBytePhaseTransitions() {
        let task = ArchiveTaskRecord(
            title: "Monotonic",
            archiveURL: URL(fileURLWithPath: "/tmp/mono.7z"),
            phase: .preparing
        )
        task.update(progress: OperationProgress(phase: .compressing, completedBytes: 80_000, totalBytes: 100_000))
        XCTAssertEqual(task.fractionCompleted, 0.8, accuracy: 0.001)

        // Transitioning to savingSafely with 0/0 must NOT drop fractionCompleted back to 0%
        task.update(progress: OperationProgress(phase: .savingSafely, completedBytes: 0, totalBytes: 0))
        XCTAssertEqual(task.phase, .savingSafely)
        XCTAssertEqual(task.fractionCompleted, 0.8, accuracy: 0.001)

        task.update(progress: OperationProgress(phase: .completed, completedBytes: 100_000, totalBytes: 100_000))
        XCTAssertEqual(task.fractionCompleted, 1.0, accuracy: 0.001)
    }

    func testCreationProfileHonorsCustomOverviewOverridesAcrossPurposes() {
        // Default fallback when omitted
        let defaultWindows = CreationProfile(purpose: .windows, format: .sevenZip)
        XCTAssertFalse(defaultWindows.preserveMacMetadata)
        XCTAssertTrue(defaultWindows.repairWindowsNames)

        let defaultMac = CreationProfile(purpose: .mac, format: .zip)
        XCTAssertTrue(defaultMac.preserveMacMetadata)
        XCTAssertFalse(defaultMac.repairWindowsNames)

        // Custom user overrides in 压缩包概览 must be respected even under .windows / .mac purposes
        let customWindows = CreationProfile(
            purpose: .windows,
            format: .sevenZip,
            preserveMacMetadata: true,
            repairWindowsNames: false
        )
        XCTAssertTrue(customWindows.preserveMacMetadata)
        XCTAssertFalse(customWindows.repairWindowsNames)

        let customMac = CreationProfile(
            purpose: .mac,
            format: .zip,
            preserveMacMetadata: false,
            repairWindowsNames: true
        )
        XCTAssertFalse(customMac.preserveMacMetadata)
        XCTAssertTrue(customMac.repairWindowsNames)
    }

    func testArchiveCreationDialogStandaloneWindowResizesFlexibly() {
        let vm = makeTestAppViewModel()
        let dialog = ArchiveCreationDialogView(
            defaultName: "deliverables",
            isStandaloneWindow: true,
            appViewModel: vm
        )
        .environmentObject(vm)

        let hosting = NSHostingView(rootView: dialog)
        hosting.safeAreaRegions = []
        hosting.autoresizingMask = [.width, .height]
        hosting.sizingOptions = [.minSize]

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 720),
            styleMask: [.titled, .fullSizeContentView, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 820, height: 560)
        window.contentMinSize = NSSize(width: 820, height: 560)
        window.contentView = hosting

        for targetSize in [
            NSSize(width: 820, height: 560),
            NSSize(width: 920, height: 720),
            NSSize(width: 1180, height: 880)
        ] {
            window.setContentSize(targetSize)
            hosting.layoutSubtreeIfNeeded()
            XCTAssertEqual(hosting.bounds.width, targetSize.width, accuracy: 1.0)
            XCTAssertEqual(hosting.bounds.height, targetSize.height, accuracy: 1.0)
        }
    }

    func testSevenZipCreateHonorsPreserveMacMetadataToggle() async throws {
        guard SevenZipEngine.resolveBinaryURL() != nil else { throw XCTSkip("7-Zip unavailable") }
        let tempDir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let srcFolder = tempDir.appendingPathComponent("deliverables", isDirectory: true)
        try FileManager.default.createDirectory(at: srcFolder, withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: srcFolder.appendingPathComponent("readme.txt"))
        try Data("junk".utf8).write(to: srcFolder.appendingPathComponent(".DS_Store"))

        let engine = SevenZipEngine()

        // 1. excludeMacJunk = true (preserveMacMetadata = false) -> .DS_Store excluded
        let clean7z = tempDir.appendingPathComponent("clean.7z")
        let cleanProfile = CreationProfile(purpose: .windows, format: .sevenZip, preserveMacMetadata: false)
        try await engine.create(sources: [srcFolder], at: clean7z, profile: cleanProfile, password: nil, progress: { _ in })
        let cleanEntries = try await engine.list(clean7z, password: nil, progress: { _ in })
        XCTAssertFalse(cleanEntries.contains { $0.name == ".DS_Store" || $0.path.hasSuffix(".DS_Store") })
        XCTAssertTrue(cleanEntries.contains { $0.path.hasSuffix("readme.txt") })

        // 2. Custom override under .windows: preserveMacMetadata = true -> .DS_Store preserved!
        let preserved7z = tempDir.appendingPathComponent("preserved.7z")
        let preservedProfile = CreationProfile(purpose: .windows, format: .sevenZip, preserveMacMetadata: true)
        try await engine.create(sources: [srcFolder], at: preserved7z, profile: preservedProfile, password: nil, progress: { _ in })
        let preservedEntries = try await engine.list(preserved7z, password: nil, progress: { _ in })
        XCTAssertTrue(preservedEntries.contains { $0.name == ".DS_Store" || $0.path.hasSuffix(".DS_Store") })
    }

    func testSevenZipProgressSnapshotParserHandlesExtractionOpenAndByteFallback() {
        // Extraction format with `- ` item separator
        let extractChunk = Data("\u{08}\u{08}\u{08}\u{08} 21% - movie.mkv".utf8)
        let extractParsed = SevenZipEngine.parseDetailedProgressSnapshot(from: extractChunk)
        XCTAssertEqual(extractParsed, .init(stage: .transfer, percent: 21, processedBytes: nil, currentItem: "movie.mkv"))
        XCTAssertEqual(SevenZipEngine.parseProgressSnapshot(from: extractChunk)?.percent, 21)
        XCTAssertEqual(SevenZipEngine.parseProgressSnapshot(from: extractChunk)?.currentItem, "movie.mkv")

        // Extraction with file counter + `- ` separator + `+ ` inside filename
        let countedChunk = Data("\u{08}\u{08} 85% 13 - clip + bonus.bin".utf8)
        XCTAssertEqual(
            SevenZipEngine.parseDetailedProgressSnapshot(from: countedChunk),
            .init(stage: .transfer, percent: 85, processedBytes: nil, currentItem: "clip + bonus.bin")
        )

        // Extraction count-only segment (no item name)
        let countOnlyChunk = Data("\u{08}\u{08} 60% 3700".utf8)
        XCTAssertEqual(
            SevenZipEngine.parseDetailedProgressSnapshot(from: countOnlyChunk),
            .init(stage: .transfer, percent: 60, processedBytes: nil, currentItem: nil)
        )

        // Multi-volume RAR pre-transfer Open progress must be classified as .opening and ignored by parseProgressSnapshot
        let openChunk = Data("Extracting archive: demo.part001.rar\n 98% 100 Open".utf8)
        XCTAssertEqual(
            SevenZipEngine.parseDetailedProgressSnapshot(from: openChunk),
            .init(stage: .opening, percent: 98, processedBytes: nil, currentItem: nil)
        )
        XCTAssertNil(SevenZipEngine.parseProgressSnapshot(from: openChunk))

        // A real file literally named "Open" still parses as .transfer because of `- `
        let fileNamedOpen = Data(" 50% - Open".utf8)
        XCTAssertEqual(
            SevenZipEngine.parseDetailedProgressSnapshot(from: fileNamedOpen),
            .init(stage: .transfer, percent: 50, processedBytes: nil, currentItem: "Open")
        )

        // Unknown-total byte-count fallback vs drive Scan
        let scanChunk = Data("  0M Scan /tmp/dir".utf8)
        XCTAssertEqual(
            SevenZipEngine.parseDetailedProgressSnapshot(from: scanChunk),
            .init(stage: .opening, percent: nil, processedBytes: 0, currentItem: nil)
        )
        let byteTransferChunk = Data(" 64M - huge_stream.bin".utf8)
        XCTAssertEqual(
            SevenZipEngine.parseDetailedProgressSnapshot(from: byteTransferChunk),
            .init(stage: .transfer, percent: nil, processedBytes: 64 * 1024 * 1024, currentItem: "huge_stream.bin")
        )
    }

    func testSplitVolumeFamilyResolvesOldStyleRarVolumes() throws {
        let tempDir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rar = tempDir.appendingPathComponent("archive.rar")
        let r00 = tempDir.appendingPathComponent("archive.r00")
        let r01 = tempDir.appendingPathComponent("archive.r01")
        try Data("part0".utf8).write(to: rar)
        try Data("part1".utf8).write(to: r00)
        try Data("part2".utf8).write(to: r01)

        let fromRar = SplitVolumeFamily.resolve(for: rar)
        XCTAssertTrue(fromRar.isSplit)
        XCTAssertTrue(fromRar.isComplete)
        XCTAssertFalse(fromRar.hasEmptyVolume)
        XCTAssertEqual(fromRar.primaryVolumeURL.standardizedFileURL, rar.standardizedFileURL)
        XCTAssertEqual(fromRar.volumeURLs.map(\.lastPathComponent), ["archive.rar", "archive.r00", "archive.r01"])

        let fromR01 = SplitVolumeFamily.resolve(for: r01)
        XCTAssertTrue(fromR01.isSplit)
        XCTAssertTrue(fromR01.isComplete)
        XCTAssertEqual(fromR01.primaryVolumeURL.standardizedFileURL, rar.standardizedFileURL)

        // Missing middle volume (.r00) must be detected as incomplete
        try FileManager.default.removeItem(at: r00)
        let incomplete = SplitVolumeFamily.resolve(for: r01)
        XCTAssertTrue(incomplete.isSplit)
        XCTAssertFalse(incomplete.isComplete)
    }

    private static func makeSplitStoredRAR4Archive(
        in directory: URL,
        baseName: String,
        fileName: String,
        payload: Data,
        partSize: Int
    ) throws -> [URL] {
        func crc32Value(_ data: Data) -> UInt32 {
            data.withUnsafeBytes { ptr in
                guard let base = ptr.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return UInt32(zlib.crc32(0, base, uInt(data.count)))
            }
        }

        func appendUInt16LE(_ v: UInt16, to data: inout Data) {
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }

        func appendUInt32LE(_ v: UInt32, to data: inout Data) {
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }

        func rarBlock(type: UInt8, flags: UInt16, body: Data) -> Data {
            var header = Data()
            header.append(type)
            appendUInt16LE(flags, to: &header)
            appendUInt16LE(UInt16(7 + body.count), to: &header)
            header.append(body)
            let crc16 = UInt16(crc32Value(header) & 0xFFFF)
            var out = Data()
            appendUInt16LE(crc16, to: &out)
            out.append(header)
            return out
        }

        let marker = Data([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00])
        let nameBytes = Data(fileName.utf8)
        let fullCRC = crc32Value(payload)
        var volumes: [Data] = []
        var offset = 0
        var volIndex = 0

        while offset < payload.count {
            var vol = Data()
            vol.append(marker)
            let mainFlags: UInt16 = 0x0001 | 0x0010 | (volIndex == 0 ? 0x0100 : 0)
            vol.append(rarBlock(type: 0x73, flags: mainFlags, body: Data(count: 6)))

            let headerBudget = 32 + nameBytes.count + 20
            let chunkLen = min(payload.count - offset, max(1024, partSize - vol.count - headerBudget))
            let chunk = payload.subdata(in: offset..<(offset + chunkLen))
            let splitBefore = offset > 0
            let splitAfter = (offset + chunkLen) < payload.count

            var fileFlags: UInt16 = 0x8000
            if splitBefore { fileFlags |= 0x0001 }
            if splitAfter { fileFlags |= 0x0002 }
            let partCRC = splitAfter ? crc32Value(chunk) : fullCRC

            var body = Data()
            appendUInt32LE(UInt32(chunk.count), to: &body)
            appendUInt32LE(UInt32(payload.count), to: &body)
            body.append(3) // Unix host OS
            appendUInt32LE(partCRC, to: &body)
            appendUInt32LE(0x50210000, to: &body)
            body.append(29) // unp ver
            body.append(0x30) // store
            appendUInt16LE(UInt16(nameBytes.count), to: &body)
            appendUInt32LE(0o100644, to: &body)
            body.append(nameBytes)

            vol.append(rarBlock(type: 0x74, flags: fileFlags, body: body))
            vol.append(chunk)
            vol.append(rarBlock(type: 0x7B, flags: splitAfter ? 0x0001 : 0x0000, body: Data()))

            volumes.append(vol)
            offset += chunkLen
            volIndex += 1
        }

        var urls: [URL] = []
        for (idx, volData) in volumes.enumerated() {
            let url = directory.appendingPathComponent("\(baseName).part\(idx + 1).rar")
            try volData.write(to: url)
            urls.append(url)
        }
        return urls
    }

    func testSplitRarExtractionStreamsRealTimeProgressUpdates() async throws {
        guard SevenZipEngine.resolveBinaryURL() != nil else { throw XCTSkip("7-Zip unavailable") }
        let tempDir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Build a 384 MiB split RAR4 across 8 volumes so 7-Zip extraction emits real-time -bsp1 updates.
        let pattern = Data((0..<1024).map { UInt8($0 & 0xFF) })
        var chunk1MiB = Data(capacity: 1024 * 1024)
        for _ in 0..<1024 { chunk1MiB.append(pattern) }
        var payload = Data(capacity: 384 * 1024 * 1024)
        for _ in 0..<384 { payload.append(chunk1MiB) }

        let volumes = try Self.makeSplitStoredRAR4Archive(
            in: tempDir,
            baseName: "bundle",
            fileName: "video.mkv",
            payload: payload,
            partSize: 50 * 1024 * 1024
        )
        XCTAssertGreaterThanOrEqual(volumes.count, 8)

        let broker = ArchiveEngineBroker()
        let descriptor = try await broker.probe(volumes[2])
        XCTAssertTrue(descriptor.isSplitVolume)
        XCTAssertEqual(descriptor.format, .rar)
        XCTAssertGreaterThanOrEqual(descriptor.totalCompressedSize, Int64(payload.count))

        let entries = try await broker.list(volumes[2], password: nil)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.path, "video.mkv")

        let destDir = tempDir.appendingPathComponent("extracted", isDirectory: true)
        final class ProgressRecorder: @unchecked Sendable {
            let lock = NSLock()
            var snapshots: [OperationProgress] = []
            func append(_ p: OperationProgress) {
                lock.lock()
                snapshots.append(p)
                lock.unlock()
            }
        }
        let recorder = ProgressRecorder()

        let report = try await broker.extract(
            entries,
            from: volumes[2],
            to: destDir,
            password: nil,
            options: ExtractionOptions(conflictResolution: .replace)
        ) { progress in
            recorder.append(progress)
        }

        XCTAssertEqual(report.extractedCount, 1)
        let extractedFile = destDir.appendingPathComponent("video.mkv")
        let extractedSize = (try? extractedFile.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        XCTAssertEqual(extractedSize, payload.count)

        let snapshots = recorder.snapshots
        let extractingFractions = snapshots
            .filter { $0.phase == .extracting }
            .map(\.fractionCompleted)
        XCTAssertTrue(
            extractingFractions.contains { $0 > 0.06 && $0 < 0.94 },
            "Expected real-time mid-extraction progress between 6% and 94%, got: \(extractingFractions)"
        )
        XCTAssertTrue(
            snapshots.contains { $0.phase == .extracting && $0.totalBytes == Int64(payload.count) && $0.completedBytes > 0 },
            "Expected byte-accurate extraction progress for speed/ETA calculation"
        )

        let allFractions = snapshots.map(\.fractionCompleted)
        XCTAssertEqual(allFractions.last, 1.0)
        for i in 1..<allFractions.count {
            XCTAssertGreaterThanOrEqual(
                allFractions[i] + 1e-9,
                allFractions[i - 1],
                "Extraction progress must be monotonically non-decreasing: \(allFractions)"
            )
        }
    }

    func testNativeZipSingleLargeFileExtractionStreamsMidFileProgress() async throws {
        let tempDir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // 16 MiB moderately compressible file in a single-entry ZIP
        let srcFile = tempDir.appendingPathComponent("dataset.bin")
        var block = Data(capacity: 65_536)
        for i in 0..<65_536 {
            block.append(UInt8((i &* 31 &+ (i >> 6)) & 0xFF))
        }
        var payload = Data(capacity: 16 * 1024 * 1024)
        for _ in 0..<256 { payload.append(block) }
        try payload.write(to: srcFile)

        let zipURL = tempDir.appendingPathComponent("single_large.zip")
        let engine = NativeZipEngine()
        try await engine.create(
            sources: [srcFile],
            at: zipURL,
            profile: CreationProfile(purpose: .general, format: .zip, strength: .fast),
            password: nil,
            progress: { _ in }
        )

        let entries = try await engine.list(zipURL, password: nil, progress: { _ in })
        XCTAssertEqual(entries.count, 1)

        final class Recorder: @unchecked Sendable {
            let lock = NSLock()
            var snapshots: [OperationProgress] = []
            func record(_ p: OperationProgress) {
                lock.withLock { snapshots.append(p) }
            }
        }
        let recorder = Recorder()
        let outDir = tempDir.appendingPathComponent("zip_out", isDirectory: true)
        let report = try await engine.extract(
            entries,
            from: zipURL,
            to: outDir,
            password: nil,
            options: ExtractionOptions(conflictResolution: .replace)
        ) { progress in
            recorder.record(progress)
        }

        XCTAssertEqual(report.extractedCount, 1)
        let extractedData = try Data(contentsOf: outDir.appendingPathComponent("dataset.bin"))
        XCTAssertEqual(extractedData.count, payload.count)

        let snapshots = recorder.snapshots
        let midExtract = snapshots.filter { $0.phase == .extracting }.map(\.fractionCompleted)
        XCTAssertTrue(
            midExtract.contains { $0 > 0.10 && $0 < 0.90 },
            "Expected mid-file ZIP inflate progress between 10% and 90%, got: \(midExtract)"
        )
        let allFractions = snapshots.map(\.fractionCompleted)
        XCTAssertEqual(allFractions.last, 1.0)
        for i in 1..<allFractions.count {
            XCTAssertGreaterThanOrEqual(allFractions[i] + 1e-9, allFractions[i - 1])
        }
    }

    func testLibarchiveTarGzAndGzipStreamRealTimeExtractionAndCreationProgress() async throws {
        let tempDir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // 24 MiB source file (mix of pattern and incompressible bytes so tar.gz / gz take >50ms)
        let srcFile = tempDir.appendingPathComponent("backup.bin")
        var block = Data(count: 65_536)
        block.withUnsafeMutableBytes { buf in
            guard let ptr = buf.bindMemory(to: UInt8.self).baseAddress else { return }
            var state: UInt64 = 0x9E37_79B9_7F4A_7C15
            for i in 0..<32_768 {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                ptr[i] = UInt8(truncatingIfNeeded: state >> 56)
            }
            for i in 32_768..<65_536 {
                ptr[i] = UInt8(i & 0x3F)
            }
        }
        var payload = Data(capacity: 24 * 1024 * 1024)
        for _ in 0..<384 { payload.append(block) }
        try payload.write(to: srcFile)

        let engine = LibarchiveEngine()
        final class Recorder: @unchecked Sendable {
            let lock = NSLock()
            var snapshots: [OperationProgress] = []
            func record(_ p: OperationProgress) {
                lock.withLock { snapshots.append(p) }
            }
        }

        // 1. TAR.GZ creation + extraction progress
        let tarGzURL = tempDir.appendingPathComponent("bundle.tar.gz")
        let tarCreateRec = Recorder()
        try await engine.create(
            sources: [srcFile],
            at: tarGzURL,
            profile: CreationProfile(purpose: .general, format: .tarGz),
            password: nil
        ) { tarCreateRec.record($0) }
        XCTAssertEqual(tarCreateRec.snapshots.last?.fractionCompleted, 1.0)

        let tarEntries = try await engine.list(tarGzURL, password: nil, progress: { _ in })
        let tarExtractRec = Recorder()
        let tarOut = tempDir.appendingPathComponent("tar_out", isDirectory: true)
        let tarReport = try await engine.extract(
            tarEntries,
            from: tarGzURL,
            to: tarOut,
            password: nil,
            options: ExtractionOptions(conflictResolution: .replace)
        ) { tarExtractRec.record($0) }
        XCTAssertEqual(tarReport.extractedCount, 1)
        XCTAssertEqual(
            (try? tarOut.appendingPathComponent("backup.bin").resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0,
            payload.count
        )
        let tarExtractMid = tarExtractRec.snapshots.filter { $0.phase == .extracting }.map(\.fractionCompleted)
        XCTAssertTrue(
            tarExtractMid.contains { $0 > 0.08 && $0 < 0.94 },
            "Expected mid-extraction tar.gz progress between 8% and 94%, got: \(tarExtractMid)"
        )

        // 2. Single-stream .gz creation + extraction progress
        let gzURL = tempDir.appendingPathComponent("backup.bin.gz")
        let gzCreateRec = Recorder()
        try await engine.create(
            sources: [srcFile],
            at: gzURL,
            profile: CreationProfile(purpose: .general, format: .gzip),
            password: nil
        ) { gzCreateRec.record($0) }
        let gzCreateMid = gzCreateRec.snapshots.filter { $0.phase == .compressing }.map(\.fractionCompleted)
        XCTAssertTrue(
            gzCreateMid.contains { $0 > 0.08 && $0 < 0.95 },
            "Expected mid-compression .gz progress between 8% and 95%, got: \(gzCreateMid)"
        )

        let gzEntries = try await engine.list(gzURL, password: nil, progress: { _ in })
        let gzExtractRec = Recorder()
        let gzOut = tempDir.appendingPathComponent("gz_out", isDirectory: true)
        let gzReport = try await engine.extract(
            gzEntries,
            from: gzURL,
            to: gzOut,
            password: nil,
            options: ExtractionOptions(conflictResolution: .replace)
        ) { gzExtractRec.record($0) }
        XCTAssertEqual(gzReport.extractedCount, 1)
        XCTAssertEqual(
            (try? gzOut.appendingPathComponent("backup.bin").resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0,
            payload.count
        )
        let gzExtractMid = gzExtractRec.snapshots.filter { $0.phase == .extracting }.map(\.fractionCompleted)
        XCTAssertTrue(
            gzExtractMid.contains { $0 > 0.08 && $0 < 0.94 },
            "Expected mid-extraction .gz progress between 8% and 94%, got: \(gzExtractMid)"
        )
    }
}
