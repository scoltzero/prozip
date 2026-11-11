import Foundation
import XCTest
import ProZipShared
import ProZipCore
import ProZipEngines
@testable import ProZipUI

@MainActor
final class DraftStateIntegrityTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("prozip-draft-integrity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func directory(_ path: String, in root: URL, files: [String: String]) throws -> URL {
        let result = root.appendingPathComponent(path, isDirectory: true)
        try FileManager.default.createDirectory(at: result, withIntermediateDirectories: true)
        for (name, text) in files {
            let file = result.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: file)
        }
        return result
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("The session did not finish refreshing")
    }

    private func preparedModel(_ mutations: [ArchiveMutation], in root: URL) async throws -> ProZipAppViewModel {
        let session = ArchiveBrowsingSession(url: root.appendingPathComponent("draft-\(UUID().uuidString).zip"))
        for mutation in mutations { session.addDraftMutation(mutation) }
        let model = makeTestAppViewModel()
        model.sessions = [session]
        model.activeSessionID = session.id
        model.saveChanges(for: session)
        try await waitUntil { model.isCreationDialogPresented || model.isAlertPresented }
        XCTAssertTrue(model.isCreationDialogPresented, model.alertMessage)
        return model
    }

    private func removeStaging(_ model: ProZipAppViewModel) {
        if let source = model.creationSources.first { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
    }

    func testAddingSameNamedDirectoriesStagesTheTreeShownInTheDraft() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try directory("first/docs", in: root, files: ["a.txt": "first", "nested/keep.txt": "nested first"])
        let second = try directory("second/docs", in: root, files: ["b.txt": "second", "nested/new.txt": "nested second"])
        let session = ArchiveBrowsingSession()
        try session.addFiles([first, second])
        await session.enterDirectory("docs")
        XCTAssertEqual(Set(session.displayedEntries.map(\.name)), ["a.txt", "b.txt", "nested"])
        let sources = try await ProZipAppViewModel.stageNewArchiveDraft(session.pendingMutations)
        let staged = try XCTUnwrap(sources.first)
        defer { try? FileManager.default.removeItem(at: staged.deletingLastPathComponent()) }
        let names = try FileManager.default.contentsOfDirectory(at: staged, includingPropertiesForKeys: nil).map(\.lastPathComponent)
        XCTAssertEqual(Set(names), Set(session.displayedEntries.map(\.name)))
        XCTAssertEqual(try String(contentsOf: staged.appendingPathComponent("nested/keep.txt"), encoding: .utf8), "nested first")
        XCTAssertEqual(try String(contentsOf: staged.appendingPathComponent("nested/new.txt"), encoding: .utf8), "nested second")
        let archive = root.appendingPathComponent("merged.zip")
        let engine = NativeZipEngine()
        try await engine.create(sources: sources, at: archive, profile: CreationProfile(format: .zip), password: nil, progress: { _ in })
        let entries = try await engine.list(archive, password: nil, progress: { _ in })
        XCTAssertEqual(Set(entries.filter { !$0.isDirectory }.map(\.path)), ["docs/a.txt", "docs/b.txt", "docs/nested/keep.txt", "docs/nested/new.txt"])
    }

    func testPendingRenameIsRejectedBeforeSelectingDiskEntries() async throws {
        let session = ArchiveBrowsingSession()
        try await session.loadEntries([ArchiveEntry(path: "old.txt", type: .file)])
        try session.renameEntry(try XCTUnwrap(session.displayedEntries.first), to: "new.txt")
        await session.refreshDisplayedEntries()
        let selected = try XCTUnwrap(session.displayedEntries.first)
        do {
            _ = try await makeTestAppViewModel().extractionEntries(for: [selected], in: session)
            XCTFail("Pending edits must request saving, rather than silently select zero disk entries")
        } catch let error as ProZipError {
            guard case .structureConflict(let message) = error else { return XCTFail("Expected save-first guidance") }
            XCTAssertTrue(message.contains("保存"))
        }
    }

    func testMissingSelectionIsRejectedInsteadOfSilentlyExtractingASubset() async throws {
        let present = ArchiveEntry(path: "present.txt", type: .file)
        let absent = ArchiveEntry(path: "absent.txt", type: .file)
        let session = ArchiveBrowsingSession()
        try await session.loadEntries([present])
        do {
            _ = try await makeTestAppViewModel().extractionEntries(for: [present, absent], in: session)
            XCTFail("Every explicitly selected entry must be found")
        } catch let error as ProZipError {
            guard case .structureConflict = error else { return XCTFail("Expected a stale-selection error") }
        }
    }

    func testShowingAuxiliaryEntriesChangesTheActualSessionRows() async throws {
        let session = ArchiveBrowsingSession()
        let visible = ArchiveEntry(path: "visible.txt", type: .file)
        let hidden = ArchiveEntry(path: ".DS_Store", type: .file)
        try await session.loadEntries([visible, hidden])
        XCTAssertEqual(session.displayedEntries.map(\.path), [visible.path])
        XCTAssertEqual(session.auxiliaryEntryCount, 1)
        session.showsAuxiliaryEntries = true
        await session.refreshDisplayedEntries()
        XCTAssertEqual(Set(session.displayedEntries.map(\.path)), [visible.path, hidden.path])
        XCTAssertEqual(session.auxiliaryEntryCount, 1)
    }

    func testAuxiliaryBadgeCountsImmediateNodesAndTracksDraftDeletion() async throws {
        let session = ArchiveBrowsingSession()
        try await session.loadEntries([
            ArchiveEntry(path: "visible.txt", type: .file),
            ArchiveEntry(path: ".DS_Store", type: .file),
            ArchiveEntry(path: "__MACOSX/._visible.txt", type: .file),
            ArchiveEntry(path: "Documents/.DS_Store", type: .file)
        ])
        XCTAssertEqual(session.auxiliaryEntryCount, 2)
        await session.enterDirectory("__MACOSX")
        XCTAssertEqual(session.auxiliaryEntryCount, 1)
        XCTAssertTrue(session.displayedEntries.isEmpty)
        session.showsAuxiliaryEntries = true
        await session.refreshDisplayedEntries()
        let hidden = try XCTUnwrap(session.displayedEntries.first)
        try session.deleteEntries([hidden])
        await session.refreshDisplayedEntries()
        XCTAssertEqual(session.auxiliaryEntryCount, 0)
        await session.undo()
        XCTAssertEqual(session.auxiliaryEntryCount, 1)
        await session.enterDirectory("Documents")
        XCTAssertEqual(session.auxiliaryEntryCount, 1)
    }

    func testMergedDirectoriesOnlyOfferCompleteOriginalSourcesForTrash() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try directory("first/docs", in: root, files: ["a.txt": "first"])
        let second = try directory("second/docs", in: root, files: ["b.txt": "second"])
        let complete = try await preparedModel([.addFile(sourceURL: first, archivePath: "docs"), .addFile(sourceURL: second, archivePath: "docs")], in: root)
        defer { removeStaging(complete) }
        XCTAssertEqual(complete.creationSourcesToTrash, [first, second])

        let replacement = try directory("replacement/docs", in: root, files: ["a.txt": "replacement", "new.txt": "new"])
        let partial = try await preparedModel([.addFile(sourceURL: first, archivePath: "docs"), .addFile(sourceURL: replacement, archivePath: "docs")], in: root)
        defer { removeStaging(partial) }
        XCTAssertEqual(partial.creationSourcesToTrash, [replacement])
        XCTAssertEqual(try String(contentsOf: first.appendingPathComponent("a.txt"), encoding: .utf8), "first")
    }

    func testDirectoryReplacementStillRemovesThePreviousSubtree() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try directory("first/docs", in: root, files: ["old.txt": "old"])
        let second = try directory("second/docs", in: root, files: ["new.txt": "new"])
        let sources = try await ProZipAppViewModel.stageNewArchiveDraft([.addFile(sourceURL: first, archivePath: "docs"), .replaceEntry(archivePath: "docs", replacementSourceURL: second)])
        let staged = try XCTUnwrap(sources.first)
        defer { try? FileManager.default.removeItem(at: staged.deletingLastPathComponent()) }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: staged.path), ["new.txt"])
    }

    func testDirectoryMergeNeverWritesThroughAPreviousSourceSymlink() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = try directory("outside", in: root, files: ["untouched.txt": "outside"])
        let first = try directory("first/docs", in: root, files: [:])
        try FileManager.default.createSymbolicLink(atPath: first.appendingPathComponent("link").path, withDestinationPath: outside.path)
        let second = try directory("second/docs", in: root, files: ["link/added.txt": "inside"])
        let sources = try await ProZipAppViewModel.stageNewArchiveDraft([.addFile(sourceURL: first, archivePath: "docs"), .addFile(sourceURL: second, archivePath: "docs")])
        let staged = try XCTUnwrap(sources.first)
        defer { try? FileManager.default.removeItem(at: staged.deletingLastPathComponent()) }
        XCTAssertEqual(try String(contentsOf: staged.appendingPathComponent("link/added.txt"), encoding: .utf8), "inside")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outside.path), ["untouched.txt"])
        XCTAssertEqual(try String(contentsOf: outside.appendingPathComponent("untouched.txt"), encoding: .utf8), "outside")
    }

    func testCaseCollisionsCannotSilentlyOverwriteAStagedMember() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try directory("first/docs", in: root, files: ["a.txt": "first"])
        let second = try directory("second/docs", in: root, files: ["A.txt": "second"])
        let aliasesExistingFile = FileManager.default.fileExists(atPath: first.appendingPathComponent("A.txt").path)
        do {
            let sources = try await ProZipAppViewModel.stageNewArchiveDraft([.addFile(sourceURL: first, archivePath: "docs"), .addFile(sourceURL: second, archivePath: "docs")])
            let staged = try XCTUnwrap(sources.first)
            defer { try? FileManager.default.removeItem(at: staged.deletingLastPathComponent()) }
            XCTAssertFalse(aliasesExistingFile, "A case-insensitive staging volume must report the conflict")
            XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: staged.path)), ["a.txt", "A.txt"])
        } catch let error as ProZipError {
            XCTAssertTrue(aliasesExistingFile)
            guard case .structureConflict = error else { return XCTFail("Expected a case-collision error") }
        }
        XCTAssertEqual(try String(contentsOf: first.appendingPathComponent("a.txt"), encoding: .utf8), "first")
    }

    func testDirtyExtractionEntrypointsKeepTheDraftAndArchiveUntouched() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("old.txt")
        try Data("original".utf8).write(to: source)
        let archive = root.appendingPathComponent("archive.zip")
        let engine = NativeZipEngine()
        try await engine.create(sources: [source], at: archive, profile: CreationProfile(format: .zip), password: nil, progress: { _ in })
        let original = try Data(contentsOf: archive)
        let session = ArchiveBrowsingSession(url: archive)
        try await session.loadEntries(try await engine.list(archive, password: nil, progress: { _ in }))
        try session.renameEntry(try XCTUnwrap(session.displayedEntries.first), to: "renamed.txt")
        await session.refreshDisplayedEntries()
        let model = makeTestAppViewModel()
        let reveal = model.preferences.automaticallySelectsResults
        model.preferences.automaticallySelectsResults = false
        defer { model.preferences.automaticallySelectsResults = reveal }
        let output = root.appendingPathComponent("output")
        model.extractAll(in: session, to: output)
        XCTAssertTrue(model.isAlertPresented)
        XCTAssertTrue(model.alertMessage.contains("保存"))
        XCTAssertTrue(model.tasks.isEmpty)
        model.isAlertPresented = false
        model.extractSelection(session.displayedEntries, in: session, to: output)
        XCTAssertTrue(model.isAlertPresented)
        XCTAssertTrue(model.tasks.isEmpty)
        XCTAssertTrue(session.hasUnsavedChanges)
        XCTAssertEqual(try Data(contentsOf: archive), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        do {
            _ = try await model.extractionEntries(for: nil, in: session)
            XCTFail("Extract-all must also reject pending mutations")
        } catch let error as ProZipError {
            guard case .structureConflict = error else { return XCTFail("Expected save-first guidance") }
        }
    }

    func testExplicitAuxiliaryFilesAndVirtualDirectoriesSurviveDefaultExtractionFilters() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let metadata = root.appendingPathComponent(".DS_Store")
        try Data("metadata".utf8).write(to: metadata)
        let folder = try directory("__MACOSX", in: root, files: ["payload.txt": "auxiliary"])
        let archive = root.appendingPathComponent("archive.zip")
        let engine = NativeZipEngine()
        try await engine.create(sources: [metadata, folder], at: archive, profile: CreationProfile(format: .zip, preserveMacMetadata: true), password: nil, progress: { _ in })
        let entries = try await engine.list(archive, password: nil, progress: { _ in })
        let session = ArchiveBrowsingSession(url: archive)
        try await session.loadEntries(entries.filter { !$0.isDirectory })
        let storedFolder = try await session.index.entry(forPath: "__MACOSX")
        let selectedFolder = try XCTUnwrap(storedFolder)
        let model = makeTestAppViewModel()
        let requested = try await model.extractionEntries(for: [selectedFolder], in: session)
        XCTAssertEqual(Set(requested.map(\.path)), ["__MACOSX", "__MACOSX/payload.txt"])
        var options = ExtractionOptions(stripSingleRootFolderIfMatching: false)
        options.explicitlySelectedEntryIDs = [selectedFolder.id]
        let destination = root.appendingPathComponent("folder-output")
        let report = try await engine.extract(requested, from: archive, to: destination, password: nil, options: options, progress: { _ in })
        XCTAssertEqual(report.skippedCount, 0)
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("__MACOSX/payload.txt"), encoding: .utf8), "auxiliary")
        let selectedFile = try XCTUnwrap(entries.first { $0.path == ".DS_Store" })
        let fileEntries = try await model.extractionEntries(for: [selectedFile], in: session)
        options.explicitlySelectedEntryIDs = [selectedFile.id]
        let fileDestination = root.appendingPathComponent("file-output")
        _ = try await engine.extract(fileEntries, from: archive, to: fileDestination, password: nil, options: options, progress: { _ in })
        XCTAssertEqual(try String(contentsOf: fileDestination.appendingPathComponent(".DS_Store"), encoding: .utf8), "metadata")
    }

    func testAuxiliarySwitchAutomaticallyRefreshesSearchAndPrunesHiddenSelection() async throws {
        let session = ArchiveBrowsingSession()
        let hidden = ArchiveEntry(path: ".DS_Store", type: .file)
        try await session.loadEntries([hidden, ArchiveEntry(path: "visible.txt", type: .file)])
        session.searchQuery = "DS_Store"
        await session.refreshDisplayedEntries()
        XCTAssertTrue(session.displayedEntries.isEmpty)
        session.showsAuxiliaryEntries = true
        try await waitUntil { session.displayedEntries.map(\.id) == [hidden.id] }
        session.selectOnly(hidden.id)
        let revision = session.displayedEntriesRevision
        session.showsAuxiliaryEntries = false
        try await waitUntil { session.displayedEntries.isEmpty && session.selectedEntryIDs.isEmpty }
        XCTAssertGreaterThan(session.displayedEntriesRevision, revision)
        XCTAssertTrue(session.selectedEntries.isEmpty)
        XCTAssertNil(session.selectionAnchorID)
        XCTAssertNil(session.selectionLeadID)
    }

    func testDirectoryStatisticsIncludeHiddenMembersRegardlessOfDisplayPreference() async throws {
        let session = ArchiveBrowsingSession()
        try await session.loadEntries([
            ArchiveEntry(path: "folder/visible.txt", type: .file, uncompressedSize: 5),
            ArchiveEntry(path: "folder/.DS_Store", type: .file, uncompressedSize: 7),
            ArchiveEntry(path: "folder/.background/image.jpg", type: .file, uncompressedSize: 11),
            ArchiveEntry(path: "folder/Applications", type: .symlink, uncompressedSize: 13, symlinkTarget: "missing"),
            ArchiveEntry(path: "folder/.env", type: .file, uncompressedSize: 17)
        ])
        await session.enterDirectory("folder")
        let hiddenMode = try await session.directoryEntries(at: "folder")
        XCTAssertEqual(Set(hiddenMode.map(\.name)), ["visible.txt", ".env"])
        let hiddenTotal = try await session.totalUncompressedSize(inDirectory: "folder")
        XCTAssertEqual(hiddenTotal, 53)
        session.showsAuxiliaryEntries = true
        let shownMode = try await session.directoryEntries(at: "folder")
        XCTAssertEqual(Set(shownMode.map(\.name)), ["visible.txt", ".env", ".DS_Store", ".background", "Applications"])
        let shownTotal = try await session.totalUncompressedSize(inDirectory: "folder")
        XCTAssertEqual(shownTotal, 53)
        XCTAssertEqual(session.currentDirectoryPath, "folder")
    }

    func testAuxiliaryRefreshPreservesVisibleKeyboardRangeAnchorAndLead() async throws {
        let session = ArchiveBrowsingSession()
        let visible = ["a.txt", "b.txt", "c.txt"].map { ArchiveEntry(path: $0, type: .file) }
        try await session.loadEntries(visible + [ArchiveEntry(path: ".DS_Store", type: .file)])
        session.selectOnly(visible[0].id)
        session.selectRange(to: visible[2].id, in: session.displayedEntries)
        session.showsAuxiliaryEntries = true
        try await waitUntil { session.displayedEntries.count == 4 }
        XCTAssertEqual(session.selectionAnchorID, visible[0].id)
        XCTAssertEqual(session.selectionLeadID, visible[2].id)
        session.moveSelection(by: -1, in: session.displayedEntries, extending: true)
        XCTAssertEqual(session.selectedEntryIDs, Set(visible.prefix(2).map(\.id)))
        session.showsAuxiliaryEntries = false
        try await waitUntil { session.displayedEntries.count == 3 }
        session.moveSelection(by: 1, in: session.displayedEntries, extending: true)
        XCTAssertEqual(session.selectedEntryIDs, Set(visible.map(\.id)))
        XCTAssertEqual(session.selectedEntries.count, 3)
        XCTAssertEqual(session.selectionAnchorID, visible[0].id)
    }
}
