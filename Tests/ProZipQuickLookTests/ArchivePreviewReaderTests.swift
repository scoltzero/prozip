import CArchive
import Darwin
import Foundation
import XCTest
import ProZipShared
@testable import ProZipQuickLook

final class ArchivePreviewReaderTests: XCTestCase {
    private enum Format: CaseIterable { case zip, tar, sevenZip }
    private struct Member {
        let name: String
        var data = Data()
        var type = mode_t(S_IFREG)
        var link: String?
        var hardLink: String?
    }
    private struct FixtureError: Error { let status: Int32 }

    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("prozip-quicklook-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.resolvingSymlinksInPath()
    }

    private func check(_ status: Int32) throws {
        guard status == ARCHIVE_OK else { throw FixtureError(status: status) }
    }

    private func archive(_ format: Format, members: [Member], in root: URL, password: String? = nil) throws -> URL {
        let url = root.appendingPathComponent(UUID().uuidString).appendingPathExtension(format == .zip ? "zip" : format == .tar ? "tar" : "7z")
        let writer = try XCTUnwrap(archive_write_new())
        defer { archive_write_free(writer) }
        switch format {
        case .zip: try check(archive_write_set_format_zip(writer))
        case .tar: try check(archive_write_set_format_pax_restricted(writer))
        case .sevenZip: try check(archive_write_set_format_7zip(writer))
        }
        if let password {
            try check(archive_write_set_options(writer, "zip:encryption=zipcrypt"))
            try check(archive_write_set_passphrase(writer, password))
        }
        try check(archive_write_open_filename(writer, url.path))
        for (index, member) in members.enumerated() {
            let entry = try XCTUnwrap(archive_entry_new())
            defer { archive_entry_free(entry) }
            archive_entry_set_pathname_utf8(entry, member.name)
            archive_entry_set_filetype(entry, UInt32(member.type))
            archive_entry_set_perm(entry, member.type == mode_t(S_IFDIR) ? 0o755 : 0o644)
            archive_entry_set_size(entry, Int64(member.data.count))
            archive_entry_set_mtime(entry, 1_700_000_000 + index, 0)
            if let link = member.link { archive_entry_set_symlink_utf8(entry, link) }
            if let link = member.hardLink { archive_entry_set_hardlink_utf8(entry, link) }
            try check(archive_write_header(writer, entry))
            if !member.data.isEmpty {
                let written = member.data.withUnsafeBytes { archive_write_data(writer, $0.baseAddress, $0.count) }
                XCTAssertEqual(written, member.data.count)
            }
            try check(archive_write_finish_entry(writer))
        }
        try check(archive_write_close(writer))
        return url
    }

    func testRealZIPTARAndSevenZipPreserveChineseNamesSizesDatesAndSourceBytes() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        for format in Format.allCases {
            let members = [Member(name: "中文说明.txt", data: Data("公开样本".utf8)), Member(name: "folder/second.txt", data: Data("second".utf8))]
            let url = try archive(format, members: members, in: root)
            let before = try Data(contentsOf: url)
            let listing = ArchivePreviewReader.read(url)
            XCTAssertEqual(listing.status, .complete, listing.status.message(visibleCount: listing.entries.count))
            XCTAssertEqual(Set(listing.entries.map(\.path)), Set(members.map(\.name)))
            XCTAssertEqual(listing.sourceSize, Int64(before.count))
            XCTAssertEqual(listing.decodedBytes, Int64(members.reduce(0) { $0 + $1.data.count }))
            for member in members {
                let entry = try XCTUnwrap(listing.entries.first { $0.path == member.name })
                XCTAssertEqual(entry.size, Int64(member.data.count))
                XCTAssertNotNil(entry.modifiedAt)
                XCTAssertEqual(entry.kind, .file)
            }
            XCTAssertEqual(try Data(contentsOf: url), before)
        }
    }

    func testEncryptedZIPShowsAnExplicitPasswordStateWithoutReadingMemberData() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try archive(.zip, members: [Member(name: "fixture.txt", data: Data("public encryption fixture".utf8))], in: root, password: "quicklook-fixture-password")
        let listing = ArchivePreviewReader.read(url)
        XCTAssertEqual(listing.status, .encrypted)
        XCTAssertEqual(listing.decodedBytes, 0)
        XCTAssertTrue(listing.status.message(visibleCount: listing.entries.count).contains("密码"))
    }

    func testLinksAndSpecialEntriesAreListedWithoutExtractingAnything() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let marker = root.appendingPathComponent("untouched.txt")
        try Data("untouched".utf8).write(to: marker)
        let members = [
            Member(name: "../escape.txt", data: Data("not extracted".utf8)),
            Member(name: "folder/", type: mode_t(S_IFDIR)),
            Member(name: "symbolic", type: mode_t(S_IFLNK), link: marker.path),
            Member(name: "hard", hardLink: "../escape.txt"),
            Member(name: "named-pipe", type: mode_t(S_IFIFO))
        ]
        let url = try archive(.tar, members: members, in: root)
        let before = Set(try FileManager.default.contentsOfDirectory(atPath: root.path))
        let listing = ArchivePreviewReader.read(url)
        XCTAssertEqual(listing.status, .complete)
        XCTAssertEqual(listing.entries.first { $0.path == "symbolic" }?.kind, .symbolicLink)
        XCTAssertEqual(listing.entries.first { $0.path == "hard" }?.kind, .hardLink)
        XCTAssertEqual(listing.entries.first { $0.path == "named-pipe" }?.kind, .special)
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: root.path)), before)
        XCTAssertEqual(try String(contentsOf: marker, encoding: .utf8), "untouched")
    }

    func testDisplayCountIsHardCappedAtFiveHundredAndMarkedIncomplete() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try archive(.zip, members: (0..<600).map { Member(name: "file-\($0).txt") }, in: root)
        var limits = ArchivePreviewLimits()
        limits.maxEntries = 900
        let listing = ArchivePreviewReader.read(url, limits: limits)
        XCTAssertEqual(listing.entries.count, 500)
        XCTAssertEqual(listing.status, .limited(.entries))
        XCTAssertTrue(listing.status.message(visibleCount: 500).contains("可能不完整"))
    }

    func testLargeFirstMemberStopsBeforePayloadDrainOrFollowingHeader() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try archive(.zip, members: [Member(name: "large.bin", data: Data(repeating: 0x61, count: 1024 * 1024)), Member(name: "must-not-skip.txt", data: Data("later".utf8))], in: root)
        var limits = ArchivePreviewLimits()
        limits.maxMemberBytes = 1024
        let listing = ArchivePreviewReader.read(url, limits: limits)
        XCTAssertEqual(listing.status, .limited(.memberSize))
        XCTAssertEqual(listing.entries.map(\.path), ["large.bin"])
        XCTAssertEqual(listing.decodedBytes, 0)
    }

    func testDecodedByteBudgetStopsWithoutImplicitlySkippingTheNextPayload() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try archive(.tar, members: [Member(name: "first.bin", data: Data(repeating: 1, count: 3072)), Member(name: "second.bin", data: Data(repeating: 2, count: 3072)), Member(name: "third.txt")], in: root)
        var limits = ArchivePreviewLimits()
        limits.maxDecodedBytes = 4096
        let listing = ArchivePreviewReader.read(url, limits: limits)
        XCTAssertEqual(listing.status, .limited(.decodedData))
        XCTAssertEqual(listing.entries.map(\.path), ["first.bin", "second.bin"])
        XCTAssertEqual(listing.decodedBytes, 3072)
        XCTAssertLessThanOrEqual(listing.decodedBytes, limits.maxDecodedBytes)
    }

    func testOriginalFileAndActualSourceReadBudgetsAreEnforced() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try archive(.tar, members: [Member(name: "data.bin", data: Data(repeating: 0x42, count: 128 * 1024))], in: root)
        var limits = ArchivePreviewLimits()
        limits.maxFileBytes = 100
        let tooLarge = ArchivePreviewReader.read(url, limits: limits)
        XCTAssertEqual(tooLarge.status, .limited(.sourceFile))
        XCTAssertEqual(tooLarge.sourceBytesRead, 0)
        limits.maxFileBytes = 128 * 1024 * 1024
        limits.maxSourceReadBytes = 2048
        let bounded = ArchivePreviewReader.read(url, limits: limits)
        XCTAssertEqual(bounded.status, .limited(.sourceReads))
        XCTAssertLessThanOrEqual(bounded.sourceBytesRead, 2048)
    }

    func testStreamingZIPWithUnknownSizeStopsWithoutSkippingItsData() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try archive(.zip, members: [Member(name: "unknown.bin", data: Data(repeating: 0x5a, count: 4096))], in: root)
        var bytes = try Data(contentsOf: url)
        let central = try XCTUnwrap(bytes.range(of: Data([0x50, 0x4b, 0x01, 0x02])))
        bytes = bytes.prefix(central.lowerBound)
        bytes[6] |= 1 << 3
        bytes.replaceSubrange(18..<26, with: repeatElement(UInt8(0), count: 8))
        try bytes.write(to: url)
        let listing = ArchivePreviewReader.read(url)
        XCTAssertEqual(listing.status, .limited(.unknownSize))
        XCTAssertEqual(listing.decodedBytes, 0)
        XCTAssertLessThanOrEqual(listing.entries.count, 1)
    }

    func testCancellationBeforeIOAndDuringListingReleasesTheInput() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try archive(.tar, members: (0..<100).map { Member(name: "item-\($0)", data: Data(repeating: 0x41, count: 256)) }, in: root)
        let gate = ArchiveReadTestGate()
        let task = Task.detached {
            await gate.wait()
            return ArchivePreviewReader.read(url)
        }
        task.cancel()
        await gate.release()
        let cancelled = await task.value
        XCTAssertEqual(cancelled.status, .cancelled)
        XCTAssertEqual(cancelled.sourceBytesRead, 0)
        let signal = CancellationAfterChecks(limit: 40)
        let running = await Task.detached { ArchivePreviewReader.read(url, isCancelled: { signal.check() }) }.value
        XCTAssertEqual(running.status, .cancelled)
        XCTAssertLessThan(running.entries.count, 100)
        XCTAssertLessThanOrEqual(running.decodedBytes, ArchivePreviewLimits().maxDecodedBytes)
        let again = ArchivePreviewReader.read(url)
        XCTAssertEqual(again.status, .complete)
        XCTAssertEqual(again.entries.count, 100)
    }

    func testUnsupportedInputAndSourceLinksReturnSafeStatuses() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let invalid = root.appendingPathComponent("invalid.zip")
        try Data("private-looking fixture data must never become an error message".utf8).write(to: invalid)
        let listing = ArchivePreviewReader.read(invalid)
        XCTAssertNotEqual(listing.status, .complete)
        XCTAssertTrue(listing.entries.isEmpty)
        XCTAssertFalse(listing.status.message(visibleCount: 0).contains("private-looking"))
        let linked = root.appendingPathComponent("linked.zip")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: invalid)
        XCTAssertEqual(ArchivePreviewReader.read(linked).status, .unreadable)
    }

    func testMainAppURLRoundTripsThroughTheExistingFinderProtocol() throws {
        let file = URL(fileURLWithPath: "/tmp/公开 样本/#notes & details.zip")
        let url = try XCTUnwrap(ArchivePreviewReader.mainAppURL(for: file))
        let decoded = try FinderActionRequest(url: url)
        XCTAssertEqual(decoded.action, .browseArchive)
        XCTAssertEqual(decoded.files, [file.standardizedFileURL])
        XCTAssertEqual(url, try FinderActionRequest(action: .browseArchive, files: [file]).url)
        XCTAssertNil(ArchivePreviewReader.mainAppURL(for: URL(string: "https://example.com/archive.zip")!))
        XCTAssertNil(ArchivePreviewReader.mainAppURL(for: URL(string: "file:///tmp/a%00b.zip")!))
    }
}

private actor ArchiveReadTestGate {
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        if released { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

private final class CancellationAfterChecks: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private let limit: Int
    init(limit: Int) { self.limit = limit }
    func check() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count >= limit
    }
}
