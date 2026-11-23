import Foundation
import ProZipShared
import ProZipCore

// MARK: - Process Cancellation & Budget Controller (doc/03 section 4 & data/engine-strings.txt)

private final class ProcessOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var stdoutData = Data()
    private var stderrData = Data()
    private var budgetError: ProZipError?
    private var stdoutLineBytes = 0
    private var stderrLineBytes = 0
    private var binaryOutputBytes: Int64 = 0
    private let stdoutFile: FileHandle?
    private let stdoutByteLimit: Int64
    private let stdoutPrefixLimit: Int64?
    private var prefixLimitReached = false

    init(stdoutFile: FileHandle?, stdoutByteLimit: Int64, stdoutPrefixLimit: Int64?) {
        self.stdoutFile = stdoutFile
        self.stdoutByteLimit = stdoutByteLimit
        self.stdoutPrefixLimit = stdoutPrefixLimit
    }

    func appendStdout(_ data: Data, maxTotal: Int, maxLine: Int) -> ProZipError? {
        lock.lock()
        defer { lock.unlock() }
        if budgetError != nil { return budgetError }
        if let stdoutFile {
            let accepted = stdoutPrefixLimit.map { data.prefix(Int(min(Int64(data.count), max(0, $0 - binaryOutputBytes)))) } ?? data[...]
            binaryOutputBytes += Int64(accepted.count)
            guard binaryOutputBytes <= stdoutByteLimit else {
                budgetError = .outputExceedsBudget("归档成员输出超过 \(stdoutByteLimit / 1024 / 1024) MiB 上限，任务已停止")
                return budgetError
            }
            do {
                try stdoutFile.write(contentsOf: accepted)
                if let stdoutPrefixLimit, binaryOutputBytes >= stdoutPrefixLimit { prefixLimitReached = true }
            } catch {
                budgetError = .destinationNotWritable(error.localizedDescription)
            }
            return budgetError
        }
        stdoutData.append(data)
        for byte in data {
            if byte == 0x0A || byte == 0x0D || byte == 0x08 {
                stdoutLineBytes = 0
            } else {
                stdoutLineBytes += 1
                if stdoutLineBytes > maxLine && budgetError == nil {
                    budgetError = ProZipError.outputExceedsBudget("归档辅助进程单行输出超过 4 MiB 上限，任务已停止")
                }
            }
        }
        if (stdoutData.count + stderrData.count) > maxTotal && budgetError == nil {
            budgetError = ProZipError.outputExceedsBudget("归档辅助进程输出超过 16 MiB 上限，任务已停止")
        }
        return budgetError
    }

    func appendStderr(_ data: Data, maxTotal: Int, maxLine: Int) -> ProZipError? {
        lock.lock()
        defer { lock.unlock() }
        if budgetError != nil { return budgetError }
        stderrData.append(data)
        for byte in data {
            if byte == 0x0A || byte == 0x0D || byte == 0x08 {
                stderrLineBytes = 0
            } else {
                stderrLineBytes += 1
                if stderrLineBytes > maxLine && budgetError == nil {
                    budgetError = ProZipError.outputExceedsBudget("归档辅助进程单行输出超过 4 MiB 上限，任务已停止")
                }
            }
        }
        if (stdoutData.count + stderrData.count) > maxTotal && budgetError == nil {
            budgetError = ProZipError.outputExceedsBudget("归档辅助进程输出超过 16 MiB 上限，任务已停止")
        }
        return budgetError
    }

    var reachedPrefixLimit: Bool {
        lock.lock()
        defer { lock.unlock() }
        return prefixLimitReached
    }

    func snapshot() -> (stdout: Data, stderr: Data, error: ProZipError?, reachedPrefixLimit: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (stdoutData, stderrData, budgetError, prefixLimitReached)
    }
}

private final class ChildProcessLifecycle: @unchecked Sendable {
    private let lock = NSLock()
    private let process: Process
    private var isCancelled = false

    init(_ process: Process) { self.process = process }

    func start() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !isCancelled else { throw CancellationError() }
        try process.run()
    }

    var isStopped: Bool {
        lock.withLock { isCancelled }
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard !isCancelled else { return }
        isCancelled = true
        guard process.isRunning else { return }
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [process] in
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }
}

/// Executes child processes with strict output budget enforcement (16 MiB total, 4 MiB single line),
/// cooperative Task cancellation (SIGTERM -> SIGKILL), and secure stdin streaming.
public final class ProcessCancellationController: @unchecked Sendable {
    public static let maxTotalOutputBytes: Int = 16 * 1024 * 1024       // 16 MiB
    public static let maxSingleLineBytes: Int = 4 * 1024 * 1024         // 4 MiB
    public static let maxBinaryOutputBytes: Int64 = 512 * 1024 * 1024

    public struct ProcessResult: Sendable {
        public let stdout: Data
        public let stderr: Data
        public let exitCode: Int32
        public let combinedOutputString: String
        public let reachedPrefixLimit: Bool

        public init(stdout: Data, stderr: Data, exitCode: Int32, reachedPrefixLimit: Bool = false) {
            self.stdout = stdout
            self.stderr = stderr
            self.exitCode = exitCode
            self.reachedPrefixLimit = reachedPrefixLimit
            let outStr = String(data: stdout, encoding: .utf8) ?? String(decoding: stdout, as: UTF8.self)
            let errStr = String(data: stderr, encoding: .utf8) ?? String(decoding: stderr, as: UTF8.self)
            self.combinedOutputString = outStr + "\n" + errStr
        }
    }

    /// A prefix limit stops member output early; it does not certify the unread suffix or its CRC.
    public static func run(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL? = nil,
        environment: [String: String]? = nil,
        stdinData: Data? = nil,
        stdinFileURL: URL? = nil,
        stdoutFile: FileHandle? = nil,
        stdoutByteLimit: Int64 = .max,
        stdoutPrefixLimit: Int64? = nil,
        onStdoutChunk: (@Sendable (Data) -> Void)? = nil,
        onStderrChunk: (@Sendable (Data) -> Void)? = nil,
        onStdinProgress: (@Sendable (Int64, Int64) -> Void)? = nil
    ) async throws -> ProcessResult {
        try Task.checkCancellation()
        if let stdoutPrefixLimit {
            guard stdoutFile != nil, stdoutPrefixLimit >= 0 else {
                throw ProZipError.invalidArchive("预览读取边界无效")
            }
            if stdoutPrefixLimit == 0 {
                return ProcessResult(stdout: Data(), stderr: Data(), exitCode: 0, reachedPrefixLimit: true)
            }
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        if let workingDir = workingDirectoryURL {
            process.currentDirectoryURL = workingDir
        }
        if let env = environment {
            var fullEnv = ProcessInfo.processInfo.environment
            fullEnv.merge(env) { _, new in new }
            process.environment = fullEnv
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()

        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = stdinPipe

        let buffer = ProcessOutputBuffer(stdoutFile: stdoutFile, stdoutByteLimit: stdoutByteLimit, stdoutPrefixLimit: stdoutPrefixLimit)
        let lifecycle = ChildProcessLifecycle(process)

        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading

        let stdoutSource = DispatchSource.makeReadSource(fileDescriptor: stdoutHandle.fileDescriptor, queue: DispatchQueue.global(qos: .userInitiated))
        let stderrSource = DispatchSource.makeReadSource(fileDescriptor: stderrHandle.fileDescriptor, queue: DispatchQueue.global(qos: .userInitiated))
        let finishedReaders = DispatchGroup()
        finishedReaders.enter()
        finishedReaders.enter()
        stdoutSource.setCancelHandler { finishedReaders.leave() }
        stderrSource.setCancelHandler { finishedReaders.leave() }

        stdoutSource.setEventHandler {
            let available = stdoutHandle.availableData
            guard !available.isEmpty else { stdoutSource.cancel(); return }
            if stdoutFile == nil {
                onStdoutChunk?(available)
            }
            if buffer.appendStdout(available, maxTotal: maxTotalOutputBytes, maxLine: maxSingleLineBytes) != nil || buffer.reachedPrefixLimit {
                lifecycle.stop()
            }
        }

        stderrSource.setEventHandler {
            let available = stderrHandle.availableData
            guard !available.isEmpty else { stderrSource.cancel(); return }
            onStderrChunk?(available)
            if buffer.appendStderr(available, maxTotal: maxTotalOutputBytes, maxLine: maxSingleLineBytes) != nil {
                lifecycle.stop()
            }
        }

        stdoutSource.resume()
        stderrSource.resume()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { process in
                    process.terminationHandler = nil
                    continuation.resume()
                }
                do {
                    try lifecycle.start()
                } catch {
                    process.terminationHandler = nil
                    stdoutSource.cancel()
                    stderrSource.cancel()
                    try? stdinPipe.fileHandleForWriting.close()
                    if error is CancellationError {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(throwing: ProZipError.invalidArchive("无法启动归档辅助进程：\(error.localizedDescription)"))
                    }
                    return
                }

                // Closing stdin also unblocks helpers that finish after EOF.
                if let stdinFileURL {
                    let writeHandle = stdinPipe.fileHandleForWriting
                    let writeFD = writeHandle.fileDescriptor
                    _ = fcntl(writeFD, F_SETNOSIGPIPE, 1)
                    DispatchQueue.global(qos: .userInitiated).async {
                        defer { try? writeHandle.close() }
                        guard let reader = try? FileHandle(forReadingFrom: stdinFileURL) else { return }
                        defer { try? reader.close() }
                        let totalBytes = Int64(max(0, (try? stdinFileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0))
                        let chunkSize = 262_144
                        var totalWritten: Int64 = 0
                        var lastEmittedBytes: Int64 = 0
                        var lastEmitTime: CFAbsoluteTime = 0
                        while !lifecycle.isStopped {
                            guard let chunk = try? reader.read(upToCount: chunkSize), !chunk.isEmpty else { break }
                            let wroteAll = chunk.withUnsafeBytes { rawBuf -> Bool in
                                guard let base = rawBuf.baseAddress else { return true }
                                var offset = 0
                                while offset < chunk.count {
                                    if lifecycle.isStopped { return false }
                                    let n = Darwin.write(writeFD, base.advanced(by: offset), chunk.count - offset)
                                    if n > 0 {
                                        offset += n
                                    } else if n < 0 && errno == EINTR {
                                        continue
                                    } else {
                                        return false
                                    }
                                }
                                return true
                            }
                            guard wroteAll else { break }
                            totalWritten += Int64(chunk.count)
                            let now = CFAbsoluteTimeGetCurrent()
                            let stepReached = totalBytes > 0 && (totalWritten - lastEmittedBytes) >= max(Int64(chunkSize), totalBytes / 40)
                            if let onStdinProgress,
                               (lastEmitTime == 0 || (now - lastEmitTime) >= 0.025 || stepReached || totalWritten >= totalBytes) {
                                lastEmitTime = now
                                lastEmittedBytes = totalWritten
                                onStdinProgress(totalWritten, totalBytes)
                            }
                        }
                    }
                } else {
                    if let input = stdinData, !input.isEmpty {
                        try? stdinPipe.fileHandleForWriting.write(contentsOf: input)
                    }
                    try? stdinPipe.fileHandleForWriting.close()
                }
            }

            stdoutSource.cancel()
            stderrSource.cancel()
            await withCheckedContinuation { continuation in
                finishedReaders.notify(queue: .global(qos: .userInitiated)) { continuation.resume() }
            }

            let remainingOut = stdoutHandle.readDataToEndOfFile()
            let remainingErr = stderrHandle.readDataToEndOfFile()

            _ = buffer.appendStdout(remainingOut, maxTotal: maxTotalOutputBytes, maxLine: maxSingleLineBytes)
            _ = buffer.appendStderr(remainingErr, maxTotal: maxTotalOutputBytes, maxLine: maxSingleLineBytes)
            let snapshot = buffer.snapshot()
            try Task.checkCancellation()

            if let error = snapshot.error {
                throw error
            }

            return ProcessResult(stdout: snapshot.stdout, stderr: snapshot.stderr, exitCode: process.terminationStatus, reachedPrefixLimit: snapshot.reachedPrefixLimit)
        } onCancel: {
            lifecycle.stop()
        }
    }
}

// MARK: - SevenZipEngine (L2 Archive Engine)

public struct SevenZipEngine: ArchiveEngine {
    public static let capabilities = EngineCapabilities(
        read: Set(ArchiveFormat.allCases.filter { $0 != .dmg && $0 != .unknown }),
        write: [.sevenZip, .zip],
        edit: [.sevenZip, .zip],
        encryptedRead: true,
        encryptedWrite: true,
        headerEncryption: true,
        split: true,
        streamingMemberRead: true
    )

    public var engineName: String { "7-Zip" }

    public init() {}

    // MARK: - Binary Resolution & Core Pre-warming

    private static let binaryCacheLock = NSLock()
    private static var cachedBinaryPath: String?

    public static func resolveBinaryURL() -> URL? {
        if let path = resolveBinaryPath() {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    public static func resolveBinaryPath() -> String? {
        let fm = FileManager.default
        binaryCacheLock.lock()
        let cached = cachedBinaryPath
        binaryCacheLock.unlock()
        if let cached, fm.isExecutableFile(atPath: cached) {
            return cached
        }

        let candidates: [String?] = [
            Bundle.main.url(forResource: "7zz", withExtension: nil)?.path,
            "/opt/homebrew/bin/7zz",
            "/opt/homebrew/bin/7z",
            "/usr/local/bin/7zz",
            "/usr/local/bin/7z",
            "/usr/bin/7z"
        ]

        for candidate in candidates {
            guard let path = candidate, !path.isEmpty else { continue }
            if fm.isExecutableFile(atPath: path) {
                binaryCacheLock.lock()
                cachedBinaryPath = path
                binaryCacheLock.unlock()
                return path
            }
        }
        return nil
    }

    /// Faults the external 7-Zip binary and dynamic codecs into macOS's unified buffer cache.
    public static func prewarm() async {
        guard let bin = resolveBinaryURL() else { return }
        _ = try? await ProcessCancellationController.run(
            executableURL: bin,
            arguments: ["i"]
        )
    }

    public struct SevenZipProgressSnapshot: Equatable, Sendable {
        public enum Stage: Equatable, Sendable {
            case opening
            case transfer
        }

        public let stage: Stage
        public let percent: Int?
        public let processedBytes: Int64?
        public let currentItem: String?

        public init(stage: Stage, percent: Int?, processedBytes: Int64?, currentItem: String?) {
            self.stage = stage
            self.percent = percent
            self.processedBytes = processedBytes
            self.currentItem = currentItem
        }
    }

    /// Parses `-bsp1` progress chunks emitted by 7zz / p7zip for both compression and extraction,
    /// distinguishing pre-transfer volume opening (`" 98% 100 Open"`, `" 0M Scan"`) from real
    /// transfer progress (`" 49% + big.bin"`, `" 21% - movie.mkv"`, `" 85% 13 - file.bin"`, `" 64M - huge.bin"`).
    public static func parseDetailedProgressSnapshot(from chunk: Data) -> SevenZipProgressSnapshot? {
        guard !chunk.isEmpty else { return nil }
        let text = String(decoding: chunk, as: UTF8.self)
        let segments = text.split { $0 == "\n" || $0 == "\r" || $0 == "\u{08}" }
        for rawSegment in segments.reversed() {
            let trimmed = rawSegment.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if let snapshot = parseProgressSegment(trimmed) {
                return snapshot
            }
        }
        return nil
    }

    /// Parses `-bsp1` transfer percentage snapshots emitted by 7zz / p7zip
    /// (e.g. `" 49% + big.bin"`, `"100% 1 + big.bin"`, `" 21% - movie.mkv"`).
    /// Pre-transfer `"Open"` / `"Scan"` segments return `nil` so callers never mistake volume scanning for completion.
    public static func parseProgressSnapshot(from chunk: Data) -> (percent: Int, currentItem: String?)? {
        guard let detailed = parseDetailedProgressSnapshot(from: chunk),
              detailed.stage == .transfer,
              let percent = detailed.percent else {
            return nil
        }
        return (percent, detailed.currentItem)
    }

    private static func parseProgressSegment(_ trimmed: String) -> SevenZipProgressSnapshot? {
        // 1. Percentage form: "<0..100>% [count] [action [item]]"
        if let percentIndex = trimmed.firstIndex(of: "%") {
            let prefix = trimmed[..<percentIndex]
            if !prefix.isEmpty, prefix.count <= 3, prefix.allSatisfy(\.isNumber),
               let pct = Int(prefix), (0...100).contains(pct) {
                let suffix = trimmed[trimmed.index(after: percentIndex)...]
                if let parsed = classifyProgressSuffix(suffix) {
                    return SevenZipProgressSnapshot(
                        stage: parsed.stage,
                        percent: pct,
                        processedBytes: nil,
                        currentItem: parsed.currentItem
                    )
                }
            }
        }

        // 2. Unknown-total byte-count form: "<N>[BKMG] [count] [action [item]]"
        var digitEnd = trimmed.startIndex
        while digitEnd < trimmed.endIndex, trimmed[digitEnd].isASCII, trimmed[digitEnd].isNumber {
            digitEnd = trimmed.index(after: digitEnd)
        }
        if digitEnd > trimmed.startIndex, digitEnd < trimmed.endIndex {
            let unitChar = trimmed[digitEnd]
            let multiplier: Int64?
            switch unitChar {
            case "B": multiplier = 1
            case "K": multiplier = 1024
            case "M": multiplier = 1024 * 1024
            case "G": multiplier = 1024 * 1024 * 1024
            default: multiplier = nil
            }
            if let multiplier,
               let value = Int64(trimmed[..<digitEnd]), value >= 0 {
                let afterUnit = trimmed.index(after: digitEnd)
                if afterUnit == trimmed.endIndex || trimmed[afterUnit].isWhitespace {
                    let suffix = trimmed[afterUnit...]
                    if let parsed = classifyProgressSuffix(suffix) {
                        let (bytes, overflow) = value.multipliedReportingOverflow(by: multiplier)
                        return SevenZipProgressSnapshot(
                            stage: parsed.stage,
                            percent: nil,
                            processedBytes: overflow ? Int64.max : bytes,
                            currentItem: parsed.currentItem
                        )
                    }
                }
            }
        }

        return nil
    }

    private static func classifyProgressSuffix(_ rawSuffix: Substring) -> (stage: SevenZipProgressSnapshot.Stage, currentItem: String?)? {
        var rest = rawSuffix.drop(while: { $0.isWhitespace })
        if rest.isEmpty {
            return (.transfer, nil)
        }

        // Skip optional file / volume count token (e.g. "13 - file.bin", "100 Open", "3700").
        var countEnd = rest.startIndex
        while countEnd < rest.endIndex, rest[countEnd].isASCII, rest[countEnd].isNumber {
            countEnd = rest.index(after: countEnd)
        }
        if countEnd > rest.startIndex, countEnd == rest.endIndex || rest[countEnd].isWhitespace {
            rest = rest[countEnd...].drop(while: { $0.isWhitespace })
            if rest.isEmpty {
                return (.transfer, nil)
            }
        }

        if rest == "Open" || rest.hasPrefix("Open ") || rest == "Scan" || rest.hasPrefix("Scan ") {
            return (.opening, nil)
        }

        for marker in ["+ ", "- ", "U ", "= ", "T "] {
            if rest.hasPrefix(marker) {
                let candidate = rest.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
                return (.transfer, candidate.isEmpty ? nil : candidate)
            }
        }
        if rest == "+" || rest == "-" || rest == "U" || rest == "=" || rest == "T" {
            return (.transfer, nil)
        }

        return nil
    }

    private static func directoryRegularFileBytes(at root: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: []
        ) else { return 0 }
        var total: Int64 = 0
        while let child = enumerator.nextObject() as? URL {
            if let vals = try? child.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
               vals.isRegularFile == true {
                total += Int64(max(0, vals.fileSize ?? 0))
            }
        }
        return total
    }

    private static func estimateSourceBytes(_ sources: [URL]) -> Int64 {
        let fm = FileManager.default
        var total: Int64 = 0
        for root in sources {
            let values = try? root.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey])
            if values?.isDirectory == true {
                guard let enumerator = fm.enumerator(
                    at: root,
                    includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                    options: []
                ) else { continue }
                while let child = enumerator.nextObject() as? URL {
                    if let childVals = try? child.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                       childVals.isRegularFile == true {
                        total += Int64(max(0, childVals.fileSize ?? 0))
                    }
                }
            } else {
                total += Int64(max(0, values?.fileSize ?? 0))
            }
        }
        return total
    }

    private func requireBinaryURL() throws -> URL {
        guard let url = Self.resolveBinaryURL() else {
            throw ProZipError.invalidArchive("未找到内置 7-Zip 引擎")
        }
        return url
    }

    // MARK: - Command Line Argument Security (doc/03 section 4 & test D8)

    /// Builds command-line arguments ensuring PLAINTEXT PASSWORDS NEVER APPEAR in argv.
    /// Payload writes use bare `-p`; password-free writes add no password switch.
    /// Reads keep the dummy fail-fast switch when no password is supplied.
    public static func buildCommandArguments(
        subcommand: String,
        archivePath: String,
        extraArgs: [String] = [],
        hasPassword: Bool
    ) -> [String] {
        var args: [String] = [subcommand]
        args.append(contentsOf: extraArgs)
        if subcommand == "a" {
            if hasPassword { args.append("-p") }
        } else if !hasPassword {
            args.append("-p__ARCZIP_NO_PASSWORD__")
        }
        // Use "--" to mark end of options, ensuring archive paths starting with hyphen are treated safely
        args.append("--")
        args.append(archivePath)
        return args
    }

    // MARK: - Probe

    public func probe(_ url: URL) async throws -> ArchiveDescriptor {
        let bin = try requireBinaryURL()
        let family = SplitVolumeFamily.resolve(for: url)
        let targetURL = family.primaryVolumeURL

        let args = Self.buildCommandArguments(
            subcommand: "l",
            archivePath: targetURL.path,
            extraArgs: ["-slt", "-sccUTF-8", "-ba"],
            hasPassword: false
        )

        let result = try await ProcessCancellationController.run(
            executableURL: bin,
            arguments: args
        )

        let outString = result.combinedOutputString
        var isEncryptedHeader = Self.isEncryptedHeaderError(outString)
        if !isEncryptedHeader, result.exitCode != 0, family.isSplit {
            do { _ = try await inspectWriteArchive(targetURL, password: nil) }
            catch ProZipError.passwordRequired { isEncryptedHeader = true }
        }

        let format = ArchiveFormat.detect(from: url)
        let fileSize = family.volumeURLs.reduce(Int64(0)) { sum, volumeURL in
            sum + Int64(max(0, (try? volumeURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0))
        }

        if isEncryptedHeader {
            return ArchiveDescriptor(
                url: url,
                primaryVolumeURL: family.primaryVolumeURL,
                volumeURLs: family.volumeURLs,
                format: format,
                isEncrypted: true,
                hasEncryptedHeaders: true,
                isSplitVolume: family.isSplit,
                totalCompressedSize: fileSize
            )
        }
        guard result.exitCode == 0 else {
            throw ProZipError.corruptedArchive("7-Zip 无法读取压缩包信息，退出码 \(result.exitCode)")
        }

        // Parse format type, comment, and general encryption from 7z -slt output
        var detectedFormat = format
        var comment: String?
        var hasEncryptedEntries = false
        var entryCount = 0

        let blocks = outString.components(separatedBy: "\n\n")
        for block in blocks {
            let lines = block.split(separator: "\n").map(String.init)
            for line in lines {
                if line.hasPrefix("Type = ") {
                    let typeStr = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces).lowercased()
                    if typeStr == "7z" { detectedFormat = .sevenZip }
                    else if typeStr == "zip" { detectedFormat = .zip }
                    else if typeStr == "rar" { detectedFormat = .rar }
                    else if typeStr == "tar" { detectedFormat = .tar }
                } else if line.hasPrefix("Comment = ") {
                    comment = String(line.dropFirst(10))
                } else if line.hasPrefix("Path = ") {
                    entryCount += 1
                } else if line == "Encrypted = +" {
                    hasEncryptedEntries = true
                }
            }
        }

        return ArchiveDescriptor(
            url: url,
            primaryVolumeURL: family.primaryVolumeURL,
            volumeURLs: family.volumeURLs,
            format: detectedFormat,
            isEncrypted: hasEncryptedEntries,
            hasEncryptedHeaders: false,
            isSplitVolume: family.isSplit,
            totalCompressedSize: fileSize,
            entryCountHint: entryCount > 0 ? entryCount : nil,
            comment: comment
        )
    }

    // MARK: - List

    public func list(
        _ url: URL,
        password: String?,
        progress: @escaping ProgressSink
    ) async throws -> [ArchiveEntry] {
        let bin = try requireBinaryURL()
        let family = SplitVolumeFamily.resolve(for: url)

        if family.isSplit {
            if !family.isComplete {
                throw ProZipError.splitVolumeIncomplete("分卷输出不连续或包含空卷，未发布压缩包")
            }
            if family.hasEmptyVolume {
                throw ProZipError.splitVolumeIncomplete("分卷包含空卷：\(url.lastPathComponent)")
            }
        }

        progress(OperationProgress(phase: .indexing, completedBytes: 0, totalBytes: 0))

        let hasPwd = (password != nil && !(password!.isEmpty))
        let args = Self.buildCommandArguments(
            subcommand: "l",
            archivePath: family.primaryVolumeURL.path,
            extraArgs: ["-slt", "-sccUTF-8", "-ba"],
            hasPassword: hasPwd
        )

        let stdinData = hasPwd ? "\(password!)\n".data(using: .utf8) : nil

        let result = try await ProcessCancellationController.run(
            executableURL: bin,
            arguments: args,
            stdinData: stdinData
        )

        let combined = result.combinedOutputString

        // Check for password issues
        if Self.isEncryptedHeaderError(combined) ||
            (result.exitCode != 0 && Self.hasConsolePasswordPrompt(combined)) {
            if !hasPwd {
                throw ProZipError.passwordRequired(url.lastPathComponent)
            } else {
                throw ProZipError.wrongPassword("密码错误：\(url.lastPathComponent)")
            }
        }

        if combined.contains("data error in encrypted file") ||
            combined.contains("crc failed in encrypted file") ||
            combined.contains("Wrong password") {
            throw ProZipError.wrongPassword("密码错误：\(url.lastPathComponent)")
        }

        if result.exitCode != 0, !hasPwd, family.isSplit,
           try await probe(url).hasEncryptedHeaders {
            throw ProZipError.passwordRequired(url.lastPathComponent)
        }
        if result.exitCode != 0 {
            throw ProZipError.corruptedArchive("压缩包无效或已损坏，退出码 \(result.exitCode)：\(url.lastPathComponent)")
        }

        let entries = parseSLTOutput(combined)
        progress(OperationProgress(phase: .completed, completedBytes: Int64(entries.count), totalBytes: Int64(entries.count)))
        return entries
    }

    // MARK: - Open Member (Streaming)

    public func openMember(
        _ entry: ArchiveEntry,
        in url: URL,
        password: String?,
        range: Range<Int64>?
    ) async throws -> AsyncThrowingStream<Data, Error> {
        let bin = try requireBinaryURL()

        let hasPwd = (password != nil && !(password!.isEmpty))
        var extra = ["-so", "-y", "-bso0", "-bse2"]
        if !hasPwd {
            extra.append("-p__ARCZIP_NO_PASSWORD__")
        }

        var cmdArgs = ["x"]
        cmdArgs.append(contentsOf: extra)
        cmdArgs.append("--")
        cmdArgs.append(url.path)
        cmdArgs.append(entry.path)

        let stdinData = hasPwd ? "\(password!)\n".data(using: .utf8) : nil

        let arguments = cmdArgs
        return try await streamMemberOutput(expectedSize: entry.uncompressedSize, range: range) { output in
            let result = try await ProcessCancellationController.run(
                executableURL: bin, arguments: arguments, stdinData: stdinData, stdoutFile: output,
                stdoutByteLimit: ProcessCancellationController.maxBinaryOutputBytes,
                stdoutPrefixLimit: memberOutputPrefixLimit(expectedSize: entry.uncompressedSize, range: range))
            if result.reachedPrefixLimit { return }
            if result.exitCode != 0 {
                let err = result.combinedOutputString.lowercased()
                if err.contains("wrong password") || err.contains("encrypted") {
                    throw ProZipError.wrongPassword("密码错误：\(entry.name)")
                }
                throw ProZipError.corruptedArchive("提取条目失败：\(entry.path)")
            }
        }
    }

    // MARK: - Extract

    public func extract(
        _ entries: [ArchiveEntry],
        from url: URL,
        to dir: URL,
        password: String?,
        options: ExtractionOptions,
        progress: @escaping ProgressSink
    ) async throws -> ExtractionReport {
        let bin = try requireBinaryURL()

        // 1. Build extraction plan using security policy
        let plan = try ArchiveExtractionPolicy.buildPlan(
            entries: entries,
            archiveURL: url,
            destinationURL: dir,
            options: options
        )

        guard !plan.itemsToExtract.isEmpty else {
            return ExtractionReport(
                destinationURL: dir,
                extractedCount: 0,
                skippedCount: plan.skippedEntries.count,
                failedCount: 0,
                extractedURLs: [],
                skippedReasons: plan.skippedEntries.map(\.reason)
            )
        }

        let plannedUncompressedBytes = plan.itemsToExtract.reduce(Int64(0)) { $0 + max(0, $1.entry.uncompressedSize) }
        let progressTotalBytes = plannedUncompressedBytes > 0 ? plannedUncompressedBytes : Int64(plan.itemsToExtract.count)
        let firstItemName = plan.itemsToExtract.first?.entry.name

        progress(OperationProgress(
            phase: .preparing,
            completedBytes: 0,
            totalBytes: progressTotalBytes,
            currentItem: firstItemName,
            fractionCompleted: 0.02
        ))

        // 2. Setup private staging directory and external UTF-8 entry listfile
        let fm = FileManager.default
        let stagingUUID = UUID().uuidString
        let stagingParent = dir.deletingLastPathComponent()
        let stagingURL = stagingParent.appendingPathComponent(".prozip-extract-staging-\(stagingUUID)", isDirectory: true)
        let listFileURL = stagingParent.appendingPathComponent(".prozip-extract-list-\(stagingUUID).txt")
        try fm.createDirectory(at: stagingURL, withIntermediateDirectories: true)

        defer {
            try? fm.removeItem(at: listFileURL)
            try? fm.removeItem(at: stagingURL)
        }

        // 3. Extract items to staging directory with real-time -bsp1 progress streaming
        let hasPwd = (password != nil && !(password!.isEmpty))
        let entryPathsContent = plan.itemsToExtract.map(\.entry.path).joined(separator: "\n")
        try entryPathsContent.write(to: listFileURL, atomically: true, encoding: .utf8)

        var extraArgs = ["-o\(stagingURL.path)", "-y", "-bsp1", "-scsUTF-8", "-i@\(listFileURL.path)"]
        if !hasPwd {
            extraArgs.append("-p__ARCZIP_NO_PASSWORD__")
        }

        var args = ["x"]
        args.append(contentsOf: extraArgs)
        args.append("--")
        args.append(url.path)

        let stdinData = hasPwd ? "\(password!)\n".data(using: .utf8) : nil

        progress(OperationProgress(
            phase: .extracting,
            completedBytes: 0,
            totalBytes: progressTotalBytes,
            currentItem: firstItemName,
            fractionCompleted: 0.05
        ))

        final class ExtractStreamProgressState: @unchecked Sendable {
            let lock = NSLock()
            var lastEmitTime: CFAbsoluteTime = 0
            var lastTransferTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
            var lastFraction: Double = 0.05
            var lastOpenPercent: Int = -1
            var lastItem: String?
            var hasSeenTransferProgress = false
        }
        let streamState = ExtractStreamProgressState()

        // Fallback disk monitor: stays idle while 7-Zip streams -bsp1 progress, and only polls
        // staged output bytes if stdout progress is silent for >= 0.75s (e.g. exotic split/solid streams).
        let fallbackMonitor: Task<Void, Never>?
        if plannedUncompressedBytes > 0 && plan.itemsToExtract.count <= 2000 {
            fallbackMonitor = Task.detached(priority: .utility) {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    guard !Task.isCancelled else { break }

                    let now = CFAbsoluteTimeGetCurrent()
                    let isSilent = streamState.lock.withLock {
                        (now - streamState.lastTransferTime) >= 0.75
                    }
                    guard isSilent else { continue }

                    let stagedBytes = Self.directoryRegularFileBytes(at: stagingURL)
                    guard stagedBytes > 0 else { continue }
                    let ratio = min(0.98, max(0.0, Double(stagedBytes) / Double(plannedUncompressedBytes)))
                    let targetFraction = 0.05 + 0.89 * ratio

                    let shouldSend = streamState.lock.withLock {
                        guard targetFraction > streamState.lastFraction + 0.004 else { return false }
                        streamState.lastFraction = targetFraction
                        streamState.lastEmitTime = now
                        streamState.hasSeenTransferProgress = true
                        return true
                    }

                    if shouldSend {
                        progress(OperationProgress(
                            phase: .extracting,
                            completedBytes: min(plannedUncompressedBytes, stagedBytes),
                            totalBytes: progressTotalBytes,
                            currentItem: nil,
                            fractionCompleted: targetFraction
                        ))
                    }
                }
            }
        } else {
            fallbackMonitor = nil
        }
        defer { fallbackMonitor?.cancel() }

        let result = try await ProcessCancellationController.run(
            executableURL: bin,
            arguments: args,
            stdinData: stdinData,
            onStdoutChunk: { chunk in
                guard let snapshot = Self.parseDetailedProgressSnapshot(from: chunk) else { return }
                let now = CFAbsoluteTimeGetCurrent()

                switch snapshot.stage {
                case .opening:
                    guard let pct = snapshot.percent else { return }
                    var shouldSend = false
                    let openFraction = 0.02 + 0.03 * (Double(pct) / 100.0)
                    streamState.lock.lock()
                    if !streamState.hasSeenTransferProgress,
                       pct > streamState.lastOpenPercent,
                       (streamState.lastEmitTime == 0 || (now - streamState.lastEmitTime) >= 0.05 || pct == 100) {
                        streamState.lastOpenPercent = pct
                        streamState.lastEmitTime = now
                        shouldSend = true
                    }
                    streamState.lock.unlock()
                    if shouldSend {
                        progress(OperationProgress(
                            phase: .checkingArchive,
                            completedBytes: 0,
                            totalBytes: progressTotalBytes,
                            currentItem: url.lastPathComponent,
                            fractionCompleted: openFraction
                        ))
                    }

                case .transfer:
                    let ratio: Double
                    if let pct = snapshot.percent {
                        ratio = Double(pct) / 100.0
                    } else if let processed = snapshot.processedBytes, plannedUncompressedBytes > 0 {
                        ratio = min(0.99, max(0.0, Double(processed) / Double(plannedUncompressedBytes)))
                    } else {
                        return
                    }

                    let targetFraction = 0.05 + 0.89 * ratio
                    var shouldSend = false
                    var effectiveFraction = targetFraction
                    streamState.lock.lock()
                    streamState.hasSeenTransferProgress = true
                    streamState.lastTransferTime = now
                    let fractionAdvanced = targetFraction > streamState.lastFraction + 1e-4
                    let itemChanged = snapshot.currentItem != nil && snapshot.currentItem != streamState.lastItem
                    let throttlePassed = streamState.lastEmitTime == 0 ||
                        (now - streamState.lastEmitTime) >= 0.025 ||
                        (targetFraction - streamState.lastFraction) >= 0.015 ||
                        ratio >= 1.0
                    if (fractionAdvanced || (itemChanged && (now - streamState.lastEmitTime) >= 0.05)) && throttlePassed {
                        if targetFraction > streamState.lastFraction {
                            streamState.lastFraction = targetFraction
                        }
                        effectiveFraction = streamState.lastFraction
                        if let item = snapshot.currentItem {
                            streamState.lastItem = item
                        }
                        streamState.lastEmitTime = now
                        shouldSend = true
                    }
                    streamState.lock.unlock()

                    guard shouldSend else { return }
                    let clampedRatio = max(0.0, min(1.0, (effectiveFraction - 0.05) / 0.89))
                    let completed = Int64(Double(progressTotalBytes) * clampedRatio)
                    progress(OperationProgress(
                        phase: .extracting,
                        completedBytes: completed,
                        totalBytes: progressTotalBytes,
                        currentItem: snapshot.currentItem,
                        fractionCompleted: effectiveFraction
                    ))
                }
            }
        )
        fallbackMonitor?.cancel()

        let combined = result.combinedOutputString
        if result.exitCode == 1 {
            throw ProZipError.corruptedArchive("7-Zip 解压时报告了警告，未接受可能不完整的结果")
        } else if result.exitCode != 0 {
            let lowerCombined = combined.lowercased()
            if lowerCombined.contains("wrong password") || lowerCombined.contains("encrypted") {
                throw ProZipError.wrongPassword("密码错误：\(url.lastPathComponent)")
            }
            throw ProZipError.corruptedArchive("7-Zip 提取失败，退出码 \(result.exitCode)")
        }

        // 4. Publish validated files from staging to target destination according to plan
        progress(OperationProgress(
            phase: .savingSafely,
            completedBytes: progressTotalBytes,
            totalBytes: progressTotalBytes,
            fractionCompleted: 0.94
        ))

        var publishedURLs: [URL] = []
        var skippedCount = plan.skippedEntries.count
        var skippedReasons = plan.skippedEntries.map(\.reason)
        let totalItemsToPublish = max(1, plan.itemsToExtract.count)
        var lastPublishEmitTime = CFAbsoluteTimeGetCurrent()

        for (index, item) in plan.itemsToExtract.enumerated() {
            try Task.checkCancellation()
            let stagedItemURL = stagingURL.appendingPathComponent(item.entry.path)
            guard (try? fm.attributesOfItem(atPath: stagedItemURL.path)) != nil else {
                continue
            }

            let destURL = item.destinationURL
            let destParent = destURL.deletingLastPathComponent()
            try ArchiveExtractionPolicy.validateDestinationDirectory(item.entry.isDirectory ? destURL : destParent)
            if !fm.fileExists(atPath: destParent.path) {
                try fm.createDirectory(at: destParent, withIntermediateDirectories: true)
            }

            if item.entry.isDirectory {
                try fm.createDirectory(at: destURL, withIntermediateDirectories: true)
                publishedURLs.append(destURL)
            } else if fm.fileExists(atPath: destURL.path) {
                switch item.conflictAction {
                case .replace:
                    _ = try fm.replaceItemAt(destURL, withItemAt: stagedItemURL, options: .usingNewMetadataOnly)
                    publishedURLs.append(destURL)
                case .skip:
                    skippedCount += 1
                    skippedReasons.append("跳过已存在项目：\(destURL.lastPathComponent)")
                case .keepBoth, .ask:
                    // Unique name resolution has already been applied by buildPlan if keepBoth was selected
                    try fm.moveItem(at: stagedItemURL, to: destURL)
                    publishedURLs.append(destURL)
                }
            } else {
                try fm.moveItem(at: stagedItemURL, to: destURL)
                publishedURLs.append(destURL)
            }

            let now = CFAbsoluteTimeGetCurrent()
            if index == totalItemsToPublish - 1 || (now - lastPublishEmitTime) >= 0.04 {
                lastPublishEmitTime = now
                let publishRatio = Double(index + 1) / Double(totalItemsToPublish)
                progress(OperationProgress(
                    phase: .savingSafely,
                    completedBytes: progressTotalBytes,
                    totalBytes: progressTotalBytes,
                    fractionCompleted: 0.94 + 0.05 * publishRatio
                ))
            }
        }

        progress(OperationProgress(
            phase: .completed,
            completedBytes: progressTotalBytes,
            totalBytes: progressTotalBytes,
            fractionCompleted: 1.0
        ))

        return ExtractionReport(
            destinationURL: dir,
            extractedCount: publishedURLs.count,
            skippedCount: skippedCount,
            failedCount: 0,
            extractedURLs: publishedURLs,
            skippedReasons: skippedReasons
        )
    }

    // MARK: - Create

    public func create(
        sources: [URL],
        at url: URL,
        profile: CreationProfile,
        password: String?,
        progress: @escaping ProgressSink
    ) async throws {
        try Self.validateConsoleWritePassword(password)
        let bin = try requireBinaryURL()
        try profile.validate()

        guard profile.format == .sevenZip || profile.format == .zip else {
            throw ProZipError.invalidCreationProfile("7-Zip 引擎仅支持创建 7Z 和 ZIP 归档")
        }
        let hasPwd = password?.isEmpty == false
        guard !profile.encryptHeaders || (profile.format == .sevenZip && hasPwd) else {
            throw ProZipError.invalidCreationProfile("文件名加密仅支持已设置密码的 7Z 归档")
        }
        let existing = try SplitArchivePublication.existingItems(baseURL: url)
        if profile.split != nil || existing.contains(where: {
            $0.lastPathComponent.caseInsensitiveCompare(url.lastPathComponent) != .orderedSame
        }) {
            try SplitArchivePublication.ensureAvailable(baseURL: url)
        }

        progress(OperationProgress(phase: .preparing, completedBytes: 0, totalBytes: 0))

        let fm = FileManager.default
        let stagingUUID = UUID().uuidString
        let stagingDir = url.deletingLastPathComponent().appendingPathComponent(".prozip-create-staging-\(stagingUUID)", isDirectory: true)
        try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: stagingDir) }

        let stagingArchiveURL = stagingDir.appendingPathComponent(url.lastPathComponent)

        var extraArgs: [String] = []
        if profile.format == .sevenZip {
            extraArgs.append("-t7z")
            if profile.strength == .maximum {
                extraArgs.append("-ms=4g") // Maximum LZMA2 with 4 GB solid blocks (doc/03 section 4)
            }
            if profile.encryptHeaders {
                extraArgs.append("-mhe=on")
            }
        } else {
            extraArgs.append("-tzip")
        }

        extraArgs.append("-mx=\(profile.strength.sevenZipLevel)")
        extraArgs.append("-mmt=\(max(1, profile.processorCount))")
        if !profile.preserveMacMetadata {
            extraArgs.append(contentsOf: ["-xr!.DS_Store", "-xr!__MACOSX", "-xr!._*"])
        }
        extraArgs.append("-bsp1")

        // Count-based splitting needs the final compressed size, so only size-based splitting uses -v.
        if let split = profile.split, case .bySize(let bytes) = split {
            extraArgs.append("-v\(bytes)b")
        }

        var cmdArgs = Self.buildCommandArguments(subcommand: "a", archivePath: stagingArchiveURL.path,
                                                extraArgs: extraArgs, hasPassword: hasPwd)
        for s in sources {
            cmdArgs.append(s.path)
        }

        // Bare -p asks for both the new password and its confirmation, even with piped stdin.
        let stdinData = hasPwd ? Data("\(password!)\n\(password!)\n".utf8) : nil
        let estimatedTotalBytes = Self.estimateSourceBytes(sources)

        progress(OperationProgress(
            phase: .compressing,
            completedBytes: 0,
            totalBytes: estimatedTotalBytes,
            currentItem: sources.first?.lastPathComponent,
            fractionCompleted: 0.05
        ))

        final class StreamProgressState: @unchecked Sendable {
            let lock = NSLock()
            var lastEmitTime: CFAbsoluteTime = 0
            var lastPercent: Int = -1
        }
        let streamState = StreamProgressState()

        let result = try await ProcessCancellationController.run(
            executableURL: bin,
            arguments: cmdArgs,
            stdinData: stdinData,
            onStdoutChunk: { chunk in
                guard let snapshot = Self.parseProgressSnapshot(from: chunk) else { return }
                let now = CFAbsoluteTimeGetCurrent()
                var shouldSend = false
                streamState.lock.lock()
                if snapshot.percent > streamState.lastPercent,
                   (streamState.lastEmitTime == 0 || (now - streamState.lastEmitTime) >= 0.025 || snapshot.percent - streamState.lastPercent >= 2 || snapshot.percent == 100) {
                    streamState.lastPercent = snapshot.percent
                    streamState.lastEmitTime = now
                    shouldSend = true
                }
                streamState.lock.unlock()
                guard shouldSend else { return }

                let ratio = Double(snapshot.percent) / 100.0
                let completed = estimatedTotalBytes > 0 ? Int64(Double(estimatedTotalBytes) * ratio) : Int64(snapshot.percent)
                let total = estimatedTotalBytes > 0 ? estimatedTotalBytes : 100
                progress(OperationProgress(
                    phase: .compressing,
                    completedBytes: completed,
                    totalBytes: total,
                    currentItem: snapshot.currentItem,
                    fractionCompleted: 0.05 + 0.87 * ratio
                ))
            }
        )

        if result.exitCode == 1 {
            throw ProZipError.corruptedArchive("7-Zip 创建归档时报告了警告，未发布可能不完整的压缩包")
        } else if result.exitCode != 0 {
            throw ProZipError.invalidArchive("7-Zip 创建归档失败，退出码 \(result.exitCode)")
        }
        var partsToPublish: [URL]?
        var verificationURL = stagingArchiveURL
        if let split = profile.split, case .bySize = split {
            let family = SplitVolumeFamily.resolve(for: stagingArchiveURL.appendingPathExtension("001"))
            let generatedParts = try SplitArchivePublication.existingItems(baseURL: stagingArchiveURL)
            guard family.isComplete, !family.hasEmptyVolume, family.volumeURLs.count == generatedParts.count else {
                throw ProZipError.splitVolumeIncomplete("分卷输出不连续或包含空卷，未发布压缩包")
            }
            partsToPublish = family.volumeURLs
            verificationURL = family.primaryVolumeURL
        }
        progress(OperationProgress(
            phase: .verifying,
            completedBytes: estimatedTotalBytes,
            totalBytes: estimatedTotalBytes,
            fractionCompleted: 0.95
        ))
        try await verifyWrittenArchive(verificationURL, password: password, encrypted: hasPwd,
                                       encryptedHeaders: profile.encryptHeaders)
        if let split = profile.split, case .byCount = split {
            partsToPublish = try SplitArchivePublication.stageParts(
                archiveURL: stagingArchiveURL, outputBaseURL: stagingArchiveURL, plan: split
            )
        }

        // Publish archive safely
        progress(OperationProgress(
            phase: .savingSafely,
            completedBytes: estimatedTotalBytes,
            totalBytes: estimatedTotalBytes,
            fractionCompleted: 0.98
        ))

        if let parts = partsToPublish {
            _ = try SplitArchivePublication.publish(stagedParts: parts, baseURL: url)
        } else {
            guard fm.fileExists(atPath: stagingArchiveURL.path) else {
                throw ProZipError.corruptedArchive("7-Zip 未生成有效的压缩包文件")
            }
            try Task.checkCancellation()
            if fm.fileExists(atPath: url.path) {
                _ = try fm.replaceItemAt(url, withItemAt: stagingArchiveURL, options: .usingNewMetadataOnly)
            } else {
                try fm.moveItem(at: stagingArchiveURL, to: url)
            }
        }

        let finalTotal = max(1, estimatedTotalBytes)
        progress(OperationProgress(phase: .completed, completedBytes: finalTotal, totalBytes: finalTotal, fractionCompleted: 1.0))
    }

    // MARK: - Apply Mutations (Incremental Editing)

    public func applyMutations(
        _ mutations: [ArchiveMutation],
        to sourceURL: URL,
        outputURL: URL,
        profile: CreationProfile,
        password: String?,
        progress: @escaping ProgressSink
    ) async throws {
        try Self.validateConsoleWritePassword(password)
        let bin = try requireBinaryURL()
        let fm = FileManager.default
        progress(OperationProgress(phase: .preparing, completedBytes: 0, totalBytes: Int64(mutations.count)))
        let hasPwd = password?.isEmpty == false
        let writesPayload = mutations.contains {
            switch $0 {
            case .addFile, .replaceEntry: return true
            default: return false
            }
        }
        var writeEncrypted = false
        var writeEncryptedHeaders = false
        if writesPayload {
            let source = try await inspectWriteArchive(sourceURL, password: password)
            let dataEntries = source.entries.filter { !$0.isDirectory && $0.uncompressedSize > 0 }
            writeEncryptedHeaders = source.encryptedHeaders
            writeEncrypted = writeEncryptedHeaders || source.entries.contains { $0.isEncrypted } ||
                (hasPwd && dataEntries.isEmpty)
            if writeEncrypted {
                guard hasPwd else { throw ProZipError.passwordRequired(sourceURL.lastPathComponent) }
                guard dataEntries.allSatisfy(\.isEncrypted) else {
                    throw ProZipError.invalidCreationProfile("压缩包含有不同加密状态的成员，无法安全地统一新增内容的密码")
                }
                // SLT cannot prove that different encrypted blocks share a key; verify all groups once.
                try await testArchiveIntegrity(sourceURL, password: password)
            } else if hasPwd {
                throw ProZipError.invalidCreationProfile("修改未加密归档时不能仅为新增成员设置密码，请重新创建加密归档")
            }
        }

        // Create working copy: .arczip-update-work-<uuid>
        let workDir = outputURL.deletingLastPathComponent()
        let workURL = workDir.appendingPathComponent(".arczip-update-work-\(UUID().uuidString)")
        try fm.copyItem(at: sourceURL, to: workURL)
        defer { try? fm.removeItem(at: workURL) }

        let stdinData = hasPwd ? "\(password!)\n".data(using: .utf8) : nil

        for (index, mutation) in mutations.enumerated() {
            try Task.checkCancellation()
            progress(OperationProgress(
                phase: .compressing,
                completedBytes: Int64(index),
                totalBytes: Int64(mutations.count),
                currentItem: mutation.actionDescription
            ))

            switch mutation {
            case .deleteEntry(let archivePath):
                var args = ["d", "-y"]
                if !hasPwd { args.append("-p__ARCZIP_NO_PASSWORD__") }
                args.append("--")
                args.append(workURL.path)
                args.append(archivePath)

                let res = try await ProcessCancellationController.run(
                    executableURL: bin,
                    arguments: args,
                    stdinData: stdinData
                )
                if res.exitCode != 0 {
                    throw ProZipError.corruptedArchive("7-Zip 删除条目失败：\(archivePath)")
                }

            case .renameEntry(let oldPath, let newPath):
                var args = ["rn", "-y"]
                if !hasPwd { args.append("-p__ARCZIP_NO_PASSWORD__") }
                args.append("--")
                args.append(workURL.path)
                args.append(oldPath)
                args.append(newPath)

                let res = try await ProcessCancellationController.run(
                    executableURL: bin,
                    arguments: args,
                    stdinData: stdinData
                )
                if res.exitCode != 0 {
                    throw ProZipError.corruptedArchive("7-Zip 重命名条目失败：\(oldPath) -> \(newPath)")
                }

            case .addFile(let sourceURL, let archivePath), .replaceEntry(let archivePath, let sourceURL):
                let relativePath = try ArchiveExtractionPolicy.validateRelativeArchivePath(archivePath)
                let inputDir = workDir.appendingPathComponent(".prozip-update-input-\(UUID().uuidString)", isDirectory: true)
                defer { try? fm.removeItem(at: inputDir) }
                let inputURL = inputDir.appendingPathComponent(relativePath)
                try fm.createDirectory(at: inputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: sourceURL, to: inputURL)
                var extra = ["-y"]
                if writeEncryptedHeaders { extra.append("-mhe=on") }
                var args = Self.buildCommandArguments(subcommand: "a", archivePath: workURL.path,
                                                     extraArgs: extra, hasPassword: writeEncrypted)
                args.append(relativePath)

                // An encrypted header consumes one line before the new password and confirmation.
                let writeInput = writeEncrypted
                    ? Data(String(repeating: "\(password!)\n", count: writeEncryptedHeaders ? 3 : 2).utf8)
                    : nil
                let res = try await ProcessCancellationController.run(
                    executableURL: bin,
                    arguments: args,
                    workingDirectoryURL: inputDir,
                    stdinData: writeInput
                )
                if res.exitCode != 0 {
                    throw ProZipError.corruptedArchive("7-Zip 添加条目失败：\(archivePath)")
                }

            }
        }

        if writesPayload {
            try await verifyWrittenArchive(workURL, password: writeEncrypted ? password : nil,
                                           encrypted: writeEncrypted, encryptedHeaders: writeEncryptedHeaders)
        }

        // Publish modified archive
        try Task.checkCancellation()
        if fm.fileExists(atPath: outputURL.path) {
            _ = try fm.replaceItemAt(outputURL, withItemAt: workURL, options: .usingNewMetadataOnly)
        } else {
            try fm.moveItem(at: workURL, to: outputURL)
        }
        progress(OperationProgress(phase: .completed, completedBytes: Int64(mutations.count), totalBytes: Int64(mutations.count)))
    }

    // MARK: - Private Helpers

    private static func validateConsoleWritePassword(_ password: String?) throws {
        if let password, password.utf8.contains(where: { $0 == 0 || $0 == 10 || $0 == 13 }) {
            throw ProZipError.invalidCreationProfile("7-Zip 控制台密码不能包含换行、回车或空字符")
        }
    }

    private static func isEncryptedHeaderError(_ output: String) -> Bool {
        let lower = output.lowercased()
        return lower.contains("cannot open encrypted archive") ||
            lower.contains("can not open encrypted archive") ||
            lower.contains("headers error in encrypted archive")
    }

    private static func hasConsolePasswordPrompt(_ output: String) -> Bool {
        output.split(separator: "\n").contains { $0.hasPrefix("Enter password (will not be echoed):") }
    }

    private func inspectWriteArchive(_ url: URL, password: String?) async throws
        -> (entries: [ArchiveEntry], encryptedHeaders: Bool) {
        let result = try await ProcessCancellationController.run(
            executableURL: requireBinaryURL(), arguments: ["l", "-slt", "-ba", "-sccUTF-8", "--", url.path]
        )
        if result.exitCode == 0 {
            return (parseSLTOutput(result.combinedOutputString), false)
        }
        guard Self.isEncryptedHeaderError(result.combinedOutputString) ||
                Self.hasConsolePasswordPrompt(result.combinedOutputString) else {
            throw ProZipError.corruptedArchive("7-Zip 无法验证原归档信息，退出码 \(result.exitCode)")
        }
        guard let password, !password.isEmpty else { throw ProZipError.passwordRequired(url.lastPathComponent) }
        return (try await list(url, password: password, progress: { _ in }), true)
    }

    private func testArchiveIntegrity(_ url: URL, password: String?) async throws {
        let result = try await ProcessCancellationController.run(
            executableURL: requireBinaryURL(), arguments: ["t", "-y", "--", url.path],
            stdinData: password?.isEmpty == false ? Data("\(password!)\n".utf8) : nil
        )
        guard result.exitCode == 0 else {
            let lower = result.combinedOutputString.lowercased()
            if lower.contains("wrong password") || lower.contains("encrypted") {
                throw ProZipError.wrongPassword("无法用所提供的密码验证全部加密成员，未保存更改")
            }
            throw ProZipError.corruptedArchive("7-Zip 完整性验证失败，退出码 \(result.exitCode)")
        }
    }

    private func verifyWrittenArchive(_ url: URL, password: String?, encrypted: Bool, encryptedHeaders: Bool) async throws {
        let written = try await inspectWriteArchive(url, password: password)
        guard written.encryptedHeaders == encryptedHeaders,
              written.entries.filter({ !$0.isDirectory && $0.uncompressedSize > 0 })
                .allSatisfy({ $0.isEncrypted == encrypted }) else {
            throw ProZipError.corruptedArchive("7-Zip 输出的加密状态与请求不符，未发布压缩包")
        }
        // Exit 0 alone cannot prove which password stdin selected after an unexpected EOF.
        try await testArchiveIntegrity(url, password: password)
    }

    private func parseSLTOutput(_ output: String) -> [ArchiveEntry] {
        var entries: [ArchiveEntry] = []
        let blocks = output.components(separatedBy: "\n\n")

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone.current

        for block in blocks {
            let lines = block.split(separator: "\n").map(String.init)
            var path: String?
            var size: Int64 = 0
            var packedSize: Int64 = 0
            var modified = Date()
            var isFolder = false
            var crc: UInt32 = 0
            var isEncrypted = false
            var symlinkTarget: String?
            var attributes: String = ""

            for rawLine in lines {
                let prompt = "Enter password (will not be echoed):"
                let line = rawLine.hasPrefix(prompt) ? String(rawLine.dropFirst(prompt.count)) : rawLine
                guard let eqIdx = line.firstIndex(of: "=") else { continue }
                let key = line[..<eqIdx].trimmingCharacters(in: .whitespaces)
                let val = line[line.index(after: eqIdx)...].trimmingCharacters(in: .whitespaces)

                switch key {
                case "Path":
                    path = val
                case "Size":
                    size = Int64(val) ?? 0
                case "Packed Size":
                    packedSize = Int64(val) ?? 0
                case "Folder":
                    isFolder = (val == "+")
                case "Modified":
                    dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSS"
                    if let d = dateFormatter.date(from: val) {
                        modified = d
                    } else {
                        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                        if let d = dateFormatter.date(from: val) {
                            modified = d
                        }
                    }
                case "Attributes":
                    attributes = val
                case "CRC":
                    crc = UInt32(val, radix: 16) ?? 0
                case "Encrypted":
                    isEncrypted = (val == "+")
                case "Symbolic Link":
                    symlinkTarget = val
                default:
                    break
                }
            }

            guard let itemPath = path, !itemPath.isEmpty else { continue }

            let type: EntryType
            if isFolder || attributes.contains("D") {
                type = .directory
            } else if let link = symlinkTarget, !link.isEmpty {
                type = .symlink
            } else {
                type = .file
            }

            let entry = ArchiveEntry(
                path: itemPath,
                type: type,
                uncompressedSize: size,
                compressedSize: packedSize,
                modifiedAt: modified,
                permissions: type == .directory ? 493 : 420,
                crc32: crc,
                isEncrypted: isEncrypted,
                symlinkTarget: symlinkTarget
            )
            entries.append(entry)
        }

        return entries
    }
}
