import Darwin
import Foundation
import ProZipShared

/// Publishes an already verified, numbered split archive without replacing any existing family.
public enum SplitArchivePublication {
    public static let replacementUnavailableMessage = "暂不支持原地替换分卷族或同名基名文件；请选择“同时保留”或使用新名称。"

    /// Includes the base, all numeric parts (even incomplete families), and legacy ZIP .zNN parts.
    public static func existingItems(baseURL: URL) throws -> [URL] {
        let parent = baseURL.deletingLastPathComponent()
        let items: [URL]
        do { items = try FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil) }
        catch {
            let error = error as NSError
            if (error.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code)) ||
                (error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT)) { return [] }
            throw ProZipError.destinationNotWritable("无法检查分卷目标目录：\(error.localizedDescription)")
        }
        let base = baseURL.lastPathComponent.lowercased()
        let legacyPrefix = baseURL.pathExtension.lowercased() == "zip" ? baseURL.deletingPathExtension().lastPathComponent.lowercased() + ".z" : nil
        return items.filter { item in
            let name = item.lastPathComponent.lowercased()
            if name == base { return true }
            if name.hasPrefix(base + "."), isNumeric(String(name.dropFirst(base.count + 1))) { return true }
            if let legacyPrefix, name.hasPrefix(legacyPrefix), isNumeric(String(name.dropFirst(legacyPrefix.count))) { return true }
            return false
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    public static func ensureAvailable(baseURL: URL) throws {
        guard try existingItems(baseURL: baseURL).isEmpty else {
            throw ProZipError.destinationNotWritable(replacementUnavailableMessage)
        }
    }

    public static func uniqueBaseURL(for url: URL) throws -> URL {
        let parent = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var index = 2
        while true {
            var candidate = parent.appendingPathComponent("\(stem) (\(index))")
            if !ext.isEmpty { candidate.appendPathExtension(ext) }
            if try existingItems(baseURL: candidate).isEmpty { return candidate }
            index += 1
        }
    }

    public static func publishedFirstPart(baseURL: URL) throws -> URL {
        let parts = try validatedParts(existingItems(baseURL: baseURL))
        let first = baseURL.appendingPathExtension("001")
        guard parts[0].url.lastPathComponent.caseInsensitiveCompare(first.lastPathComponent) == .orderedSame,
              (try? Identity.capture(first)) == parts[0].identity else {
            throw ProZipError.splitVolumeIncomplete("未找到已发布的首卷")
        }
        return first
    }

    /// Splits verified archive bytes into a private child directory of outputBaseURL's parent.
    /// The caller removes that directory after publication; failures remove it here.
    public static func stageParts(archiveURL: URL, outputBaseURL: URL, plan: CreationProfile.SplitPlan) throws -> [URL] {
        try stageParts(archiveURL: archiveURL, outputBaseURL: outputBaseURL, plan: plan) { handle, count in
            try handle.read(upToCount: count)
        }
    }

    static func stageParts(archiveURL: URL, outputBaseURL: URL, plan: CreationProfile.SplitPlan,
                           read: (FileHandle, Int) throws -> Data?) throws -> [URL] {
        guard archiveURL.isFileURL, outputBaseURL.isFileURL,
              !outputBaseURL.lastPathComponent.isEmpty, outputBaseURL.lastPathComponent != "/" else {
            throw ProZipError.invalidCreationProfile("分卷归档与基名必须是本地文件")
        }
        let original = try Identity.capture(archiveURL)
        guard original.kind == UInt32(S_IFREG), original.size > 0 else {
            throw ProZipError.splitVolumeIncomplete("待分卷归档必须是非空普通文件")
        }
        let lengths: [Int64]
        let total = Int64(original.size)
        switch plan {
        case .byCount(let count):
            guard (2...999).contains(count) else { throw ProZipError.invalidCreationProfile("分卷数量必须在 2 到 999 之间") }
            guard total >= Int64(count) else { throw ProZipError.splitVolumeIncomplete("归档字节数不足以生成指定数量的非空分卷") }
            let quotient = total / Int64(count)
            let remainder = total % Int64(count)
            lengths = (0..<count).map { quotient + (Int64($0) < remainder ? 1 : 0) }
        case .bySize(let bytes):
            guard bytes >= 1024 else { throw ProZipError.invalidCreationProfile("每卷大小必须大于零（至少 1 KB）") }
            let count = total / bytes + (total % bytes == 0 ? 0 : 1)
            guard count <= 999 else { throw ProZipError.splitVolumeIncomplete("分卷数量超过 999，请增大每卷大小") }
            lengths = (0..<Int(count)).map { min(bytes, total - Int64($0) * bytes) }
        }
        try Task.checkCancellation()
        let descriptor = open(archiveURL.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let reader = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? reader.close() }
        guard try Identity.capture(fileDescriptor: descriptor) == original else { throw ProZipError.splitVolumeIncomplete("待分卷归档发生变化") }
        let fm = FileManager.default
        let directory = outputBaseURL.deletingLastPathComponent().appendingPathComponent(".prozip-parts-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var succeeded = false
        defer { if !succeeded { try? fm.removeItem(at: directory) } }
        var parts: [URL] = []
        for (index, length) in lengths.enumerated() {
            try Task.checkCancellation()
            let part = directory.appendingPathComponent(outputBaseURL.lastPathComponent).appendingPathExtension(String(format: "%03d", index + 1))
            let outputDescriptor = open(part.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, mode_t(0o600))
            guard outputDescriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            let writer = FileHandle(fileDescriptor: outputDescriptor, closeOnDealloc: true)
            defer { try? writer.close() }
            var remaining = length
            while remaining > 0 {
                try Task.checkCancellation()
                let requested = Int(min(remaining, 64 * 1024))
                guard let chunk = try read(reader, requested), !chunk.isEmpty, chunk.count <= requested else {
                    throw ProZipError.splitVolumeIncomplete("归档读取长度不足，未生成完整分卷")
                }
                try Task.checkCancellation()
                try writer.write(contentsOf: chunk)
                remaining -= Int64(chunk.count)
            }
            try writer.synchronize()
            try writer.close()
            guard try Identity.capture(part).size == length else { throw ProZipError.splitVolumeIncomplete("分卷大小与计划不一致") }
            parts.append(part)
        }
        try Task.checkCancellation()
        let extra = try read(reader, 1)
        guard extra?.isEmpty != false,
              try Identity.capture(fileDescriptor: descriptor) == original,
              try Identity.capture(archiveURL) == original else {
            throw ProZipError.splitVolumeIncomplete("归档在分卷期间发生变化，未发布压缩包")
        }
        succeeded = true
        return parts
    }

    /// Staged parts must be on the destination filesystem and named consistently as .001 ... .NNN.
    /// shortcut: No cross-file crash journal; replacement is refused until recovery can preserve an old family.
    @discardableResult
    public static func publish(stagedParts: [URL], baseURL: URL) throws -> URL {
        try publish(stagedParts: stagedParts, baseURL: baseURL) { source, destination in
            if renamex_np(source.path, destination.path, UInt32(RENAME_EXCL)) != 0 {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        }
    }

    // Separate the filesystem operation so a partial-publication failure can be tested deterministically.
    static func publish(stagedParts: [URL], baseURL: URL, move: (URL, URL) throws -> Void) throws -> URL {
        guard baseURL.isFileURL else { throw ProZipError.destinationNotWritable("分卷目标必须是本地文件") }
        let parts = try validatedParts(stagedParts)
        try ensureAvailable(baseURL: baseURL)
        try FileManager.default.createDirectory(at: baseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var published: [(URL, Identity)] = []
        do {
            for (index, part) in parts.enumerated() {
                try Task.checkCancellation()
                guard try Identity.capture(part.url) == part.identity else { throw ProZipError.splitVolumeIncomplete("待发布分卷发生变化") }
                let target = baseURL.appendingPathExtension(String(format: "%03d", index + 1))
                try move(part.url, target)
                published.append((target, part.identity))
            }
            try Task.checkCancellation()
            let expected = Set(published.map { $0.0.standardizedFileURL.path })
            guard Set(try existingItems(baseURL: baseURL).map { $0.standardizedFileURL.path }) == expected,
                  published.allSatisfy({ (try? Identity.capture($0.0)) == $0.1 }) else {
                throw ProZipError.destinationNotWritable("分卷发布期间目标发生变化；请选择“同时保留”或使用新名称。")
            }
            return published[0].0
        } catch {
            // Never remove a pre-existing or subsequently replaced file, only our own published inode.
            var rollbackFailed = false
            for (url, identity) in published.reversed() where (try? Identity.capture(url)) == identity {
                if unlink(url.path) != 0 { rollbackFailed = true }
            }
            if rollbackFailed { throw ProZipError.destinationNotWritable("分卷发布失败，部分本次新卷未能清理；已有文件未替换，请使用新名称。") }
            if error is CancellationError { throw error }
            if let error = error as? ProZipError { throw error }
            throw ProZipError.destinationNotWritable("分卷发布失败，未替换已有文件：\(error.localizedDescription)")
        }
    }

    private static func isNumeric(_ text: String) -> Bool {
        !text.isEmpty && text.utf8.allSatisfy { (48...57).contains($0) }
    }

    private static func validatedParts(_ urls: [URL]) throws -> [(url: URL, identity: Identity)] {
        guard (1...999).contains(urls.count) else { throw ProZipError.splitVolumeIncomplete("分卷数量必须在 1 到 999 之间") }
        let sorted = urls.sorted { $0.pathExtension < $1.pathExtension }
        let prefix = sorted[0].deletingPathExtension().lastPathComponent
        return try sorted.enumerated().map { index, url in
            guard url.isFileURL, url.pathExtension == String(format: "%03d", index + 1),
                  url.deletingPathExtension().lastPathComponent == prefix else {
                throw ProZipError.splitVolumeIncomplete("分卷名称不连续或不属于同一归档，未发布压缩包")
            }
            let identity = try Identity.capture(url)
            guard identity.kind == UInt32(S_IFREG), identity.size > 0 else {
                throw ProZipError.splitVolumeIncomplete("分卷必须是非空普通文件，未发布压缩包")
            }
            return (url, identity)
        }
    }

    private struct Identity: Equatable {
        let device: dev_t
        let inode: ino_t
        let kind: UInt32
        let size: off_t
        let birthSeconds: Int
        let birthNanoseconds: Int
        let modifiedSeconds: Int
        let modifiedNanoseconds: Int

        static func capture(_ url: URL) throws -> Identity {
            var info = stat()
            guard lstat(url.path, &info) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            return identity(info)
        }

        static func capture(fileDescriptor: Int32) throws -> Identity {
            var info = stat()
            guard fstat(fileDescriptor, &info) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            return identity(info)
        }

        private static func identity(_ info: stat) -> Identity {
            return Identity(device: info.st_dev, inode: info.st_ino, kind: UInt32(info.st_mode) & UInt32(S_IFMT), size: info.st_size,
                            birthSeconds: info.st_birthtimespec.tv_sec, birthNanoseconds: info.st_birthtimespec.tv_nsec,
                            modifiedSeconds: info.st_mtimespec.tv_sec, modifiedNanoseconds: info.st_mtimespec.tv_nsec)
        }
    }
}
