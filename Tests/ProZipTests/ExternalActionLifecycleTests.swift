import Foundation
import XCTest
import ProZipShared
import ProZipCore
import ProZipEngines
@testable import ProZipUI

@MainActor
final class ExternalActionLifecycleTests: XCTestCase {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("prozip-external-action-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("The operation did not reach its expected state")
    }

    func testExternalExtractionReusesDirtySessionAndCannotBypassSaveFirst() throws {
        let root = try directory()
        let archive = root.appendingPathComponent("opened.zip")
        try Data("unchanged source".utf8).write(to: archive)
        let session = ArchiveBrowsingSession(url: archive)
        session.addDraftMutation(.deleteEntry(archivePath: "removed.txt"))
        let vm = makeTestAppViewModel()
        vm.sessions = [session]
        let found = vm.sessionForExternalExtraction(at: root.appendingPathComponent("sub/../opened.zip"))
        XCTAssertTrue(found === session)
        vm.extractAll(in: found, to: root.appendingPathComponent("output"))
        XCTAssertTrue(vm.tasks.isEmpty)
        XCTAssertTrue(vm.isAlertPresented)
        XCTAssertTrue(vm.alertMessage.contains("保存"))
        XCTAssertEqual(try String(contentsOf: archive), "unchanged source")
    }

    func testUnopenedExternalArchiveGetsItsOwnPopulatedSessionInsteadOfBorrowingTheFocusedWindow() async throws {
        let root = try directory()
        let preferences = ProZipPreferences.shared
        let previous = (preferences.recentArchives, preferences.extractionCompletionAction, preferences.automaticallySelectsResults, preferences.automaticallyClosesArchive)
        defer {
            preferences.recentArchives = previous.0
            preferences.extractionCompletionAction = previous.1
            preferences.automaticallySelectsResults = previous.2
            preferences.automaticallyClosesArchive = previous.3
        }
        preferences.extractionCompletionAction = .keep
        preferences.automaticallySelectsResults = false
        preferences.automaticallyClosesArchive = false
        let archive = root.appendingPathComponent("external.zip")
        let source = root.appendingPathComponent("fixture.txt")
        try Data("fixture".utf8).write(to: source)
        try await NativeZipEngine().create(sources: [source], at: archive, profile: CreationProfile(format: .zip), password: nil, progress: { _ in })
        let unrelated = ArchiveBrowsingSession(url: root.appendingPathComponent("unrelated.zip"))
        let vm = makeTestAppViewModel()
        vm.sessions = [unrelated]
        vm.activeSessionID = unrelated.id
        let session = vm.sessionForExternalExtraction(at: archive)
        XCTAssertEqual(vm.sessions.count, 2)
        XCTAssertTrue(vm.sessions.contains { $0 === session })
        XCTAssertEqual(vm.activeSessionID, session.id)
        vm.forceCloseSession(id: unrelated.id)
        XCTAssertTrue(vm.sessions.contains { $0 === session })
        XCTAssertTrue(vm.sessionForExternalExtraction(at: archive) === session)
        vm.extractAll(in: session, to: root.appendingPathComponent("output", isDirectory: true))
        try await waitUntil { vm.tasks.first?.phase == .completed || vm.tasks.first?.phase == .failed }
        XCTAssertEqual(vm.tasks.first?.phase, .completed, vm.tasks.first?.errorMessage ?? "Extraction failed")
        guard case .ready = session.phase else { return XCTFail("The extraction must populate its new archive window") }
        XCTAssertEqual(session.displayedEntries.map(\.path), ["fixture.txt"])
        XCTAssertNotNil(session.descriptor)
        let indexed = try await session.index.allEntries(includeAuxiliary: true)
        XCTAssertEqual(indexed.map(\.path), ["fixture.txt"])
    }

    func testCreationConflictsQueueAcrossOwnersAndDismissalNeverRunsTheNextAction() throws {
        let root = try directory()
        let source = root.appendingPathComponent("source.txt")
        try Data("incoming".utf8).write(to: source)
        let a = ArchiveBrowsingSession()
        let b = ArchiveBrowsingSession()
        let vm = makeTestAppViewModel()
        vm.sessions = [a, b]
        for (owner, name) in [(a, "first.zip"), (b, "second.zip")] {
            let destination = root.appendingPathComponent(name)
            try Data("keep \(name)".utf8).write(to: destination)
            vm.activeSessionID = owner.id
            vm.createArchive(sources: [source], destinationURL: destination, profile: CreationProfile(format: .zip))
        }
        XCTAssertEqual(vm.activeConflictItem.fileName, "first.zip")
        XCTAssertTrue(vm.ownsPresentation(\.isConflictResolutionPresented, sessionID: a.id))
        vm.resolvePendingCreationConflict(.skip)
        XCTAssertFalse(vm.isConflictResolutionPresented)
        XCTAssertEqual(vm.activeConflictItem.fileName, "first.zip")
        vm.conflictDialogDidDismiss()
        XCTAssertTrue(vm.isConflictResolutionPresented)
        XCTAssertEqual(vm.activeConflictItem.fileName, "second.zip")
        XCTAssertTrue(vm.ownsPresentation(\.isConflictResolutionPresented, sessionID: b.id))
        vm.conflictDialogDidDismiss()
        XCTAssertTrue(vm.isConflictResolutionPresented)
        vm.isConflictResolutionPresented = false
        vm.conflictDialogDidDismiss()
        XCTAssertFalse(vm.isConflictResolutionPresented)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("first.zip")), "keep first.zip")
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("second.zip")), "keep second.zip")
        XCTAssertTrue(vm.tasks.isEmpty)
    }

    func testClosingConflictOwnerCancelsItsRequestAndShowsTheNextOwner() throws {
        for approveBeforeClosing in [false, true] {
            let root = try directory()
            let source = root.appendingPathComponent("source.txt")
            try Data("source".utf8).write(to: source)
            let vm = makeTestAppViewModel()
            let a = ArchiveBrowsingSession()
            let b = ArchiveBrowsingSession()
            vm.sessions = [a, b]
            for (owner, name) in [(a, "a.zip"), (b, "b.zip")] {
                let output = root.appendingPathComponent(name)
                try Data("keep".utf8).write(to: output)
                vm.activeSessionID = owner.id
                vm.createArchive(sources: [source], destinationURL: output, profile: CreationProfile(format: .zip))
            }
            if approveBeforeClosing { vm.resolvePendingCreationConflict(.replace) }
            vm.forceCloseSession(id: a.id)
            XCTAssertTrue(vm.isConflictResolutionPresented)
            XCTAssertEqual(vm.activeConflictItem.fileName, "b.zip")
            XCTAssertTrue(vm.ownsPresentation(\.isConflictResolutionPresented, sessionID: b.id))
            vm.resolvePendingCreationConflict(.skip)
            vm.conflictDialogDidDismiss()
            XCTAssertFalse(vm.isConflictResolutionPresented)
            XCTAssertTrue(vm.tasks.isEmpty)
            XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("a.zip")), "keep")
        }
    }

    func testCompletionNeverTrashesAChangedSourceEvenAfterSessionAcceptsTheNewVersion() async throws {
        let root = try directory()
        let preferences = ProZipPreferences.shared
        let previous = (preferences.extractionCompletionAction, preferences.automaticallySelectsResults, preferences.automaticallyClosesArchive)
        defer {
            preferences.extractionCompletionAction = previous.0
            preferences.automaticallySelectsResults = previous.1
            preferences.automaticallyClosesArchive = previous.2
        }
        preferences.extractionCompletionAction = .ask
        preferences.automaticallySelectsResults = false
        preferences.automaticallyClosesArchive = false
        let source = root.appendingPathComponent("payload.txt")
        try Data("old extracted content".utf8).write(to: source)
        let archive = root.appendingPathComponent("archive.zip")
        let engine = NativeZipEngine()
        try await engine.create(sources: [source], at: archive, profile: CreationProfile(format: .zip), password: nil, progress: { _ in })
        let session = ArchiveBrowsingSession(url: archive)
        let vm = makeTestAppViewModel()
        vm.sessions = [session]
        vm.activeSessionID = session.id
        vm.extractAll(in: session, to: root.appendingPathComponent("output", isDirectory: true))
        try await waitUntil { vm.isTrashConfirmationPresented || vm.tasks.first?.phase == .failed }
        XCTAssertTrue(vm.isTrashConfirmationPresented, vm.tasks.first?.errorMessage ?? "Completion prompt missing")
        let oldStat = SourceArchiveStat.read(from: archive)
        let newerBytes = Data("new saved or externally replaced archive".utf8)
        try newerBytes.write(to: archive, options: .atomic)
        session.captureSourceStat()
        session.acceptSavedChanges()
        XCTAssertFalse(session.hasUnsavedChanges)
        XCTAssertNotEqual(oldStat, session.initialSourceStat)
        vm.resolveExtractionCompletion(moveToTrash: true)
        vm.extractionCompletionDidDismiss()
        XCTAssertTrue(vm.isAlertPresented)
        XCTAssertTrue(vm.alertMessage.contains("发生变化"))
        XCTAssertEqual(try Data(contentsOf: archive), newerBytes)
        XCTAssertEqual(vm.sessions.count, 1)
    }

    func testBatchExtractionCompletionKeepsBothSourcesAndDoesNotChangePreference() async throws {
        let root = try directory()
        let preferences = ProZipPreferences.shared
        let previousAction = preferences.extractionCompletionAction
        let previousSelect = preferences.automaticallySelectsResults
        let previousClose = preferences.automaticallyClosesArchive
        defer {
            preferences.extractionCompletionAction = previousAction
            preferences.automaticallySelectsResults = previousSelect
            preferences.automaticallyClosesArchive = previousClose
        }
        preferences.extractionCompletionAction = .ask
        preferences.automaticallySelectsResults = false
        preferences.automaticallyClosesArchive = false
        let vm = makeTestAppViewModel()
        let engine = NativeZipEngine()
        var sessions: [ArchiveBrowsingSession] = []
        for name in ["first", "second"] {
            let source = root.appendingPathComponent("\(name).txt")
            try Data("payload \(name)".utf8).write(to: source)
            let archive = root.appendingPathComponent("\(name).zip")
            try await engine.create(sources: [source], at: archive, profile: CreationProfile(format: .zip), password: nil, progress: { _ in })
            let session = ArchiveBrowsingSession(url: archive)
            try await session.loadEntries(try await engine.list(archive, password: nil, progress: { _ in }))
            sessions.append(session)
        }
        vm.sessions = sessions
        vm.activeSessionID = sessions.last?.id
        for session in sessions { vm.extractAll(in: session, to: root.appendingPathComponent(session.url.deletingPathExtension().lastPathComponent, isDirectory: true)) }
        try await waitUntil { vm.tasks.count == 2 && vm.tasks.allSatisfy { $0.phase == .completed || $0.phase == .failed } }
        XCTAssertTrue(vm.tasks.allSatisfy { $0.phase == .completed }, vm.tasks.compactMap(\.errorMessage).joined(separator: ", "))
        let firstURL = try XCTUnwrap(vm.completedExtractionArchiveURL)
        let firstSession = try XCTUnwrap(sessions.first { $0.url == firstURL })
        XCTAssertTrue(vm.ownsPresentation(\.isTrashConfirmationPresented, sessionID: firstSession.id))
        vm.resolveExtractionCompletion(moveToTrash: false)
        vm.extractionCompletionDidDismiss()
        XCTAssertTrue(vm.isTrashConfirmationPresented)
        let secondURL = try XCTUnwrap(vm.completedExtractionArchiveURL)
        XCTAssertNotEqual(firstURL, secondURL)
        // Editing while the completion question is visible must preserve the source.
        let secondSession = try XCTUnwrap(sessions.first { $0.url == secondURL })
        secondSession.addDraftMutation(.deleteEntry(archivePath: "changed.txt"))
        vm.resolveExtractionCompletion(moveToTrash: true)
        vm.extractionCompletionDidDismiss()
        XCTAssertFalse(vm.isTrashConfirmationPresented)
        XCTAssertTrue(vm.isAlertPresented)
        XCTAssertEqual(preferences.extractionCompletionAction, .ask)
        for session in sessions { XCTAssertTrue(FileManager.default.fileExists(atPath: session.url.path)) }
    }

    func testAllFileInputsRejectMalformedExistingURLsBeforePathTruncation() throws {
        let root = try directory()
        let source = root.appendingPathComponent("fixture.txt")
        try Data("keep".utf8).write(to: source)
        try FileURLDrop.validateSources([source])
        let malformed = [
            source.absoluteString + "%00suffix",
            source.absoluteString + "?ignored=1",
            source.absoluteString.replacingOccurrences(of: "file:///", with: "file://remote-host/")
        ]
        for value in malformed {
            XCTAssertThrowsError(try FileURLDrop.validateSources([try XCTUnwrap(URL(string: value))]), value)
        }
        XCTAssertThrowsError(try FileURLDrop.validateSources(Array(repeating: source, count: 1001)))
        let literal = root.appendingPathComponent("literal%00.txt")
        try Data("literal".utf8).write(to: literal)
        try FileURLDrop.validateSources([literal])
        XCTAssertEqual(try String(contentsOf: source), "keep")
    }
}
