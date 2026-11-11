import CoreServices
import Foundation
import UniformTypeIdentifiers

public enum FileAssociationSection: String, CaseIterable, Hashable, Sendable {
    case common = "常用压缩包"
    case singleStream = "单文件压缩"
    case other = "磁盘映像与其他格式"
    case softwarePackage = "软件包（谨慎）"
}

public struct FileAssociationGroup: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let extensionSummary: String
    public let description: String
    public let section: FileAssociationSection
    public let extensions: [String]

    public static let all: [FileAssociationGroup] = [
        .init(id: "zip", title: "ZIP", extensionSummary: ".zip .zipx .z01–.z99", description: "ZIP 与 ZIPX 压缩包", section: .common, extensions: ["zip", "zipx"] + (1...99).map { String(format: "z%02d", $0) }),
        .init(id: "7z", title: "7-Zip", extensionSummary: ".7z", description: "7Z 压缩包", section: .common, extensions: ["7z"]),
        .init(id: "split", title: "分卷压缩包", extensionSummary: ".001–.999", description: "ZIP、7Z 等以 .001 开始的数字分卷", section: .common, extensions: (1...999).map { String(format: "%03d", $0) }),
        .init(id: "rar", title: "RAR", extensionSummary: ".rar .r00–.r99", description: "RAR 压缩包", section: .common, extensions: ["rar"] + (0...99).map { String(format: "r%02d", $0) }),
        .init(id: "cbr", title: "Comic RAR", extensionSummary: ".cbr", description: "以 RAR 封装的漫画归档", section: .common, extensions: ["cbr"]),
        .init(id: "tar", title: "TAR", extensionSummary: ".tar .tgz .tbz .tbz2 .txz", description: "TAR 及其短扩展名变体", section: .common, extensions: ["tar", "tgz", "tbz", "tbz2", "txz"]),
        .init(id: "gzip", title: "Gzip / TAR.GZ", extensionSummary: ".gz .gzip", description: "macOS 按末尾扩展名关联，.gz 同时覆盖 .tar.gz", section: .singleStream, extensions: ["gz", "gzip"]),
        .init(id: "bzip2", title: "Bzip2 / TAR.BZ2", extensionSummary: ".bz2 .bzip2", description: "同时覆盖 Bzip2 文件与 .tar.bz2", section: .singleStream, extensions: ["bz2", "bzip2"]),
        .init(id: "xz", title: "XZ / TAR.XZ", extensionSummary: ".xz", description: "同时覆盖 XZ 文件与 .tar.xz", section: .singleStream, extensions: ["xz"]),
        .init(id: "lzma", title: "LZMA", extensionSummary: ".lzma", description: "单文件 LZMA 压缩流", section: .singleStream, extensions: ["lzma"]),
        .init(id: "lzip", title: "Lzip", extensionSummary: ".lz", description: "单文件 Lzip 压缩流", section: .singleStream, extensions: ["lz"]),
        .init(id: "dmg", title: "DMG", extensionSummary: ".dmg", description: "以只读方式浏览磁盘映像，并快速安装其中的 macOS 应用", section: .other, extensions: ["dmg"]),
        .init(id: "iso", title: "ISO", extensionSummary: ".iso", description: "以只读方式挂载并浏览光盘与文件系统镜像", section: .other, extensions: ["iso"]),
        .init(id: "cab", title: "CAB", extensionSummary: ".cab", description: "Microsoft Cabinet 压缩包", section: .other, extensions: ["cab"]),
        .init(id: "cpio", title: "CPIO", extensionSummary: ".cpio", description: "Unix CPIO 归档", section: .other, extensions: ["cpio"]),
        .init(id: "lha", title: "LHA / LZH", extensionSummary: ".lha .lzh", description: "传统 LHA 系列压缩包", section: .other, extensions: ["lha", "lzh"]),
        .init(id: "arj", title: "ARJ", extensionSummary: ".arj", description: "传统 ARJ 压缩包", section: .other, extensions: ["arj"]),
        .init(id: "xar", title: "XAR", extensionSummary: ".xar", description: "Extensible Archive 容器", section: .other, extensions: ["xar"]),
        .init(id: "rpm", title: "RPM", extensionSummary: ".rpm", description: "Linux RPM 软件包容器", section: .other, extensions: ["rpm"]),
        .init(id: "msi", title: "MSI", extensionSummary: ".msi", description: "Windows Installer 软件包", section: .other, extensions: ["msi"]),
        .init(id: "jar", title: "JAR", extensionSummary: ".jar", description: "会替代 Java 启动器；ProZip 仅预览和解压", section: .softwarePackage, extensions: ["jar"]),
        .init(id: "apk", title: "APK", extensionSummary: ".apk", description: "Android 应用软件包", section: .softwarePackage, extensions: ["apk"]),
        .init(id: "spk", title: "SPK", extensionSummary: ".spk", description: "Synology 软件包", section: .softwarePackage, extensions: ["spk"])
    ]
    public static let allExtensions = all.flatMap(\.extensions)
    // Provisional common-archive proposal; the reference application's recommendation was not exercised.
    public static let provisionalRecommendedIDs: Set<String> = ["zip", "7z", "rar", "tar", "gzip", "bzip2", "xz"]
}

public struct FileAssociationGroupStatus: Equatable, Sendable {
    public let associatedCount: Int
    public let totalCount: Int
    public let unresolvedCount: Int
    public var isFullyAssociated: Bool { totalCount > 0 && associatedCount == totalCount }
    public var isPartiallyAssociated: Bool { associatedCount > 0 && associatedCount < totalCount }
}

public protocol FileAssociationSystem: Sendable {
    var applicationBundleID: String? { get }
    var isPackagedApplication: Bool { get }
    func contentType(forExtension ext: String) -> String?
    func defaultHandler(forContentType type: String) -> String?
    func setDefaultHandler(_ identifier: String, forContentType type: String) throws
}

public struct LaunchServicesFileAssociationSystem: FileAssociationSystem {
    public init() {}
    public var applicationBundleID: String? { Bundle.main.bundleIdentifier }
    public var isPackagedApplication: Bool { Bundle.main.bundleURL.pathExtension == "app" }
    public func contentType(forExtension ext: String) -> String? {
        let suffix = (ext as NSString).pathExtension
        let normalized = (suffix.isEmpty ? ext.trimmingCharacters(in: CharacterSet(charactersIn: ".")) : suffix).lowercased()
        guard !normalized.isEmpty else { return nil }
        return UTType(filenameExtension: normalized)?.identifier ??
            UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, normalized as CFString, nil)?.takeRetainedValue() as String?
    }
    public func defaultHandler(forContentType type: String) -> String? {
        LSCopyDefaultRoleHandlerForContentType(type as CFString, .all)?.takeRetainedValue() as String?
    }
    public func setDefaultHandler(_ identifier: String, forContentType type: String) throws {
        let status = LSSetDefaultRoleHandlerForContentType(type as CFString, .all, identifier as CFString)
        guard status == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "macOS 未能更改默认打开方式（\(status)）。"])
        }
    }
}
