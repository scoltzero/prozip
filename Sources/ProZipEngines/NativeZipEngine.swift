import Foundation
import CoreFoundation
import zlib
import ProZipShared
import ProZipCore

// MARK: - CompressionBodyProbe (doc/03 section 6.2 & test C2)

/// Bounded in-process compression sampling probe that decides whether Deflate yields
/// a net size reduction over Store for a given payload.
public struct CompressionBodyProbe: Sendable {

    /// Determines whether Deflate compression should be used for the given data.
    ///
    /// - Parameters:
    ///   - data: Payload data to sample.
    ///   - strength: Compression strength requested by the user.
    ///   - sampleBudgetBytes: Maximum bytes to sample (default: 65,536).
    /// - Returns: `true` if Deflate yields a net size reduction; `false` otherwise.
    public static func shouldUseDeflate(
        for data: Data,
        strength: CreationProfile.Strength,
        sampleBudgetBytes: Int = 65_536
    ) -> Bool {
        if strength == .store || data.isEmpty {
            return false
        }

        let sampleSize = min(data.count, sampleBudgetBytes)
        guard sampleSize > 0 else { return false }
        let sample = data.prefix(sampleSize)

        var stream = z_stream()
        let initRet = deflateInit2_(
            &stream,
            strength.zlibLevel,
            Z_DEFLATED,
            -MAX_WBITS,
            8,
            Z_DEFAULT_STRATEGY,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initRet == Z_OK else {
            return false
        }
        defer { deflateEnd(&stream) }

        let bufferCapacity = sampleSize + 64
        var outputBuffer = [UInt8](repeating: 0, count: bufferCapacity)
        var totalCompressed = 0

        sample.withUnsafeBytes { rawIn in
            guard let inBase = rawIn.bindMemory(to: UInt8.self).baseAddress else { return }
            stream.next_in = UnsafeMutablePointer(mutating: inBase)
            stream.avail_in = uInt(sampleSize)

            outputBuffer.withUnsafeMutableBufferPointer { outBuf in
                guard let outBase = outBuf.baseAddress else { return }
                stream.next_out = outBase
                stream.avail_out = uInt(bufferCapacity)

                let status = deflate(&stream, Z_FINISH)
                if status == Z_STREAM_END || status == Z_OK {
                    totalCompressed = bufferCapacity - Int(stream.avail_out)
                } else {
                    totalCompressed = sampleSize + 1
                }
            }
        }

        // If compressed sample >= sample size (no net compression gain), use Store (method 0)!
        return totalCompressed < sampleSize
    }
}

// MARK: - CreationManifest & ManifestItem (doc/03 section 6.1 & 6.4, test C3)

public struct CreationManifestItem: Equatable, Sendable {
    public let path: String
    public let type: EntryType
    public let compressionMethod: UInt16 // 0 = Store, 8 = Deflate
    public let uncompressedSize: Int64
    public let crc32: UInt32

    public init(
        path: String,
        type: EntryType,
        compressionMethod: UInt16,
        uncompressedSize: Int64,
        crc32: UInt32
    ) {
        self.path = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.type = type
        self.compressionMethod = compressionMethod
        self.uncompressedSize = type == .directory ? 0 : uncompressedSize
        self.crc32 = type == .directory ? 0 : crc32
    }
}

public struct CreationManifest: Equatable, Sendable {
    public let items: [CreationManifestItem]

    public init(items: [CreationManifestItem]) {
        self.items = items
    }
}

// MARK: - Traditional PKWARE ZipCrypto Cipher (tests D1, D2)

/// Standard 3-key PKWARE stream cipher implementation for traditional ZIP encryption and decryption.
public struct ZipCryptoCipher: Sendable {
    public static let crcTable: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                if (c & 1) != 0 {
                    c = 0xEDB88320 ^ (c >> 1)
                } else {
                    c = c >> 1
                }
            }
            return c
        }
    }()

    private var key0: UInt32 = 0x12345678
    private var key1: UInt32 = 0x23456789
    private var key2: UInt32 = 0x34567890

    public init(password: String) {
        for b in password.utf8 {
            updateKeys(b)
        }
    }

    @inline(__always)
    private mutating func crc32Byte(_ b: UInt8, _ crc: UInt32) -> UInt32 {
        (crc >> 8) ^ Self.crcTable[Int((crc ^ UInt32(b)) & 0xFF)]
    }

    @inline(__always)
    private mutating func updateKeys(_ b: UInt8) {
        key0 = crc32Byte(b, key0)
        key1 = (key1 &+ (key0 & 0xFF)) &* 134775813 &+ 1
        key2 = crc32Byte(UInt8((key1 >> 24) & 0xFF), key2)
    }

    @inline(__always)
    public mutating func decryptByte(_ c: UInt8) -> UInt8 {
        let k = key2 | 2
        let plain = c ^ UInt8(((k &* (k ^ 1)) >> 8) & 0xFF)
        updateKeys(plain)
        return plain
    }

    @inline(__always)
    public mutating func encryptByte(_ p: UInt8) -> UInt8 {
        let k = key2 | 2
        let cipher = p ^ UInt8(((k &* (k ^ 1)) >> 8) & 0xFF)
        updateKeys(p)
        return cipher
    }

    public mutating func decryptData(_ data: Data) -> Data {
        var result = Data(count: data.count)
        result.withUnsafeMutableBytes { outBuf in
            guard let outPtr = outBuf.bindMemory(to: UInt8.self).baseAddress else { return }
            data.withUnsafeBytes { inBuf in
                guard let inPtr = inBuf.bindMemory(to: UInt8.self).baseAddress else { return }
                for i in 0..<data.count {
                    outPtr[i] = decryptByte(inPtr[i])
                }
            }
        }
        return result
    }

    public mutating func encryptData(_ data: Data) -> Data {
        var result = Data(count: data.count)
        result.withUnsafeMutableBytes { outBuf in
            guard let outPtr = outBuf.bindMemory(to: UInt8.self).baseAddress else { return }
            data.withUnsafeBytes { inBuf in
                guard let inPtr = inBuf.bindMemory(to: UInt8.self).baseAddress else { return }
                for i in 0..<data.count {
                    outPtr[i] = encryptByte(inPtr[i])
                }
            }
        }
        return result
    }
}

// MARK: - NativeZipEngine (ArchiveEngine)

/// High-performance, memory-safe, pure Swift ZIP engine using system zlib.
/// Supports ZIP creation, browsing, member streaming, extraction, in-place mutation,
/// and ZipCrypto encryption/decryption with full structural verification.
public struct NativeZipEngine: ArchiveEngine {

    public static var capabilities: EngineCapabilities {
        EngineCapabilities(
            read: [.zip, .jar, .apk],
            write: [.zip],
            edit: [.zip],
            encryptedRead: true,
            encryptedWrite: true,
            headerEncryption: false,
            split: true,
            streamingMemberRead: true
        )
    }

    public var engineName: String { "NativeZipEngine" }

    public init() {}

    // MARK: - Internal Record Structures

    struct CentralDirectoryEntry {
        var versionMadeBy: UInt16
        var versionNeeded: UInt16
        var flags: UInt16
        var compressionMethod: UInt16
        var modTime: UInt16
        var modDate: UInt16
        var crc32: UInt32
        var compressedSize: Int64
        var uncompressedSize: Int64
        var diskNumberStart: UInt16
        var internalAttributes: UInt16
        var externalAttributes: UInt32
        var localHeaderOffset: Int64
        var fileNameData: Data
        var fileName: String
        var extraFieldData: Data
        var commentData: Data
        var comment: String
        var hasNonUTF8: Bool
        var detectedEncoding: String
        var symlinkTarget: String?
    }

    struct ParsedCentralDirectory {
        var entries: [CentralDirectoryEntry]
        var totalCompressedSize: Int64
        var isSplitVolume: Bool
        var isConcatenated: Bool
        var hasNonUTF8Encoding: Bool
        var detectedEncodingName: String?
        var comment: String?
    }

    // MARK: - Archive Verification (test C3)

    /// Re-reads the written ZIP file's Central Directory from disk and verifies structural integrity
    /// against the expected creation manifest.
    public static func verifyArchive(at url: URL, against manifest: CreationManifest) throws {
        let engine = NativeZipEngine()
        let parsed = try engine.parseCentralDirectory(at: url, readSymlinkTargets: false)

        // 1. Check entry count
        if parsed.entries.count != manifest.items.count {
            throw ProZipError.verificationFailed(
                "ZIP 中央目录项目数不一致（清单 \(manifest.items.count)，中央目录 \(parsed.entries.count)）"
            )
        }

        // 2. Index manifest by normalized path
        var manifestMap: [String: CreationManifestItem] = [:]
        for item in manifest.items {
            manifestMap[item.path] = item
        }

        // 3. Verify each entry in Central Directory
        for actual in parsed.entries {
            let normalizedActualPath = actual.fileName.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard let expected = manifestMap[normalizedActualPath] else {
                throw ProZipError.verificationFailed("ZIP 结构验证发现计划外项目：\(actual.fileName)")
            }

            let actualType = engine.determineEntryType(
                externalAttributes: actual.externalAttributes,
                fileName: actual.fileName
            )

            if actualType != expected.type {
                throw ProZipError.verificationFailed("ZIP 结构验证与 Creation Manifest 不一致：\(actual.fileName) 类型不匹配")
            }

            if actual.compressionMethod != expected.compressionMethod {
                let expName = expected.compressionMethod == 0 ? "Store" : "Deflate"
                throw ProZipError.verificationFailed("ZIP 方法验证不一致，应为 \(expName)：\(actual.fileName)")
            }

            if actual.uncompressedSize != expected.uncompressedSize {
                throw ProZipError.verificationFailed("ZIP 结构验证与 Creation Manifest 不一致：\(actual.fileName) 大小不匹配")
            }

            if actualType != .directory && actual.crc32 != expected.crc32 {
                throw ProZipError.verificationFailed("ZIP 结构验证与 Creation Manifest 不一致：\(actual.fileName) CRC32 不匹配")
            }
        }
    }

    // MARK: - ArchiveEngine: probe

    public func probe(_ url: URL) async throws -> ArchiveDescriptor {
        let parsed = try parseCentralDirectory(at: url, readSymlinkTargets: false)
        let isEncrypted = parsed.entries.contains { ($0.flags & 1) != 0 || $0.compressionMethod == 99 }

        let format = ArchiveFormat.detect(from: url)
        let effectiveFormat = format.isZipFamily ? format : .zip

        return ArchiveDescriptor(
            url: url,
            primaryVolumeURL: url,
            volumeURLs: [url],
            format: effectiveFormat,
            isEncrypted: isEncrypted,
            hasEncryptedHeaders: false,
            isSplitVolume: parsed.isSplitVolume,
            isConcatenated: parsed.isConcatenated,
            hasNonUTF8Encoding: parsed.hasNonUTF8Encoding,
            detectedEncodingName: parsed.detectedEncodingName ?? "UTF-8",
            totalCompressedSize: parsed.totalCompressedSize,
            entryCountHint: parsed.entries.count,
            comment: parsed.comment
        )
    }

    // MARK: - ArchiveEngine: list

    public func list(
        _ url: URL,
        password: String?,
        progress: @escaping ProgressSink
    ) async throws -> [ArchiveEntry] {
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }

        let fileSize = Int64(fileHandle.seekToEndOfFile())
        progress(OperationProgress(phase: .indexing, completedBytes: 0, totalBytes: fileSize))

        let parsed = try parseCentralDirectory(at: url, readSymlinkTargets: true, fileHandle: fileHandle)

        var entries: [ArchiveEntry] = []
        entries.reserveCapacity(parsed.entries.count)

        for item in parsed.entries {
            let normalizedPath = item.fileName.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let type = determineEntryType(externalAttributes: item.externalAttributes, fileName: item.fileName)
            let perms = determinePermissions(externalAttributes: item.externalAttributes, type: type)
            let modDate = date(fromDosTime: item.modTime, dosDate: item.modDate)
            let isEncrypted = (item.flags & 1) != 0 || item.compressionMethod == 99

            let entry = ArchiveEntry(
                path: normalizedPath,
                type: type,
                uncompressedSize: type == .directory ? 0 : item.uncompressedSize,
                compressedSize: type == .directory ? 0 : item.compressedSize,
                modifiedAt: modDate,
                permissions: perms,
                crc32: type == .directory ? 0 : item.crc32,
                isEncrypted: isEncrypted,
                symlinkTarget: item.symlinkTarget
            )
            entries.append(entry)
        }

        // Sort: directories first, then alphabetical case-insensitive (doc/02 & test A1)
        entries.sort { a, b in
            if a.isDirectory != b.isDirectory {
                return a.isDirectory && !b.isDirectory
            }
            let comp = a.path.localizedStandardCompare(b.path)
            if comp != .orderedSame {
                return comp == .orderedAscending
            }
            return a.path < b.path
        }

        progress(OperationProgress(phase: .completed, completedBytes: fileSize, totalBytes: fileSize))
        return entries
    }

    // MARK: - ArchiveEngine: openMember

    public func openMember(
        _ entry: ArchiveEntry,
        in url: URL,
        password: String?,
        range: Range<Int64>?
    ) async throws -> AsyncThrowingStream<Data, Error> {
        try Task.checkCancellation()
        try await MemberReadBudgetLimiter.shared.acquire(requestedBytes: entry.uncompressedSize)
        var input: FileHandle?
        do {
            try Task.checkCancellation()
            let handle = try FileHandle(forReadingFrom: url)
            input = handle
            let parsed = try parseCentralDirectory(at: url, readSymlinkTargets: false, fileHandle: handle)
            let path = entry.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard let item = parsed.entries.first(where: { $0.fileName.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == path }) else {
                throw ProZipError.corruptedArchive("未在压缩包中找到项目：\(entry.path)")
            }
            let reader = try MemberReader(input: handle, item: item, password: password, range: range)
            return AsyncThrowingStream(unfolding: {
                try await withTaskCancellationHandler {
                    try await reader.next()
                } onCancel: {
                    Task { await reader.close() }
                }
            })
        } catch {
            try? input?.close()
            await MemberReadBudgetLimiter.shared.release()
            throw error
        }
    }

    /// Each pull produces at most 64 KiB. A partial range deliberately does not verify the whole member's CRC.
    private actor MemberReader {
        private let input: FileHandle
        private let item: CentralDirectoryEntry
        private var cipher: ZipCryptoCipher?
        private var inflater: UnsafeMutablePointer<z_stream>?
        private var compressedRemaining: Int64 = 0
        private var compressedBuffer = Data()
        private var compressedOffset = 0
        private var outputOffset: Int64 = 0
        private var lowerBound: Int64 = 0
        private var upperBound: Int64 = 0
        private var verifiesWholeMember = false
        private var checksum: UInt32 = 0
        private var finished = false
        private var closed = false
        private var ownsBudget = false

        init(input: FileHandle, item: CentralDirectoryEntry, password: String?, range: Range<Int64>?) throws {
            self.input = input
            self.item = item
            guard item.compressedSize >= 0, item.uncompressedSize >= 0,
                  item.compressedSize <= ProcessCancellationController.maxBinaryOutputBytes,
                  item.uncompressedSize <= ProcessCancellationController.maxBinaryOutputBytes else {
                throw ProZipError.outputExceedsBudget("原生 ZIP 项目预算为 512 MiB，请使用兼容引擎处理此项目")
            }
            guard let fileSize = Int64(exactly: try input.seekToEnd()), fileSize >= 30,
                  item.localHeaderOffset >= 0, item.localHeaderOffset <= fileSize - 30 else {
                throw ProZipError.corruptedArchive("本地文件头偏移无效：\(item.fileName)")
            }
            try input.seek(toOffset: UInt64(item.localHeaderOffset))
            let header = try NativeZipEngine.readMemberBytes(30, from: input, name: item.fileName)
            guard header.readUInt32(at: 0) == 0x04034b50 else { throw ProZipError.corruptedArchive("本地文件头签名不匹配：\(item.fileName)") }
            let variableSize = Int64(header.readUInt16(at: 26)) + Int64(header.readUInt16(at: 28))
            guard variableSize <= fileSize - item.localHeaderOffset - 30 else { throw ProZipError.corruptedArchive("本地文件头截断：\(item.fileName)") }
            let payloadOffset = item.localHeaderOffset + 30 + variableSize
            guard item.compressedSize <= fileSize - payloadOffset else { throw ProZipError.corruptedArchive("文件数据截断：\(item.fileName)") }
            try input.seek(toOffset: UInt64(payloadOffset))
            compressedRemaining = item.compressedSize

            let encrypted = (item.flags & 1) != 0 || item.compressionMethod == 99
            if encrypted {
                guard let password, !password.isEmpty else { throw ProZipError.passwordRequired(item.fileName) }
                guard compressedRemaining >= 12 else { throw ProZipError.corruptedArchive("加密头截断：\(item.fileName)") }
                var cipher = ZipCryptoCipher(password: password)
                let encryptedHeader = try NativeZipEngine.readMemberBytes(12, from: input, name: item.fileName)
                let checkByte = cipher.decryptData(encryptedHeader)[11]
                let crcCheck = UInt8((item.crc32 >> 24) & 0xff)
                let dosCheck = UInt8((item.modTime >> 8) & 0xff)
                guard checkByte == crcCheck || checkByte == dosCheck else { throw ProZipError.wrongPassword("密码错误") }
                self.cipher = cipher
                compressedRemaining -= 12
            }

            let lower = max(0, min(range?.lowerBound ?? 0, item.uncompressedSize))
            let upper = max(lower, min(range?.upperBound ?? item.uncompressedSize, item.uncompressedSize))
            let wholeMember = lower == 0 && upper == item.uncompressedSize
            lowerBound = lower
            upperBound = upper
            verifiesWholeMember = wholeMember
            switch item.compressionMethod {
            case 0:
                guard compressedRemaining == item.uncompressedSize else { throw ProZipError.corruptedArchive("解压大小不匹配：\(item.fileName)") }
                if !encrypted && !wholeMember {
                    try input.seek(toOffset: UInt64(payloadOffset + lower))
                    compressedRemaining -= lower
                    outputOffset = lower
                }
            case 8:
                let stream = UnsafeMutablePointer<z_stream>.allocate(capacity: 1)
                stream.initialize(to: z_stream())
                let status = inflateInit2_(stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
                guard status == Z_OK else {
                    stream.deinitialize(count: 1)
                    stream.deallocate()
                    throw ProZipError.corruptedArchive("Inflate 初始化失败 (\(status))")
                }
                inflater = stream
            case 99:
                throw ProZipError.corruptedArchive("此 ZIP 的压缩方法（AES-99）需要使用兼容引擎")
            default:
                throw ProZipError.corruptedArchive("不支持的压缩方法 (\(item.compressionMethod))：\(item.fileName)")
            }
            ownsBudget = true
        }

        func next() async throws -> Data? {
            guard !closed else { return nil }
            do {
                try Task.checkCancellation()
                if lowerBound == upperBound && !verifiesWholeMember {
                    await close()
                    return nil
                }
                while outputOffset < upperBound {
                    let start = outputOffset
                    let block = try readOutput(maximumCount: Int(min(65_536, upperBound - start)))
                    outputOffset += Int64(block.count)
                    guard outputOffset <= item.uncompressedSize, !finished || outputOffset == item.uncompressedSize else {
                        throw ProZipError.corruptedArchive("解压大小不匹配：\(item.fileName)")
                    }
                    if verifiesWholeMember {
                        checksum = block.withUnsafeBytes { bytes in
                            UInt32(zlib.crc32(uLong(checksum), bytes.bindMemory(to: UInt8.self).baseAddress, uInt(block.count)))
                        }
                    }
                    let selected = outputOffset > lowerBound ? block.subdata(in: Int(max(0, lowerBound - start))..<block.count) : Data()
                    if outputOffset == upperBound {
                        if verifiesWholeMember { try verifyEnd() }
                        await close()
                    }
                    if !selected.isEmpty { return selected }
                }
                if verifiesWholeMember { try verifyEnd() }
                await close()
                return nil
            } catch {
                await close()
                throw error
            }
        }

        private func readCompressed(_ count: Int) throws -> Data {
            var data = try NativeZipEngine.readMemberBytes(count, from: input, name: item.fileName)
            compressedRemaining -= Int64(data.count)
            if var cipher {
                data = cipher.decryptData(data)
                self.cipher = cipher
            }
            return data
        }

        private func readOutput(maximumCount: Int) throws -> Data {
            try Task.checkCancellation()
            if item.compressionMethod == 0 {
                let count = Int(min(Int64(maximumCount), compressedRemaining))
                let block = try readCompressed(count)
                finished = compressedRemaining == 0
                return block
            }
            guard let stream = inflater else { throw ProZipError.corruptedArchive("Inflate 状态已关闭") }
            var output = Data(count: maximumCount)
            var written = 0
            while written == 0 && !finished {
                try Task.checkCancellation()
                if compressedOffset == compressedBuffer.count && compressedRemaining > 0 {
                    compressedBuffer = try readCompressed(Int(min(65_536, compressedRemaining)))
                    compressedOffset = 0
                }
                var consumed = 0
                let status = compressedBuffer.withUnsafeBytes { source in
                    output.withUnsafeMutableBytes { destination in
                        let available = compressedBuffer.count - compressedOffset
                        stream.pointee.next_in = source.bindMemory(to: UInt8.self).baseAddress.map { UnsafeMutablePointer(mutating: $0.advanced(by: compressedOffset)) }
                        stream.pointee.avail_in = uInt(available)
                        stream.pointee.next_out = destination.bindMemory(to: UInt8.self).baseAddress
                        stream.pointee.avail_out = uInt(maximumCount)
                        let status = inflate(stream, Z_NO_FLUSH)
                        consumed = available - Int(stream.pointee.avail_in)
                        written = maximumCount - Int(stream.pointee.avail_out)
                        stream.pointee.next_in = nil
                        stream.pointee.next_out = nil
                        return status
                    }
                }
                compressedOffset += consumed
                if status == Z_STREAM_END {
                    finished = true
                } else if status != Z_OK && status != Z_BUF_ERROR {
                    throw ProZipError.corruptedArchive("Inflate 解压未正常结束 (\(status))：\(item.fileName)")
                } else if consumed == 0 && written == 0 {
                    throw ProZipError.corruptedArchive("Deflate 数据截断或损坏：\(item.fileName)")
                }
            }
            output.count = written
            return output
        }

        private func verifyEnd() throws {
            while !finished {
                guard try readOutput(maximumCount: 1).isEmpty else { throw ProZipError.corruptedArchive("解压内容超过 ZIP 目录记录的项目大小") }
            }
            guard outputOffset == item.uncompressedSize else { throw ProZipError.corruptedArchive("解压大小不匹配：\(item.fileName)") }
            guard checksum == item.crc32 else {
                if (item.flags & 1) != 0 { throw ProZipError.wrongPassword("密码错误") }
                throw ProZipError.corruptedArchive("CRC32 校验失败：\(item.fileName)")
            }
        }

        func close() async {
            guard !closed else { return }
            closed = true
            try? input.close()
            if let inflater {
                inflateEnd(inflater)
                inflater.deinitialize(count: 1)
                inflater.deallocate()
                self.inflater = nil
            }
            compressedBuffer = Data()
            if ownsBudget {
                ownsBudget = false
                await MemberReadBudgetLimiter.shared.release()
            }
        }

        deinit {
            if !closed { try? input.close() }
            if let inflater {
                inflateEnd(inflater)
                inflater.deinitialize(count: 1)
                inflater.deallocate()
            }
            if ownsBudget { Task { await MemberReadBudgetLimiter.shared.release() } }
        }
    }

    private static func readMemberBytes(_ count: Int, from input: FileHandle, name: String) throws -> Data {
        var data = Data()
        data.reserveCapacity(count)
        while data.count < count {
            try Task.checkCancellation()
            guard let chunk = try input.read(upToCount: count - data.count), !chunk.isEmpty else {
                throw ProZipError.corruptedArchive("文件数据截断：\(name)")
            }
            data.append(chunk)
        }
        return data
    }

    // MARK: - ArchiveEngine: extract

    public func extract(
        _ entries: [ArchiveEntry],
        from url: URL,
        to dir: URL,
        password: String?,
        options: ExtractionOptions,
        progress: @escaping ProgressSink
    ) async throws -> ExtractionReport {
        let plan = try ArchiveExtractionPolicy.buildPlan(
            entries: entries,
            archiveURL: url,
            destinationURL: dir,
            options: options
        )
        guard !plan.itemsToExtract.contains(where: {
            $0.entry.type == .file && ($0.entry.uncompressedSize > ProcessCancellationController.maxBinaryOutputBytes ||
                $0.entry.compressedSize > ProcessCancellationController.maxBinaryOutputBytes)
        }) else {
            throw ProZipError.outputExceedsBudget("原生 ZIP 内存预算为 512 MiB，请使用兼容引擎解压")
        }

        let fileManager = FileManager.default
        let sessionID = UUID().uuidString
        let stagingDir = dir.deletingLastPathComponent()
            .appendingPathComponent("prozip-extract-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        let stagingArtifactID = try? await ManagedTemporaryArtifactRegistry.shared.registerArtifact(
            at: stagingDir,
            purpose: .streamExtraction,
            sessionID: sessionID
        )
        defer {
            if let aid = stagingArtifactID {
                try? await ManagedTemporaryArtifactRegistry.shared.safelyRemoveArtifact(artifactID: aid)
            }
            try? fileManager.removeItem(at: stagingDir)
        }

        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }

        let parsed = try parseCentralDirectory(at: url, readSymlinkTargets: false, fileHandle: fileHandle)
        var cdMap: [String: CentralDirectoryEntry] = [:]
        for item in parsed.entries {
            cdMap[item.fileName.trimmingCharacters(in: CharacterSet(charactersIn: "/"))] = item
        }

        let totalBytes = plan.itemsToExtract.reduce(Int64(0)) { $0 + $1.entry.uncompressedSize }
        var completedBytes: Int64 = 0
        var extractedCount = 0
        var skippedCount = plan.skippedEntries.count
        var failedCount = 0
        var extractedURLs: [URL] = []
        var skippedReasons: [String] = plan.skippedEntries.map(\.reason)
        var errors: [String] = []

        progress(OperationProgress(phase: .preparing, completedBytes: 0, totalBytes: totalBytes))

        for plannedItem in plan.itemsToExtract {
            if Task.isCancelled {
                throw ProZipError.cancelled
            }

            let entry = plannedItem.entry
            let stagedItemURL = stagingDir.appendingPathComponent(plannedItem.relativeOutputPath)
            progress(OperationProgress(
                phase: .extracting,
                completedBytes: completedBytes,
                totalBytes: totalBytes,
                currentItem: entry.name
            ))

            switch entry.type {
            case .directory:
                do {
                    try fileManager.createDirectory(at: stagedItemURL, withIntermediateDirectories: true)
                    extractedCount += 1
                } catch {
                    errors.append("\(entry.path): \(error.localizedDescription)")
                    failedCount += 1
                }

            case .symlink:
                do {
                    guard let symTarget = entry.symlinkTarget ?? cdMap[entry.path]?.symlinkTarget else {
                        throw ProZipError.corruptedArchive("符号链接缺少目标路径：\(entry.path)")
                    }
                    try ArchiveExtractionPolicy.validateSymlinkTarget(
                        linkDestinationURL: plannedItem.destinationURL,
                        targetPath: symTarget,
                        extractionRootURL: plan.rootDestinationURL
                    )
                    let parent = stagedItemURL.deletingLastPathComponent()
                    try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
                    try fileManager.createSymbolicLink(atPath: stagedItemURL.path, withDestinationPath: symTarget)
                    extractedCount += 1
                } catch {
                    errors.append("\(entry.path): \(error.localizedDescription)")
                    failedCount += 1
                    skippedCount += 1
                    skippedReasons.append("\(entry.path): \(error.localizedDescription)")
                }

            case .special:
                // Special files (FIFO, sockets, device nodes) skipped per test B7
                skippedCount += 1
                skippedReasons.append("特殊文件默认不解压：\(entry.path)")

            case .file:
                do {
                    guard let cdItem = cdMap[entry.path] else {
                        throw ProZipError.corruptedArchive("未在中央目录中找到文件数据：\(entry.path)")
                    }
                    let data = try readAndDecompressEntry(cdItem: cdItem, fileHandle: fileHandle, password: password)
                    let parent = stagedItemURL.deletingLastPathComponent()
                    try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
                    try data.write(to: stagedItemURL, options: .atomic)
                    extractedCount += 1
                    completedBytes += entry.uncompressedSize
                } catch {
                    failedCount += 1
                    skippedCount += 1
                    let desc = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    errors.append("\(entry.path): \(desc)")
                    skippedReasons.append("\(entry.path): \(desc)")
                }
            }
        }

        // If all items failed, rethrow the fatal error!
        if extractedCount == 0 && !errors.isEmpty {
            if let firstErr = errors.first {
                if firstErr.contains("密码错误") {
                    throw ProZipError.wrongPassword("密码错误")
                } else if firstErr.contains("受密码保护") {
                    throw ProZipError.passwordRequired("密码保护")
                } else {
                    throw ProZipError.corruptedArchive(firstErr)
                }
            }
        }

        // Publish from staging directory to destinationURL
        progress(OperationProgress(phase: .savingSafely, completedBytes: completedBytes, totalBytes: totalBytes))
        try fileManager.createDirectory(at: plan.rootDestinationURL, withIntermediateDirectories: true)

        for plannedItem in plan.itemsToExtract {
            try Task.checkCancellation()
            let stagedItemURL = stagingDir.appendingPathComponent(plannedItem.relativeOutputPath)
            guard (try? fileManager.attributesOfItem(atPath: stagedItemURL.path)) != nil else { continue }

            var destURL = plannedItem.destinationURL
            let destParent = destURL.deletingLastPathComponent()
            try ArchiveExtractionPolicy.validateDestinationDirectory(plannedItem.entry.isDirectory ? destURL : destParent)
            try fileManager.createDirectory(at: destParent, withIntermediateDirectories: true)

            if plannedItem.entry.isDirectory {
                try fileManager.createDirectory(at: destURL, withIntermediateDirectories: true)
                extractedURLs.append(destURL)
                continue
            }

            var alreadyPublished = false
            switch plannedItem.conflictAction {
            case .skip:
                if fileManager.fileExists(atPath: destURL.path) {
                    continue
                }
            case .replace:
                if fileManager.fileExists(atPath: destURL.path) {
                    _ = try fileManager.replaceItemAt(destURL, withItemAt: stagedItemURL, options: .usingNewMetadataOnly)
                    alreadyPublished = true
                }
            case .keepBoth:
                if fileManager.fileExists(atPath: destURL.path) {
                    destURL = autoNumberedDestinationURL(for: destURL)
                }
            case .ask:
                if fileManager.fileExists(atPath: destURL.path) {
                    throw ProZipError.structureConflict("目标文件已存在，需要选择如何处理：\(destURL.path)")
                }
            }

            if !alreadyPublished {
                try fileManager.moveItem(at: stagedItemURL, to: destURL)
            }

            if options.preservePermissions && plannedItem.entry.type != .symlink {
                try? fileManager.setAttributes([
                    .posixPermissions: plannedItem.entry.permissions,
                    .modificationDate: plannedItem.entry.modifiedAt
                ], ofItemAtPath: destURL.path)
            }

            extractedURLs.append(destURL)
        }

        progress(OperationProgress(phase: .completed, completedBytes: completedBytes, totalBytes: totalBytes))
        return ExtractionReport(
            destinationURL: plan.rootDestinationURL,
            extractedCount: extractedCount,
            skippedCount: skippedCount,
            failedCount: failedCount,
            extractedURLs: extractedURLs,
            skippedReasons: skippedReasons,
            errors: errors
        )
    }

    // MARK: - ArchiveEngine: create

    public func create(
        sources: [URL],
        at url: URL,
        profile: CreationProfile,
        password: String?,
        progress: @escaping ProgressSink
    ) async throws {
        try profile.validate()
        let existingOutputs = try SplitArchivePublication.existingItems(baseURL: url)
        if profile.split != nil || existingOutputs.contains(where: { $0.lastPathComponent.caseInsensitiveCompare(url.lastPathComponent) != .orderedSame }) {
            try SplitArchivePublication.ensureAvailable(baseURL: url)
        }

        let effectivePassword = (profile.password?.isEmpty == false) ? profile.password : password
        if let pwd = effectivePassword, !pwd.isEmpty {
            let isASCII = pwd.unicodeScalars.allSatisfy { $0.isASCII }
            guard isASCII else {
                throw ProZipError.invalidCreationProfile("为保证跨平台可解压，创建 ZIP 时密码仅支持 ASCII。中文密码请使用 7Z")
            }
        }

        progress(OperationProgress(phase: .preparing, completedBytes: 0, totalBytes: 0))

        // Collect items to archive
        let collectedItems = try collectSourceItems(
            sources: sources,
            preserveMacMetadata: profile.preserveMacMetadata,
            repairWindowsNames: profile.repairWindowsNames
        )

        // Read payloads, probe with CompressionBodyProbe, build Manifest
        var itemsWithPayload: [ZipEntryPayload] = []
        var manifestItems: [CreationManifestItem] = []
        var totalUncompressedBytes: Int64 = 0

        for item in collectedItems {
            try Task.checkCancellation()
            switch item.type {
            case .directory:
                itemsWithPayload.append(ZipEntryPayload(
                    path: item.archivePath,
                    type: .directory,
                    data: Data(),
                    method: 0,
                    crc32: 0,
                    uncompressedSize: 0,
                    modifiedAt: item.modifiedAt,
                    permissions: item.permissions,
                    symlinkTarget: nil
                ))
                manifestItems.append(CreationManifestItem(
                    path: item.archivePath,
                    type: .directory,
                    compressionMethod: 0,
                    uncompressedSize: 0,
                    crc32: 0
                ))

            case .symlink:
                let target = item.symlinkTarget ?? ""
                let targetData = Data(target.utf8)
                let crc = computeCRC32(for: targetData)
                itemsWithPayload.append(ZipEntryPayload(
                    path: item.archivePath,
                    type: .symlink,
                    data: targetData,
                    method: 0,
                    crc32: crc,
                    uncompressedSize: Int64(targetData.count),
                    modifiedAt: item.modifiedAt,
                    permissions: item.permissions,
                    symlinkTarget: target
                ))
                manifestItems.append(CreationManifestItem(
                    path: item.archivePath,
                    type: .symlink,
                    compressionMethod: 0,
                    uncompressedSize: Int64(targetData.count),
                    crc32: crc
                ))
                totalUncompressedBytes += Int64(targetData.count)

            case .file:
                guard let sourceURL = item.sourceURL else { continue }
                let fileData = try readSourceData(at: sourceURL, remainingBudget: ProcessCancellationController.maxBinaryOutputBytes - totalUncompressedBytes)
                let crc = computeCRC32(for: fileData)
                let useDeflate = CompressionBodyProbe.shouldUseDeflate(for: fileData, strength: profile.strength)
                let method: UInt16 = useDeflate ? 8 : 0

                itemsWithPayload.append(ZipEntryPayload(
                    path: item.archivePath,
                    type: .file,
                    data: fileData,
                    method: method,
                    crc32: crc,
                    uncompressedSize: Int64(fileData.count),
                    modifiedAt: item.modifiedAt,
                    permissions: item.permissions,
                    symlinkTarget: nil
                ))
                manifestItems.append(CreationManifestItem(
                    path: item.archivePath,
                    type: .file,
                    compressionMethod: method,
                    uncompressedSize: Int64(fileData.count),
                    crc32: crc
                ))
                totalUncompressedBytes += Int64(fileData.count)

            case .special:
                continue
            }
        }

        let manifest = CreationManifest(items: manifestItems)
        let totalBytesToRecord = totalUncompressedBytes
        let payloadsToWrite = itemsWithPayload
        let profileStrength = profile.strength

        // Handle split volumes vs atomic single archive
        if let split = profile.split {
            try await writeSplitArchive(
                items: itemsWithPayload,
                manifest: manifest,
                targetURL: url,
                splitPlan: split,
                password: effectivePassword,
                strength: profile.strength,
                progress: progress
            )
        } else {
            let targetDir = url.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: targetDir.path) {
                try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
            }

            _ = try await ManagedTemporaryArtifactRegistry.shared.publishAtomically(
                targetURL: url,
                allowOverwrite: true,
                writer: { partialURL in
                    progress(OperationProgress(
                        phase: .compressing,
                        completedBytes: 0,
                        totalBytes: totalBytesToRecord
                    ))
                    try self.writeZipArchive(
                        items: payloadsToWrite,
                        password: effectivePassword,
                        strength: profileStrength,
                        to: partialURL,
                        progress: progress
                    )
                },
                verifier: { partialURL in
                    progress(OperationProgress(
                        phase: .verifying,
                        completedBytes: totalBytesToRecord,
                        totalBytes: totalBytesToRecord
                    ))
                    try Self.verifyArchive(at: partialURL, against: manifest)
                }
            )

            progress(OperationProgress(
                phase: .completed,
                completedBytes: totalBytesToRecord,
                totalBytes: totalBytesToRecord
            ))
        }
    }

    // MARK: - ArchiveEngine: applyMutations (doc/07 & test E1..E7)

    public func applyMutations(
        _ mutations: [ArchiveMutation],
        to sourceURL: URL,
        outputURL: URL,
        profile: CreationProfile,
        password: String?,
        progress: @escaping ProgressSink
    ) async throws {
        let desc = try await probe(sourceURL)
        let eligibility = desc.editingEligibility
        guard eligibility.allowed else {
            throw ProZipError.editingNotSupported(eligibility.reason ?? "当前压缩包不支持编辑保存")
        }

        let currentEntries = try await list(sourceURL, password: password, progress: progress)

        // Working mutable map: normalized archive path -> MutableEntryState
        var entryMap: [String: MutableEntryState] = [:]
        for entry in currentEntries {
            entryMap[entry.path] = .existing(entry)
        }

        // Apply mutations in order
        for mutation in mutations {
            switch mutation {
            case .deleteEntry(let archivePath):
                let norm = try ArchiveExtractionPolicy.validateRelativeArchivePath(archivePath)
                entryMap.removeValue(forKey: norm)
                // Remove recursive children if directory
                let prefix = norm + "/"
                entryMap = entryMap.filter { !$0.key.hasPrefix(prefix) }

            case .renameEntry(let oldArchivePath, let newArchivePath):
                let oldNorm = try ArchiveExtractionPolicy.validateRelativeArchivePath(oldArchivePath)
                let newNorm = try ArchiveExtractionPolicy.validateRelativeArchivePath(newArchivePath)
                let oldPrefix = oldNorm + "/"
                let subtree = entryMap.filter { $0.key == oldNorm || $0.key.hasPrefix(oldPrefix) }
                for key in subtree.keys {
                    entryMap.removeValue(forKey: key)
                }
                for (key, state) in subtree {
                    entryMap[newNorm + key.dropFirst(oldNorm.count)] = state
                }

            case .addFile(let sourceURL, let archivePath), .replaceEntry(let archivePath, let sourceURL):
                let norm = try ArchiveExtractionPolicy.validateRelativeArchivePath(archivePath)
                let items = try collectSourceItems(
                    sources: [sourceURL],
                    preserveMacMetadata: profile.preserveMacMetadata,
                    repairWindowsNames: profile.repairWindowsNames
                )
                guard let rootPath = items.first?.archivePath else { continue }
                if case .replaceEntry = mutation {
                    entryMap = entryMap.filter { $0.key != norm && !$0.key.hasPrefix(norm + "/") }
                }
                for item in items {
                    let path = norm + item.archivePath.dropFirst(rootPath.count)
                    if item.type != .directory {
                        entryMap = entryMap.filter { !$0.key.hasPrefix(path + "/") }
                    }
                    entryMap[path] = .source(item)
                }
            }
        }

        // Build target entries payload
        var targetPayloads: [ZipEntryPayload] = []
        var manifestItems: [CreationManifestItem] = []
        var totalBytes: Int64 = 0

        // Read source central directory for raw copies
        let sourceFileHandle = try FileHandle(forReadingFrom: sourceURL)
        defer { try? sourceFileHandle.close() }
        let sourceParsed = try parseCentralDirectory(at: sourceURL, readSymlinkTargets: true, fileHandle: sourceFileHandle)
        var sourceCDMap: [String: CentralDirectoryEntry] = [:]
        for item in sourceParsed.entries {
            sourceCDMap[item.fileName.trimmingCharacters(in: CharacterSet(charactersIn: "/"))] = item
        }

        for (path, state) in entryMap {
            try Task.checkCancellation()
            switch state {
            case .existing(let oldEntry):
                guard oldEntry.uncompressedSize <= ProcessCancellationController.maxBinaryOutputBytes - totalBytes else {
                    throw ProZipError.outputExceedsBudget("原生 ZIP 编辑内存预算为 512 MiB")
                }
                guard let cdItem = sourceCDMap[oldEntry.path] else {
                    throw ProZipError.corruptedArchive("未找到原项目数据：\(oldEntry.path)")
                }
                let data: Data
                if oldEntry.type == .file {
                    data = try readAndDecompressEntry(cdItem: cdItem, fileHandle: sourceFileHandle, password: password)
                } else if oldEntry.type == .symlink {
                    data = Data((oldEntry.symlinkTarget ?? "").utf8)
                } else {
                    data = Data()
                }

                let useDeflate = CompressionBodyProbe.shouldUseDeflate(for: data, strength: profile.strength)
                let method: UInt16 = oldEntry.type == .file ? (useDeflate ? 8 : 0) : 0
                let crc = oldEntry.type == .file ? computeCRC32(for: data) : oldEntry.crc32

                targetPayloads.append(ZipEntryPayload(
                    path: path,
                    type: oldEntry.type,
                    data: data,
                    method: method,
                    crc32: crc,
                    uncompressedSize: Int64(data.count),
                    modifiedAt: oldEntry.modifiedAt,
                    permissions: oldEntry.permissions,
                    symlinkTarget: oldEntry.symlinkTarget
                ))
                manifestItems.append(CreationManifestItem(
                    path: path,
                    type: oldEntry.type,
                    compressionMethod: method,
                    uncompressedSize: Int64(data.count),
                    crc32: crc
                ))
                totalBytes += Int64(data.count)

            case .source(let item):
                let data: Data
                switch item.type {
                case .directory:
                    data = Data()
                case .symlink:
                    data = Data((item.symlinkTarget ?? "").utf8)
                    guard Int64(data.count) <= ProcessCancellationController.maxBinaryOutputBytes - totalBytes else {
                        throw ProZipError.outputExceedsBudget("原生 ZIP 编辑内存预算为 512 MiB")
                    }
                case .file:
                    guard let sourceURL = item.sourceURL else { continue }
                    data = try readSourceData(at: sourceURL, remainingBudget: ProcessCancellationController.maxBinaryOutputBytes - totalBytes)
                case .special:
                    continue
                }
                let crc = computeCRC32(for: data)
                let useDeflate = CompressionBodyProbe.shouldUseDeflate(for: data, strength: profile.strength)
                let method: UInt16 = item.type == .file && useDeflate ? 8 : 0

                targetPayloads.append(ZipEntryPayload(
                    path: path,
                    type: item.type,
                    data: data,
                    method: method,
                    crc32: crc,
                    uncompressedSize: Int64(data.count),
                    modifiedAt: item.modifiedAt,
                    permissions: item.permissions,
                    symlinkTarget: item.symlinkTarget
                ))
                manifestItems.append(CreationManifestItem(
                    path: path,
                    type: item.type,
                    compressionMethod: method,
                    uncompressedSize: Int64(data.count),
                    crc32: crc
                ))
                totalBytes += Int64(data.count)
            }
        }

        let targetManifest = CreationManifest(items: manifestItems)
        let totalTargetBytes = totalBytes
        let payloadsToApply = targetPayloads
        let currentProfileStrength = profile.strength

        _ = try await ManagedTemporaryArtifactRegistry.shared.publishAtomically(
            targetURL: outputURL,
            allowOverwrite: true,
            writer: { partialURL in
                progress(OperationProgress(phase: .compressing, completedBytes: 0, totalBytes: totalTargetBytes))
                try self.writeZipArchive(
                    items: payloadsToApply,
                    password: password,
                    strength: currentProfileStrength,
                    to: partialURL,
                    progress: progress
                )
            },
            verifier: { partialURL in
                progress(OperationProgress(phase: .verifying, completedBytes: totalTargetBytes, totalBytes: totalTargetBytes))
                try Self.verifyArchive(at: partialURL, against: targetManifest)
            }
        )

        progress(OperationProgress(phase: .completed, completedBytes: totalTargetBytes, totalBytes: totalTargetBytes))
    }

    private enum MutableEntryState {
        case existing(ArchiveEntry)
        case source(SourceItem)
    }

    // MARK: - Internal ZIP Creation Engine

    struct ZipEntryPayload {
        let path: String
        let type: EntryType
        let data: Data
        let method: UInt16
        let crc32: UInt32
        let uncompressedSize: Int64
        let modifiedAt: Date
        let permissions: UInt16
        let symlinkTarget: String?
    }

    private func writeZipArchive(
        items: [ZipEntryPayload],
        password: String?,
        strength: CreationProfile.Strength,
        to targetURL: URL,
        progress: ProgressSink? = nil
    ) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: targetURL.path) {
            try fileManager.removeItem(at: targetURL)
        }
        fileManager.createFile(atPath: targetURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: targetURL)
        defer { try? handle.close() }

        var centralDirectoryEntries: [Data] = []
        var currentOffset: UInt64 = 0

        for item in items {
            try Task.checkCancellation()
            let normalizedPath = item.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let isDirectory = item.type == .directory
            let entryPath = isDirectory ? "\(normalizedPath)/" : normalizedPath
            let fileNameBytes = Data(entryPath.utf8)

            let (dosTime, dosDate) = Self.dosDateTime(from: item.modifiedAt)

            var compressedData: Data
            var method = item.method

            if isDirectory {
                compressedData = Data()
                method = 0
            } else if item.type == .symlink {
                compressedData = item.data
                method = 0
            } else {
                if method == 8 {
                    compressedData = try Self.deflateRaw(data: item.data, level: strength.zlibLevel)
                } else {
                    compressedData = item.data
                }
            }

            var flags: UInt16 = 1 << 11 // UTF-8 filename flag
            let isEncrypted = (password?.isEmpty == false) && item.type == .file

            if isEncrypted, let pwd = password {
                flags |= 1 // Bit 0: encryption
                var cipher = ZipCryptoCipher(password: pwd)

                // 12-byte encryption header: 11 random bytes + 1 check byte
                var encHeader = (0..<11).map { _ in UInt8.random(in: 0...255) }
                encHeader.append(UInt8((item.crc32 >> 24) & 0xFF))

                var encryptedPayload = Data()
                encryptedPayload.reserveCapacity(12 + compressedData.count)
                for b in encHeader {
                    encryptedPayload.append(cipher.encryptByte(b))
                }
                encryptedPayload.append(cipher.encryptData(compressedData))
                compressedData = encryptedPayload
            }

            let localHeaderOffset = currentOffset

            // Write Local Header
            var localHeader = Data()
            localHeader.append(contentsOf: [0x50, 0x4B, 0x03, 0x04]) // Signature
            localHeader.appendUInt16(20) // Version needed
            localHeader.appendUInt16(flags)
            localHeader.appendUInt16(method)
            localHeader.appendUInt16(dosTime)
            localHeader.appendUInt16(dosDate)
            localHeader.appendUInt32(item.crc32)
            localHeader.appendUInt32(UInt32(compressedData.count))
            localHeader.appendUInt32(UInt32(item.uncompressedSize))
            localHeader.appendUInt16(UInt16(fileNameBytes.count))
            localHeader.appendUInt16(0) // Extra field length
            localHeader.append(fileNameBytes)
            localHeader.append(compressedData)

            try handle.write(contentsOf: localHeader)
            currentOffset += UInt64(localHeader.count)

            // Construct Central Directory Record
            var cdEntry = Data()
            cdEntry.append(contentsOf: [0x50, 0x4B, 0x01, 0x02]) // Signature
            cdEntry.appendUInt16((3 << 8) | 20) // Version made by (UNIX 2.0)
            cdEntry.appendUInt16(20) // Version needed
            cdEntry.appendUInt16(flags)
            cdEntry.appendUInt16(method)
            cdEntry.appendUInt16(dosTime)
            cdEntry.appendUInt16(dosDate)
            cdEntry.appendUInt32(item.crc32)
            cdEntry.appendUInt32(UInt32(compressedData.count))
            cdEntry.appendUInt32(UInt32(item.uncompressedSize))
            cdEntry.appendUInt16(UInt16(fileNameBytes.count))
            cdEntry.appendUInt16(0) // Extra field length
            cdEntry.appendUInt16(0) // Comment length
            cdEntry.appendUInt16(0) // Disk start
            cdEntry.appendUInt16(0) // Internal attributes

            let extAttr: UInt32
            switch item.type {
            case .directory:
                extAttr = (UInt32(item.permissions | 0o040000) << 16) | 0x10
            case .symlink:
                extAttr = UInt32(item.permissions | 0o120000) << 16
            case .file, .special:
                extAttr = (UInt32(item.permissions) << 16) | (0o100000 << 16)
            }
            cdEntry.appendUInt32(extAttr)
            cdEntry.appendUInt32(UInt32(localHeaderOffset))
            cdEntry.append(fileNameBytes)

            centralDirectoryEntries.append(cdEntry)
        }

        let cdStartOffset = currentOffset
        var cdTotalSize: UInt64 = 0

        for cdData in centralDirectoryEntries {
            try handle.write(contentsOf: cdData)
            currentOffset += UInt64(cdData.count)
            cdTotalSize += UInt64(cdData.count)
        }

        // End of Central Directory
        var eocd = Data()
        eocd.append(contentsOf: [0x50, 0x4B, 0x05, 0x06]) // Signature
        eocd.appendUInt16(0) // Disk number
        eocd.appendUInt16(0) // CD start disk
        eocd.appendUInt16(UInt16(items.count))
        eocd.appendUInt16(UInt16(items.count))
        eocd.appendUInt32(UInt32(cdTotalSize))
        eocd.appendUInt32(UInt32(cdStartOffset))
        eocd.appendUInt16(0) // Comment length

        try handle.write(contentsOf: eocd)
        try handle.synchronize()
    }

    private func writeSplitArchive(
        items: [ZipEntryPayload],
        manifest: CreationManifest,
        targetURL: URL,
        splitPlan: CreationProfile.SplitPlan,
        password: String?,
        strength: CreationProfile.Strength,
        progress: @escaping ProgressSink
    ) async throws {
        try SplitArchivePublication.ensureAvailable(baseURL: targetURL)
        let fm = FileManager.default
        let parent = targetURL.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appendingPathComponent(".prozip-split-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        let fullZipURL = staging.appendingPathComponent("full-archive.zip")
        try writeZipArchive(items: items, password: password, strength: strength, to: fullZipURL, progress: progress)
        try Self.verifyArchive(at: fullZipURL, against: manifest)

        let parts = try SplitArchivePublication.stageParts(
            archiveURL: fullZipURL,
            outputBaseURL: staging.appendingPathComponent(targetURL.lastPathComponent),
            plan: splitPlan
        )
        let totalBytes = Int64(try fullZipURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        progress(OperationProgress(phase: .savingSafely, completedBytes: totalBytes, totalBytes: totalBytes))
        try SplitArchivePublication.publish(stagedParts: parts, baseURL: targetURL)
        progress(OperationProgress(phase: .completed, completedBytes: totalBytes, totalBytes: totalBytes))
    }

    // MARK: - Central Directory & EOCD Parser (doc/03 section 3 & test A1..A5)

    func parseCentralDirectory(
        at url: URL,
        readSymlinkTargets: Bool,
        fileHandle: FileHandle? = nil
    ) throws -> ParsedCentralDirectory {
        let handle: FileHandle
        let shouldClose: Bool
        if let h = fileHandle {
            handle = h
            shouldClose = false
        } else {
            handle = try FileHandle(forReadingFrom: url)
            shouldClose = true
        }
        defer {
            if shouldClose {
                try? handle.close()
            }
        }

        guard let fileSize = Int64(exactly: handle.seekToEndOfFile()) else {
            throw ProZipError.corruptedArchive("压缩包大小超出可处理范围")
        }
        guard fileSize >= 22 else {
            throw ProZipError.corruptedArchive("压缩包无效或已损坏：文件过小")
        }

        // Check if file starts with local header
        handle.seek(toFileOffset: 0)
        let headMagic = handle.readData(ofLength: 4)
        var isConcatenated = false
        if headMagic.count == 4 {
            let isZipMagic = (headMagic[0] == 0x50 && headMagic[1] == 0x4B &&
                (headMagic[2] == 0x03 || headMagic[2] == 0x05))
            if !isZipMagic {
                isConcatenated = true
            }
        }

        // Search backward for EOCD (0x06054B50)
        let maxSearch = min(fileSize, Int64(65_536 + 22))
        let searchStart = fileSize - maxSearch
        handle.seek(toFileOffset: UInt64(searchStart))
        let tailData = handle.readData(ofLength: Int(maxSearch))

        guard let eocdRelOffset = findEOCDSignature(in: tailData) else {
            throw ProZipError.corruptedArchive("压缩包无效或已损坏：未找到中央目录结束标记")
        }

        let eocdAbsOffset = UInt64(searchStart + Int64(eocdRelOffset))
        let eocdData = tailData.subdata(in: eocdRelOffset..<tailData.count)
        guard eocdData.count >= 22 else {
            throw ProZipError.corruptedArchive("压缩包无效或已损坏：中央目录结束记录截断")
        }

        let diskNumber = eocdData.readUInt16(at: 4)
        let cdStartDisk = eocdData.readUInt16(at: 6)
        let totalEntries32 = UInt64(eocdData.readUInt16(at: 10))
        var cdSize = UInt64(eocdData.readUInt32(at: 12))
        var cdOffset = UInt64(eocdData.readUInt32(at: 16))
        let commentLen = Int(eocdData.readUInt16(at: 20))

        var archiveComment: String?
        if commentLen > 0 && eocdData.count >= 22 + commentLen {
            let cData = eocdData.subdata(in: 22..<(22 + commentLen))
            archiveComment = String(data: cData, encoding: .utf8) ?? String(decoding: cData, as: UTF8.self)
        }

        let isSplitVolume = (diskNumber != 0 || cdStartDisk != 0)
        var totalEntries = totalEntries32

        // Check for ZIP64 EOCD Locator (0x07064B50) 20 bytes before EOCD
        if eocdAbsOffset >= 20 {
            handle.seek(toFileOffset: eocdAbsOffset - 20)
            let locatorData = handle.readData(ofLength: 20)
            if locatorData.count == 20 && locatorData.readUInt32(at: 0) == 0x07064B50 {
                let zip64EOCDOffset = locatorData.readUInt64(at: 8)
                guard fileSize >= 56, zip64EOCDOffset <= UInt64(fileSize - 56) else {
                    throw ProZipError.corruptedArchive("ZIP64 中央目录记录偏移越界")
                }
                handle.seek(toFileOffset: zip64EOCDOffset)
                let zip64EOCDData = handle.readData(ofLength: 56)
                if zip64EOCDData.count >= 56 && zip64EOCDData.readUInt32(at: 0) == 0x06064B50 {
                    totalEntries = zip64EOCDData.readUInt64(at: 32)
                    cdSize = zip64EOCDData.readUInt64(at: 40)
                    cdOffset = zip64EOCDData.readUInt64(at: 48)
                }
            }
        }

        guard cdSize <= UInt64(fileSize), cdOffset <= UInt64(fileSize) else {
            throw ProZipError.corruptedArchive("压缩包无效或已损坏：中央目录偏移越界")
        }
        // Check for concatenated ZIP
        let expectedCDOffset = eocdAbsOffset > cdSize ? (eocdAbsOffset - cdSize) : cdOffset
        let shift: Int64
        if expectedCDOffset > cdOffset {
            shift = Int64(expectedCDOffset - cdOffset)
            isConcatenated = true
        } else {
            shift = 0
        }

        // Read and parse Central Directory
        let actualCDOffset = UInt64(Int64(cdOffset) + shift)
        guard actualCDOffset <= UInt64(fileSize) - cdSize else {
            throw ProZipError.corruptedArchive("压缩包无效或已损坏：中央目录偏移越界")
        }

        handle.seek(toFileOffset: actualCDOffset)
        let cdData = handle.readData(ofLength: Int(cdSize))
        guard cdData.count == Int(cdSize) else {
            throw ProZipError.corruptedArchive("压缩包无效或已损坏：中央目录读取不完整")
        }

        var entries: [CentralDirectoryEntry] = []
        entries.reserveCapacity(Int(min(totalEntries, 50_000)))

        var cdCursor = 0
        var hasNonUTF8 = false
        var detectedEncodingName: String?

        while cdCursor + 46 <= cdData.count {
            let sig = cdData.readUInt32(at: cdCursor)
            guard sig == 0x02014B50 else {
                break
            }

            let versionMadeBy = cdData.readUInt16(at: cdCursor + 4)
            let versionNeeded = cdData.readUInt16(at: cdCursor + 6)
            let flags = cdData.readUInt16(at: cdCursor + 8)
            let compressionMethod = cdData.readUInt16(at: cdCursor + 10)
            let modTime = cdData.readUInt16(at: cdCursor + 12)
            let modDate = cdData.readUInt16(at: cdCursor + 14)
            let crc32 = cdData.readUInt32(at: cdCursor + 16)
            var compSize = Int64(cdData.readUInt32(at: cdCursor + 20))
            var uncompSize = Int64(cdData.readUInt32(at: cdCursor + 24))
            let fnLen = Int(cdData.readUInt16(at: cdCursor + 28))
            let efLen = Int(cdData.readUInt16(at: cdCursor + 30))
            let commLen = Int(cdData.readUInt16(at: cdCursor + 32))
            let diskStart = cdData.readUInt16(at: cdCursor + 34)
            let intAttr = cdData.readUInt16(at: cdCursor + 36)
            let extAttr = cdData.readUInt32(at: cdCursor + 38)
            var localHeaderOffset = Int64(cdData.readUInt32(at: cdCursor + 42))

            let entryTotalLen = 46 + fnLen + efLen + commLen
            guard cdCursor + entryTotalLen <= cdData.count else {
                throw ProZipError.corruptedArchive("压缩包无效或已损坏：中央目录头截断")
            }

            let fnData = cdData.subdata(in: (cdCursor + 46)..<(cdCursor + 46 + fnLen))
            let efData = cdData.subdata(in: (cdCursor + 46 + fnLen)..<(cdCursor + 46 + fnLen + efLen))
            let commentData = cdData.subdata(in: (cdCursor + 46 + fnLen + efLen)..<(cdCursor + entryTotalLen))

            // Parse ZIP64 extra field (0x0001)
            var efCursor = 0
            while efCursor + 4 <= efData.count {
                let tag = efData.readUInt16(at: efCursor)
                let len = Int(efData.readUInt16(at: efCursor + 2))
                efCursor += 4
                guard len <= efData.count - efCursor else {
                    throw ProZipError.corruptedArchive("ZIP 扩展字段截断")
                }
                let fieldEnd = efCursor + len
                if tag == 0x0001 {
                    var z64Cursor = efCursor
                    if uncompSize == 0xFFFFFFFF && z64Cursor + 8 <= fieldEnd {
                        guard let value = Int64(exactly: efData.readUInt64(at: z64Cursor)) else {
                            throw ProZipError.corruptedArchive("ZIP64 项目大小超出可处理范围")
                        }
                        uncompSize = value
                        z64Cursor += 8
                    }
                    if compSize == 0xFFFFFFFF && z64Cursor + 8 <= fieldEnd {
                        guard let value = Int64(exactly: efData.readUInt64(at: z64Cursor)) else {
                            throw ProZipError.corruptedArchive("ZIP64 压缩大小超出可处理范围")
                        }
                        compSize = value
                        z64Cursor += 8
                    }
                    if localHeaderOffset == 0xFFFFFFFF && z64Cursor + 8 <= fieldEnd {
                        guard let value = Int64(exactly: efData.readUInt64(at: z64Cursor)) else {
                            throw ProZipError.corruptedArchive("ZIP64 文件头偏移超出可处理范围")
                        }
                        localHeaderOffset = value
                        z64Cursor += 8
                    }
                }
                efCursor += len
            }

            guard localHeaderOffset <= fileSize - shift, compSize <= fileSize else {
                throw ProZipError.corruptedArchive("ZIP 项目偏移或压缩大小越界")
            }
            localHeaderOffset += shift

            // Filename encoding detection (test A2, A3, E7)
            let (decodedName, isNonUTF8, encName) = decodeFilename(data: fnData, flags: flags)
            if isNonUTF8 {
                hasNonUTF8 = true
                detectedEncodingName = encName
            }

            let commentStr = String(data: commentData, encoding: .utf8) ?? String(decoding: commentData, as: UTF8.self)

            var symTarget: String?
            let type = determineEntryType(externalAttributes: extAttr, fileName: decodedName)
            if type == .symlink && readSymlinkTargets && (flags & 1) == 0 {
                symTarget = try? readSymlinkPayload(
                    localHeaderOffset: localHeaderOffset,
                    compressedSize: compSize,
                    fileHandle: handle
                )
            }

            entries.append(CentralDirectoryEntry(
                versionMadeBy: versionMadeBy,
                versionNeeded: versionNeeded,
                flags: flags,
                compressionMethod: compressionMethod,
                modTime: modTime,
                modDate: modDate,
                crc32: crc32,
                compressedSize: compSize,
                uncompressedSize: uncompSize,
                diskNumberStart: diskStart,
                internalAttributes: intAttr,
                externalAttributes: extAttr,
                localHeaderOffset: localHeaderOffset,
                fileNameData: fnData,
                fileName: decodedName,
                extraFieldData: efData,
                commentData: commentData,
                comment: commentStr,
                hasNonUTF8: isNonUTF8,
                detectedEncoding: encName,
                symlinkTarget: symTarget
            ))

            cdCursor += entryTotalLen
        }

        return ParsedCentralDirectory(
            entries: entries,
            totalCompressedSize: fileSize,
            isSplitVolume: isSplitVolume,
            isConcatenated: isConcatenated,
            hasNonUTF8Encoding: hasNonUTF8,
            detectedEncodingName: detectedEncodingName,
            comment: archiveComment
        )
    }

    private func findEOCDSignature(in data: Data) -> Int? {
        guard data.count >= 22 else { return nil }
        var i = data.count - 22
        while i >= 0 {
            if data[i] == 0x50 && data[i + 1] == 0x4B && data[i + 2] == 0x05 && data[i + 3] == 0x06 {
                return i
            }
            i -= 1
        }
        return nil
    }

    // MARK: - Filename Encoding Detection (test A2, A3)

    private func decodeFilename(data: Data, flags: UInt16) -> (name: String, isNonUTF8: Bool, encodingName: String) {
        let isBit11 = (flags & (1 << 11)) != 0
        if isBit11 {
            let str = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            return (str, false, "UTF-8")
        }

        // Pure ASCII check
        if data.allSatisfy({ $0 < 128 }) {
            let str = String(data: data, encoding: .ascii) ?? String(decoding: data, as: UTF8.self)
            return (str, false, "UTF-8")
        }

        // Try UTF-8 first
        if let utf8 = String(data: data, encoding: .utf8) {
            return (utf8, false, "UTF-8")
        }

        // Try GBK / GB18030 via CoreFoundation (test A3 & E7)
        let gbkEncoding = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
        if let gbkStr = String(data: data, encoding: String.Encoding(rawValue: gbkEncoding)) {
            return (gbkStr, true, "GBK")
        }

        // Fallback to CP437 (DOS Latin US)
        let cp437Encoding = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.dosLatinUS.rawValue)
        )
        if let cp437Str = String(data: data, encoding: String.Encoding(rawValue: cp437Encoding)) {
            return (cp437Str, true, "CP437")
        }

        // Fallback to ISO Latin 1
        let latin1 = String(data: data, encoding: .isoLatin1) ?? String(decoding: data, as: UTF8.self)
        return (latin1, true, "ISO-8859-1")
    }

    // MARK: - Entry Types & Permissions

    func determineEntryType(externalAttributes: UInt32, fileName: String) -> EntryType {
        let upper16 = UInt16((externalAttributes >> 16) & 0xFFFF)
        let mode = upper16 & 0o170000

        if mode == 0o120000 {
            return .symlink
        } else if mode == 0o040000 || fileName.hasSuffix("/") {
            return .directory
        } else if mode == 0o010000 || mode == 0o020000 || mode == 0o060000 || mode == 0o140000 {
            return .special
        } else if upper16 == 0 && ((externalAttributes & 0x10) != 0 || fileName.hasSuffix("/")) {
            return .directory
        } else {
            return .file
        }
    }

    func determinePermissions(externalAttributes: UInt32, type: EntryType) -> UInt16 {
        let upper16 = UInt16((externalAttributes >> 16) & 0xFFFF)
        let perms = upper16 & 0o7777
        if upper16 != 0 {
            return perms
        }
        return type == .directory ? 0o755 : 0o644
    }

    // MARK: - Payload Decompression & Decryption

    private func readAndDecompressEntry(
        cdItem: CentralDirectoryEntry,
        fileHandle: FileHandle,
        password: String?
    ) throws -> Data {
        guard cdItem.compressedSize <= ProcessCancellationController.maxBinaryOutputBytes,
              cdItem.uncompressedSize <= ProcessCancellationController.maxBinaryOutputBytes else {
            throw ProZipError.outputExceedsBudget("原生 ZIP 内存预算为 512 MiB，请使用兼容引擎处理此项目")
        }
        guard cdItem.localHeaderOffset >= 0 else {
            throw ProZipError.corruptedArchive("本地文件头偏移无效：\(cdItem.fileName)")
        }

        fileHandle.seek(toFileOffset: UInt64(cdItem.localHeaderOffset))
        let lhData = fileHandle.readData(ofLength: 30)
        guard lhData.count == 30, lhData.readUInt32(at: 0) == 0x04034B50 else {
            throw ProZipError.corruptedArchive("本地文件头签名不匹配：\(cdItem.fileName)")
        }

        let fnLen = Int(lhData.readUInt16(at: 26))
        let efLen = Int(lhData.readUInt16(at: 28))
        let payloadOffset = UInt64(cdItem.localHeaderOffset + 30 + Int64(fnLen + efLen))

        fileHandle.seek(toFileOffset: payloadOffset)
        var rawPayload = fileHandle.readData(ofLength: Int(cdItem.compressedSize))
        guard rawPayload.count == Int(cdItem.compressedSize) else {
            throw ProZipError.corruptedArchive("压缩包无效或已损坏：文件数据截断 (\(cdItem.fileName))")
        }

        let isEncrypted = (cdItem.flags & 1) != 0 || cdItem.compressionMethod == 99
        if isEncrypted {
            guard let pwd = password, !pwd.isEmpty else {
                throw ProZipError.passwordRequired(cdItem.fileName)
            }
            guard rawPayload.count >= 12 else {
                throw ProZipError.corruptedArchive("加密头截断：\(cdItem.fileName)")
            }

            var cipher = ZipCryptoCipher(password: pwd)
            let header = rawPayload.prefix(12)
            var decryptedHeader = [UInt8]()
            for b in header {
                decryptedHeader.append(cipher.decryptByte(b))
            }

            let checkByte = decryptedHeader[11]
            let crcCheck = UInt8((cdItem.crc32 >> 24) & 0xFF)
            let dosCheck = UInt8((cdItem.modTime >> 8) & 0xFF)
            let isDataDescriptor = (cdItem.flags & (1 << 3)) != 0

            let checkPassed = isDataDescriptor ? (checkByte == dosCheck || checkByte == crcCheck) : (checkByte == crcCheck || checkByte == dosCheck)
            guard checkPassed else {
                throw ProZipError.wrongPassword("密码错误")
            }

            let cipherBody = rawPayload.dropFirst(12)
            rawPayload = cipher.decryptData(Data(cipherBody))
        }

        var uncompressedData: Data
        switch cdItem.compressionMethod {
        case 0:
            uncompressedData = rawPayload
        case 8:
            uncompressedData = try Self.inflateRaw(data: rawPayload, expectedSize: cdItem.uncompressedSize)
        case 99:
            throw ProZipError.corruptedArchive("此 ZIP 的压缩方法（AES-99）需要使用兼容引擎")
        default:
            throw ProZipError.corruptedArchive("不支持的压缩方法 (\(cdItem.compressionMethod))：\(cdItem.fileName)")
        }

        let computedCRC = computeCRC32(for: uncompressedData)
        if computedCRC != cdItem.crc32 && cdItem.crc32 != 0 {
            if isEncrypted {
                throw ProZipError.wrongPassword("密码错误")
            } else {
                throw ProZipError.corruptedArchive("CRC32 校验失败：\(cdItem.fileName)")
            }
        }

        if Int64(uncompressedData.count) != cdItem.uncompressedSize {
            throw ProZipError.corruptedArchive("解压大小不匹配：\(cdItem.fileName)")
        }

        return uncompressedData
    }

    private func readSymlinkPayload(
        localHeaderOffset: Int64,
        compressedSize: Int64,
        fileHandle: FileHandle
    ) throws -> String {
        fileHandle.seek(toFileOffset: UInt64(localHeaderOffset))
        let lhData = fileHandle.readData(ofLength: 30)
        guard lhData.count == 30, lhData.readUInt32(at: 0) == 0x04034B50 else { return "" }
        let fnLen = Int(lhData.readUInt16(at: 26))
        let efLen = Int(lhData.readUInt16(at: 28))
        let payloadOffset = UInt64(localHeaderOffset + 30 + Int64(fnLen + efLen))

        fileHandle.seek(toFileOffset: payloadOffset)
        let data = fileHandle.readData(ofLength: Int(compressedSize))
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    // MARK: - Helpers: Source Collection

    struct SourceItem {
        let archivePath: String
        let type: EntryType
        let sourceURL: URL?
        let symlinkTarget: String?
        let modifiedAt: Date
        let permissions: UInt16
    }

    private func readSourceData(at url: URL, remainingBudget: Int64) throws -> Data {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard Int64(size) <= remainingBudget else {
            throw ProZipError.outputExceedsBudget("原生 ZIP 内存预算为 512 MiB，请使用兼容引擎处理")
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard Int64(data.count) <= remainingBudget else {
            throw ProZipError.outputExceedsBudget("原生 ZIP 内存预算为 512 MiB，请使用兼容引擎处理")
        }
        return data
    }

    private func collectSourceItems(
        sources: [URL],
        preserveMacMetadata: Bool,
        repairWindowsNames: Bool
    ) throws -> [SourceItem] {
        var items: [SourceItem] = []
        let fileManager = FileManager.default

        for rootURL in sources {
            try Task.checkCancellation()
            let attributes = try fileManager.attributesOfItem(atPath: rootURL.path)

            let rawRootName = rootURL.lastPathComponent
            let rootName = repairWindowsNames ? WindowsNameRepairPolicy.repairComponent(rawRootName) : rawRootName

            if attributes[.type] as? FileAttributeType == .typeDirectory {
                let resolvedRootPath = rootURL.standardizedFileURL.path
                items.append(SourceItem(
                    archivePath: rootName,
                    type: .directory,
                    sourceURL: rootURL,
                    symlinkTarget: nil,
                    modifiedAt: (try? rootURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date(),
                    permissions: (attributes[.posixPermissions] as? NSNumber)?.uint16Value ?? 0o755
                ))

                var enumerationError: Error?
                guard let enumerator = fileManager.enumerator(
                    at: rootURL,
                    includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey],
                    options: [],
                    errorHandler: { _, error in
                        enumerationError = error
                        return false
                    }
                ) else { throw ProZipError.invalidCreationProfile("无法读取源文件夹：\(rootURL.lastPathComponent)") }

                while let childURL = enumerator.nextObject() as? URL {
                    try Task.checkCancellation()
                    let resolvedChildPath = childURL.standardizedFileURL.path
                    let subPath: String
                    if resolvedChildPath.hasPrefix(resolvedRootPath + "/") {
                        subPath = String(resolvedChildPath.dropFirst(resolvedRootPath.count + 1))
                    } else {
                        subPath = childURL.lastPathComponent
                    }

                    if !preserveMacMetadata && ArchiveEntry.detectAuxiliary(path: subPath) {
                        continue
                    }

                    let repairedSubPath = repairWindowsNames ? WindowsNameRepairPolicy.repairPath(subPath) : subPath
                    let archivePath = "\(rootName)/\(repairedSubPath)"
                    let values = try? childURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey])

                    let modDate = values?.contentModificationDate ?? Date()
                    let perms = (try? fileManager.attributesOfItem(atPath: childURL.path)[.posixPermissions] as? NSNumber)?.uint16Value

                    if values?.isSymbolicLink == true {
                        let symTarget = try fileManager.destinationOfSymbolicLink(atPath: childURL.path)
                        items.append(SourceItem(
                            archivePath: archivePath,
                            type: .symlink,
                            sourceURL: childURL,
                            symlinkTarget: symTarget,
                            modifiedAt: modDate,
                            permissions: perms ?? 0o777
                        ))
                    } else if values?.isDirectory == true {
                        items.append(SourceItem(
                            archivePath: archivePath,
                            type: .directory,
                            sourceURL: childURL,
                            symlinkTarget: nil,
                            modifiedAt: modDate,
                            permissions: perms ?? 0o755
                        ))
                    } else {
                        items.append(SourceItem(
                            archivePath: archivePath,
                            type: .file,
                            sourceURL: childURL,
                            symlinkTarget: nil,
                            modifiedAt: modDate,
                            permissions: perms ?? 0o644
                        ))
                    }
                }
                if let enumerationError { throw enumerationError }
            } else {
                let values = try? rootURL.resourceValues(forKeys: [.isSymbolicLinkKey, .contentModificationDateKey])
                let modDate = values?.contentModificationDate ?? Date()
                let perms = (attributes[.posixPermissions] as? NSNumber)?.uint16Value

                if values?.isSymbolicLink == true {
                    let symTarget = try fileManager.destinationOfSymbolicLink(atPath: rootURL.path)
                    items.append(SourceItem(
                        archivePath: rootName,
                        type: .symlink,
                        sourceURL: rootURL,
                        symlinkTarget: symTarget,
                        modifiedAt: modDate,
                        permissions: perms ?? 0o777
                    ))
                } else {
                    items.append(SourceItem(
                        archivePath: rootName,
                        type: .file,
                        sourceURL: rootURL,
                        symlinkTarget: nil,
                        modifiedAt: modDate,
                        permissions: perms ?? 0o644
                    ))
                }
            }
        }

        return items
    }

    private func autoNumberedDestinationURL(for url: URL) -> URL {
        let dir = url.deletingLastPathComponent()
        let filename = url.lastPathComponent
        let ns = filename as NSString
        let ext = ns.pathExtension
        let base = ext.isEmpty ? filename : ns.deletingPathExtension

        var counter = 2
        while true {
            let candidateName = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            let candidateURL = dir.appendingPathComponent(candidateName)
            if !FileManager.default.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
            counter += 1
        }
    }

    // MARK: - Helpers: Raw Deflate / Inflate (system zlib)

    public static func deflateRaw(data: Data, level: Int32) throws -> Data {
        var stream = z_stream()
        let initRet = deflateInit2_(
            &stream,
            level,
            Z_DEFLATED,
            -MAX_WBITS,
            8,
            Z_DEFAULT_STRATEGY,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initRet == Z_OK else {
            throw ProZipError.corruptedArchive("Deflate 初始化失败 (\(initRet))")
        }
        defer { deflateEnd(&stream) }

        var output = Data()
        let chunkSize = 65_536
        var buffer = [UInt8](repeating: 0, count: chunkSize)

        try data.withUnsafeBytes { rawIn in
            guard let inBase = rawIn.bindMemory(to: UInt8.self).baseAddress else { return }
            stream.next_in = UnsafeMutablePointer(mutating: inBase)
            stream.avail_in = uInt(data.count)

            var status = Z_OK
            while status == Z_OK {
                buffer.withUnsafeMutableBufferPointer { outBuf in
                    guard let outBase = outBuf.baseAddress else { return }
                    stream.next_out = outBase
                    stream.avail_out = uInt(chunkSize)

                    status = deflate(&stream, Z_FINISH)
                    let written = chunkSize - Int(stream.avail_out)
                    if written > 0 {
                        output.append(outBase, count: written)
                    }
                }
            }
            guard status == Z_STREAM_END else {
                throw ProZipError.corruptedArchive("Deflate 压缩异常中断 (\(status))")
            }
        }
        return output
    }

    public static func inflateRaw(data: Data, expectedSize: Int64) throws -> Data {
        guard expectedSize >= 0, expectedSize <= ProcessCancellationController.maxBinaryOutputBytes else {
            throw ProZipError.outputExceedsBudget("原生 ZIP 内存预算为 512 MiB")
        }
        var stream = z_stream()
        let initRet = inflateInit2_(
            &stream,
            -MAX_WBITS,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initRet == Z_OK else {
            throw ProZipError.corruptedArchive("Inflate 初始化失败 (\(initRet))")
        }
        defer { inflateEnd(&stream) }

        var output = Data()
        if expectedSize > 0 && expectedSize <= 256 * 1024 * 1024 {
            output.reserveCapacity(Int(expectedSize))
        }
        let chunkSize = 65_536
        var buffer = [UInt8](repeating: 0, count: chunkSize)

        try data.withUnsafeBytes { rawIn in
            guard let inBase = rawIn.bindMemory(to: UInt8.self).baseAddress else { return }
            stream.next_in = UnsafeMutablePointer(mutating: inBase)
            stream.avail_in = uInt(data.count)

            var status = Z_OK
            while status == Z_OK {
                try Task.checkCancellation()
                try buffer.withUnsafeMutableBufferPointer { outBuf in
                    guard let outBase = outBuf.baseAddress else { return }
                    stream.next_out = outBase
                    stream.avail_out = uInt(chunkSize)

                    status = inflate(&stream, Z_NO_FLUSH)
                    let written = chunkSize - Int(stream.avail_out)
                    if written > 0 {
                        guard Int64(output.count) + Int64(written) <= expectedSize else {
                            throw ProZipError.corruptedArchive("解压内容超过 ZIP 目录记录的项目大小")
                        }
                        output.append(outBase, count: written)
                    }
                }
            }
            guard status == Z_STREAM_END || (status == Z_OK && stream.avail_in == 0) else {
                throw ProZipError.corruptedArchive("Inflate 解压未正常结束 (\(status))")
            }
        }
        return output
    }

    public func computeCRC32(for data: Data) -> UInt32 {
        guard !data.isEmpty else { return 0 }
        return data.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return UInt32(zlib.crc32(0, base, uInt(data.count)))
        }
    }

    // MARK: - MS-DOS Date Time Conversion

    static func dosDateTime(from date: Date) -> (UInt16, UInt16) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = max(1980, min(2107, comps.year ?? 1980))
        let month = max(1, min(12, comps.month ?? 1))
        let day = max(1, min(31, comps.day ?? 1))
        let hour = max(0, min(23, comps.hour ?? 0))
        let minute = max(0, min(59, comps.minute ?? 0))
        let second = max(0, min(59, comps.second ?? 0))

        let dosDate = UInt16(((year - 1980) << 9) | (month << 5) | day)
        let dosTime = UInt16((hour << 11) | (minute << 5) | (second / 2))
        return (dosTime, dosDate)
    }

    func date(fromDosTime modTime: UInt16, dosDate modDate: UInt16) -> Date {
        let year = Int((modDate >> 9) & 0x7F) + 1980
        let month = max(1, min(12, Int((modDate >> 5) & 0x0F)))
        let day = max(1, min(31, Int(modDate & 0x1F)))
        let hour = max(0, min(23, Int((modTime >> 11) & 0x1F)))
        let minute = max(0, min(59, Int((modTime >> 5) & 0x3F)))
        let second = max(0, min(59, Int((modTime & 0x1F) * 2)))

        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        comps.second = second
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return cal.date(from: comps) ?? Date()
    }
}

// MARK: - Binary Data Serialization Helpers

private extension Data {
    @inline(__always)
    func readUInt16(at offset: Int) -> UInt16 {
        withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self).littleEndian }
    }

    @inline(__always)
    func readUInt32(at offset: Int) -> UInt32 {
        withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian }
    }

    @inline(__always)
    func readUInt64(at offset: Int) -> UInt64 {
        withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt64.self).littleEndian }
    }

    @inline(__always)
    mutating func appendUInt16(_ val: UInt16) {
        var v = val.littleEndian
        append(Data(bytes: &v, count: 2))
    }

    @inline(__always)
    mutating func appendUInt32(_ val: UInt32) {
        var v = val.littleEndian
        append(Data(bytes: &v, count: 4))
    }

    @inline(__always)
    mutating func appendUInt64(_ val: UInt64) {
        var v = val.littleEndian
        append(Data(bytes: &v, count: 8))
    }
}
