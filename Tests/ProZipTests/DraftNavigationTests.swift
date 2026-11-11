import XCTest
import Foundation
import ProZipCore
import ProZipShared

@MainActor
final class DraftNavigationTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("prozip-draft-navigation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    func testRenamedIndexedDirectoryRemainsNavigableBeforeSaving() async throws {
        let session = ArchiveBrowsingSession()
        try await session.loadEntries([
            ArchiveEntry(path: "old", type: .directory),
            ArchiveEntry(path: "old/old/file.txt", type: .file, uncompressedSize: 7)
        ])
        let old = try XCTUnwrap(session.displayedEntries.first)
        try session.renameEntry(old, to: "new")
        await session.refreshDisplayedEntries()
        await session.enterDirectory("new")
        XCTAssertEqual(session.displayedEntries.map(\.path), ["new/old"])
        await session.enterDirectory("new/old")
        XCTAssertEqual(session.displayedEntries.map(\.path), ["new/old/file.txt"])
    }

    func testAddedLocalDirectoryAndItsSubdirectoryAreNavigable() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source folder", isDirectory: true)
        let child = source.appendingPathComponent("child folder", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try Data("contents".utf8).write(to: child.appendingPathComponent("file name.txt"))
        let session = ArchiveBrowsingSession()
        try session.addFiles([source])
        await session.refreshDisplayedEntries()
        XCTAssertEqual(session.displayedEntries.map(\.path), ["source folder"])
        await session.enterDirectory("source folder")
        XCTAssertEqual(session.displayedEntries.map(\.path), ["source folder/child folder"])
        await session.enterDirectory("source folder/child folder")
        XCTAssertEqual(session.displayedEntries.map(\.path), ["source folder/child folder/file name.txt"])
    }

    func testChainedDirectoryRenamesAllowFurtherEditsAndUndo() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let extra = root.appendingPathComponent("added.txt")
        try Data("added".utf8).write(to: extra)
        let session = ArchiveBrowsingSession()
        try await session.loadEntries([
            ArchiveEntry(path: "old/old/file.txt", type: .file, uncompressedSize: 7, permissions: 0o750, isEncrypted: true, encryptionGroupID: "group"),
            ArchiveEntry(path: "old/old/link", type: .symlink, symlinkTarget: "file.txt")
        ])
        try session.renameEntry(try XCTUnwrap(session.displayedEntries.first), to: "new")
        await session.enterDirectory("new")
        try session.renameEntry(try XCTUnwrap(session.displayedEntries.first), to: "nested")
        await session.enterDirectory("new/nested")
        XCTAssertEqual(Set(session.displayedEntries.map(\.path)), ["new/nested/file.txt", "new/nested/link"])
        let file = try XCTUnwrap(session.displayedEntries.first { $0.name == "file.txt" })
        XCTAssertEqual(file.permissions, 0o750)
        XCTAssertEqual(file.encryptionGroupID, "group")
        XCTAssertEqual(session.displayedEntries.first { $0.name == "link" }?.symlinkTarget, "file.txt")

        try session.addFiles([extra])
        await session.refreshDisplayedEntries()
        XCTAssertEqual(Set(session.displayedEntries.map(\.name)), ["file.txt", "link", "added.txt"])
        try session.deleteEntries([file])
        await session.refreshDisplayedEntries()
        XCTAssertEqual(Set(session.displayedEntries.map(\.name)), ["link", "added.txt"])
        await session.undo()
        XCTAssertEqual(Set(session.displayedEntries.map(\.name)), ["file.txt", "link", "added.txt"])
        await session.redo()
        XCTAssertEqual(Set(session.displayedEntries.map(\.name)), ["link", "added.txt"])

        await session.enterDirectory("")
        await session.discardChanges()
        XCTAssertEqual(session.displayedEntries.map(\.path), ["old"])
        await session.enterDirectory("old/old")
        XCTAssertEqual(Set(session.displayedEntries.map(\.name)), ["file.txt", "link"])
    }

    func testAddedDirectoryRenamesAndHiddenFilteringFollowTheDraft() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source", isDirectory: true)
        let child = source.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("__MACOSX"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent(".background"), withIntermediateDirectories: true)
        for name in [".DS_Store", "._file", ".env", ".gitignore"] {
            try Data().write(to: source.appendingPathComponent(name))
        }
        try Data("child".utf8).write(to: child.appendingPathComponent("keep.txt"))
        let session = ArchiveBrowsingSession()
        try session.addFiles([source])
        await session.refreshDisplayedEntries()
        try session.renameEntry(try XCTUnwrap(session.displayedEntries.first), to: "renamed")
        await session.enterDirectory("renamed")
        XCTAssertEqual(Set(session.displayedEntries.map(\.name)), ["child", ".env", ".gitignore"])
        let directory = try XCTUnwrap(session.displayedEntries.first { $0.isDirectory })
        try session.renameEntry(directory, to: "nested")
        await session.enterDirectory("renamed/nested")
        let file = try XCTUnwrap(session.displayedEntries.first)
        XCTAssertEqual(file.path, "renamed/nested/keep.txt")
        try session.renameEntry(file, to: "changed.txt")
        await session.refreshDisplayedEntries()
        XCTAssertEqual(session.displayedEntries.map(\.path), ["renamed/nested/changed.txt"])
        try session.deleteEntries(session.displayedEntries)
        await session.refreshDisplayedEntries()
        XCTAssertTrue(session.displayedEntries.isEmpty)
        await session.undo()
        XCTAssertEqual(session.displayedEntries.map(\.name), ["changed.txt"])
        await session.undo()
        XCTAssertEqual(session.displayedEntries.map(\.name), ["keep.txt"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: child.appendingPathComponent("keep.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.appendingPathComponent("nested").path))
    }

    func testLocalSymlinksKeepTheirTypeAndAreNeverTraversed() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source", isDirectory: true)
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: outside.appendingPathComponent("should-not-appear.txt"))
        try FileManager.default.createSymbolicLink(atPath: source.appendingPathComponent("directory-link").path, withDestinationPath: "../outside")
        let broken = root.appendingPathComponent("broken")
        try FileManager.default.createSymbolicLink(atPath: broken.path, withDestinationPath: "missing")
        let session = ArchiveBrowsingSession()
        try session.addFiles([source, broken])
        await session.refreshDisplayedEntries()
        XCTAssertEqual(session.displayedEntries.first { $0.name == "broken" }?.type, .symlink)
        await session.enterDirectory("source")
        let link = try XCTUnwrap(session.displayedEntries.first)
        XCTAssertEqual(link.type, .symlink)
        XCTAssertEqual(link.symlinkTarget, "../outside")
        await session.enterDirectory(link.path)
        XCTAssertTrue(session.displayedEntries.isEmpty)
        session.searchQuery = "should-not-appear"
        await session.refreshDisplayedEntries()
        XCTAssertTrue(session.displayedEntries.isEmpty)
        session.searchQuery = "broken"
        await session.refreshDisplayedEntries()
        XCTAssertEqual(session.displayedEntries.map(\.type), [.symlink])
    }

    func testNavigationPreservesSpacesAndCaseDistinctNames() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent(" root ", isDirectory: true)
        let child = source.appendingPathComponent(" child ", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        let extra = root.appendingPathComponent("extra.txt")
        try Data("extra".utf8).write(to: extra)
        try Data("file".utf8).write(to: child.appendingPathComponent(" file "))
        let session = ArchiveBrowsingSession()
        try session.addFiles([source])
        await session.enterDirectory(" root / child ")
        XCTAssertEqual(session.currentDirectoryPath, " root / child ")
        XCTAssertEqual(session.displayedEntries.map(\.name), [" file "])
        try session.addFiles([extra])
        await session.refreshDisplayedEntries()
        XCTAssertEqual(Set(session.displayedEntries.map(\.path)), [" root / child / file ", " root / child /extra.txt"])

        let indexed = ArchiveBrowsingSession()
        try await indexed.loadEntries([ArchiveEntry(path: "Extra.txt", type: .file)])
        try indexed.addFiles([extra])
        await indexed.refreshDisplayedEntries()
        XCTAssertEqual(Set(indexed.displayedEntries.map(\.name)), ["Extra.txt", "extra.txt"])
    }

    func testSearchMatchesRenamedAncestorsAndLocalDescendants() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("local".utf8).write(to: source.appendingPathComponent("local.txt"))
        try Data().write(to: source.appendingPathComponent(".DS_Store"))
        let session = ArchiveBrowsingSession()
        try await session.loadEntries([ArchiveEntry(path: "old/indexed.txt", type: .file)])
        try session.renameEntry(try XCTUnwrap(session.displayedEntries.first), to: "new")
        try session.addFiles([source], toDirectory: "new")
        session.searchQuery = "new"
        await session.refreshDisplayedEntries()
        XCTAssertEqual(Set(session.displayedEntries.map(\.path)), ["new/indexed.txt", "new/source", "new/source/local.txt"])
        session.searchQuery = "old"
        await session.refreshDisplayedEntries()
        XCTAssertTrue(session.displayedEntries.isEmpty)
    }

    func testAddedDirectoryMergesWithIndexedChildrenBeforeSaving() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("tree", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("local".utf8).write(to: source.appendingPathComponent("local.txt"))
        let session = ArchiveBrowsingSession()
        try await session.loadEntries([ArchiveEntry(path: "tree/indexed-child/keep.txt", type: .file)])
        try session.addFiles([source])
        await session.enterDirectory("tree")
        XCTAssertEqual(Set(session.displayedEntries.map(\.name)), ["indexed-child", "local.txt"])
        await session.enterDirectory("tree/indexed-child")
        XCTAssertEqual(session.displayedEntries.map(\.path), ["tree/indexed-child/keep.txt"])
        session.addDraftMutation(.replaceEntry(archivePath: "tree", replacementSourceURL: source))
        await session.refreshDisplayedEntries()
        XCTAssertTrue(session.displayedEntries.isEmpty)
        await session.undo()
        XCTAssertEqual(session.displayedEntries.map(\.path), ["tree/indexed-child/keep.txt"])
    }
}
