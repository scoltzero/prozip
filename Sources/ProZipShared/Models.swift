import Foundation

// MARK: - Archive Format

public enum ArchiveFormat: String, Codable, CaseIterable, Hashable, Sendable {
    case zip
    case sevenZip = "7z"
    case rar
    case tar
    case tarGz = "tar.gz"
    case tarBz2 = "tar.bz2"
    case tarXz = "tar.xz"
    case gzip = "gz"
    case bzip2 = "bz2"
    case xz
    case lzma
    case lzip = "lz"
    case dmg
    case iso
    case cab
    case cpio
    case arj
    case lha
    case xar
    case rpm
    case msi
    case pkg
    case jar
    case apk
    case spk
    case exe
    case swf
    case unknown

    public var displayName: String {
        switch self {
        case .zip: return "ZIP 压缩包"
        case .sevenZip: return "7Z 压缩包"
        case .rar: return "RAR 压缩包"
        case .tar: return "TAR 归档"
        case .tarGz: return "TAR.GZ 压缩包"
        case .tarBz2: return "TAR.BZ2 压缩包"
        case .tarXz: return "TAR.XZ 压缩包"
        case .gzip: return "GZIP 压缩流"
        case .bzip2: return "BZIP2 压缩流"
        case .xz: return "XZ 压缩流"
        case .lzma: return "LZMA 压缩流"
        case .lzip: return "Lzip 压缩流"
        case .dmg: return "DMG 磁盘映像"
        case .iso: return "ISO 光盘映像"
        case .cab: return "CAB 压缩包"
        case .cpio: return "CPIO 归档"
        case .arj: return "ARJ 压缩包"
        case .lha: return "LHA 压缩包"
        case .xar: return "XAR 归档"
        case .rpm: return "RPM 软件包"
        case .msi: return "MSI 安装包"
        case .pkg: return "PKG 安装包"
        case .jar: return "JAR 归档"
        case .apk: return "APK 应用包"
        case .spk: return "SPK 套件包"
        case .exe: return "EXE 自解压包"
        case .swf: return "SWF 容器"
        case .unknown: return "未知格式"
        }
    }

    public var defaultExtension: String {
        rawValue
    }

    public var isSingleStream: Bool {
        switch self {
        case .gzip, .bzip2, .xz, .lzma, .lzip:
            return true
        default:
            return false
        }
    }

    public var isDiskImage: Bool {
        self == .dmg || self == .iso
    }

    public var isZipFamily: Bool {
        switch self {
        case .zip, .jar, .apk:
            return true
        default:
            return false
        }
    }

    public var supportsCreation: Bool {
        switch self {
        case .zip, .sevenZip, .tar, .tarGz, .tarBz2, .tarXz, .gzip, .bzip2, .xz:
            return true
        default:
            return false
        }
    }

    public var supportsSplitVolumes: Bool {
        self == .zip || self == .sevenZip
    }

    public var supportsEncryptionWrite: Bool {
        self == .zip || self == .sevenZip
    }

    public var supportsHeaderEncryption: Bool {
        self == .sevenZip
    }

    public static func detect(from url: URL, magicBytes: Data? = nil) -> ArchiveFormat {
        let filename = url.lastPathComponent.lowercased()

        // Strip numeric split suffix (.001 .. .999) if preceded by another extension
        let normalizedName: String
        if let range = filename.range(of: #"\.\d{3}$"#, options: .regularExpression) {
            let prefix = String(filename[..<range.lowerBound])
            if prefix.contains(".") {
                normalizedName = prefix
            } else {
                normalizedName = filename
            }
        } else {
            normalizedName = filename
        }

        if normalizedName.hasSuffix(".tar.gz") || normalizedName.hasSuffix(".tgz") {
            return .tarGz
        }
        if normalizedName.hasSuffix(".tar.bz2") || normalizedName.hasSuffix(".tbz") || normalizedName.hasSuffix(".tbz2") {
            return .tarBz2
        }
        if normalizedName.hasSuffix(".tar.xz") || normalizedName.hasSuffix(".txz") {
            return .tarXz
        }

        // Check magic bytes first if provided
        if let magic = magicBytes, magic.count >= 4 {
            let bytes = [UInt8](magic.prefix(8))
            // PK\x03\x04 or PK\x05\x06 (empty zip) or PK\x07\x08 (spanned zip)
            if bytes[0] == 0x50 && bytes[1] == 0x4B &&
                (bytes[2] == 0x03 || bytes[2] == 0x05 || bytes[2] == 0x07) {
                let ext = (normalizedName as NSString).pathExtension
                if ext == "jar" { return .jar }
                if ext == "apk" { return .apk }
                return .zip
            }
            // 7z magic: 37 7A BC AF 27 1C
            if bytes.count >= 6 && bytes[0] == 0x37 && bytes[1] == 0x7A &&
                bytes[2] == 0xBC && bytes[3] == 0xAF && bytes[4] == 0x27 && bytes[5] == 0x1C {
                return .sevenZip
            }
            // RAR magic: 52 61 72 21 1A 07
            if bytes.count >= 6 && bytes[0] == 0x52 && bytes[1] == 0x61 &&
                bytes[2] == 0x72 && bytes[3] == 0x21 && bytes[4] == 0x1A && bytes[5] == 0x07 {
                return .rar
            }
            // GZ magic: 1F 8B
            if bytes[0] == 0x1F && bytes[1] == 0x8B {
                return .gzip
            }
            // BZ2 magic: 42 5A 68 ("BZh")
            if bytes[0] == 0x42 && bytes[1] == 0x5A && bytes[2] == 0x68 {
                return .bzip2
            }
            // XZ magic: FD 37 7A 58 5A 00
            if bytes.count >= 6 && bytes[0] == 0xFD && bytes[1] == 0x37 &&
                bytes[2] == 0x7A && bytes[3] == 0x58 && bytes[4] == 0x5A && bytes[5] == 0x00 {
                return .xz
            }
            // LZIP magic: 4C 5A 49 50 ("LZIP")
            if bytes[0] == 0x4C && bytes[1] == 0x5A && bytes[2] == 0x49 && bytes[3] == 0x50 {
                return .lzip
            }
            // XAR magic: 78 61 72 21 ("xar!")
            if bytes[0] == 0x78 && bytes[1] == 0x61 && bytes[2] == 0x72 && bytes[3] == 0x21 {
                let ext = (normalizedName as NSString).pathExtension
                if ext == "pkg" { return .pkg }
                return .xar
            }
            // CAB magic: 4D 53 43 46 ("MSCF")
            if bytes[0] == 0x4D && bytes[1] == 0x53 && bytes[2] == 0x43 && bytes[3] == 0x46 {
                return .cab
            }
            // RPM magic: ED AB EE DB
            if bytes[0] == 0xED && bytes[1] == 0xAB && bytes[2] == 0xEE && bytes[3] == 0xDB {
                return .rpm
            }
        }

        let ext = (normalizedName as NSString).pathExtension.lowercased()
        switch ext {
        case "zip", "zipx", "cbz": return .zip
        case "z01"..."z99": return .zip
        case "7z", "cb7": return .sevenZip
        case "rar", "cbr": return .rar
        case "r00"..."r99": return .rar
        case "tar": return .tar
        case "gz", "gzip": return .gzip
        case "bz2", "bzip2": return .bzip2
        case "xz": return .xz
        case "lzma": return .lzma
        case "lz", "lzip": return .lzip
        case "dmg", "sparseimage", "cdr": return .dmg
        case "iso", "udf": return .iso
        case "cab": return .cab
        case "cpio": return .cpio
        case "arj": return .arj
        case "lha", "lzh": return .lha
        case "xar": return .xar
        case "rpm": return .rpm
        case "msi": return .msi
        case "pkg": return .pkg
        case "jar": return .jar
        case "apk": return .apk
        case "spk": return .spk
        case "exe": return .exe
        case "swf": return .swf
        default:
            // Read first 8 bytes on disk if file exists
            if magicBytes == nil, let handle = try? FileHandle(forReadingFrom: url) {
                defer { try? handle.close() }
                if let head = try? handle.read(upToCount: 8), !head.isEmpty {
                    return detect(from: url, magicBytes: head)
                }
            }
            return .unknown
        }
    }
}

// MARK: - Split Volume Family Detection

public struct SplitVolumeFamily: Sendable, Equatable {
    public let primaryVolumeURL: URL
    public let volumeURLs: [URL]
    public let isSplit: Bool
    public let isComplete: Bool
    public let hasEmptyVolume: Bool

    public init(primaryVolumeURL: URL, volumeURLs: [URL], isSplit: Bool, isComplete: Bool, hasEmptyVolume: Bool) {
        self.primaryVolumeURL = primaryVolumeURL
        self.volumeURLs = volumeURLs
        self.isSplit = isSplit
        self.isComplete = isComplete
        self.hasEmptyVolume = hasEmptyVolume
    }

    public static func resolve(for url: URL) -> SplitVolumeFamily {
        let dir = url.deletingLastPathComponent()
        let filename = url.lastPathComponent
        let fm = FileManager.default

        // Case 1: .001 ... .999
        if let match = filename.range(of: #"\.(\d{3})$"#, options: .regularExpression) {
            let base = String(filename[..<match.lowerBound])
            var volumes: [(Int, URL)] = []
            if let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) {
                for item in items {
                    let name = item.lastPathComponent
                    if name.hasPrefix(base + "."), name.count == base.count + 4 {
                        let suffix = String(name.suffix(3))
                        if let num = Int(suffix), num >= 1 && num <= 999 {
                            volumes.append((num, item))
                        }
                    }
                }
            }
            volumes.sort { $0.0 < $1.0 }
            let urls = volumes.map(\.1)
            let primary = urls.first ?? dir.appendingPathComponent("\(base).001")
            let expectedIndices = Array(1...max(1, volumes.count))
            let actualIndices = volumes.map(\.0)
            let complete = !volumes.isEmpty && actualIndices == expectedIndices
            let hasEmpty = urls.contains { u in
                let size = (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return size <= 0
            }
            return SplitVolumeFamily(
                primaryVolumeURL: primary,
                volumeURLs: urls.isEmpty ? [url] : urls,
                isSplit: true,
                isComplete: complete,
                hasEmptyVolume: hasEmpty
            )
        }

        // Case 2: .z01 ... .z99 + .zip
        if filename.range(of: #"\.(z\d{2}|zip)$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            let base = (filename as NSString).deletingPathExtension
            let zipURL = dir.appendingPathComponent("\(base).zip")
            let z01URL = dir.appendingPathComponent("\(base).z01")
            if fm.fileExists(atPath: z01URL.path) {
                var zParts: [(Int, URL)] = []
                if let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) {
                    for item in items {
                        let name = item.lastPathComponent
                        if name.lowercased().hasPrefix(base.lowercased() + ".z"), name.count == base.count + 4 {
                            let suffix = String(name.suffix(2))
                            if let num = Int(suffix), num >= 1 {
                                zParts.append((num, item))
                            }
                        }
                    }
                }
                zParts.sort { $0.0 < $1.0 }
                var urls = zParts.map(\.1)
                let hasFinalZip = fm.fileExists(atPath: zipURL.path)
                if hasFinalZip {
                    urls.append(zipURL)
                }
                let expectedIndices = Array(1...max(1, zParts.count))
                let complete = hasFinalZip && zParts.map(\.0) == expectedIndices
                let hasEmpty = urls.contains { u in
                    let size = (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    return size <= 0
                }
                return SplitVolumeFamily(
                    primaryVolumeURL: z01URL,
                    volumeURLs: urls,
                    isSplit: true,
                    isComplete: complete,
                    hasEmptyVolume: hasEmpty
                )
            }
        }

        // Case 3: .partN.rar
        if let match = filename.range(of: #"\.part(\d+)\.rar$"#, options: [.regularExpression, .caseInsensitive]) {
            let base = String(filename[..<match.lowerBound])
            var parts: [(Int, URL)] = []
            if let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) {
                for item in items {
                    let name = item.lastPathComponent
                    if name.lowercased().hasPrefix(base.lowercased() + ".part") && name.lowercased().hasSuffix(".rar") {
                        let mid = name.dropFirst(base.count + 5).dropLast(4)
                        if let num = Int(mid), num >= 1 {
                            parts.append((num, item))
                        }
                    }
                }
            }
            parts.sort { $0.0 < $1.0 }
            let urls = parts.map(\.1)
            let primary = urls.first ?? url
            let complete = !parts.isEmpty && parts.map(\.0) == Array(1...parts.count)
            let hasEmpty = urls.contains { u in
                let size = (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return size <= 0
            }
            return SplitVolumeFamily(
                primaryVolumeURL: primary,
                volumeURLs: urls.isEmpty ? [url] : urls,
                isSplit: true,
                isComplete: complete,
                hasEmptyVolume: hasEmpty
            )
        }

        // Single volume
        let exists = fm.fileExists(atPath: url.path)
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return SplitVolumeFamily(
            primaryVolumeURL: url,
            volumeURLs: [url],
            isSplit: false,
            isComplete: exists,
            hasEmptyVolume: exists && size == 0
        )
    }
}

// MARK: - Archive Entry & Payload

public enum EntryType: String, Codable, Hashable, Sendable {
    case file
    case directory
    case symlink
    case special
}

public struct ArchiveEntry: Codable, Hashable, Identifiable, Sendable {
    public let id: String            // "<path>#<crc32>#<size>" or "<path>/#0#0"
    public let path: String          // Archive-relative normalized path (no leading or trailing slash)
    public let type: EntryType
    public let uncompressedSize: Int64
    public let compressedSize: Int64
    public let modifiedAt: Date      // Stored as Apple epoch seconds in SQLite payload
    public let permissions: UInt16
    public let crc32: UInt32
    public let isEncrypted: Bool
    public let symlinkTarget: String?
    public let isAuxiliary: Bool
    public let isDiskImageBackground: Bool
    public let isApplicationsShortcut: Bool
    public let encryptionGroupID: String?

    public var name: String {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if let lastSlash = trimmed.lastIndex(of: "/") {
            return String(trimmed[trimmed.index(after: lastSlash)...])
        }
        return trimmed
    }

    public var parentPath: String {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if let lastSlash = trimmed.lastIndex(of: "/") {
            return String(trimmed[..<lastSlash])
        }
        return ""
    }

    public var isDirectory: Bool {
        type == .directory
    }

    public var fileExtension: String {
        (name as NSString).pathExtension.lowercased()
    }

    public static func makeID(path: String, type: EntryType, crc32: UInt32, uncompressedSize: Int64) -> String {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if type == .directory {
            return "\(trimmed)/#0#0"
        }
        return "\(trimmed)#\(crc32)#\(uncompressedSize)"
    }

    public static func detectAuxiliary(path: String) -> Bool {
        let components = path.split(separator: "/").map(String.init)
        guard let last = components.last else { return false }

        if components.contains("__MACOSX") { return true }
        if last.hasPrefix("._") { return true }

        let exactAuxNames: Set<String> = [
            ".ds_store",
            "thumbs.db",
            "desktop.ini",
            ".spotlight-v100",
            ".fseventsd",
            ".trashes",
            ".temporaryitems",
            ".apdisk"
        ]
        if exactAuxNames.contains(last.lowercased()) {
            return true
        }
        if components.contains(where: { exactAuxNames.contains($0.lowercased()) }) {
            return true
        }
        // Keep developer dot-files like .gitignore, .env, .editorconfig
        return false
    }

    public static func detectDiskImageBackground(path: String) -> Bool {
        let components = path.split(separator: "/").map { $0.lowercased() }
        if components.contains(".background") { return true }
        if let last = components.last, last == ".volumeicon.icns" || last == ".ds_store" {
            return true
        }
        return false
    }

    public static func detectApplicationsShortcut(path: String, type: EntryType, symlinkTarget: String?) -> Bool {
        let name = (path as NSString).lastPathComponent
        if type == .symlink, let target = symlinkTarget {
            if target == "/Applications" || target == "/Applications/" {
                return true
            }
        }
        if name == "Applications" && type == .symlink {
            return true
        }
        return false
    }

    public init(
        id: String? = nil,
        path: String,
        type: EntryType,
        uncompressedSize: Int64 = 0,
        compressedSize: Int64 = 0,
        modifiedAt: Date = Date(),
        permissions: UInt16? = nil,
        crc32: UInt32 = 0,
        isEncrypted: Bool = false,
        symlinkTarget: String? = nil,
        isAuxiliary: Bool? = nil,
        isDiskImageBackground: Bool? = nil,
        isApplicationsShortcut: Bool? = nil,
        encryptionGroupID: String? = nil
    ) {
        let normalizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.path = normalizedPath
        self.type = type
        self.uncompressedSize = type == .directory ? 0 : uncompressedSize
        self.compressedSize = type == .directory ? 0 : compressedSize
        self.modifiedAt = modifiedAt
        self.permissions = permissions ?? (type == .directory ? 493 : 420) // 0755 : 0644
        self.crc32 = type == .directory ? 0 : crc32
        self.isEncrypted = isEncrypted
        self.symlinkTarget = symlinkTarget
        self.isAuxiliary = isAuxiliary ?? Self.detectAuxiliary(path: normalizedPath)
        self.isDiskImageBackground = isDiskImageBackground ?? Self.detectDiskImageBackground(path: normalizedPath)
        self.isApplicationsShortcut = isApplicationsShortcut ?? Self.detectApplicationsShortcut(
            path: normalizedPath,
            type: type,
            symlinkTarget: symlinkTarget
        )
        self.encryptionGroupID = encryptionGroupID
        self.id = id ?? Self.makeID(
            path: normalizedPath,
            type: type,
            crc32: self.crc32,
            uncompressedSize: self.uncompressedSize
        )
    }

    // Payload representation matching doc/02-浏览与索引.md section 2.2
    private enum CodingKeys: String, CodingKey {
        case id
        case path
        case type
        case modifiedAt
        case permissions
        case uncompressedSize
        case compressedSize
        case encrypted
        case checksum
        case symlinkTarget
        case isAuxiliary
        case isDiskImageBackground
        case isApplicationsShortcut
        case encryptionGroupID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let path = try container.decode(String.self, forKey: .path)
        let type = try container.decode(EntryType.self, forKey: .type)
        let appleEpochSeconds = try container.decodeIfPresent(Double.self, forKey: .modifiedAt) ?? 0
        let modifiedAt = Date(timeIntervalSinceReferenceDate: appleEpochSeconds)
        let permissions = try container.decodeIfPresent(UInt16.self, forKey: .permissions) ?? (type == .directory ? 493 : 420)
        let uncompressedSize = try container.decodeIfPresent(Int64.self, forKey: .uncompressedSize) ?? 0
        let compressedSize = try container.decodeIfPresent(Int64.self, forKey: .compressedSize) ?? 0
        let encrypted = try container.decodeIfPresent(Bool.self, forKey: .encrypted) ?? false
        let checksum = try container.decodeIfPresent(UInt32.self, forKey: .checksum) ?? 0
        let symlinkTarget = try container.decodeIfPresent(String.self, forKey: .symlinkTarget)
        let decodedID = try container.decodeIfPresent(String.self, forKey: .id)
        let aux = try container.decodeIfPresent(Bool.self, forKey: .isAuxiliary)
        let dmgBg = try container.decodeIfPresent(Bool.self, forKey: .isDiskImageBackground)
        let dmgApp = try container.decodeIfPresent(Bool.self, forKey: .isApplicationsShortcut)
        let groupID = try container.decodeIfPresent(String.self, forKey: .encryptionGroupID)

        self.init(
            id: decodedID,
            path: path,
            type: type,
            uncompressedSize: uncompressedSize,
            compressedSize: compressedSize,
            modifiedAt: modifiedAt,
            permissions: permissions,
            crc32: checksum,
            isEncrypted: encrypted,
            symlinkTarget: symlinkTarget,
            isAuxiliary: aux,
            isDiskImageBackground: dmgBg,
            isApplicationsShortcut: dmgApp,
            encryptionGroupID: groupID
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(path, forKey: .path)
        try container.encode(type, forKey: .type)
        try container.encode(Int64(modifiedAt.timeIntervalSinceReferenceDate), forKey: .modifiedAt)
        try container.encode(permissions, forKey: .permissions)
        try container.encode(uncompressedSize, forKey: .uncompressedSize)
        try container.encode(compressedSize, forKey: .compressedSize)
        try container.encode(isEncrypted, forKey: .encrypted)
        try container.encode(crc32, forKey: .checksum)
        try container.encodeIfPresent(symlinkTarget, forKey: .symlinkTarget)
        try container.encode(isAuxiliary, forKey: .isAuxiliary)
        try container.encode(isDiskImageBackground, forKey: .isDiskImageBackground)
        try container.encode(isApplicationsShortcut, forKey: .isApplicationsShortcut)
        try container.encodeIfPresent(encryptionGroupID, forKey: .encryptionGroupID)
    }
}

// MARK: - Archive Descriptor

public struct ArchiveDescriptor: Codable, Hashable, Sendable {
    public let url: URL
    public let primaryVolumeURL: URL
    public let volumeURLs: [URL]
    public let format: ArchiveFormat
    public let isEncrypted: Bool
    public let hasEncryptedHeaders: Bool
    public let isSplitVolume: Bool
    public let isConcatenated: Bool
    public let hasNonUTF8Encoding: Bool
    public let detectedEncodingName: String?
    public let totalCompressedSize: Int64
    public let entryCountHint: Int?
    public let comment: String?

    public init(
        url: URL,
        primaryVolumeURL: URL? = nil,
        volumeURLs: [URL]? = nil,
        format: ArchiveFormat,
        isEncrypted: Bool = false,
        hasEncryptedHeaders: Bool = false,
        isSplitVolume: Bool = false,
        isConcatenated: Bool = false,
        hasNonUTF8Encoding: Bool = false,
        detectedEncodingName: String? = "UTF-8",
        totalCompressedSize: Int64 = 0,
        entryCountHint: Int? = nil,
        comment: String? = nil
    ) {
        self.url = url
        self.primaryVolumeURL = primaryVolumeURL ?? url
        self.volumeURLs = volumeURLs ?? [url]
        self.format = format
        self.isEncrypted = isEncrypted
        self.hasEncryptedHeaders = hasEncryptedHeaders
        self.isSplitVolume = isSplitVolume
        self.isConcatenated = isConcatenated
        self.hasNonUTF8Encoding = hasNonUTF8Encoding
        self.detectedEncodingName = detectedEncodingName
        self.totalCompressedSize = totalCompressedSize
        self.entryCountHint = entryCountHint
        self.comment = comment
    }

    public var editingEligibility: (allowed: Bool, reason: String?) {
        if format.isSingleStream {
            return (false, "单文件压缩流不支持归档式编辑")
        }
        if isSplitVolume {
            return (false, "分卷压缩包暂不支持原位编辑")
        }
        if isConcatenated {
            return (false, "拼接 ZIP 暂不支持编辑保存")
        }
        if hasNonUTF8Encoding {
            return (false, "自动识别为 \(detectedEncodingName ?? "GBK") 的 ZIP 暂不支持编辑保存；请先解压后重新创建压缩包")
        }
        switch format {
        case .zip, .sevenZip:
            return (true, nil)
        case .tar:
            return (true, nil)
        default:
            return (false, "原生增量修改仅支持 ZIP 和 7Z")
        }
    }
}

// MARK: - Index Phase & Capability Gates (doc/02 section 3)

public enum IndexPhase: Equatable, Sendable {
    case idle
    case preliminary(loadedCount: Int)
    case ready(totalCount: Int)
    case failed(message: String)

    public var canBrowse: Bool {
        switch self {
        case .preliminary, .ready: return true
        default: return false
        }
    }

    public var canExtractAll: Bool {
        switch self {
        case .preliminary, .ready: return true
        default: return false
        }
    }

    public var canSearch: Bool {
        if case .ready = self { return true }
        return false
    }

    public var canPreview: Bool {
        if case .ready = self { return true }
        return false
    }

    public var canDragOut: Bool {
        if case .ready = self { return true }
        return false
    }

    public var canExtractSelected: Bool {
        if case .ready = self { return true }
        return false
    }

    public var canEdit: Bool {
        if case .ready = self { return true }
        return false
    }

    public var statusBannerText: String? {
        switch self {
        case .idle:
            return "正在准备打开…"
        case .preliminary:
            return "正在建立文件索引… 可以浏览和全部解压。文件列表读取完成后可搜索、预览、拖出或解压所选文件。"
        case .ready:
            return nil
        case .failed(let message):
            return message
        }
    }

    public func disabledReason(for actionName: String) -> String? {
        switch self {
        case .ready:
            return nil
        case .preliminary, .idle:
            return "请等待文件列表读取完成，再\(actionName)。"
        case .failed(let msg):
            return msg
        }
    }
}

// MARK: - Creation Profile (doc/04)

public struct CreationProfile: Codable, Hashable, Sendable {
    public enum Purpose: String, Codable, CaseIterable, Hashable, Sendable {
        case general
        case windows
        case mac
        case unix
        case smallest

        public var title: String {
            switch self {
            case .general: return "通用分享"
            case .windows: return "Windows 用户"
            case .mac: return "Mac 之间传递"
            case .unix: return "Linux 与服务器"
            case .smallest: return "尽可能小"
            }
        }

        public var subtitle: String {
            switch self {
            case .general: return "兼顾兼容性与效率"
            case .windows: return "优化跨平台使用"
            case .mac: return "保留 macOS 辅助文件"
            case .unix: return "适合 Unix 目录归档"
            case .smallest: return "优先减小压缩包体积"
            }
        }

        public var sfSymbol: String {
            switch self {
            case .general: return "person.2"
            case .windows: return "square.grid.2x2.fill"
            case .mac: return "desktopcomputer"
            case .unix: return "terminal"
            case .smallest: return "leaf"
            }
        }

        public var allowedFormats: [ArchiveFormat] {
            switch self {
            case .general, .windows, .mac:
                return [.zip, .sevenZip, .tar]
            case .unix:
                return [.tar]
            case .smallest:
                return [.zip, .sevenZip]
            }
        }

        public var defaultFormat: ArchiveFormat {
            switch self {
            case .general: return .zip
            case .windows: return .sevenZip
            case .mac: return .zip
            case .unix: return .tar
            case .smallest: return .sevenZip
            }
        }

        public var defaultStrength: Strength {
            switch self {
            case .smallest: return .maximum
            default: return .balanced
            }
        }
    }

    public enum Strength: Int, Codable, CaseIterable, Hashable, Sendable {
        case store = 0
        case fastest = 1
        case fast = 2
        case balanced = 3
        case maximum = 4

        public var title: String {
            switch self {
            case .store: return "仅打包"
            case .fastest: return "极速"
            case .fast: return "更快"
            case .balanced: return "均衡"
            case .maximum: return "极限"
            }
        }

        public var subtitle: String {
            switch self {
            case .store: return "不压缩，仅封装归档"
            case .fastest: return "最快完成压缩"
            case .fast: return "偏向速度的压缩"
            case .balanced: return "兼顾速度和大小"
            case .maximum: return "最大化压缩率（LZMA2 4GB 固实 / 最高 Deflate）"
            }
        }

        public var zlibLevel: Int32 {
            switch self {
            case .store: return 0
            case .fastest: return 1
            case .fast: return 3
            case .balanced: return 6
            case .maximum: return 9
            }
        }

        public var sevenZipLevel: Int {
            switch self {
            case .store: return 0
            case .fastest: return 1
            case .fast: return 3
            case .balanced: return 5
            case .maximum: return 9
            }
        }
    }

    public enum SplitPlan: Codable, Hashable, Sendable {
        case byCount(Int)
        case bySize(Int64)
    }

    public var purpose: Purpose
    public var format: ArchiveFormat
    public var strength: Strength
    public var split: SplitPlan?
    public var password: String?
    public var encryptHeaders: Bool
    public var preserveMacMetadata: Bool
    public var processorCount: Int
    public var repairWindowsNames: Bool

    public init(
        purpose: Purpose = .general,
        format: ArchiveFormat = .zip,
        strength: Strength = .balanced,
        split: SplitPlan? = nil,
        password: String? = nil,
        encryptHeaders: Bool = false,
        preserveMacMetadata: Bool? = nil,
        processorCount: Int = ProcessInfo.processInfo.activeProcessorCount,
        repairWindowsNames: Bool? = nil
    ) {
        self.purpose = purpose
        self.format = format
        self.strength = purpose == .smallest ? .maximum : strength
        self.split = split
        self.password = password
        self.encryptHeaders = encryptHeaders
        self.preserveMacMetadata = preserveMacMetadata ?? (purpose == .mac)
        self.processorCount = max(1, processorCount)
        self.repairWindowsNames = repairWindowsNames ?? (purpose == .windows)
    }

    public var canAdjustStrength: Bool {
        if format == .tar { return false }
        if purpose == .smallest { return false }
        return true
    }

    public func validate() throws {
        if purpose == .unix && format != .tar {
            throw ProZipError.invalidCreationProfile("Linux 与服务器用途仅支持 TAR 格式")
        }
        if purpose == .smallest && (format != .zip && format != .sevenZip) {
            throw ProZipError.invalidCreationProfile("尽可能小用途仅支持 ZIP 和 7Z 格式")
        }
        if let split = split {
            guard format.supportsSplitVolumes else {
                throw ProZipError.invalidCreationProfile("仅 ZIP 和 7Z 支持分卷")
            }
            switch split {
            case .byCount(let count):
                guard (2...999).contains(count) else {
                    throw ProZipError.invalidCreationProfile("分卷数量必须在 2 到 999 之间")
                }
            case .bySize(let bytes):
                guard bytes >= 1024 else {
                    throw ProZipError.invalidCreationProfile("每卷大小必须大于零（至少 1 KB）")
                }
            }
        }
        if let pwd = password, !pwd.isEmpty {
            if format == .tar {
                throw ProZipError.invalidCreationProfile("TAR 格式不支持密码加密")
            }
            if format == .zip {
                let isASCII = pwd.unicodeScalars.allSatisfy { $0.isASCII }
                if !isASCII {
                    throw ProZipError.invalidCreationProfile("为保证跨平台可解压，创建 ZIP 时密码仅支持 ASCII。中文密码请使用 7Z")
                }
            }
        }
    }
}

// MARK: - Extraction Options & Report (doc/05)

public enum ConflictResolution: String, Codable, CaseIterable, Sendable {
    case ask
    case replace
    case keepBoth
    case skip

    public var title: String {
        switch self {
        case .ask: return "每次询问"
        case .replace: return "替换"
        case .keepBoth: return "保留两者"
        case .skip: return "跳过"
        }
    }
}

public enum ArchiveCompletionAction: String, Codable, CaseIterable, Sendable {
    case ask
    case keep
    case trash

    public var title: String {
        switch self {
        case .ask: return "每次均询问"
        case .keep: return "始终保留"
        case .trash: return "始终移入废纸篓"
        }
    }
}

public struct ExtractionOptions: Codable, Hashable, Sendable {
    public var filterSystemAuxiliaryFiles: Bool
    public var filterDMGInstallerArtifacts: Bool
    public var explicitlySelectedEntryIDs: Set<String>
    public var conflictResolution: ConflictResolution
    public var stripSingleRootFolderIfMatching: Bool
    public var preservePermissions: Bool

    public init(
        filterSystemAuxiliaryFiles: Bool = true,
        filterDMGInstallerArtifacts: Bool = true,
        explicitlySelectedEntryIDs: Set<String> = [],
        conflictResolution: ConflictResolution = .replace,
        stripSingleRootFolderIfMatching: Bool = true,
        preservePermissions: Bool = true
    ) {
        self.filterSystemAuxiliaryFiles = filterSystemAuxiliaryFiles
        self.filterDMGInstallerArtifacts = filterDMGInstallerArtifacts
        self.explicitlySelectedEntryIDs = explicitlySelectedEntryIDs
        self.conflictResolution = conflictResolution
        self.stripSingleRootFolderIfMatching = stripSingleRootFolderIfMatching
        self.preservePermissions = preservePermissions
    }
}

public struct ExtractionReport: Codable, Hashable, Sendable {
    public let destinationURL: URL
    public let extractedCount: Int
    public let skippedCount: Int
    public let failedCount: Int
    public let extractedURLs: [URL]
    public let skippedReasons: [String]
    public let errors: [String]

    public var isFullSuccess: Bool {
        failedCount == 0 && skippedCount == 0
    }

    public init(
        destinationURL: URL,
        extractedCount: Int,
        skippedCount: Int = 0,
        failedCount: Int = 0,
        extractedURLs: [URL] = [],
        skippedReasons: [String] = [],
        errors: [String] = []
    ) {
        self.destinationURL = destinationURL
        self.extractedCount = extractedCount
        self.skippedCount = skippedCount
        self.failedCount = failedCount
        self.extractedURLs = extractedURLs
        self.skippedReasons = skippedReasons
        self.errors = errors
    }
}

// MARK: - Progress Reporting

public enum OperationPhase: String, Codable, Sendable {
    case preparing = "正在准备"
    case checkingArchive = "正在核对压缩包目录"
    case indexing = "正在建立文件索引"
    case starting = "正在启动"
    case compressing = "正在压缩"
    case decodingStream = "正在解码压缩流"
    case extracting = "正在解压"
    case verifying = "正在验证归档结构"
    case savingSafely = "正在安全保存"
    case finishing = "正在完成"
    case completed = "已完成"
    case cancelled = "操作已取消"
    case failed = "操作失败"
}

public struct OperationProgress: Codable, Hashable, Sendable {
    public let phase: OperationPhase
    public let completedBytes: Int64
    public let totalBytes: Int64
    public let currentItem: String?
    public let fractionCompleted: Double

    public init(
        phase: OperationPhase,
        completedBytes: Int64 = 0,
        totalBytes: Int64 = 0,
        currentItem: String? = nil,
        fractionCompleted: Double? = nil
    ) {
        self.phase = phase
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
        self.currentItem = currentItem
        if let f = fractionCompleted {
            self.fractionCompleted = min(1.0, max(0.0, f))
        } else if totalBytes > 0 {
            self.fractionCompleted = min(1.0, max(0.0, Double(completedBytes) / Double(totalBytes)))
        } else {
            self.fractionCompleted = phase == .completed ? 1.0 : 0.0
        }
    }
}

public typealias ProgressSink = @Sendable (OperationProgress) -> Void

// MARK: - Flow Action IDs & 32 Allowed Open Formats (doc/09)

public enum FlowActionID: String, CaseIterable, Codable, Hashable, Sendable {
    case addFiles = "app.arczip.archive.add-files"
    case extractAll = "app.arczip.archive.extract-all"
    case extractDirectory = "app.arczip.archive.extract-directory"
    case extractSelection = "app.arczip.archive.extract-selection"
    case diskImageApplicationPrefersOpen = "app.arczip.disk-image.application.prefers-open"
    case installApplication = "app.arczip.install.application"
    case installFont = "app.arczip.install.font"
    case installPackage = "app.arczip.install.package"
    case openFileAllowedExtensions = "app.arczip.open-file.allowed-extensions"
    case openDiskImageApplication = "app.arczip.open.disk-image-application"
    case openFile = "app.arczip.open.file"
    case openInstalledApplication = "app.arczip.open.installed-application"
    case unavailable = "app.arczip.unavailable"

    public var title: String {
        switch self {
        case .addFiles: return "添加文件"
        case .extractAll: return "全部解压"
        case .extractDirectory: return "解压"
        case .extractSelection: return "解压所选项目"
        case .diskImageApplicationPrefersOpen: return "直接打开应用"
        case .installApplication: return "安装到“应用程序”"
        case .installFont: return "安装字体"
        case .installPackage: return "运行安装器"
        case .openFileAllowedExtensions: return "允许打开的格式"
        case .openDiskImageApplication: return "打开应用"
        case .openFile: return "打开文件"
        case .openInstalledApplication: return "打开已安装的应用"
        case .unavailable: return "暂不可用"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .addFiles: return "plus.circle"
        case .extractAll: return "arrow.up.square"
        case .extractDirectory: return "folder.badge.gearshape"
        case .extractSelection: return "arrow.up.doc"
        case .diskImageApplicationPrefersOpen, .openDiskImageApplication, .openInstalledApplication:
            return "app.badge.checkmark"
        case .installApplication: return "arrow.down.app"
        case .installFont: return "textformat"
        case .installPackage: return "shippingbox"
        case .openFileAllowedExtensions: return "checklist"
        case .openFile: return "arrow.up.forward.app"
        case .unavailable: return "exclamationmark.circle"
        }
    }
}

public enum OpenFileCategory: String, CaseIterable, Sendable {
    case document = "文档"
    case image = "图像"
    case audio = "音频"
    case video = "视频"
    case other = "其它"
}

public struct AllowedOpenFormat: Identifiable, Hashable, Sendable {
    public let id: String          // Logical format key from data/allowed-open-formats.txt
    public let displayName: String
    public let category: OpenFileCategory
    public let extensions: [String]

    public static let exact32: [AllowedOpenFormat] = [
        // 文档 (9)
        AllowedOpenFormat(id: "pdf", displayName: "PDF", category: .document, extensions: ["pdf"]),
        AllowedOpenFormat(id: "plain-text", displayName: "纯文本", category: .document, extensions: ["txt", "text", "log"]),
        AllowedOpenFormat(id: "markdown", displayName: "Markdown", category: .document, extensions: ["md", "markdown"]),
        AllowedOpenFormat(id: "rtf", displayName: "RTF", category: .document, extensions: ["rtf"]),
        AllowedOpenFormat(id: "csv", displayName: "CSV", category: .document, extensions: ["csv", "tsv"]),
        AllowedOpenFormat(id: "word", displayName: "Word", category: .document, extensions: ["doc", "docx"]),
        AllowedOpenFormat(id: "excel", displayName: "Excel", category: .document, extensions: ["xls", "xlsx"]),
        AllowedOpenFormat(id: "powerpoint", displayName: "PowerPoint", category: .document, extensions: ["ppt", "pptx"]),
        AllowedOpenFormat(id: "epub", displayName: "EPUB", category: .document, extensions: ["epub"]),
        // 图像 (8)
        AllowedOpenFormat(id: "jpeg", displayName: "JPEG", category: .image, extensions: ["jpg", "jpeg"]),
        AllowedOpenFormat(id: "png", displayName: "PNG", category: .image, extensions: ["png"]),
        AllowedOpenFormat(id: "gif", displayName: "GIF", category: .image, extensions: ["gif"]),
        AllowedOpenFormat(id: "webp", displayName: "WebP", category: .image, extensions: ["webp"]),
        AllowedOpenFormat(id: "heif", displayName: "HEIF / HEIC", category: .image, extensions: ["heic", "heif"]),
        AllowedOpenFormat(id: "tiff", displayName: "TIFF", category: .image, extensions: ["tif", "tiff"]),
        AllowedOpenFormat(id: "bmp", displayName: "BMP", category: .image, extensions: ["bmp"]),
        AllowedOpenFormat(id: "svg", displayName: "SVG", category: .image, extensions: ["svg"]),
        // 音频 (5)
        AllowedOpenFormat(id: "mp3", displayName: "MP3", category: .audio, extensions: ["mp3"]),
        AllowedOpenFormat(id: "m4a", displayName: "M4A / AAC", category: .audio, extensions: ["m4a", "aac"]),
        AllowedOpenFormat(id: "wav", displayName: "WAV", category: .audio, extensions: ["wav"]),
        AllowedOpenFormat(id: "flac", displayName: "FLAC", category: .audio, extensions: ["flac"]),
        AllowedOpenFormat(id: "ogg-audio", displayName: "OGG", category: .audio, extensions: ["ogg", "oga"]),
        // 视频 (5)
        AllowedOpenFormat(id: "mp4", displayName: "MP4 / M4V", category: .video, extensions: ["mp4", "m4v"]),
        AllowedOpenFormat(id: "mov", displayName: "MOV", category: .video, extensions: ["mov"]),
        AllowedOpenFormat(id: "mkv", displayName: "MKV", category: .video, extensions: ["mkv"]),
        AllowedOpenFormat(id: "avi", displayName: "AVI", category: .video, extensions: ["avi"]),
        AllowedOpenFormat(id: "webm", displayName: "WebM", category: .video, extensions: ["webm"]),
        // 其它 (5)
        AllowedOpenFormat(id: "html", displayName: "HTML", category: .other, extensions: ["html", "htm"]),
        AllowedOpenFormat(id: "css", displayName: "CSS", category: .other, extensions: ["css"]),
        AllowedOpenFormat(id: "json", displayName: "JSON", category: .other, extensions: ["json"]),
        AllowedOpenFormat(id: "xml", displayName: "XML", category: .other, extensions: ["xml", "plist"]),
        AllowedOpenFormat(id: "yaml", displayName: "YAML", category: .other, extensions: ["yml", "yaml"])
    ]

    public static var defaultAllowedIDs: Set<String> {
        Set(exact32.map(\.id))
    }

    public static func formatID(forExtension ext: String) -> String? {
        let lower = ext.lowercased()
        return exact32.first { $0.extensions.contains(lower) }?.id
    }
}

// MARK: - Unified ProZip Errors

public enum ProZipError: LocalizedError, Equatable, Sendable {
    case invalidArchive(String)
    case corruptedArchive(String)
    case formatMismatch(String)
    case passwordRequired(String)
    case licenseAgreementRequired(String)
    case wrongPassword(String)
    case unsafePath(String)
    case symlinkOutOfBounds(String)
    case structureConflict(String)
    case destinationIsSymlink(String)
    case destinationNotWritable(String)
    case invalidCreationProfile(String)
    case verificationFailed(String)
    case splitVolumeIncomplete(String)
    case sourceArchiveModified(String)
    case editingNotSupported(String)
    case outputExceedsBudget(String)
    case tooManyActiveMemberReads
    case indexNotReady(String)
    case artifactIdentityMismatch(String)
    case publicationRollbackFailed(String)
    case diskImageError(String)
    case installationError(stage: String, reason: String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidArchive(let detail):
            return "无法读取压缩包：\(detail)"
        case .corruptedArchive(let detail):
            return "压缩包无效或已损坏：\(detail)"
        case .formatMismatch(let detail):
            return "压缩包内容与识别格式不一致：\(detail)"
        case .passwordRequired(let item):
            return "此压缩包受密码保护（\(item)）"
        case .licenseAgreementRequired(let item):
            return "磁盘映像包含软件许可协议（\(item)）"
        case .wrongPassword(let detail):
            return "密码错误：\(detail)"
        case .unsafePath(let path):
            return "不安全的归档路径（包含绝对路径、父目录跳转 .. 或非法字符）：\(path)"
        case .symlinkOutOfBounds(let target):
            return "ZIP 符号链接目标超出提取范围：\(target)"
        case .structureConflict(let path):
            return "文件与目录结构冲突：\(path)"
        case .destinationIsSymlink(let path):
            return "解压目标包含符号链接目录：\(path)"
        case .destinationNotWritable(let path):
            return "无法写入目标位置，请选择其他文件夹存放结果：\(path)"
        case .invalidCreationProfile(let reason):
            return reason
        case .verificationFailed(let reason):
            return "ZIP 结构验证与 Creation Manifest 不一致：\(reason)"
        case .splitVolumeIncomplete(let reason):
            return "分卷输出不连续或包含空卷，未发布压缩包：\(reason)"
        case .sourceArchiveModified(let reason):
            return "现有压缩包在操作期间发生了变化，未执行覆盖：\(reason)"
        case .editingNotSupported(let reason):
            return reason
        case .outputExceedsBudget(let reason):
            return "归档辅助进程输出超过 16 MiB 上限或成员超出预算，任务已停止：\(reason)"
        case .tooManyActiveMemberReads:
            return "并发成员读取超过配额上限（Too many active member reads）"
        case .indexNotReady(let action):
            return "请等待文件列表读取完成，再\(action)。"
        case .artifactIdentityMismatch(let path):
            return "临时路径当前身份与登记身份不一致，拒绝删除：\(path)"
        case .publicationRollbackFailed(let reason):
            return "原压缩包未能完整恢复：\(reason)"
        case .diskImageError(let reason):
            return reason
        case .installationError(let stage, let reason):
            return "安装阶段 [\(stage)] 失败：\(reason)"
        case .cancelled:
            return "操作已取消"
        }
    }
}

// MARK: - Archive Editing & Draft Mutations (doc/07)

public enum ArchiveMutation: Codable, Hashable, Sendable {
    case addFile(sourceURL: URL, archivePath: String)
    case deleteEntry(archivePath: String)
    case renameEntry(oldArchivePath: String, newArchivePath: String)
    case replaceEntry(archivePath: String, replacementSourceURL: URL)

    public var actionDescription: String {
        switch self {
        case .addFile(_, let path):
            return "添加 \((path as NSString).lastPathComponent)"
        case .deleteEntry(let path):
            return "删除 \((path as NSString).lastPathComponent)"
        case .renameEntry(let oldPath, let newPath):
            return "重命名 \((oldPath as NSString).lastPathComponent) 为 \((newPath as NSString).lastPathComponent)"
        case .replaceEntry(let path, _):
            return "替换 \((path as NSString).lastPathComponent)"
        }
    }
}

