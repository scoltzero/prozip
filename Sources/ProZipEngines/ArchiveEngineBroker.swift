import Foundation
import ProZipShared
import ProZipCore

// MARK: - ArchiveEngineBroker (doc/03 section 2 & doc/11 section 3)

public final class ArchiveEngineBroker: @unchecked Sendable {
    public static let shared = ArchiveEngineBroker()

    public var nativeZipEngine: any ArchiveEngine
    public let sevenZipEngine: SevenZipEngine
    public let libarchiveEngine: LibarchiveEngine
    public let diskImageEngine: DiskImageEngine

    private let prewarmLock = NSLock()
    private var hasStartedPrewarm = false

    public init(
        nativeZipEngine: (any ArchiveEngine)? = nil,
        sevenZipEngine: SevenZipEngine = SevenZipEngine(),
        libarchiveEngine: LibarchiveEngine = LibarchiveEngine(),
        diskImageEngine: DiskImageEngine = DiskImageEngine()
    ) {
        if let native = nativeZipEngine {
            self.nativeZipEngine = native
        } else {
            self.nativeZipEngine = NativeZipEngine()
        }
        self.sevenZipEngine = sevenZipEngine
        self.libarchiveEngine = libarchiveEngine
        self.diskImageEngine = diskImageEngine
    }

    /// Pre-loads in-process zlib tables and faults external compression cores (`7zz`, `bsdtar`)
    /// into macOS's unified buffer cache once on a low-priority background task.
    public func prewarmEngines() {
        prewarmLock.lock()
        let shouldStart = !hasStartedPrewarm
        if shouldStart { hasStartedPrewarm = true }
        prewarmLock.unlock()
        guard shouldStart else { return }

        Task.detached(priority: .utility) {
            _ = try? NativeZipEngine.deflateRaw(data: Data("prozip-prewarm".utf8), level: 6)
            await SevenZipEngine.prewarm()
            let bsdtarURL = URL(fileURLWithPath: LibarchiveEngine.bsdtarPath)
            if FileManager.default.isExecutableFile(atPath: bsdtarURL.path) {
                _ = try? await ProcessCancellationController.run(
                    executableURL: bsdtarURL,
                    arguments: ["--version"]
                )
            }
        }
    }

    // MARK: - Routing Matrix (doc/03 section 2)

    public func candidateEngines(
        for format: ArchiveFormat,
        isSplit: Bool = false,
        isEncrypted: Bool = false,
        forWriting: Bool = false
    ) -> [any ArchiveEngine] {
        if forWriting {
            if format.isZipFamily {
                // ZIP (unencrypted & non-split, or ASCII password / split) -> [nativeZipEngine, sevenZipEngine]
                return [nativeZipEngine, sevenZipEngine]
            } else if format == .sevenZip {
                // 7Z -> [sevenZipEngine]
                return [sevenZipEngine]
            } else if format == .tar || format == .tarGz || format == .tarBz2 || format == .tarXz ||
                        format == .gzip || format == .bzip2 || format == .xz {
                // TAR / GZ / BZ2 / XZ -> [libarchiveEngine]
                return [libarchiveEngine]
            } else {
                return [sevenZipEngine, libarchiveEngine]
            }
        } else {
            // Open / Extract Routing
            if format.isDiskImage {
                // DMG / ISO -> [diskImageEngine, libarchiveEngine, sevenZipEngine]
                return [diskImageEngine, libarchiveEngine, sevenZipEngine]
            } else if format.isZipFamily {
                if isSplit {
                    // ZIP split -> [sevenZipEngine, nativeZipEngine, libarchiveEngine]
                    return [sevenZipEngine, nativeZipEngine, libarchiveEngine]
                } else {
                    // ZIP (non-split, or ZipCrypto) -> [nativeZipEngine, sevenZipEngine, libarchiveEngine]
                    return [nativeZipEngine, sevenZipEngine, libarchiveEngine]
                }
            } else if format == .sevenZip || format == .rar || format == .msi || format == .pkg ||
                        format == .spk || format == .exe || format == .swf {
                // 7Z / RAR / MSI / PKG / SPK / EXE -> [sevenZipEngine, libarchiveEngine]
                return [sevenZipEngine, libarchiveEngine]
            } else {
                // TAR family / single streams / CAB / CPIO / XAR / RPM -> [libarchiveEngine, sevenZipEngine]
                return [libarchiveEngine, sevenZipEngine]
            }
        }
    }

    // MARK: - Split Volume Family Resolution

    private func resolveTargetURL(for url: URL) throws -> (targetURL: URL, isSplit: Bool) {
        let family = SplitVolumeFamily.resolve(for: url)
        if family.isSplit {
            guard family.isComplete else {
                throw ProZipError.splitVolumeIncomplete("分卷不完整或压缩包头损坏：\(url.lastPathComponent)")
            }
            guard !family.hasEmptyVolume else {
                throw ProZipError.splitVolumeIncomplete("分卷包含空卷：\(url.lastPathComponent)")
            }
            return (family.primaryVolumeURL, true)
        }
        return (url, false)
    }

    // MARK: - Unified High-Level Operations

    public func probe(_ url: URL) async throws -> ArchiveDescriptor {
        let (targetURL, isSplit) = try resolveTargetURL(for: url)
        let format = ArchiveFormat.detect(from: targetURL)
        let candidates = candidateEngines(for: format, isSplit: isSplit, isEncrypted: false, forWriting: false)

        var lastError: Error?
        for engine in candidates {
            try Task.checkCancellation()
            do {
                var descriptor = try await engine.probe(targetURL)
                // If original URL was a non-primary split part, preserve primary descriptor links
                if isSplit {
                    let family = SplitVolumeFamily.resolve(for: url)
                    descriptor = ArchiveDescriptor(
                        url: url,
                        primaryVolumeURL: family.primaryVolumeURL,
                        volumeURLs: family.volumeURLs,
                        format: descriptor.format,
                        isEncrypted: descriptor.isEncrypted,
                        hasEncryptedHeaders: descriptor.hasEncryptedHeaders,
                        isSplitVolume: true,
                        isConcatenated: descriptor.isConcatenated,
                        hasNonUTF8Encoding: descriptor.hasNonUTF8Encoding,
                        detectedEncodingName: descriptor.detectedEncodingName,
                        totalCompressedSize: descriptor.totalCompressedSize,
                        entryCountHint: descriptor.entryCountHint,
                        comment: descriptor.comment
                    )
                }
                return descriptor
            } catch let error as ProZipError where error == .passwordRequired(targetURL.lastPathComponent) || error == .passwordRequired(url.lastPathComponent) || error == .licenseAgreementRequired(targetURL.lastPathComponent) {
                // Return encrypted descriptor on password required
                let family = SplitVolumeFamily.resolve(for: url)
                return ArchiveDescriptor(
                    url: url,
                    primaryVolumeURL: family.primaryVolumeURL,
                    volumeURLs: family.volumeURLs,
                    format: format,
                    isEncrypted: true,
                    hasEncryptedHeaders: true,
                    isSplitVolume: isSplit
                )
            } catch {
                lastError = error
                continue
            }
        }

        throw lastError ?? ProZipError.invalidArchive("无法读取压缩包：\(url.lastPathComponent)")
    }

    public func list(
        _ url: URL,
        password: String? = nil,
        progress: @escaping ProgressSink = { _ in }
    ) async throws -> [ArchiveEntry] {
        let (targetURL, isSplit) = try resolveTargetURL(for: url)
        let format = ArchiveFormat.detect(from: targetURL)
        let candidates = candidateEngines(for: format, isSplit: isSplit, isEncrypted: password != nil, forWriting: false)

        var lastError: Error?
        for engine in candidates {
            try Task.checkCancellation()
            do {
                return try await engine.list(targetURL, password: password, progress: progress)
            } catch let err as ProZipError {
                // Security / Authentication errors must NOT be swallowed by fallback!
                switch err {
                case .passwordRequired, .wrongPassword, .licenseAgreementRequired:
                    throw err
                case .splitVolumeIncomplete:
                    throw err
                default:
                    lastError = err
                    continue
                }
            } catch {
                lastError = error
                continue
            }
        }

        throw lastError ?? ProZipError.invalidArchive("无法读取压缩包目录：\(url.lastPathComponent)")
    }

    public func openMember(
        _ entry: ArchiveEntry,
        in url: URL,
        password: String? = nil,
        range: Range<Int64>? = nil
    ) async throws -> AsyncThrowingStream<Data, Error> {
        let (targetURL, isSplit) = try resolveTargetURL(for: url)
        let format = ArchiveFormat.detect(from: targetURL)
        let candidates = candidateEngines(for: format, isSplit: isSplit, isEncrypted: password != nil, forWriting: false)

        var lastError: Error?
        for engine in candidates {
            try Task.checkCancellation()
            do {
                return try await engine.openMember(entry, in: targetURL, password: password, range: range)
            } catch {
                lastError = error
                continue
            }
        }

        throw lastError ?? ProZipError.corruptedArchive("无法打开条目：\(entry.name)")
    }

    public func extract(
        _ entries: [ArchiveEntry],
        from url: URL,
        to dir: URL,
        password: String? = nil,
        options: ExtractionOptions = ExtractionOptions(),
        progress: @escaping ProgressSink = { _ in }
    ) async throws -> ExtractionReport {
        let (targetURL, isSplit) = try resolveTargetURL(for: url)
        let format = ArchiveFormat.detect(from: targetURL)
        let candidates = candidateEngines(for: format, isSplit: isSplit, isEncrypted: password != nil, forWriting: false)

        var lastError: Error?
        for engine in candidates {
            try Task.checkCancellation()
            do {
                return try await engine.extract(
                    entries,
                    from: targetURL,
                    to: dir,
                    password: password,
                    options: options,
                    progress: progress
                )
            } catch let err as ProZipError {
                switch err {
                case .passwordRequired, .wrongPassword, .licenseAgreementRequired, .unsafePath, .symlinkOutOfBounds, .structureConflict, .destinationIsSymlink, .destinationNotWritable:
                    // Critical security and authentication errors must be thrown directly
                    throw err
                default:
                    lastError = err
                    continue
                }
            } catch {
                lastError = error
                continue
            }
        }

        throw lastError ?? ProZipError.corruptedArchive("解压失败：\(url.lastPathComponent)")
    }

    public func create(
        sources: [URL],
        at url: URL,
        profile: CreationProfile,
        password: String? = nil,
        progress: @escaping ProgressSink = { _ in }
    ) async throws {
        try profile.validate()
        let isSplit = profile.split != nil
        let isEncrypted = password != nil && !password!.isEmpty
        let candidates = candidateEngines(for: profile.format, isSplit: isSplit, isEncrypted: isEncrypted, forWriting: true)

        var lastError: Error?
        for engine in candidates {
            try Task.checkCancellation()
            do {
                try await engine.create(
                    sources: sources,
                    at: url,
                    profile: profile,
                    password: password,
                    progress: progress
                )
                return
            } catch let err as ProZipError {
                switch err {
                case .invalidCreationProfile, .splitVolumeIncomplete, .destinationNotWritable:
                    throw err
                default:
                    lastError = err
                    continue
                }
            } catch {
                lastError = error
                continue
            }
        }

        throw lastError ?? ProZipError.invalidArchive("创建压缩包失败：\(url.lastPathComponent)")
    }

    public func applyMutations(
        _ mutations: [ArchiveMutation],
        to sourceURL: URL,
        outputURL: URL,
        profile: CreationProfile,
        password: String? = nil,
        progress: @escaping ProgressSink = { _ in }
    ) async throws {
        let (targetURL, isSplit) = try resolveTargetURL(for: sourceURL)
        if isSplit {
            throw ProZipError.editingNotSupported("分卷压缩包暂不支持原位编辑")
        }

        let format = ArchiveFormat.detect(from: targetURL)
        let candidates = candidateEngines(for: format, isSplit: false, isEncrypted: password != nil, forWriting: true)

        var lastError: Error?
        for engine in candidates {
            try Task.checkCancellation()
            do {
                try await engine.applyMutations(
                    mutations,
                    to: targetURL,
                    outputURL: outputURL,
                    profile: profile,
                    password: password,
                    progress: progress
                )
                return
            } catch let err as ProZipError {
                if case .outputExceedsBudget = err {
                    lastError = err
                    continue
                }
                if err == .editingNotSupported("\(engine.engineName) 不支持原位增量修改") {
                    lastError = err
                    continue
                }
                throw err
            } catch {
                throw error
            }
        }

        throw lastError ?? ProZipError.editingNotSupported("该格式不支持原位增量修改")
    }
}
