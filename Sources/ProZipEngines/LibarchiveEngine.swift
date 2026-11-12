import Foundation
import ProZipShared
import ProZipCore

// MARK: - LibarchiveEngine (L3 System libarchive / bsdtar Engine)

public struct LibarchiveEngine: ArchiveEngine {
    public static let capabilities = EngineCapabilities(
        read: [
            .tar, .tarGz, .tarBz2, .tarXz,
            .cpio, .xar, .cab, .lha, .arj, .rpm, .iso, .pkg,
            .gzip, .bzip2, .xz, .lzma, .lzip, .zip
        ],
        write: [.tar, .tarGz, .tarBz2, .tarXz, .gzip, .bzip2, .xz],
        edit: [.tar],
        encryptedRead: false,
        encryptedWrite: false,
        headerEncryption: false,
        split: false,
        streamingMemberRead: true
    )

    public var engineName: String { "bsdtar" }

    public static let bsdtarPath = "/usr/bin/bsdtar"

    public init() {}

    private func requireBsdtarURL() throws -> URL {
        let fm = FileManager.default
        if fm.isExecutableFile(atPath: Self.bsdtarPath) {
            return URL(fileURLWithPath: Self.bsdtarPath)
        }
        throw ProZipError.invalidArchive("无法初始化系统 libarchive：未找到 \(Self.bsdtarPath)")
    }

    private static func singleStreamBinary(for format: ArchiveFormat) throws -> URL {
        let name: String
        switch format {
        case .gzip: name = "gzip"
        case .bzip2: name = "bzip2"
        case .xz, .lzma: name = "xz"
        case .lzip: name = "lzip"
        default: throw ProZipError.invalidArchive("不支持的单文件压缩流：\(format.displayName)")
        }
        for directory in ["/usr/bin", "/opt/homebrew/bin", "/usr/local/bin"] {
            let url = URL(fileURLWithPath: directory).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        throw ProZipError.invalidArchive("未找到解压工具：\(name)")
    }

    // MARK: - Probe

    public func probe(_ url: URL) async throws -> ArchiveDescriptor {
        let format = ArchiveFormat.detect(from: url)
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0

        // Single-stream formats have exactly one virtual entry
        if format.isSingleStream {
            return ArchiveDescriptor(
                url: url,
                format: format,
                isEncrypted: false,
                hasEncryptedHeaders: false,
                isSplitVolume: false,
                totalCompressedSize: fileSize,
                entryCountHint: 1
            )
        }

        // Multi-entry archive probing via bsdtar -tf
        let bin = try requireBsdtarURL()
        let result = try await ProcessCancellationController.run(
            executableURL: bin,
            arguments: ["-tf", url.path]
        )

        if result.exitCode != 0 {
            let combined = result.combinedOutputString
            if combined.contains("passphrase required") || combined.contains("encrypted") {
                return ArchiveDescriptor(
                    url: url,
                    format: format,
                    isEncrypted: true,
                    hasEncryptedHeaders: false,
                    isSplitVolume: false,
                    totalCompressedSize: fileSize
                )
            }
            throw ProZipError.invalidArchive("libarchive 无法读取压缩包：\(url.lastPathComponent)")
        }

        let lines = result.combinedOutputString.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        return ArchiveDescriptor(
            url: url,
            format: format,
            isEncrypted: false,
            hasEncryptedHeaders: false,
            isSplitVolume: false,
            totalCompressedSize: fileSize,
            entryCountHint: lines.count
        )
    }

    // MARK: - List

    public func list(
        _ url: URL,
        password: String?,
        progress: @escaping ProgressSink
    ) async throws -> [ArchiveEntry] {
        let format = ArchiveFormat.detect(from: url)
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()

        progress(OperationProgress(phase: .indexing, completedBytes: 0, totalBytes: 0))

        // 1. Single stream files (.gz, .bz2, .xz, .lzma, .lz) -> Virtual single entry
        if format.isSingleStream {
            let strippedName = Self.stripSingleStreamExtension(from: url.lastPathComponent, format: format)
            let virtualEntry = ArchiveEntry(
                path: strippedName,
                type: .file,
                uncompressedSize: 0,
                compressedSize: fileSize,
                modifiedAt: modDate,
                permissions: 420 // 0644
            )
            progress(OperationProgress(phase: .completed, completedBytes: 1, totalBytes: 1))
            return [virtualEntry]
        }

        // 2. Multi-entry archive via bsdtar -tvvf
        let bin = try requireBsdtarURL()
        let result = try await ProcessCancellationController.run(
            executableURL: bin,
            arguments: ["-tvvf", url.path],
            environment: ["LC_ALL": "C"]
        )

        let combined = result.combinedOutputString
        if result.exitCode != 0 {
            if combined.contains("passphrase required") || combined.contains("encrypted") {
                if password == nil || password!.isEmpty {
                    throw ProZipError.passwordRequired(url.lastPathComponent)
                } else {
                    throw ProZipError.wrongPassword("密码错误：\(url.lastPathComponent)")
                }
            }
            throw ProZipError.corruptedArchive("libarchive 无法读取压缩包：\(url.lastPathComponent)")
        }

        let entries = Self.parseBsdtarListing(combined)
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
        let format = ArchiveFormat.detect(from: url)
        let bin = try format.isSingleStream ? Self.singleStreamBinary(for: format) : requireBsdtarURL()
        let arguments = format.isSingleStream ? ["-dc", "--", url.path] : ["-xOf", url.path, "--", entry.path]
        return try await streamMemberOutput(expectedSize: entry.uncompressedSize, range: range) { output in
            let result = try await ProcessCancellationController.run(
                executableURL: bin, arguments: arguments, stdoutFile: output,
                stdoutByteLimit: ProcessCancellationController.maxBinaryOutputBytes,
                stdoutPrefixLimit: memberOutputPrefixLimit(expectedSize: entry.uncompressedSize, range: range))
            if result.reachedPrefixLimit { return }
            if result.exitCode != 0 {
                throw ProZipError.corruptedArchive("无法读取压缩包成员：\(entry.name)")
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
        let bin = try requireBsdtarURL()
        let format = ArchiveFormat.detect(from: url)

        // 1. Validate entries and destination with extraction policy
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

        progress(OperationProgress(phase: .preparing, completedBytes: 0, totalBytes: Int64(plan.itemsToExtract.count)))

        let fm = FileManager.default
        let stagingUUID = UUID().uuidString
        let stagingURL = dir.deletingLastPathComponent().appendingPathComponent(".prozip-bsdtar-staging-\(stagingUUID)", isDirectory: true)
        try fm.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: stagingURL) }

        progress(OperationProgress(phase: .extracting, completedBytes: 0, totalBytes: Int64(plan.itemsToExtract.count)))

        if format.isSingleStream {
            // Decompress single stream to staging file
            guard let item = plan.itemsToExtract.first else {
                throw ProZipError.invalidArchive("单文件压缩流没有可提取的内容")
            }
            let stagedOutputURL = stagingURL.appendingPathComponent(item.relativeOutputPath)
            try fm.createDirectory(at: stagedOutputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard fm.createFile(atPath: stagedOutputURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw ProZipError.destinationNotWritable(stagedOutputURL.path)
            }
            let output = try FileHandle(forWritingTo: stagedOutputURL)
            defer { try? output.close() }
            let result = try await ProcessCancellationController.run(
                executableURL: Self.singleStreamBinary(for: format),
                arguments: ["-dc", "--", url.path],
                stdoutFile: output
            )
            if result.exitCode != 0 {
                throw ProZipError.corruptedArchive("无法解压压缩流：\(url.lastPathComponent)")
            }
        } else {
            // Multi-entry extraction using --no-mac-metadata and --no-same-permissions
            var args = [
                "-xf", url.path,
                "-C", stagingURL.path,
                "--no-mac-metadata",
                "--no-same-permissions",
                "--no-recursion"
            ]
            args.append("--")

            for item in plan.itemsToExtract {
                args.append(item.entry.path)
            }

            let result = try await ProcessCancellationController.run(
                executableURL: bin,
                arguments: args
            )
            if result.exitCode != 0 {
                throw ProZipError.corruptedArchive("bsdtar 提取归档失败，退出码 \(result.exitCode)")
            }
        }

        // 2. Publish items safely to final destination
        progress(OperationProgress(phase: .savingSafely, completedBytes: 0, totalBytes: Int64(plan.itemsToExtract.count)))

        var publishedURLs: [URL] = []
        var skippedCount = plan.skippedEntries.count
        var skippedReasons = plan.skippedEntries.map(\.reason)

        for item in plan.itemsToExtract {
            try Task.checkCancellation()
            let stagedPath = format.isSingleStream ? item.relativeOutputPath : item.entry.path
            let stagedItemURL = stagingURL.appendingPathComponent(stagedPath)
            guard (try? fm.attributesOfItem(atPath: stagedItemURL.path)) != nil else { continue }

            let destURL = item.destinationURL
            let destParent = destURL.deletingLastPathComponent()
            try ArchiveExtractionPolicy.validateDestinationDirectory(item.entry.isDirectory ? destURL : destParent)
            if !fm.fileExists(atPath: destParent.path) {
                try fm.createDirectory(at: destParent, withIntermediateDirectories: true)
            }

            if item.entry.isDirectory {
                try fm.createDirectory(at: destURL, withIntermediateDirectories: true)
                publishedURLs.append(destURL)
                continue
            }

            if fm.fileExists(atPath: destURL.path) {
                switch item.conflictAction {
                case .replace:
                    _ = try fm.replaceItemAt(destURL, withItemAt: stagedItemURL, options: .usingNewMetadataOnly)
                    publishedURLs.append(destURL)
                case .skip:
                    skippedCount += 1
                    skippedReasons.append("跳过已存在项目：\(destURL.lastPathComponent)")
                case .keepBoth, .ask:
                    try fm.moveItem(at: stagedItemURL, to: destURL)
                    publishedURLs.append(destURL)
                }
            } else {
                try fm.moveItem(at: stagedItemURL, to: destURL)
                publishedURLs.append(destURL)
            }
        }

        progress(OperationProgress(phase: .completed, completedBytes: Int64(publishedURLs.count), totalBytes: Int64(publishedURLs.count)))

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
        let bin = try requireBsdtarURL()
        try profile.validate()

        if let pwd = password, !pwd.isEmpty {
            throw ProZipError.invalidCreationProfile("TAR 与单文件流格式不支持密码加密")
        }

        let supportedWriteFormats: Set<ArchiveFormat> = [
            .tar, .tarGz, .tarBz2, .tarXz, .gzip, .bzip2, .xz
        ]
        guard supportedWriteFormats.contains(profile.format) else {
            throw ProZipError.invalidCreationProfile("bsdtar 引擎不支持创建格式：\(profile.format.displayName)")
        }

        progress(OperationProgress(phase: .preparing, completedBytes: 0, totalBytes: 0))

        let fm = FileManager.default
        let stagingUUID = UUID().uuidString
        let stagingDir = url.deletingLastPathComponent().appendingPathComponent(".prozip-bsdtar-create-\(stagingUUID)", isDirectory: true)
        try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: stagingDir) }

        let stagingArchiveURL = stagingDir.appendingPathComponent(url.lastPathComponent)

        progress(OperationProgress(phase: .compressing, completedBytes: 0, totalBytes: 0))

        if profile.format.isSingleStream {
            guard let firstSource = sources.first else {
                throw ProZipError.invalidCreationProfile("单文件压缩流需要至少一个源文件")
            }
            // Use system command line compress tools for raw single streams
            let streamBin = try Self.singleStreamBinary(for: profile.format)

            guard fm.createFile(atPath: stagingArchiveURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw ProZipError.destinationNotWritable(stagingArchiveURL.path)
            }
            let output = try FileHandle(forWritingTo: stagingArchiveURL)
            defer { try? output.close() }
            let result = try await ProcessCancellationController.run(
                executableURL: streamBin,
                arguments: ["-c", firstSource.path],
                stdoutFile: output
            )
            if result.exitCode != 0 {
                throw ProZipError.corruptedArchive("单流压缩失败，退出码 \(result.exitCode)")
            }
        } else {
            guard !sources.isEmpty else {
                throw ProZipError.invalidCreationProfile("创建归档需要至少一个源文件")
            }

            var args: [String] = []
            switch profile.format {
            case .tar:
                args.append("-cf")
            case .tarGz:
                args.append("-czf")
            case .tarBz2:
                args.append("-cjf")
            case .tarXz:
                args.append("--xz")
                args.append("-cf")
            default:
                args.append("-cf")
            }

            args.append(stagingArchiveURL.path)

            if !profile.preserveMacMetadata {
                args.append("--no-mac-metadata")
            }

            // Strip leading "./" from member names only (S preserves symlink targets untouched),
            // while "./<basename>" avoids option-flag ambiguity for leading-dash filenames.
            args.append(contentsOf: ["-s", "#^\\./##S"])

            for s in sources {
                let name = s.lastPathComponent
                guard !name.isEmpty, name != "/" else {
                    throw ProZipError.invalidCreationProfile("无效的源文件路径：\(s.path)")
                }
                args.append(contentsOf: ["-C", s.deletingLastPathComponent().path, "./\(name)"])
            }

            let result = try await ProcessCancellationController.run(
                executableURL: bin,
                arguments: args
            )
            if result.exitCode != 0 {
                throw ProZipError.corruptedArchive("bsdtar 创建归档失败，退出码 \(result.exitCode)")
            }
        }

        // Publish safely
        progress(OperationProgress(phase: .savingSafely, completedBytes: 0, totalBytes: 0))

        guard fm.fileExists(atPath: stagingArchiveURL.path) else {
            throw ProZipError.corruptedArchive("bsdtar 未生成有效的归档文件")
        }

        try Task.checkCancellation()
        if fm.fileExists(atPath: url.path) {
            _ = try fm.replaceItemAt(url, withItemAt: stagingArchiveURL, options: .usingNewMetadataOnly)
        } else {
            try fm.moveItem(at: stagingArchiveURL, to: url)
        }

        progress(OperationProgress(phase: .completed, completedBytes: 1, totalBytes: 1))
    }

    // MARK: - Helpers

    public static func stripSingleStreamExtension(from filename: String, format: ArchiveFormat) -> String {
        let lower = filename.lowercased()
        switch format {
        case .gzip:
            if lower.hasSuffix(".gz") { return String(filename.dropLast(3)) }
            if lower.hasSuffix(".gzip") { return String(filename.dropLast(5)) }
        case .bzip2:
            if lower.hasSuffix(".bz2") { return String(filename.dropLast(4)) }
            if lower.hasSuffix(".bzip2") { return String(filename.dropLast(6)) }
        case .xz:
            if lower.hasSuffix(".xz") { return String(filename.dropLast(3)) }
        case .lzma:
            if lower.hasSuffix(".lzma") { return String(filename.dropLast(5)) }
        case .lzip:
            if lower.hasSuffix(".lz") { return String(filename.dropLast(3)) }
            if lower.hasSuffix(".lzip") { return String(filename.dropLast(5)) }
        default:
            break
        }
        return (filename as NSString).deletingPathExtension
    }

    public static func parseBsdtarListing(_ output: String, referenceDate: Date = Date()) -> [ArchiveEntry] {
        var entries: [ArchiveEntry] = []
        let lines = output.components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let parts = trimmed.split(maxSplits: 8, whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard parts.count == 9 else { continue }

            let modeStr = parts[0]
            guard let mode = modeStr.first, "dl-bcps".contains(mode), let size = Int64(parts[4]) else { continue }
            let isDir = modeStr.hasPrefix("d")
            let isSymlink = modeStr.hasPrefix("l")

            let modifiedAt = Self.parseBsdtarDate(
                monthToken: parts[5],
                dayToken: parts[6],
                timeOrYearToken: parts[7],
                referenceDate: referenceDate
            )

            let pathAndLink = parts[8]
            let path: String
            let symlinkTarget: String?

            if isSymlink && pathAndLink.contains(" -> ") {
                let linkComponents = pathAndLink.components(separatedBy: " -> ")
                path = linkComponents[0]
                symlinkTarget = linkComponents[1]
            } else {
                path = pathAndLink
                symlinkTarget = nil
            }

            guard !path.isEmpty else { continue }

            let type: EntryType
            if isDir || path.hasSuffix("/") {
                type = .directory
            } else if isSymlink {
                type = .symlink
            } else if mode != "-" {
                type = .special
            } else {
                type = .file
            }

            let entry = ArchiveEntry(
                path: path,
                type: type,
                uncompressedSize: size,
                compressedSize: 0,
                modifiedAt: modifiedAt,
                permissions: isDir ? 493 : 420,
                symlinkTarget: symlinkTarget
            )
            entries.append(entry)
        }

        return entries
    }

    private static let posixMonthMap: [String: Int] = [
        "jan": 1, "feb": 2, "mar": 3, "apr": 4,
        "may": 5, "jun": 6, "jul": 7, "aug": 8,
        "sep": 9, "oct": 10, "nov": 11, "dec": 12
    ]

    private static func parseBsdtarDate(
        monthToken: String,
        dayToken: String,
        timeOrYearToken: String,
        referenceDate: Date
    ) -> Date {
        let month: Int?
        if let mapped = posixMonthMap[monthToken.lowercased()] {
            month = mapped
        } else if monthToken.hasSuffix("月") {
            month = Int(monthToken.dropLast())
        } else {
            month = Int(monthToken)
        }

        guard let m = month, (1...12).contains(m),
              let day = Int(dayToken), (1...31).contains(day) else {
            return referenceDate
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current

        if timeOrYearToken.contains(":") {
            let hms = timeOrYearToken.split(separator: ":").compactMap { Int($0) }
            guard hms.count >= 2, (0...23).contains(hms[0]), (0...59).contains(hms[1]) else {
                return referenceDate
            }
            let second = hms.count >= 3 ? max(0, min(59, hms[2])) : 0
            let refYear = calendar.component(.year, from: referenceDate)
            let baseComponents = DateComponents(
                year: refYear,
                month: m,
                day: day,
                hour: hms[0],
                minute: hms[1],
                second: second
            )
            guard let candidate = calendar.date(from: baseComponents) else {
                return referenceDate
            }
            // bsdtar prints HH:MM when mtime is within ~6 months of referenceDate.
            let halfYearSeconds: TimeInterval = 183 * 86_400
            let delta = candidate.timeIntervalSince(referenceDate)
            if delta > halfYearSeconds,
               let prev = calendar.date(byAdding: .year, value: -1, to: candidate) {
                return prev
            } else if delta < -halfYearSeconds,
                      let next = calendar.date(byAdding: .year, value: 1, to: candidate) {
                return next
            }
            return candidate
        } else if let year = Int(timeOrYearToken), year >= 1900 {
            let components = DateComponents(year: year, month: m, day: day, hour: 0, minute: 0, second: 0)
            return calendar.date(from: components) ?? referenceDate
        }

        return referenceDate
    }
}
