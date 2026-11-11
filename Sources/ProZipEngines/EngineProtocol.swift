import Foundation
import ProZipShared

// MARK: - Engine Capabilities & Protocol (doc/11 section 3 & doc/03)

public struct EngineCapabilities: Sendable, Equatable {
    public var read: Set<ArchiveFormat>
    public var write: Set<ArchiveFormat>
    public var edit: Set<ArchiveFormat>
    public var encryptedRead: Bool
    public var encryptedWrite: Bool
    public var headerEncryption: Bool
    public var split: Bool
    public var streamingMemberRead: Bool

    public init(
        read: Set<ArchiveFormat>,
        write: Set<ArchiveFormat> = [],
        edit: Set<ArchiveFormat> = [],
        encryptedRead: Bool = false,
        encryptedWrite: Bool = false,
        headerEncryption: Bool = false,
        split: Bool = false,
        streamingMemberRead: Bool = false
    ) {
        self.read = read
        self.write = write
        self.edit = edit
        self.encryptedRead = encryptedRead
        self.encryptedWrite = encryptedWrite
        self.headerEncryption = headerEncryption
        self.split = split
        self.streamingMemberRead = streamingMemberRead
    }
}

public protocol ArchiveEngine: Sendable {
    static var capabilities: EngineCapabilities { get }
    var engineName: String { get }

    func probe(_ url: URL) async throws -> ArchiveDescriptor
    func list(
        _ url: URL,
        password: String?,
        progress: @escaping ProgressSink
    ) async throws -> [ArchiveEntry]

    func openMember(
        _ entry: ArchiveEntry,
        in url: URL,
        password: String?,
        range: Range<Int64>?
    ) async throws -> AsyncThrowingStream<Data, Error>

    func extract(
        _ entries: [ArchiveEntry],
        from url: URL,
        to dir: URL,
        password: String?,
        options: ExtractionOptions,
        progress: @escaping ProgressSink
    ) async throws -> ExtractionReport

    func create(
        sources: [URL],
        at url: URL,
        profile: CreationProfile,
        password: String?,
        progress: @escaping ProgressSink
    ) async throws

    func applyMutations(
        _ mutations: [ArchiveMutation],
        to sourceURL: URL,
        outputURL: URL,
        profile: CreationProfile,
        password: String?,
        progress: @escaping ProgressSink
    ) async throws
}

public extension ArchiveEngine {
    func applyMutations(
        _ mutations: [ArchiveMutation],
        to sourceURL: URL,
        outputURL: URL,
        profile: CreationProfile,
        password: String?,
        progress: @escaping ProgressSink
    ) async throws {
        throw ProZipError.editingNotSupported("\(engineName) 不支持原位增量修改")
    }
}

private actor TemporaryMemberReader {
    private let directory: URL
    private let input: FileHandle
    private var remaining: Int64
    private var isClosed = false

    init(directory: URL, file: URL, range: Range<Int64>?) throws {
        self.directory = directory
        input = try FileHandle(forReadingFrom: file)
        let start = max(0, range?.lowerBound ?? 0)
        try input.seek(toOffset: UInt64(start))
        remaining = range.map { max(0, $0.upperBound - start) } ?? Int64.max
    }

    deinit {
        if !isClosed {
            try? input.close()
            try? FileManager.default.removeItem(at: directory)
            Task { await MemberReadBudgetLimiter.shared.release() }
        }
    }

    func next() async throws -> Data? {
        guard !isClosed else { return nil }
        do {
            try Task.checkCancellation()
            guard remaining > 0,
                  let chunk = try input.read(upToCount: Int(min(65_536, remaining))), !chunk.isEmpty else {
                await close()
                return nil
            }
            remaining -= Int64(chunk.count)
            return chunk
        } catch {
            await close()
            throw error
        }
    }

    func close() async {
        guard !isClosed else { return }
        isClosed = true
        try? input.close()
        try? FileManager.default.removeItem(at: directory)
        await MemberReadBudgetLimiter.shared.release()
    }
}

func memberOutputPrefixLimit(expectedSize: Int64, range: Range<Int64>?) -> Int64? {
    guard let range, expectedSize <= 0 || range.upperBound < expectedSize else { return nil }
    return max(0, range.upperBound)
}

/// File-backed unfolding reads keep binary payloads out of the diagnostic buffer and stream queue.
func streamMemberOutput(
    expectedSize: Int64,
    range: Range<Int64>?,
    writer: @escaping @Sendable (FileHandle) async throws -> Void
) async throws -> AsyncThrowingStream<Data, Error> {
    if let range, range.upperBound <= max(0, range.lowerBound) {
        return AsyncThrowingStream(unfolding: { nil })
    }
    let budget = range.map { max(0, min(expectedSize, $0.upperBound)) } ?? expectedSize
    try await MemberReadBudgetLimiter.shared.acquire(requestedBytes: budget)
    let fm = FileManager.default
    let directory = fm.temporaryDirectory.appendingPathComponent("prozip-member-\(UUID().uuidString)", isDirectory: true)
    do {
        try Task.checkCancellation()
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let file = directory.appendingPathComponent("member")
        guard fm.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw ProZipError.destinationNotWritable(file.path)
        }
        let output = try FileHandle(forWritingTo: file)
        defer { try? output.close() }
        try await writer(output)
        try Task.checkCancellation()
        let reader = try TemporaryMemberReader(directory: directory, file: file, range: range)
        return AsyncThrowingStream(unfolding: { try await reader.next() })
    } catch {
        try? fm.removeItem(at: directory)
        await MemberReadBudgetLimiter.shared.release()
        throw error
    }
}

// MARK: - Active Member Read Budget & Limiter (doc/11 section 5 & doc/03 section 8)

public actor MemberReadBudgetLimiter {
    public static let shared = MemberReadBudgetLimiter()

    public let maxConcurrentReads: Int
    public let maxSingleMemberBytes: Int64

    private var activeReads: Int = 0

    public init(maxConcurrentReads: Int = 8, maxSingleMemberBytes: Int64 = 512 * 1024 * 1024) {
        self.maxConcurrentReads = maxConcurrentReads
        self.maxSingleMemberBytes = maxSingleMemberBytes
    }

    public func acquire(requestedBytes: Int64) throws {
        if requestedBytes > maxSingleMemberBytes {
            throw ProZipError.outputExceedsBudget("Member output exceeds budget (\(requestedBytes) > \(maxSingleMemberBytes) bytes)")
        }
        if activeReads >= maxConcurrentReads {
            throw ProZipError.tooManyActiveMemberReads
        }
        activeReads += 1
    }

    public func release() {
        activeReads = max(0, activeReads - 1)
    }

    public var currentActiveReads: Int {
        activeReads
    }
}
