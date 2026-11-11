import Foundation
import XCTest
import ProZipCore
import ProZipEngines
import ProZipShared
@testable import ProZipUI

@MainActor
final class RenameSessionStateTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("prozip-rename-state-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.resolvingSymlinksInPath()
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("The rename/save state did not finish updating")
    }

    func testRenamingSelectedFileRetainsSelectionAndRangeEndpoints() async throws {
        let session = ArchiveBrowsingSession()
        let file = ArchiveEntry(path: "old#file.txt", type: .file, uncompressedSize: 7, permissions: 0o640, crc32: 0x1234, isEncrypted: true, encryptionGroupID: "fixture-group")
        try await session.loadEntries([file, ArchiveEntry(path: "other.txt", type: .file)])
        session.selectOnly(file.id)
        try session.renameEntry(file, to: "new#file.txt")
        await session.refreshDisplayedEntries()
        let expected = ArchiveEntry.makeID(path: "new#file.txt", type: file.type, crc32: file.crc32, uncompressedSize: file.uncompressedSize)
        XCTAssertEqual(session.selectedEntryIDs, [expected])
        XCTAssertEqual(session.selectionAnchorID, expected)
        XCTAssertEqual(session.selectionLeadID, expected)
        XCTAssertEqual(session.selectedEntries.first?.path, "new#file.txt")
        XCTAssertEqual(session.selectedEntries.first?.permissions, 0o640)
        XCTAssertEqual(session.selectedEntries.first?.encryptionGroupID, "fixture-group")
    }

    func testRenamingCurrentAncestorUpdatesCurrentPathAndBothHistoryStacks() async throws {
        let session = ArchiveBrowsingSession()
        let ancestor = ArchiveEntry(path: "old", type: .directory)
        try await session.loadEntries([
            ancestor,
            ArchiveEntry(path: "old/child", type: .directory),
            ArchiveEntry(path: "old/child/grand/file.txt", type: .file)
        ])
        await session.enterDirectory("old")
        await session.enterDirectory("old/child")
        await session.enterDirectory("old/child/grand")
        await session.goBack()
        try session.renameEntry(ancestor, to: "new")
        await session.refreshDisplayedEntries()
        XCTAssertEqual(session.currentDirectoryPath, "new/child")
        XCTAssertEqual(session.backStack, ["", "new"])
        XCTAssertEqual(session.forwardStack, ["new/child/grand"])
        XCTAssertEqual(session.displayedEntries.map(\.path), ["new/child/grand"])
        await session.goForward()
        XCTAssertEqual(session.displayedEntries.map(\.path), ["new/child/grand/file.txt"])
    }

    func testUndoRedoRetainsTheRenamedRangeAnchorAndUnchangedLead() async throws {
        let session = ArchiveBrowsingSession()
        let files = [
            ArchiveEntry(path: "a#file.txt", type: .file, uncompressedSize: 7, crc32: 11),
            ArchiveEntry(path: "b.txt", type: .file, uncompressedSize: 8, crc32: 22),
            ArchiveEntry(path: "c.txt", type: .file, uncompressedSize: 9, crc32: 33)
        ]
        try await session.loadEntries(files)
        session.selectOnly(files[0].id)
        session.selectRange(to: files[2].id, in: session.displayedEntries)
        try session.renameEntry(files[0], to: "z#file.txt")
        await session.refreshDisplayedEntries()
        let renamed = ArchiveEntry.makeID(path: "z#file.txt", type: .file, crc32: 11, uncompressedSize: 7)
        XCTAssertEqual(session.selectedEntryIDs, [renamed, files[1].id, files[2].id])
        XCTAssertEqual(session.selectionAnchorID, renamed)
        XCTAssertEqual(session.selectionLeadID, files[2].id)
        await session.undo()
        XCTAssertEqual(session.selectedEntryIDs, Set(files.map(\.id)))
        XCTAssertEqual(session.selectionAnchorID, files[0].id)
        XCTAssertEqual(session.selectionLeadID, files[2].id)
        await session.redo()
        XCTAssertEqual(session.selectionAnchorID, renamed)
        XCTAssertEqual(session.selectionLeadID, files[2].id)
        session.moveSelection(by: 1, in: session.displayedEntries, extending: true)
        XCTAssertEqual(session.selectedEntryIDs, [renamed])
        XCTAssertEqual(session.selectedEntries.first?.path, "z#file.txt")
    }

    func testChainedAncestorUndoRedoAndDiscardKeepDescendantSelectionAndValidHistory() async throws {
        let session = ArchiveBrowsingSession()
        let ancestor = ArchiveEntry(path: "alpha", type: .directory)
        let file = ArchiveEntry(path: "alpha/inner/file.txt", type: .file, uncompressedSize: 12, crc32: 42)
        try await session.loadEntries([ancestor, file, ArchiveEntry(path: "alphabet/untouched.txt", type: .file)])
        await session.enterDirectory("alphabet")
        await session.enterDirectory("alpha")
        await session.enterDirectory("alpha/inner")
        session.selectOnly(file.id)
        try session.renameEntry(ancestor, to: "beta")
        await session.refreshDisplayedEntries()
        try session.renameEntry(ArchiveEntry(path: "beta/inner", type: .directory), to: "renamed")
        await session.refreshDisplayedEntries()
        XCTAssertEqual(session.currentDirectoryPath, "beta/renamed")
        XCTAssertEqual(session.selectedEntries.map(\.path), ["beta/renamed/file.txt"])
        XCTAssertEqual(session.backStack, ["", "alphabet", "beta"])
        await session.undo()
        XCTAssertEqual(session.currentDirectoryPath, "beta/inner")
        XCTAssertEqual(session.selectedEntries.map(\.path), ["beta/inner/file.txt"])
        await session.undo()
        XCTAssertEqual(session.currentDirectoryPath, "alpha/inner")
        XCTAssertEqual(session.selectedEntryIDs, [file.id])
        await session.redo()
        await session.redo()
        XCTAssertEqual(session.currentDirectoryPath, "beta/renamed")
        XCTAssertEqual(session.backStack, ["", "alphabet", "beta"])
        await session.discardChanges()
        XCTAssertEqual(session.currentDirectoryPath, "alpha/inner")
        XCTAssertEqual(session.backStack, ["", "alphabet", "alpha"])
        XCTAssertEqual(session.selectedEntryIDs, [file.id])
        XCTAssertEqual(session.selectedEntries.map(\.path), [file.path])
        XCTAssertFalse(session.canUndo)
        XCTAssertFalse(session.canRedo)
    }

    func testDiscardReturnsFromAddedDirectoriesToTheNearestBaselineDirectory() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("added", isDirectory: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: source.appendingPathComponent("sub/new.txt"))
        let session = ArchiveBrowsingSession()
        try await session.loadEntries([ArchiveEntry(path: "base/kept.txt", type: .file)])
        await session.enterDirectory("base")
        try session.addFiles([source])
        await session.enterDirectory("base/added")
        await session.enterDirectory("base/added/sub")
        await session.goBack()
        await session.discardChanges()
        XCTAssertEqual(session.currentDirectoryPath, "base")
        XCTAssertEqual(session.displayedEntries.map(\.path), ["base/kept.txt"])
        XCTAssertEqual(session.backStack, [""])
        XCTAssertTrue(session.forwardStack.isEmpty)
        await session.goBack()
        XCTAssertEqual(session.currentDirectoryPath, "")
        await session.goForward()
        XCTAssertEqual(session.currentDirectoryPath, "base")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.appendingPathComponent("sub/new.txt").path))
    }

    func testAcceptingPublishedChangesNeverReversesTheTargetNavigation() async throws {
        let session = ArchiveBrowsingSession()
        let ancestor = ArchiveEntry(path: "old", type: .directory)
        let file = ArchiveEntry(path: "old/child/file.txt", type: .file, uncompressedSize: 7, crc32: 12)
        try await session.loadEntries([ancestor, file])
        await session.enterDirectory("old/child")
        session.selectOnly(file.id)
        session.addDraftMutation(.renameEntry(oldArchivePath: "old", newArchivePath: "new"))
        await session.refreshDisplayedEntries()
        session.acceptSavedChanges()
        await session.discardChanges()
        XCTAssertEqual(session.currentDirectoryPath, "new/child")
        XCTAssertEqual(session.selectedEntries.map(\.path), ["new/child/file.txt"])
        try await session.loadEntries([ArchiveEntry(path: "new/child/file.txt", type: .file, uncompressedSize: 7, crc32: 12)])
        await session.undo()
        await session.redo()
        XCTAssertEqual(session.currentDirectoryPath, "new/child")
        XCTAssertEqual(session.selectedEntries.map(\.path), ["new/child/file.txt"])
        XCTAssertFalse(session.hasUnsavedChanges)
    }

    private func sourceFolder(in root: URL) throws -> URL {
        let source = root.appendingPathComponent("old", isDirectory: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("child/grand"), withIntermediateDirectories: true)
        try Data("real saved bytes".utf8).write(to: source.appendingPathComponent("child/grand/file.txt"))
        return source
    }

    func testRealSaveReloadsThePublishedNestedPathEvenWithACompletionCallback() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try sourceFolder(in: root)
        let archive = root.appendingPathComponent("archive.zip")
        let engine = NativeZipEngine()
        try await engine.create(sources: [source], at: archive, profile: CreationProfile(format: .zip), password: nil, progress: { _ in })
        let entries = try await engine.list(archive, password: nil, progress: { _ in })
        let session = ArchiveBrowsingSession(url: archive)
        try await session.loadEntries(entries)
        let ancestor = try XCTUnwrap(session.displayedEntries.first)
        await session.enterDirectory("old")
        await session.enterDirectory("old/child")
        session.selectOnly(try XCTUnwrap(session.displayedEntries.first).id)
        try session.renameEntry(ancestor, to: "new")
        await session.refreshDisplayedEntries()
        let model = makeTestAppViewModel()
        model.sessions = [session]
        model.activeSessionID = session.id
        var completed = false
        model.saveChanges(for: session) { completed = true }
        try await waitUntil {
            if case .ready = session.phase { return completed && !session.hasUnsavedChanges }
            return false
        }
        XCTAssertEqual(session.currentDirectoryPath, "new/child")
        XCTAssertEqual(session.backStack, ["", "new"])
        let published = try await session.directoryEntries(at: "new/child")
        XCTAssertEqual(published.map(\.path), ["new/child/grand"])
        XCTAssertEqual(session.selectedEntries.map(\.path), ["new/child/grand"])
        await session.enterDirectory("new/child/grand")
        XCTAssertEqual(session.displayedEntries.map(\.path), ["new/child/grand/file.txt"])
        let bytes = try await model.previewBytes(for: try XCTUnwrap(session.displayedEntries.first), in: session, maximumCount: 100)
        XCTAssertEqual(bytes, Data("real saved bytes".utf8))
        await session.discardChanges()
        XCTAssertEqual(session.currentDirectoryPath, "new/child/grand")
        model.forceCloseSession(id: session.id)
    }

    func testRealDraftCreationKeepsThePublishedRenamedDirectory() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try sourceFolder(in: root)
        let session = ArchiveBrowsingSession(url: root.appendingPathComponent("not-created.zip"))
        try session.addFiles([source])
        await session.refreshDisplayedEntries()
        let ancestor = try XCTUnwrap(session.displayedEntries.first)
        await session.enterDirectory("old/child")
        session.selectOnly(try XCTUnwrap(session.displayedEntries.first).id)
        try session.renameEntry(ancestor, to: "new")
        await session.refreshDisplayedEntries()
        let model = makeTestAppViewModel()
        model.sessions = [session]
        model.activeSessionID = session.id
        model.saveChanges(for: session)
        try await waitUntil { model.isCreationDialogPresented || model.isAlertPresented }
        XCTAssertTrue(model.isCreationDialogPresented, model.alertMessage)
        let sources = model.creationSources
        let stagedRoot = try XCTUnwrap(sources.first).deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: stagedRoot) }
        let completion = try XCTUnwrap(model.creationCompletion)
        let originals = model.creationOriginalSources
        let destination = root.appendingPathComponent("created.zip")
        model.creationCompletion = nil
        model.isCreationDialogPresented = false
        model.createArchive(sources: sources, destinationURL: destination, profile: CreationProfile(format: .zip), sourcesToTrash: originals, completion: completion)
        model.creationDialogDidDismiss()
        try await waitUntil {
            if case .ready = session.phase { return session.url == destination && !session.hasUnsavedChanges }
            return false
        }
        XCTAssertEqual(session.currentDirectoryPath, "new/child")
        let published = try await session.directoryEntries(at: "new/child")
        XCTAssertEqual(published.map(\.path), ["new/child/grand"])
        await session.enterDirectory("new/child/grand")
        XCTAssertEqual(session.displayedEntries.map(\.path), ["new/child/grand/file.txt"])
        await session.discardChanges()
        XCTAssertEqual(session.currentDirectoryPath, "new/child/grand")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.appendingPathComponent("child/grand/file.txt").path))
        model.forceCloseSession(id: session.id)
    }
}
