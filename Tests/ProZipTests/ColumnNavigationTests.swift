import XCTest
import ProZipCore
import ProZipShared

@MainActor
final class ColumnNavigationTests: XCTestCase {
    func testReadingAncestorColumnPreservesActivePathHistoryAndSelection() async throws {
        let session = ArchiveBrowsingSession(url: URL(fileURLWithPath: "/tmp/columns.zip"))
        let folder = ArchiveEntry(path: "docs", type: .directory)
        let file = ArchiveEntry(path: "docs/readme.txt", type: .file)
        try await session.loadEntries([folder, file, ArchiveEntry(path: "root.txt", type: .file)])
        try session.renameEntry(folder, to: "renamed")
        await session.refreshDisplayedEntries()
        await session.enterDirectory("renamed")
        let selected = try XCTUnwrap(session.displayedEntries.first)
        session.selectOnly(selected.id)
        let history = session.pathHistory
        let root = try await session.directoryEntries(at: "")
        XCTAssertEqual(Set(root.map(\.path)), ["renamed", "root.txt"])
        XCTAssertEqual(session.currentDirectoryPath, "renamed")
        XCTAssertEqual(session.pathHistory, history)
        XCTAssertEqual(session.selectedEntries.map(\.path), ["renamed/readme.txt"])
    }

    func testFolderSizeIncludesNestedContentsAfterDraftRename() async throws {
        let session = ArchiveBrowsingSession(url: URL(fileURLWithPath: "/tmp/folder-size.zip"))
        let folder = ArchiveEntry(path: "docs", type: .directory)
        try await session.loadEntries([
            folder,
            ArchiveEntry(path: "docs/a.txt", type: .file, uncompressedSize: 12),
            ArchiveEntry(path: "docs/sub", type: .directory),
            ArchiveEntry(path: "docs/sub/b.txt", type: .file, uncompressedSize: 13),
            ArchiveEntry(path: "other.txt", type: .file, uncompressedSize: 100)
        ])
        try session.renameEntry(folder, to: "renamed")
        await session.refreshDisplayedEntries()
        let size = try await session.totalUncompressedSize(inDirectory: "renamed")
        XCTAssertEqual(size, 25)
    }

    func testDirectoryDoesNotSilentlyTruncateAfterOneThousandEntries() async throws {
        let session = ArchiveBrowsingSession(url: URL(fileURLWithPath: "/tmp/large-directory.zip"))
        let entries = (0..<1205).map { ArchiveEntry(path: "file-\($0).txt", type: .file) }
        try await session.loadEntries(entries)
        XCTAssertEqual(session.displayedEntries.count, entries.count)
        let column = try await session.directoryEntries(at: "")
        XCTAssertEqual(Set(column.map(\.path)), Set(entries.map(\.path)))
    }
}
