import XCTest
import Foundation
import ProZipCore
import ProZipEngines
import ProZipShared
@testable import ProZipUI

@MainActor
final class DraftEntryExportTests: XCTestCase {
    private func fixture() async throws -> (root: URL, source: URL, session: ArchiveBrowsingSession) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("prozip-export-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("docs", isDirectory: true)
        let nested = source.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("empty"), withIntermediateDirectories: true)
        try Data("fixture bytes".utf8).write(to: nested.appendingPathComponent("original.txt"))
        try Data("metadata".utf8).write(to: source.appendingPathComponent(".DS_Store"))
        let archive = root.appendingPathComponent("fixture.zip")
        let engine = NativeZipEngine()
        try await engine.create(sources: [source], at: archive, profile: CreationProfile(format: .zip, preserveMacMetadata: true), password: nil, progress: { _ in })
        let session = ArchiveBrowsingSession(url: archive)
        try await session.loadEntries(try await engine.list(archive, password: nil, progress: { _ in }))
        return (root, source, session)
    }

    func testRenamedArchivedFileReadsItsOriginalMemberAndExportsTheNewName() async throws {
        let (root, _, session) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let originalArchive = try Data(contentsOf: session.url)
        try session.renameEntry(try XCTUnwrap(session.displayedEntries.first), to: "renamed")
        await session.enterDirectory("renamed/nested")
        try session.renameEntry(try XCTUnwrap(session.displayedEntries.first), to: "changed.txt")
        await session.refreshDisplayedEntries()
        let entry = try XCTUnwrap(session.displayedEntries.first)
        do {
            let stream = try await NativeZipEngine().openMember(entry, in: session.url, password: nil, range: nil)
            for try await _ in stream {}
            XCTFail("The pending path does not yet exist in the source archive")
        } catch {}
        let model = makeTestAppViewModel()
        let previewBytes = try await model.previewBytes(for: entry, in: session, maximumCount: 7)
        XCTAssertEqual(previewBytes, Data("fixture".utf8))
        let preview = try await model.materializePreview(entry, in: session)
        defer { try? FileManager.default.removeItem(at: preview.deletingLastPathComponent()) }
        XCTAssertEqual(preview.lastPathComponent, "changed.txt")
        XCTAssertEqual(try Data(contentsOf: preview), Data("fixture bytes".utf8))
        let exported = try await model.exportEntry(entry, in: session)
        defer { try? FileManager.default.removeItem(at: exported.deletingLastPathComponent()) }
        XCTAssertEqual(exported.lastPathComponent, "changed.txt")
        XCTAssertEqual(try Data(contentsOf: exported), Data("fixture bytes".utf8))
        XCTAssertEqual(try Data(contentsOf: session.url), originalArchive)
        XCTAssertTrue(session.hasUnsavedChanges)
    }

    func testRenamedDirectoryExportPreservesTheWholeSubtree() async throws {
        let (root, _, session) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let originalArchive = try Data(contentsOf: session.url)
        try session.renameEntry(try XCTUnwrap(session.displayedEntries.first), to: "exported")
        await session.refreshDisplayedEntries()
        let entry = try XCTUnwrap(session.displayedEntries.first)
        let model = makeTestAppViewModel()
        let exported = try await model.exportEntry(entry, in: session)
        defer { try? FileManager.default.removeItem(at: exported.deletingLastPathComponent()) }
        XCTAssertEqual(exported.lastPathComponent, "exported")
        XCTAssertEqual(try Data(contentsOf: exported.appendingPathComponent("nested/original.txt")), Data("fixture bytes".utf8))
        XCTAssertEqual(try Data(contentsOf: exported.appendingPathComponent(".DS_Store")), Data("metadata".utf8))
        var directory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: exported.appendingPathComponent("empty").path, isDirectory: &directory))
        XCTAssertTrue(directory.boolValue)
        XCTAssertEqual(try Data(contentsOf: session.url), originalArchive)
        XCTAssertFalse(model.isPasswordPromptPresented)
    }

    func testDirectoryWithPendingChildDeletionOrRenameRequiresSaving() async throws {
        let (root, _, session) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let entry = try XCTUnwrap(session.displayedEntries.first)
        let model = makeTestAppViewModel()
        for mutation in [
            ArchiveMutation.deleteEntry(archivePath: "docs/nested/original.txt"),
            .renameEntry(oldArchivePath: "docs/nested/original.txt", newArchivePath: "docs/nested/renamed.txt")
        ] {
            session.addDraftMutation(mutation)
            do {
                _ = try await model.exportEntry(entry, in: session)
                XCTFail("The exporter must not silently return an old directory tree")
            } catch let error as ProZipError {
                guard case .structureConflict = error else { return XCTFail("Expected save-first guidance") }
            }
            await session.discardChanges()
        }
        XCTAssertFalse(model.isPasswordPromptPresented)
    }

    func testLocalSourcesExportDirectlyAndModifiedLocalDirectoriesRequireSaving() async throws {
        let (root, source, _) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = ArchiveBrowsingSession(url: root.appendingPathComponent("draft.zip"))
        try session.addFiles([source])
        await session.refreshDisplayedEntries()
        let model = makeTestAppViewModel()
        let directory = try XCTUnwrap(session.displayedEntries.first)
        let exportedDirectory = try await model.exportEntry(directory, in: session)
        XCTAssertEqual(exportedDirectory, source)
        await session.enterDirectory("docs/nested")
        let entry = try XCTUnwrap(session.displayedEntries.first)
        try session.renameEntry(entry, to: "renamed.txt")
        await session.refreshDisplayedEntries()
        let exportedFile = try await model.exportEntry(try XCTUnwrap(session.displayedEntries.first), in: session)
        XCTAssertEqual(exportedFile, source.appendingPathComponent("nested/original.txt"))
        do {
            _ = try await model.exportEntry(directory, in: session)
            XCTFail("A source directory cannot stand in for pending child edits")
        } catch let error as ProZipError {
            guard case .structureConflict = error else { return XCTFail("Expected save-first guidance") }
        }
    }

    func testMergedDirectorySourceDoesNotHideAnIndexedFileDuringExport() async throws {
        let (root, _, session) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let local = root.appendingPathComponent("extra/docs", isDirectory: true)
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        try Data("local".utf8).write(to: local.appendingPathComponent("local.txt"))
        try session.addFiles([local])
        await session.enterDirectory("docs/nested")
        let model = makeTestAppViewModel()
        let exported = try await model.exportEntry(try XCTUnwrap(session.displayedEntries.first), in: session)
        defer { try? FileManager.default.removeItem(at: exported.deletingLastPathComponent()) }
        XCTAssertEqual(try Data(contentsOf: exported), Data("fixture bytes".utf8))
        await session.enterDirectory("")
        do {
            _ = try await model.exportEntry(try XCTUnwrap(session.displayedEntries.first), in: session)
            XCTFail("A merged directory needs saving before exporting")
        } catch let error as ProZipError {
            guard case .structureConflict = error else { return XCTFail("Expected save-first guidance") }
        }
    }

    func testEncryptedDirectoryExportRequiresPasswordWithoutPresentingAPrompt() async throws {
        let (root, source, _) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = root.appendingPathComponent("encrypted.zip")
        let password = "export-test-fixture"
        let engine = NativeZipEngine()
        try await engine.create(sources: [source], at: archive, profile: CreationProfile(format: .zip, password: password), password: password, progress: { _ in })
        let session = ArchiveBrowsingSession(url: archive)
        try await session.loadEntries(try await engine.list(archive, password: password, progress: { _ in }))
        let model = makeTestAppViewModel()
        do {
            _ = try await model.exportEntry(try XCTUnwrap(session.displayedEntries.first), in: session)
            XCTFail("Encrypted children must not be skipped silently")
        } catch let error as ProZipError {
            guard case .passwordRequired = error else { return XCTFail("Expected a password request") }
        }
        XCTAssertFalse(model.isPasswordPromptPresented)
        XCTAssertTrue(model.tasks.isEmpty)
    }

    func testMissingLocalSourceNeverReturnsAnUnusableExportURL() async throws {
        let (root, source, _) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = source.appendingPathComponent("nested/original.txt")
        let session = ArchiveBrowsingSession(url: root.appendingPathComponent("draft.zip"))
        try session.addFiles([file])
        await session.refreshDisplayedEntries()
        let entry = try XCTUnwrap(session.displayedEntries.first)
        try FileManager.default.removeItem(at: file)
        do {
            _ = try await makeTestAppViewModel().exportEntry(entry, in: session)
            XCTFail("A missing source must throw instead of reporting success")
        } catch {}
    }

    func testDirectoryExportPreservesInternalLinksAndRejectsLinksThatEscapeAfterMoving() async throws {
        let (root, source, _) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createSymbolicLink(atPath: source.appendingPathComponent("shortcut").path, withDestinationPath: "nested/original.txt")
        try FileManager.default.createSymbolicLink(atPath: source.appendingPathComponent("nested/reenter").path, withDestinationPath: "../../docs/nested/original.txt")
        let archive = root.appendingPathComponent("links.zip")
        let engine = NativeZipEngine()
        try await engine.create(sources: [source], at: archive, profile: CreationProfile(format: .zip), password: nil, progress: { _ in })
        let session = ArchiveBrowsingSession(url: archive)
        try await session.loadEntries(try await engine.list(archive, password: nil, progress: { _ in }))
        let model = makeTestAppViewModel()
        let exported = try await model.exportEntry(try XCTUnwrap(session.displayedEntries.first), in: session)
        defer { try? FileManager.default.removeItem(at: exported.deletingLastPathComponent()) }
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: exported.appendingPathComponent("shortcut").path), "nested/original.txt")
        await session.enterDirectory("docs")
        let nested = try XCTUnwrap(session.displayedEntries.first { $0.name == "nested" })
        do {
            _ = try await model.exportEntry(nested, in: session)
            XCTFail("Moving a selected subtree must not turn an internal link into an escaping link")
        } catch let error as ProZipError {
            guard case .symlinkOutOfBounds = error else { return XCTFail("Expected an escaping-link error") }
        }
    }
}
