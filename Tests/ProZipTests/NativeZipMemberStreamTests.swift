import Foundation
import XCTest
import ProZipShared
import ProZipCore
@testable import ProZipEngines

final class NativeZipMemberStreamTests: XCTestCase {
    private let engine = NativeZipEngine()

    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("prozip-native-stream-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func fixture(_ content: Data, in root: URL, method: UInt16 = 8, crc: UInt32? = nil, password: String? = nil, descriptor: Bool = false, payloadCut: Int = 0, declaredSize: Int64? = nil, type: EntryType = .file) throws -> (url: URL, entry: ArchiveEntry, payloadOffset: Int) {
        let name = type == .directory ? "directory/" : "member.bin"
        let filename = Data(name.utf8)
        let checksum = crc ?? engine.computeCRC32(for: content)
        let size = declaredSize ?? Int64(content.count)
        let time: UInt16 = 0x4b3a
        var flags: UInt16 = 1 << 11
        if descriptor { flags |= 1 << 3 }
        var payload = method == 8 ? try NativeZipEngine.deflateRaw(data: content, level: 6) : content
        if payloadCut > 0 { payload.removeLast(min(payloadCut, payload.count)) }
        if let password {
            flags |= 1
            var cipher = ZipCryptoCipher(password: password)
            var header = Data((0..<11).map(UInt8.init))
            header.append(descriptor ? UInt8(time >> 8) : UInt8(checksum >> 24))
            payload = cipher.encryptData(header) + cipher.encryptData(payload)
        }
        var data = Data()
        data.appendStreamZIP(UInt32(0x04034b50))
        data.appendStreamZIP(UInt16(20))
        data.appendStreamZIP(flags)
        data.appendStreamZIP(method)
        data.appendStreamZIP(time)
        data.appendStreamZIP(UInt16(0x546b))
        data.appendStreamZIP(descriptor ? UInt32(0) : checksum)
        data.appendStreamZIP(descriptor ? UInt32(0) : UInt32(payload.count))
        data.appendStreamZIP(descriptor ? UInt32(0) : UInt32(size))
        data.appendStreamZIP(UInt16(filename.count))
        data.appendStreamZIP(UInt16(0))
        data.append(filename)
        let payloadOffset = data.count
        data.append(payload)
        if descriptor {
            data.appendStreamZIP(UInt32(0x08074b50))
            data.appendStreamZIP(checksum)
            data.appendStreamZIP(UInt32(payload.count))
            data.appendStreamZIP(UInt32(size))
        }
        let centralOffset = data.count
        data.appendStreamZIP(UInt32(0x02014b50))
        data.appendStreamZIP(UInt16(0x0314))
        data.appendStreamZIP(UInt16(20))
        data.appendStreamZIP(flags)
        data.appendStreamZIP(method)
        data.appendStreamZIP(time)
        data.appendStreamZIP(UInt16(0x546b))
        data.appendStreamZIP(checksum)
        data.appendStreamZIP(UInt32(payload.count))
        data.appendStreamZIP(UInt32(size))
        data.appendStreamZIP(UInt16(filename.count))
        for _ in 0..<4 { data.appendStreamZIP(UInt16(0)) }
        let mode: UInt32 = type == .directory ? 0o040755 : type == .symlink ? 0o120777 : 0o100640
        data.appendStreamZIP(mode << 16)
        data.appendStreamZIP(UInt32(0))
        data.append(filename)
        let centralSize = data.count - centralOffset
        data.appendStreamZIP(UInt32(0x06054b50))
        data.appendStreamZIP(UInt16(0))
        data.appendStreamZIP(UInt16(0))
        data.appendStreamZIP(UInt16(1))
        data.appendStreamZIP(UInt16(1))
        data.appendStreamZIP(UInt32(centralSize))
        data.appendStreamZIP(UInt32(centralOffset))
        data.appendStreamZIP(UInt16(0))
        let url = root.appendingPathComponent("fixture-\(UUID().uuidString).zip")
        try data.write(to: url)
        let entry = ArchiveEntry(path: name, type: type, uncompressedSize: size, compressedSize: Int64(payload.count), permissions: UInt16(mode & 0o7777), crc32: checksum, isEncrypted: password != nil)
        return (url, entry, payloadOffset)
    }

    private func read(_ entry: ArchiveEntry, from url: URL, password: String? = nil, range: Range<Int64>? = nil) async throws -> Data {
        var data = Data()
        for try await chunk in try await engine.openMember(entry, in: url, password: password, range: range) {
            XCTAssertLessThanOrEqual(chunk.count, 65_536)
            data.append(chunk)
        }
        return data
    }

    private func waitForActiveReads(_ count: Int) async throws {
        for _ in 0..<200 {
            if await MemberReadBudgetLimiter.shared.currentActiveReads == count { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        let actual = await MemberReadBudgetLimiter.shared.currentActiveReads
        XCTAssertEqual(actual, count)
    }

    private func assertCorrupted(_ archive: (url: URL, entry: ArchiveEntry, payloadOffset: Int), range: Range<Int64>? = nil) async throws {
        do {
            _ = try await read(archive.entry, from: archive.url, range: range)
            XCTFail("A complete read must reject invalid ZIP data")
        } catch let error as ProZipError {
            guard case .corruptedArchive = error else { return XCTFail("Expected corruptedArchive, got \(error)") }
        }
    }

    func testPrefixDoesNotReadOrVerifyAnUnrequestedSuffix() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let content = Data(repeating: 0x6b, count: 8 * 1024 * 1024)
        let archive = try fixture(content, in: root, crc: engine.computeCRC32(for: content) ^ 1)
        let prefix = try await read(archive.entry, from: archive.url, range: 0..<4096)
        XCTAssertEqual(prefix, content.prefix(4096))
    }

    func testPausedConsumerDoesNotHaveTheEntireMemberQueued() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = try fixture(Data(repeating: 0x54, count: 2 * 1024 * 1024), in: root, method: 0)
        let stream = try await engine.openMember(archive.entry, in: archive.url, password: nil, range: nil)
        var iterator = stream.makeAsyncIterator()
        let chunk = try await iterator.next()
        let first = try XCTUnwrap(chunk)
        XCTAssertEqual(first, Data(repeating: 0x54, count: 65_536))
        let writer = try FileHandle(forWritingTo: archive.url)
        try writer.truncate(atOffset: UInt64(archive.payloadOffset + first.count))
        try writer.close()
        do {
            while try await iterator.next() != nil {}
            XCTFail("A pull reader must observe truncation after the first chunk, rather than drain a preloaded member")
        } catch let error as ProZipError {
            guard case .corruptedArchive = error else { return XCTFail("Expected truncated member data") }
        }
    }

    func testFourKiBPrefixOfALargeCompressedMemberDoesNotInflateTheBrokenTail() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let content = Data(repeating: 0x61, count: 128 * 1024 * 1024)
        let archive = try fixture(content, in: root, payloadCut: 2)
        XCTAssertLessThan(archive.entry.compressedSize, archive.entry.uncompressedSize / 100)
        let prefix = try await read(archive.entry, from: archive.url, range: 0..<4096)
        XCTAssertEqual(prefix, Data(repeating: 0x61, count: 4096))
        try await waitForActiveReads(0)
    }

    func testCompleteStoredDeflateAndZipCryptoDescriptorMembersRoundTrip() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        var seed: UInt64 = 0x7265616c2d7a6970
        let content = Data((0..<260_123).map { _ -> UInt8 in
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return UInt8(truncatingIfNeeded: seed >> 32)
        })
        for method: UInt16 in [0, 8] {
            for password: String? in [nil, "stream-fixture-password"] {
                for descriptor in [false, true] {
                    let archive = try fixture(content, in: root, method: method, password: password, descriptor: descriptor)
                    let actual = try await read(archive.entry, from: archive.url, password: password)
                    XCTAssertEqual(actual, content)
                    let range = try await read(archive.entry, from: archive.url, password: password, range: 65_530..<65_550)
                    XCTAssertEqual(range, content.subdata(in: 65_530..<65_550))
                }
            }
        }
        try await waitForActiveReads(0)
    }

    func testNativeWriterArchiveRoundTripsThroughThePullReader() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.txt")
        let content = Data(repeating: 0x72, count: 131_081)
        try content.write(to: source)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: source.path)
        let url = root.appendingPathComponent("written.zip")
        let password = "native-writer-fixture"
        try await engine.create(sources: [source], at: url, profile: CreationProfile(format: .zip, password: password), password: password, progress: { _ in })
        let entries = try await engine.list(url, password: password, progress: { _ in })
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.permissions, 0o640)
        XCTAssertTrue(entry.isEncrypted)
        let full = try await read(entry, from: url, password: password)
        XCTAssertEqual(full, content)
        let prefix = try await read(entry, from: url, password: password, range: 0..<4096)
        XCTAssertEqual(prefix, content.prefix(4096))
        XCTAssertEqual(try Data(contentsOf: source), content)
        try await waitForActiveReads(0)
    }

    func testRangesClampWithoutOverflowAndEmptyRangesNeverReadThePayload() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let content = Data(repeating: 0x39, count: 131_081)
        for method: UInt16 in [0, 8] {
            let archive = try fixture(content, in: root, method: method)
            let negative = try await read(archive.entry, from: archive.url, range: -30..<9)
            XCTAssertEqual(negative, content.prefix(9))
            let suffix = try await read(archive.entry, from: archive.url, range: Int64(content.count - 7)..<Int64.max)
            XCTAssertEqual(suffix, content.suffix(7))
            let all = try await read(archive.entry, from: archive.url, range: Int64.min..<Int64.max)
            XCTAssertEqual(all, content)
        }
        let broken = try fixture(content, in: root, payloadCut: 2)
        for range in [0..<0, 20..<20, (Int64.max - 1)..<Int64.max, Int64.min..<(-1)] as [Range<Int64>] {
            let empty = try await read(broken.entry, from: broken.url, range: range)
            XCTAssertTrue(empty.isEmpty)
        }
        try await waitForActiveReads(0)
    }

    func testWholeMemberReadsValidateCRCZeroLengthAndTruncatedDeflate() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let content = Data(repeating: 0x73, count: 131_081)
        let checksum = engine.computeCRC32(for: content)
        for method: UInt16 in [0, 8] {
            let badCRC = try fixture(content, in: root, method: method, crc: checksum ^ 1)
            try await assertCorrupted(badCRC)
            try await assertCorrupted(badCRC, range: 0..<Int64.max)
            try await assertCorrupted(try fixture(content, in: root, method: method, crc: 0))
            try await assertCorrupted(try fixture(content, in: root, method: method, declaredSize: Int64(content.count - 1)))
            try await assertCorrupted(try fixture(content, in: root, method: method, declaredSize: Int64(content.count + 1)))
        }
        try await assertCorrupted(try fixture(content, in: root, payloadCut: 2))
        try await waitForActiveReads(0)
    }

    func testWrongPasswordsAndMissingFilesReleaseOnlyTheirOwnReadLease() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let content = Data(repeating: 0x45, count: 131_081)
        let plain = try fixture(content, in: root)
        var held: [AsyncThrowingStream<Data, Error>] = [try await engine.openMember(plain.entry, in: plain.url, password: nil, range: nil)]
        for descriptor in [false, true] {
            let encrypted = try fixture(content, in: root, password: "fixture-password", descriptor: descriptor)
            do {
                _ = try await read(encrypted.entry, from: encrypted.url, range: 0..<4096)
                XCTFail("Encrypted entries require a password")
            } catch let error as ProZipError {
                guard case .passwordRequired = error else { return XCTFail("Expected passwordRequired") }
            }
            do {
                _ = try await read(encrypted.entry, from: encrypted.url, password: "wrong-fixture-password", range: 0..<4096)
                XCTFail("Incorrect passwords must fail")
            } catch let error as ProZipError {
                guard case .wrongPassword = error else { return XCTFail("Expected wrongPassword, got \(error)") }
            }
        }
        do {
            _ = try await engine.openMember(plain.entry, in: root.appendingPathComponent("missing.zip"), password: nil, range: nil)
            XCTFail("A missing source must not produce a successful stream")
        } catch {}
        try await waitForActiveReads(1)
        XCTAssertEqual(held.count, 1)
        held.removeAll()
        try await waitForActiveReads(0)
    }

    func testCancellationClosesTheReaderEvenWhileTheStreamIsRetained() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = try fixture(Data(repeating: 0x58, count: 2 * 1024 * 1024), in: root, method: 0)
        let stream = try await engine.openMember(archive.entry, in: archive.url, password: nil, range: nil)
        let task = Task { () throws -> Bool in
            var iterator = stream.makeAsyncIterator()
            guard try await iterator.next()?.count == 65_536 else { return false }
            withUnsafeCurrentTask { $0?.cancel() }
            do { return try await iterator.next() == nil }
            catch is CancellationError { return true }
        }
        let cancelled = try await task.value
        XCTAssertTrue(cancelled)
        try await waitForActiveReads(0)
        _ = stream
    }

    func testUnconsumedStreamsReserveBudgetAndReleaseItWhenDropped() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = try fixture(Data(repeating: 0x23, count: 65_537), in: root)
        var streams: [AsyncThrowingStream<Data, Error>] = []
        let capacity = await MemberReadBudgetLimiter.shared.maxConcurrentReads
        for _ in 0..<capacity { streams.append(try await engine.openMember(archive.entry, in: archive.url, password: nil, range: nil)) }
        try await waitForActiveReads(capacity)
        do {
            _ = try await engine.openMember(archive.entry, in: archive.url, password: nil, range: nil)
            XCTFail("Idle streams still own an active read lease")
        } catch let error as ProZipError {
            XCTAssertEqual(error, .tooManyActiveMemberReads)
        }
        streams.removeLast()
        try await waitForActiveReads(capacity - 1)
        streams.append(try await engine.openMember(archive.entry, in: archive.url, password: nil, range: nil))
        try await waitForActiveReads(capacity)
        streams.removeAll()
        try await waitForActiveReads(0)
    }

    func testDirectorySymlinkPermissionsAndEmptyMembersRetainTheirSemantics() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        for method: UInt16 in [0, 8] {
            let empty = try fixture(Data(), in: root, method: method)
            let actual = try await read(empty.entry, from: empty.url)
            XCTAssertTrue(actual.isEmpty)
        }
        let directory = try fixture(Data(), in: root, method: 0, type: .directory)
        let directories = try await engine.list(directory.url, password: nil, progress: { _ in })
        XCTAssertEqual(directories.first?.type, .directory)
        XCTAssertEqual(directories.first?.permissions, 0o755)
        let emptyDirectory = try await read(directory.entry, from: directory.url)
        XCTAssertTrue(emptyDirectory.isEmpty)
        let target = Data("target/file.txt".utf8)
        let link = try fixture(target, in: root, method: 0, type: .symlink)
        let links = try await engine.list(link.url, password: nil, progress: { _ in })
        XCTAssertEqual(links.first?.type, .symlink)
        XCTAssertEqual(links.first?.permissions, 0o777)
        XCTAssertEqual(links.first?.symlinkTarget, "target/file.txt")
        let linkBytes = try await read(link.entry, from: link.url)
        XCTAssertEqual(linkBytes, target)
        try await waitForActiveReads(0)
    }

    func testCentralDirectoryCannotBypassTheMemberBudgetWithASmallCallerSize() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = try fixture(Data(repeating: 0x42, count: 1024), in: root, declaredSize: ProcessCancellationController.maxBinaryOutputBytes + 1)
        let misleading = ArchiveEntry(path: archive.entry.path, type: .file, uncompressedSize: 1)
        do {
            _ = try await read(misleading, from: archive.url, range: 0..<1)
            XCTFail("The central directory's actual member size must still pass the budget check")
        } catch let error as ProZipError {
            guard case .outputExceedsBudget = error else { return XCTFail("Expected outputExceedsBudget") }
        }
        try await waitForActiveReads(0)
    }
}

private extension Data {
    mutating func appendStreamZIP<T: FixedWidthInteger>(_ number: T) {
        var number = number.littleEndian
        Swift.withUnsafeBytes(of: &number) { append(contentsOf: $0) }
    }
}
