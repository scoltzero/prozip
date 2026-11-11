import CArchive
import Darwin
import Foundation

struct ArchivePreviewLimits: Sendable {
    var maxEntries = 500
    var maxFileBytes: Int64 = 128 * 1024 * 1024
    var maxSourceReadBytes: Int64 = 64 * 1024 * 1024
    var maxDecodedBytes: Int64 = 16 * 1024 * 1024
    var maxMemberBytes: Int64 = 8 * 1024 * 1024
    var maxNameBytes = 4096
    var maxSeconds: Double = 3
}

enum ArchivePreviewLimit: Equatable, Sendable {
    case sourceFile, sourceReads, entries, decodedData, memberSize, unknownSize, metadata, time
}

enum ArchivePreviewStatus: Equatable, Sendable {
    case complete
    case limited(ArchivePreviewLimit)
    case encrypted
    case unsupported
    case unreadable
    case cancelled

    func message(visibleCount: Int) -> String {
        switch self {
        case .complete: return "共 \(visibleCount) 个项目"
        case .encrypted: return "此归档需要密码；目录预览可能不完整，请在 ProZip 中打开。"
        case .unsupported: return "此格式暂不支持快速预览，请在 ProZip 中打开。"
        case .unreadable: return "无法完整读取归档目录；文件可能损坏或不受支持。"
        case .cancelled: return "预览已取消。"
        case .limited(let reason):
            let detail: String
            switch reason {
            case .sourceFile: detail = "归档超过快速预览文件大小上限"
            case .sourceReads: detail = "已达到归档读取预算"
            case .entries: detail = "已达到目录显示上限"
            case .decodedData: detail = "已达到内容读取预算"
            case .memberSize: detail = "遇到过大或大小不一致的成员"
            case .unknownSize: detail = "遇到大小未知的成员"
            case .metadata: detail = "目录项名称超过预览上限或无法解码"
            case .time: detail = "已达到快速预览时间上限"
            }
            return "已显示 \(visibleCount) 个项目，\(detail)。列表可能不完整。"
        }
    }
}

struct ArchivePreviewEntry: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case file, directory, symbolicLink, hardLink, special
    }
    let path: String
    let size: Int64?
    let modifiedAt: Date?
    let kind: Kind
}

struct ArchivePreviewListing: Sendable {
    let archiveName: String
    var sourceSize: Int64?
    var entries: [ArchivePreviewEntry] = []
    var status: ArchivePreviewStatus = .unreadable
    var sourceBytesRead: Int64 = 0
    var decodedBytes: Int64 = 0
}

private final class ArchivePreviewInput {
    var descriptor: Int32
    let fileSize: Int64
    let limits: ArchivePreviewLimits
    let isCancelled: @Sendable () -> Bool
    let buffer = UnsafeMutableRawPointer.allocate(byteCount: 32 * 1024, alignment: 16)
    let started = DispatchTime.now().uptimeNanoseconds
    var offset: Int64 = 0
    var bytesRead: Int64 = 0
    var failure: ArchivePreviewStatus?

    init(descriptor: Int32, fileSize: Int64, limits: ArchivePreviewLimits, isCancelled: @escaping @Sendable () -> Bool) {
        self.descriptor = descriptor
        self.fileSize = fileSize
        self.limits = limits
        self.isCancelled = isCancelled
    }

    func canContinue() -> Bool {
        if isCancelled() { failure = .cancelled }
        else if Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000 >= limits.maxSeconds {
            failure = .limited(.time)
        }
        return failure == nil
    }

    func close() {
        if descriptor >= 0 { Darwin.close(descriptor); descriptor = -1 }
    }

    deinit { close(); buffer.deallocate() }
}

private func previewArchiveRead(_ archive: OpaquePointer?, _ client: UnsafeMutableRawPointer?, _ output: UnsafeMutablePointer<UnsafeRawPointer?>?) -> Int {
    guard let client, let output else { return -1 }
    let input = Unmanaged<ArchivePreviewInput>.fromOpaque(client).takeUnretainedValue()
    guard input.canContinue() else { return -1 }
    if input.offset == input.fileSize { return 0 }
    let remaining = max(0, input.limits.maxSourceReadBytes) - input.bytesRead
    guard remaining > 0 else { input.failure = .limited(.sourceReads); return -1 }
    var count: Int
    repeat {
        count = Darwin.read(input.descriptor, input.buffer, Int(min(32 * 1024, remaining, input.fileSize - input.offset)))
    } while count < 0 && errno == EINTR && input.canContinue()
    guard count >= 0 else { input.failure = input.failure ?? .unreadable; return -1 }
    guard count > 0 || input.offset == input.fileSize else { input.failure = .unreadable; return -1 }
    input.offset += Int64(count)
    input.bytesRead += Int64(count)
    output.pointee = UnsafeRawPointer(input.buffer)
    return count
}

private func previewArchiveSeek(_ archive: OpaquePointer?, _ client: UnsafeMutableRawPointer?, _ offset: Int64, _ whence: Int32) -> Int64 {
    guard let client else { return -1 }
    let input = Unmanaged<ArchivePreviewInput>.fromOpaque(client).takeUnretainedValue()
    guard input.canContinue() else { return -1 }
    let base: Int64
    switch whence {
    case SEEK_SET: base = 0
    case SEEK_CUR: base = input.offset
    case SEEK_END: base = input.fileSize
    default: input.failure = .unreadable; return -1
    }
    let target = base.addingReportingOverflow(offset)
    guard !target.overflow, target.partialValue >= 0, target.partialValue <= input.fileSize,
          Darwin.lseek(input.descriptor, target.partialValue, SEEK_SET) >= 0 else { input.failure = .unreadable; return -1 }
    input.offset = target.partialValue
    return input.offset
}

private func previewArchiveClose(_ archive: OpaquePointer?, _ client: UnsafeMutableRawPointer?) -> Int32 {
    if let client { Unmanaged<ArchivePreviewInput>.fromOpaque(client).takeUnretainedValue().close() }
    return ARCHIVE_OK
}

enum ArchivePreviewReader {
    static func mainAppURL(for file: URL) -> URL? {
        guard validFileURL(file) else { return nil }
        var components = URLComponents()
        components.scheme = "prozip"
        components.host = "finder-action"
        components.queryItems = [URLQueryItem(name: "action", value: "browseArchive"), URLQueryItem(name: "file", value: file.standardizedFileURL.absoluteString)]
        return components.url
    }

    private static func validFileURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return url.isFileURL && url.path.hasPrefix("/") && !components.percentEncodedPath.lowercased().contains("%00") &&
            url.user == nil && url.password == nil && url.port == nil && url.query == nil && url.fragment == nil &&
            (url.host == nil || url.host == "" || url.host?.lowercased() == "localhost")
    }

    /// Synchronous work is called from the controller's detached task, never from its UI callback.
    static func read(_ url: URL, limits: ArchivePreviewLimits = ArchivePreviewLimits(), isCancelled: @escaping @Sendable () -> Bool = { Task.isCancelled }) -> ArchivePreviewListing {
        var listing = ArchivePreviewListing(archiveName: url.lastPathComponent)
        guard validFileURL(url) else { return listing }
        if isCancelled() { listing.status = .cancelled; return listing }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let descriptor = url.withUnsafeFileSystemRepresentation { path in
            path.map { Darwin.open($0, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK) } ?? -1
        }
        guard descriptor >= 0 else { return listing }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (UInt32(info.st_mode) & UInt32(S_IFMT)) == UInt32(S_IFREG), info.st_size >= 0 else {
            Darwin.close(descriptor)
            return listing
        }
        listing.sourceSize = info.st_size
        guard info.st_size <= max(0, limits.maxFileBytes) else {
            Darwin.close(descriptor)
            listing.status = .limited(.sourceFile)
            return listing
        }
        let input = ArchivePreviewInput(descriptor: descriptor, fileSize: info.st_size, limits: limits, isCancelled: isCancelled)
        guard let reader = archive_read_new() else { return listing }
        defer { _ = withExtendedLifetime(input) { archive_read_free(reader) } }
        archive_read_support_filter_none(reader)
        archive_read_support_format_zip(reader)
        archive_read_support_format_tar(reader)
        archive_read_support_format_7zip(reader)
        // mac-ext may decode companion resource-fork entries while reading a header.
        archive_read_set_options(reader, "zip:!mac-ext,tar:!mac-ext")
        archive_read_set_seek_callback(reader, previewArchiveSeek)
        let opened = archive_read_open2(reader, Unmanaged.passUnretained(input).toOpaque(), nil, previewArchiveRead, nil, previewArchiveClose)
        var status: ArchivePreviewStatus = .unreadable
        func parserFailure() -> ArchivePreviewStatus {
            if let failure = input.failure { return failure }
            let message = boundedString(archive_error_string(reader), maximum: 1024)?.lowercased() ?? ""
            if archive_read_has_encrypted_entries(reader) == 1 || message.contains("passphrase") || message.contains("password") || message.contains("encrypted") { return .encrypted }
            return archive_format(reader) == 0 ? .unsupported : .unreadable
        }
        guard opened == ARCHIVE_OK else {
            listing.status = parserFailure()
            listing.sourceBytesRead = input.bytesRead
            return listing
        }
        let entryLimit = min(500, max(0, limits.maxEntries))
        let dataBuffer = UnsafeMutableRawPointer.allocate(byteCount: 64 * 1024, alignment: 16)
        defer { dataBuffer.deallocate() }
        reading: while input.canContinue() {
            if listing.entries.count >= entryLimit { status = .limited(.entries); break }
            var entry: OpaquePointer?
            let result = archive_read_next_header(reader, &entry)
            if result == ARCHIVE_EOF { status = .complete; break }
            guard (result == ARCHIVE_OK || result == ARCHIVE_WARN), let entry else { status = parserFailure(); break }
            guard let path = boundedString(archive_entry_pathname_utf8(entry) ?? archive_entry_pathname(entry), maximum: min(4096, max(0, limits.maxNameBytes))) else {
                status = .limited(.metadata); break
            }
            let rawSize = archive_entry_size(entry)
            let size = archive_entry_size_is_set(entry) != 0 && rawSize >= 0 ? rawSize : nil
            let mode = UInt32(archive_entry_filetype(entry)) & UInt32(S_IFMT)
            let kind: ArchivePreviewEntry.Kind
            if archive_entry_hardlink(entry) != nil { kind = .hardLink }
            else if mode == UInt32(S_IFDIR) { kind = .directory }
            else if mode == UInt32(S_IFLNK) { kind = .symbolicLink }
            else if mode == UInt32(S_IFREG) { kind = .file }
            else { kind = .special }
            let mtime = Int64(archive_entry_mtime(entry))
            let date = archive_entry_mtime_is_set(entry) != 0 && (-62_135_596_800...253_402_300_799).contains(mtime) ? Date(timeIntervalSince1970: Double(mtime)) : nil
            listing.entries.append(ArchivePreviewEntry(path: path, size: size, modifiedAt: date, kind: kind))
            if archive_entry_is_encrypted(entry) != 0 || archive_read_has_encrypted_entries(reader) == 1 { status = .encrypted; break }
            if listing.entries.count >= entryLimit { status = .limited(.entries); break }
            guard let size else { status = .limited(.unknownSize); break }
            guard size <= max(0, limits.maxMemberBytes) else { status = .limited(.memberSize); break }
            guard size <= max(0, limits.maxDecodedBytes - listing.decodedBytes) else { status = .limited(.decodedData); break }
            var memberBytes: Int64 = 0
            // Never call next_header/data_skip on an unread large or unknown member.
            // Known small entries are drained with a bounded EOF probe before advancing.
            while input.canContinue() {
                let remaining = limits.maxDecodedBytes - listing.decodedBytes
                guard remaining > 0 else { status = .limited(.decodedData); break reading }
                let count = Int(min(64 * 1024, remaining, max(1, size - memberBytes)))
                let bytes = archive_read_data(reader, dataBuffer, count)
                guard bytes >= 0 else { status = parserFailure(); break reading }
                if bytes == 0 {
                    guard memberBytes == size else { status = .unreadable; break reading }
                    break
                }
                memberBytes += Int64(bytes)
                listing.decodedBytes += Int64(bytes)
                guard memberBytes <= size else { status = .limited(.memberSize); break reading }
            }
            if let failure = input.failure { status = failure; break }
        }
        listing.status = input.failure ?? status
        listing.sourceBytesRead = input.bytesRead
        return listing
    }

    private static func boundedString(_ pointer: UnsafePointer<CChar>?, maximum: Int) -> String? {
        guard let pointer, maximum > 0 else { return nil }
        let count = strnlen(pointer, maximum + 1)
        guard count <= maximum else { return nil }
        return String(bytes: UnsafeRawBufferPointer(start: pointer, count: count), encoding: .utf8)
    }
}
