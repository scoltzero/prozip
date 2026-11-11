import Foundation
import XCTest
import ProZipShared
@testable import ProZipCore
import ProZipEngines

@MainActor
final class SplitStagingTests: XCTestCase {
    private func fixture(_ bytes: Data) throws -> (URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("prozip-split-stream-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let archive = root.appendingPathComponent("archive.zip")
        try bytes.write(to: archive)
        return (root, archive)
    }

    private func join(_ parts: [URL]) throws -> Data {
        try parts.reduce(into: Data()) { result, part in result.append(try Data(contentsOf: part)) }
    }

    func testSevenEqualPartsStreamAtMost64KiBAndDoNotOverwriteTheFullArchive() throws {
        let original = Data((0..<1_000_003).map { UInt8($0 & 255) })
        let (root, archive) = try fixture(original)
        defer { try? FileManager.default.removeItem(at: root) }
        var maximumRead = 0
        let parts = try SplitArchivePublication.stageParts(archiveURL: archive, outputBaseURL: archive, plan: .byCount(7), read: { handle, count in
            maximumRead = max(maximumRead, count)
            return try handle.read(upToCount: count)
        })
        XCTAssertEqual(parts.count, 7)
        XCTAssertEqual(parts.map(\.lastPathComponent), (1...7).map { String(format: "archive.zip.%03d", $0) })
        let sizes = try parts.map { try Data(contentsOf: $0).count }
        XCTAssertGreaterThan(try XCTUnwrap(sizes.min()), 0)
        XCTAssertLessThanOrEqual(try XCTUnwrap(sizes.max()) - XCTUnwrap(sizes.min()), 1)
        XCTAssertEqual(maximumRead, 64 * 1024)
        XCTAssertNotEqual(parts[0].deletingLastPathComponent(), root)
        XCTAssertEqual(try join(parts), original)
        XCTAssertEqual(try Data(contentsOf: archive), original)
    }

    func testSizeLimitExactBoundaryRemainderAndHugeLimit() throws {
        for size in [2048, 2049] {
            let original = Data(repeating: 42, count: size)
            let (root, archive) = try fixture(original)
            defer { try? FileManager.default.removeItem(at: root) }
            let parts = try SplitArchivePublication.stageParts(archiveURL: archive, outputBaseURL: archive, plan: .bySize(1024))
            let lengths = try parts.map { try Data(contentsOf: $0).count }
            XCTAssertEqual(lengths, size == 2048 ? [1024, 1024] : [1024, 1024, 1])
            XCTAssertEqual(try join(parts), original)
            let one = try SplitArchivePublication.stageParts(archiveURL: archive, outputBaseURL: archive, plan: .bySize(Int64.max))
            XCTAssertEqual(one.count, 1)
            XCTAssertEqual(try join(one), original)
        }
    }

    func testInvalidCountsInsufficientBytesAndTooManySizeVolumesCreateNoParts() throws {
        let (root, archive) = try fixture(Data([1, 2]))
        defer { try? FileManager.default.removeItem(at: root) }
        let plans: [CreationProfile.SplitPlan] = [.byCount(1), .byCount(1000), .byCount(3), .bySize(1023)]
        for plan in plans {
            XCTAssertThrowsError(try SplitArchivePublication.stageParts(archiveURL: archive, outputBaseURL: archive, plan: plan))
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [archive.lastPathComponent])
        }
        let minimum = try SplitArchivePublication.stageParts(archiveURL: archive, outputBaseURL: archive, plan: .byCount(2))
        XCTAssertEqual(try minimum.map { try Data(contentsOf: $0).count }, [1, 1])
        try FileManager.default.removeItem(at: minimum[0].deletingLastPathComponent())
        let writer = try FileHandle(forWritingTo: archive)
        try writer.truncate(atOffset: 999 * 1024 + 1)
        try writer.close()
        XCTAssertThrowsError(try SplitArchivePublication.stageParts(archiveURL: archive, outputBaseURL: archive, plan: .bySize(1024)))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [archive.lastPathComponent])
    }

    func testShortReadRemovesAllPrivateParts() throws {
        let (root, archive) = try fixture(Data(repeating: 42, count: 200_003))
        defer { try? FileManager.default.removeItem(at: root) }
        var reads = 0
        XCTAssertThrowsError(try SplitArchivePublication.stageParts(archiveURL: archive, outputBaseURL: archive, plan: .byCount(7), read: { handle, count in
            reads += 1
            return reads == 1 ? try handle.read(upToCount: count) : nil
        }))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [archive.lastPathComponent])
    }

    func testSourceGrowthTruncationAndReplacementRemoveAllPrivateParts() throws {
        for change in ["grow", "truncate", "replace"] {
            let original = Data(repeating: 42, count: 200_003)
            let (root, archive) = try fixture(original)
            defer { try? FileManager.default.removeItem(at: root) }
            var changed = false
            XCTAssertThrowsError(try SplitArchivePublication.stageParts(archiveURL: archive, outputBaseURL: archive, plan: .byCount(7), read: { handle, count in
                let data = try handle.read(upToCount: count)
                if !changed {
                    changed = true
                    if change == "replace" {
                        try FileManager.default.removeItem(at: archive)
                        try original.write(to: archive)
                    } else {
                        let writer = try FileHandle(forWritingTo: archive)
                        defer { try? writer.close() }
                        if change == "truncate" { try writer.truncate(atOffset: 10) }
                        else { try writer.seekToEnd(); try writer.write(contentsOf: Data([1])) }
                    }
                }
                return data
            }))
            XCTAssertTrue(changed)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [archive.lastPathComponent])
        }
    }

    func testSmallAndLargeCompressibleNativeArchivesHaveExactlySevenReadableParts() async throws {
        guard SevenZipEngine.resolveBinaryURL() != nil else { throw XCTSkip("7-Zip unavailable") }
        for size in [32, 4 * 1024 * 1024] {
            let payload = Data(repeating: 65, count: size)
            let (root, source) = try fixture(payload)
            defer { try? FileManager.default.removeItem(at: root) }
            let base = root.appendingPathComponent("compressed.zip")
            try await NativeZipEngine().create(sources: [source], at: base, profile: CreationProfile(format: .zip, strength: .maximum, split: .byCount(7)), password: nil, progress: { _ in })
            let first = try SplitArchivePublication.publishedFirstPart(baseURL: base)
            let parts = SplitVolumeFamily.resolve(for: first).volumeURLs
            XCTAssertEqual(parts.count, 7)
            let sizes = try parts.map { try Data(contentsOf: $0).count }
            XCTAssertTrue(sizes.allSatisfy { $0 > 0 })
            XCTAssertLessThanOrEqual(try XCTUnwrap(sizes.max()) - XCTUnwrap(sizes.min()), 1)
            let rejoined = root.appendingPathComponent("rejoined.zip")
            try join(parts).write(to: rejoined)
            let nativeEntries = try await NativeZipEngine().list(rejoined, password: nil, progress: { _ in })
            XCTAssertEqual(nativeEntries.map(\.path), [source.lastPathComponent])
            let sevenZipEntries = try await SevenZipEngine().list(first, password: nil, progress: { _ in })
            XCTAssertEqual(sevenZipEntries.map(\.path), [source.lastPathComponent])
            XCTAssertEqual(sevenZipEntries.first?.uncompressedSize, Int64(size))
        }
    }
}
