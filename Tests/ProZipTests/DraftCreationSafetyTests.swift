import XCTest
import Foundation
import ProZipCore
import ProZipEngines
import ProZipShared
@testable import ProZipUI

@MainActor
final class DraftCreationSafetyTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("prozip-draft-creation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("The draft operation did not finish")
    }

    private func prepare(_ mutations: [ArchiveMutation], in root: URL) async throws -> (ProZipAppViewModel, ArchiveBrowsingSession) {
        let session = ArchiveBrowsingSession(url: root.appendingPathComponent("draft-\(UUID().uuidString).zip"))
        for mutation in mutations { session.addDraftMutation(mutation) }
        let model = makeTestAppViewModel()
        model.sessions = [session]
        model.activeSessionID = session.id
        model.saveChanges(for: session)
        try await waitUntil { model.isCreationDialogPresented || model.isAlertPresented }
        XCTAssertTrue(model.isCreationDialogPresented)
        return (model, session)
    }

    private func cleanStaging(_ model: ProZipAppViewModel) {
        if let first = model.creationSources.first {
            try? FileManager.default.removeItem(at: first.deletingLastPathComponent())
        }
    }

    func testDeletedDraftSourceIsExcludedFromTrashCandidates() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let kept = root.appendingPathComponent("kept.txt")
        let removed = root.appendingPathComponent("removed.txt")
        try Data("kept".utf8).write(to: kept)
        try Data("removed".utf8).write(to: removed)
        let (model, _) = try await prepare([
            .addFile(sourceURL: kept, archivePath: "kept.txt"),
            .addFile(sourceURL: removed, archivePath: "removed.txt"),
            .deleteEntry(archivePath: "removed.txt")
        ], in: root)
        defer { cleanStaging(model) }
        XCTAssertEqual(model.creationOriginalSources, [kept])
        XCTAssertEqual(model.creationSourcesToTrash, [kept])
        XCTAssertTrue(FileManager.default.fileExists(atPath: removed.path))
    }

    func testPartiallyRetainedDirectoryIsNeverATrashCandidate() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("kept".utf8).write(to: directory.appendingPathComponent("kept.txt"))
        try Data("omitted".utf8).write(to: directory.appendingPathComponent("omitted.txt"))
        let (model, _) = try await prepare([
            .addFile(sourceURL: directory, archivePath: "source"),
            .renameEntry(oldArchivePath: "source", newArchivePath: "renamed"),
            .deleteEntry(archivePath: "renamed/omitted.txt")
        ], in: root)
        defer { cleanStaging(model) }
        XCTAssertEqual(model.creationOriginalSources, [directory], "Keep the original location as the creation form's destination hint")
        XCTAssertEqual(model.creationSourcesToTrash, [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("omitted.txt").path))
        XCTAssertEqual(model.creationSources.map(\.lastPathComponent), ["renamed"])
    }

    func testCompleteDirectoryStillQualifiesAfterRenamesAndAnAdditionalChild() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("original".utf8).write(to: directory.appendingPathComponent("original.txt"))
        let extra = root.appendingPathComponent("extra.txt")
        try Data("extra".utf8).write(to: extra)
        let (model, _) = try await prepare([
            .addFile(sourceURL: directory, archivePath: "source"),
            .renameEntry(oldArchivePath: "source/original.txt", newArchivePath: "moved.txt"),
            .renameEntry(oldArchivePath: "source", newArchivePath: "renamed"),
            .addFile(sourceURL: extra, archivePath: "renamed/extra.txt")
        ], in: root)
        defer { cleanStaging(model) }
        XCTAssertEqual(model.creationOriginalSources, [directory, extra])
        XCTAssertEqual(model.creationSourcesToTrash, [directory, extra])
    }

    func testOverwriteReplacementAndDuplicateAddsKeepOnlyCompleteOriginals() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let old = root.appendingPathComponent("old.txt")
        let kept = root.appendingPathComponent("kept.txt")
        let replacement = root.appendingPathComponent("replacement.txt")
        for url in [old, kept, replacement] { try Data(url.lastPathComponent.utf8).write(to: url) }
        let (model, _) = try await prepare([
            .addFile(sourceURL: old, archivePath: "overwritten.txt"),
            .addFile(sourceURL: kept, archivePath: "overwritten.txt"),
            .addFile(sourceURL: kept, archivePath: "duplicate.txt"),
            .deleteEntry(archivePath: "duplicate.txt"),
            .addFile(sourceURL: old, archivePath: "replaced.txt"),
            .replaceEntry(archivePath: "replaced.txt", replacementSourceURL: replacement)
        ], in: root)
        defer { cleanStaging(model) }
        XCTAssertEqual(model.creationOriginalSources, [kept])
        XCTAssertEqual(model.creationSourcesToTrash, [kept])
    }

    func testEncryptedDraftCreationRetainsItsPasswordForPreviewAndSaving() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let preferences = ProZipPreferences.shared
        let autoSave = preferences.passwordBookAutoSave
        let autoUnlock = preferences.passwordBookAutoUnlock
        preferences.passwordBookAutoSave = true
        preferences.passwordBookAutoUnlock = false
        defer {
            preferences.passwordBookAutoSave = autoSave
            preferences.passwordBookAutoUnlock = autoUnlock
        }
        let file = root.appendingPathComponent("fixture.txt")
        let payload = Data("fixture contents".utf8)
        try payload.write(to: file)
        let (model, session) = try await prepare([.addFile(sourceURL: file, archivePath: "fixture.txt")], in: root)
        let sources = model.creationSources
        let originals = model.creationOriginalSources
        let completion = try XCTUnwrap(model.creationCompletion)
        let stagedRoot = try XCTUnwrap(sources.first).deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: stagedRoot) }
        let destination = root.appendingPathComponent("encrypted.zip")
        let password = "draft-creation-test-fixture"
        model.creationCompletion = nil
        model.isCreationDialogPresented = false
        model.createArchive(
            sources: sources,
            destinationURL: destination,
            profile: CreationProfile(format: .zip, password: password),
            savePasswordToBook: false,
            sourcesToTrash: originals,
            completion: completion
        )
        model.creationDialogDidDismiss()
        try await waitUntil { session.url == destination && !session.hasUnsavedChanges && session.descriptor?.isEncrypted == true && !session.displayedEntries.isEmpty }
        XCTAssertFalse(model.isPasswordPromptPresented)
        let entry = try XCTUnwrap(session.displayedEntries.first)
        let bytes = try await model.previewBytes(for: entry, in: session, maximumCount: payload.count)
        XCTAssertEqual(bytes, payload)

        try session.renameEntry(entry, to: "renamed.txt")
        var saved = false
        model.saveChanges(for: session) { saved = true }
        try await waitUntil { saved || model.tasks.first?.phase == .failed }
        XCTAssertTrue(saved)
        let entries = try await NativeZipEngine().list(destination, password: password, progress: { _ in })
        XCTAssertEqual(entries.map(\.path), ["renamed.txt"])
        XCTAssertTrue(entries.allSatisfy(\.isEncrypted))
        XCTAssertTrue(model.passwordEntries.isEmpty, "Leaving the save-password checkbox off must keep this password in the session only")
        model.forceCloseSession(id: session.id)
        do {
            _ = try await model.exportEntry(try XCTUnwrap(entries.first), in: session)
            XCTFail("Closing the session must clear its memory-only password")
        } catch let error as ProZipError {
            guard case .passwordRequired = error else { return XCTFail("Expected a password request") }
        }
        XCTAssertFalse(model.isPasswordPromptPresented)
    }

    func testAnOutputInsideItsOriginalDirectoryNeverTrashesThatDirectory() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("fixture.txt")
        try Data("fixture".utf8).write(to: file)
        let (model, session) = try await prepare([.addFile(sourceURL: directory, archivePath: "source")], in: root)
        let sources = model.creationSources
        let stagedRoot = try XCTUnwrap(sources.first).deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: stagedRoot) }
        let completion = try XCTUnwrap(model.creationCompletion)
        let originals = model.creationOriginalSources
        let destination = directory.appendingPathComponent("created.zip")
        model.creationCompletion = nil
        model.isCreationDialogPresented = false
        model.createArchive(sources: sources, destinationURL: destination, profile: CreationProfile(format: .zip), moveSourcesToTrash: true, sourcesToTrash: originals, completion: completion)
        model.creationDialogDidDismiss()
        try await waitUntil { session.url == destination && !session.hasUnsavedChanges }
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        model.forceCloseSession(id: session.id)
    }
}
