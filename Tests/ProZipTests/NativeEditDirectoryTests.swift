import XCTest
import Foundation
import ProZipShared
@testable import ProZipEngines

final class NativeEditDirectoryTests: XCTestCase {
    private let engine = NativeZipEngine()
    private let profile = CreationProfile(purpose: .general, format: .zip)

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("prozip-native-edit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeArchive(in root: URL) async throws -> URL {
        let file = root.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: file)
        let archive = root.appendingPathComponent("edited.zip")
        try await engine.create(sources: [file], at: archive, profile: profile, password: nil, progress: { _ in })
        return archive
    }

    private func contents(of entry: ArchiveEntry, in archive: URL) async throws -> Data {
        var data = Data()
        for try await chunk in try await engine.openMember(entry, in: archive, password: nil, range: nil) {
            data.append(chunk)
        }
        return data
    }

    func testAddsDirectoryAndSymlinksAtRequestedPathsWithPermissions() async throws {
        let fm = FileManager.default
        let root = try temporaryDirectory()
        defer { try? fm.removeItem(at: root) }
        let archive = try await makeArchive(in: root)
        let folder = root.appendingPathComponent("source-name")
        let child = folder.appendingPathComponent("child")
        let executable = child.appendingPathComponent("run.sh")
        try fm.createDirectory(at: child, withIntermediateDirectories: true)
        try fm.setAttributes([.posixPermissions: 0o750], ofItemAtPath: folder.path)
        try fm.setAttributes([.posixPermissions: 0o710], ofItemAtPath: child.path)
        try Data("echo hello".utf8).write(to: executable)
        try fm.setAttributes([.posixPermissions: 0o751], ofItemAtPath: executable.path)
        try fm.createSymbolicLink(atPath: folder.appendingPathComponent("script-link").path, withDestinationPath: "child/run.sh")
        let folderLink = root.appendingPathComponent("folder-link")
        try fm.createSymbolicLink(atPath: folderLink.path, withDestinationPath: "source-name")
        let brokenLink = root.appendingPathComponent("broken-link")
        try fm.createSymbolicLink(atPath: brokenLink.path, withDestinationPath: "missing.txt")

        try await engine.applyMutations([
            .addFile(sourceURL: folder, archivePath: "nested/renamed-root"),
            .addFile(sourceURL: folderLink, archivePath: "folder-shortcut"),
            .addFile(sourceURL: brokenLink, archivePath: "broken-shortcut")
        ], to: archive, outputURL: archive, profile: profile, password: nil, progress: { _ in })

        let entries = try await engine.list(archive, password: nil, progress: { _ in })
        let byPath = Dictionary(uniqueKeysWithValues: entries.map { ($0.path, $0) })
        XCTAssertEqual(Set(byPath.keys), ["keep.txt", "nested/renamed-root", "nested/renamed-root/child", "nested/renamed-root/child/run.sh", "nested/renamed-root/script-link", "folder-shortcut", "broken-shortcut"])
        XCTAssertEqual(byPath["nested/renamed-root"]?.type, .directory)
        XCTAssertEqual(byPath["nested/renamed-root"]?.permissions, 0o750)
        XCTAssertEqual(byPath["nested/renamed-root/child"]?.permissions, 0o710)
        let archivedExecutable = try XCTUnwrap(byPath["nested/renamed-root/child/run.sh"])
        XCTAssertEqual(archivedExecutable.permissions, 0o751)
        let payload = try await contents(of: archivedExecutable, in: archive)
        XCTAssertEqual(payload, Data("echo hello".utf8))
        XCTAssertEqual(byPath["nested/renamed-root/script-link"]?.symlinkTarget, "child/run.sh")
        XCTAssertEqual(byPath["folder-shortcut"]?.type, .symlink)
        XCTAssertEqual(byPath["folder-shortcut"]?.symlinkTarget, "source-name")
        XCTAssertEqual(byPath["broken-shortcut"]?.type, .symlink)
        XCTAssertEqual(byPath["broken-shortcut"]?.symlinkTarget, "missing.txt")
    }

    func testAddedAndReplacedFilesKeepSourcePermissions() async throws {
        let fm = FileManager.default
        let root = try temporaryDirectory()
        defer { try? fm.removeItem(at: root) }
        let archive = try await makeArchive(in: root)
        let executable = root.appendingPathComponent("source.sh")
        try Data("replacement".utf8).write(to: executable)
        try fm.setAttributes([.posixPermissions: 0o750], ofItemAtPath: executable.path)

        try await engine.applyMutations([
            .replaceEntry(archivePath: "keep.txt", replacementSourceURL: executable),
            .addFile(sourceURL: executable, archivePath: "tools/renamed.sh")
        ], to: archive, outputURL: archive, profile: profile, password: nil, progress: { _ in })

        let entries = try await engine.list(archive, password: nil, progress: { _ in })
        XCTAssertEqual(Set(entries.map(\.path)), ["keep.txt", "tools/renamed.sh"])
        for entry in entries {
            XCTAssertEqual(entry.permissions, 0o750, entry.path)
            let payload = try await contents(of: entry, in: archive)
            XCTAssertEqual(payload, Data("replacement".utf8))
        }
    }

    func testDirectoryRenamesAndDeletesApplyToExistingAndNewSubtrees() async throws {
        let fm = FileManager.default
        let root = try temporaryDirectory()
        defer { try? fm.removeItem(at: root) }
        let archive = try await makeArchive(in: root)
        let folder = root.appendingPathComponent("source")
        let child = folder.appendingPathComponent("child")
        try fm.createDirectory(at: child, withIntermediateDirectories: true)
        try Data("keep child".utf8).write(to: child.appendingPathComponent("keep.txt"))
        try Data("delete child".utf8).write(to: folder.appendingPathComponent("delete.txt"))

        try await engine.applyMutations([
            .addFile(sourceURL: folder, archivePath: "new"),
            .renameEntry(oldArchivePath: "new", newArchivePath: "renamed"),
            .deleteEntry(archivePath: "renamed/delete.txt")
        ], to: archive, outputURL: archive, profile: profile, password: nil, progress: { _ in })
        var entries = try await engine.list(archive, password: nil, progress: { _ in })
        XCTAssertEqual(Set(entries.map(\.path)), ["keep.txt", "renamed", "renamed/child", "renamed/child/keep.txt"])

        try await engine.applyMutations([
            .renameEntry(oldArchivePath: "renamed", newArchivePath: "moved/tree"),
            .deleteEntry(archivePath: "moved/tree/child")
        ], to: archive, outputURL: archive, profile: profile, password: nil, progress: { _ in })
        entries = try await engine.list(archive, password: nil, progress: { _ in })
        XCTAssertEqual(Set(entries.map(\.path)), ["keep.txt", "moved/tree"])
        try await engine.applyMutations([.deleteEntry(archivePath: "moved/tree")], to: archive, outputURL: archive, profile: profile, password: nil, progress: { _ in })
        entries = try await engine.list(archive, password: nil, progress: { _ in })
        XCTAssertEqual(entries.map(\.path), ["keep.txt"])
    }

    func testDirectoryReplacementRemovesOldSubtreeAndSupportsSymlinkReplacement() async throws {
        let fm = FileManager.default
        let root = try temporaryDirectory()
        defer { try? fm.removeItem(at: root) }
        let archive = try await makeArchive(in: root)
        let oldFolder = root.appendingPathComponent("old")
        let replacementFolder = root.appendingPathComponent("replacement")
        try fm.createDirectory(at: oldFolder, withIntermediateDirectories: true)
        try fm.createDirectory(at: replacementFolder, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: oldFolder.appendingPathComponent("old.txt"))
        try Data("new".utf8).write(to: replacementFolder.appendingPathComponent("new.txt"))
        try await engine.applyMutations([.addFile(sourceURL: oldFolder, archivePath: "target")], to: archive, outputURL: archive, profile: profile, password: nil, progress: { _ in })
        try await engine.applyMutations([.addFile(sourceURL: replacementFolder, archivePath: "target")], to: archive, outputURL: archive, profile: profile, password: nil, progress: { _ in })
        let mergedEntries = try await engine.list(archive, password: nil, progress: { _ in })
        XCTAssertEqual(Set(mergedEntries.map(\.path)), ["keep.txt", "target", "target/old.txt", "target/new.txt"])
        let link = root.appendingPathComponent("link")
        try fm.createSymbolicLink(atPath: link.path, withDestinationPath: "target/new.txt")

        try await engine.applyMutations([
            .replaceEntry(archivePath: "target", replacementSourceURL: replacementFolder),
            .replaceEntry(archivePath: "keep.txt", replacementSourceURL: link)
        ], to: archive, outputURL: archive, profile: profile, password: nil, progress: { _ in })
        let entries = try await engine.list(archive, password: nil, progress: { _ in })
        XCTAssertEqual(Set(entries.map(\.path)), ["keep.txt", "target", "target/new.txt"])
        XCTAssertEqual(entries.first(where: { $0.path == "keep.txt" })?.type, .symlink)
        XCTAssertEqual(entries.first(where: { $0.path == "keep.txt" })?.symlinkTarget, "target/new.txt")
    }

    func testUnsafeMutationPathDoesNotOverwriteArchive() async throws {
        let fm = FileManager.default
        let root = try temporaryDirectory()
        defer { try? fm.removeItem(at: root) }
        let archive = try await makeArchive(in: root)
        let originalBytes = try Data(contentsOf: archive)
        do {
            try await engine.applyMutations([.addFile(sourceURL: root.appendingPathComponent("keep.txt"), archivePath: "../../escape.txt")], to: archive, outputURL: archive, profile: profile, password: nil, progress: { _ in })
            XCTFail("Expected unsafe mutation path to be rejected")
        } catch let error as ProZipError {
            guard case .unsafePath = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertEqual(try Data(contentsOf: archive), originalBytes)
    }
}
