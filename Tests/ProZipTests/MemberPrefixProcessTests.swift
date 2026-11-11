import Foundation
import XCTest
import ProZipShared
@testable import ProZipEngines

final class MemberPrefixProcessTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("prozip-prefix-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func runPython(_ script: String, to file: URL, prefix: Int64? = nil, budget: Int64 = 512 * 1024 * 1024) async throws -> ProcessCancellationController.ProcessResult {
        guard FileManager.default.createFile(atPath: file.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        let output = try FileHandle(forWritingTo: file)
        defer { try? output.close() }
        let operation = Task {
            try await ProcessCancellationController.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/python3"), arguments: ["-c", script],
                stdoutFile: output, stdoutByteLimit: budget, stdoutPrefixLimit: prefix
            )
        }
        let timeout = Task {
            try await Task.sleep(for: .seconds(3))
            operation.cancel()
        }
        defer { timeout.cancel() }
        return try await operation.value
    }

    func testPrefixStopsAnUnfinishedProducerAndWritesOnlyRequestedBytes() async throws {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("prefix")
        let result = try await runPython("import os,time; os.write(1,b'p'*131072); time.sleep(30)", to: file, prefix: 4096, budget: 8192)
        XCTAssertTrue(result.reachedPrefixLimit)
        XCTAssertNotEqual(result.exitCode, 0, "A prefix must not pretend the terminated producer completed normally")
        XCTAssertEqual(try Data(contentsOf: file), Data(repeating: 112, count: 4096))
        XCTAssertTrue(result.stdout.isEmpty)
    }

    func testFailureBeforePrefixRemainsAFailure() async throws {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("short")
        let result = try await runPython("import os,sys; os.write(1,b'short'); sys.exit(7)", to: file, prefix: 4096)
        XCTAssertFalse(result.reachedPrefixLimit)
        XCTAssertEqual(result.exitCode, 7)
        XCTAssertEqual(try Data(contentsOf: file), Data("short".utf8))
    }

    func testCompleteOutputKeepsExitAndBudgetSemantics() async throws {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("complete")
        let result = try await runPython("import os; os.write(1,b'bytes'*20000)", to: file)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertFalse(result.reachedPrefixLimit)
        XCTAssertEqual(try Data(contentsOf: file).count, 100_000)
        do {
            _ = try await runPython("import os,time; os.write(1,b'x'*131072); time.sleep(30)", to: directory.appendingPathComponent("over-budget"), budget: 1024)
            XCTFail("Full output must retain its hard budget")
        } catch let error as ProZipError {
            guard case .outputExceedsBudget = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testPrefixCannotBypassAHarderBinaryBudget() async throws {
        let directory = try temporaryDirectory()
        do {
            _ = try await runPython("import os; os.write(1,b'x'*131072)", to: directory.appendingPathComponent("limited"), prefix: 4096, budget: 1024)
            XCTFail("The output budget must take precedence")
        } catch let error as ProZipError {
            guard case .outputExceedsBudget = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testGzipPrefixDoesNotRequireReadingTheCorruptUnrequestedSuffix() async throws {
        let directory = try temporaryDirectory()
        let source = directory.appendingPathComponent("payload")
        let bytes = Data(repeating: 65, count: 8 * 1024 * 1024)
        try bytes.write(to: source)
        let gzip = directory.appendingPathComponent("payload.gz")
        XCTAssertTrue(FileManager.default.createFile(atPath: gzip.path, contents: nil))
        let output = try FileHandle(forWritingTo: gzip)
        let compressed = try await ProcessCancellationController.run(executableURL: URL(fileURLWithPath: "/usr/bin/gzip"), arguments: ["-c", "--", source.path], stdoutFile: output)
        try output.close()
        XCTAssertEqual(compressed.exitCode, 0)
        var damaged = try Data(contentsOf: gzip)
        damaged.removeLast(8)
        try damaged.write(to: gzip)
        let entry = ArchiveEntry(path: "payload", type: .file, uncompressedSize: Int64(bytes.count))
        let engine = LibarchiveEngine()
        let stream = try await engine.openMember(entry, in: gzip, password: nil, range: 0..<4096)
        var prefix = Data()
        for try await chunk in stream { prefix.append(chunk) }
        XCTAssertEqual(prefix, bytes.prefix(4096))
        let fullRanges: [Range<Int64>?] = [nil, 0..<Int64(bytes.count)]
        for range in fullRanges {
            do {
                let full = try await engine.openMember(entry, in: gzip, password: nil, range: range)
                for try await _ in full {}
                XCTFail("Full reads must still reject the missing gzip trailer")
            } catch let error as ProZipError {
                guard case .corruptedArchive = error else { return XCTFail("Unexpected error: \(error)") }
            }
        }
    }

    func testEmptyRangeDoesNotStartAWriterOrConsumeABudgetSlot() async throws {
        let stream = try await streamMemberOutput(expectedSize: .max, range: 4..<4) { _ in
            XCTFail("An empty range must not start decompression")
        }
        var count = 0
        for try await _ in stream { count += 1 }
        XCTAssertEqual(count, 0)
    }
}
