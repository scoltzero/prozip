import Foundation
import ProZipShared

public struct FinderSelectionItem: Equatable, Sendable {
    public let url: URL
    public let isDirectory: Bool
    public init(url: URL, isDirectory: Bool) { self.url = url; self.isDirectory = isDirectory }
}

public struct FinderMenuCommand: Equatable, Sendable {
    public let title: String
    public let action: FinderAction
    public let files: [URL]

    public func requestURL() throws -> URL {
        let url = try FinderActionRequest(action: action, files: files).url
        // Apply the same encoded-size and transport validation as the receiving app.
        _ = try FinderActionRequest(url: url)
        return url
    }
}

public enum FinderMenuPolicy {
    private static let archiveExtensions = Set(FileAssociationGroup.allExtensions)

    public static func commands(for selection: [FinderSelectionItem]) -> [FinderMenuCommand] {
        guard let request = try? FinderActionRequest(action: .compressDefault, files: selection.map(\.url)) else { return [] }
        var directories: [URL: Bool] = [:]
        for item in selection where directories[item.url.standardizedFileURL] == nil {
            directories[item.url.standardizedFileURL] = item.isDirectory
        }
        let files = request.files
        let allArchives = files.allSatisfy { directories[$0] != true && archiveExtensions.contains($0.pathExtension.lowercased()) }
        if allArchives {
            var commands: [FinderMenuCommand] = []
            if files.count == 1 { commands.append(.init(title: "用 ProZip 浏览", action: .browseArchive, files: files)) }
            commands.append(.init(title: files.count == 1 ? "快速解压到当前目录" : "将 \(files.count) 个文件解压到当前目录", action: .extractHere, files: files))
            commands.append(.init(title: files.count == 1 ? "快速解压到指定目录…" : "将 \(files.count) 个文件解压到指定目录…", action: .extractTo, files: files))
            return commands
        }
        let title = files.count == 1 && directories[files[0]] == true
            ? "压缩为 \"\(files[0].lastPathComponent)\"" : "快速压缩"
        return [
            .init(title: "压缩为…", action: .compressConfigured, files: files),
            .init(title: title, action: .compressDefault, files: files)
        ]
    }
}

public struct FinderMonitoredVolume: Sendable {
    public let url: URL
    public let isInternal: Bool
    public let isRemovable: Bool
    public let isLocal: Bool
    public let isBrowsable: Bool

    public init(url: URL, isInternal: Bool, isRemovable: Bool, isLocal: Bool = true, isBrowsable: Bool = true) {
        self.url = url
        self.isInternal = isInternal
        self.isRemovable = isRemovable
        self.isLocal = isLocal
        self.isBrowsable = isBrowsable
    }
}

public enum FinderMonitoringPolicy {
    public static let applicationID = "org.prozip.ProZip"
    public static let externalVolumesKey = "finder.monitorsExternalVolumes.v1"
    public static let preferencesChanged = Notification.Name("org.prozip.ProZip.finderPreferencesChanged")

    public static func directories(home: URL, externalVolumesEnabled: Bool, volumes: [FinderMonitoredVolume]) -> Set<URL> {
        var result: Set<URL> = [home.standardizedFileURL]
        if externalVolumesEnabled {
            for volume in volumes where volume.url.isFileURL && volume.isLocal && volume.isBrowsable && (volume.isRemovable || !volume.isInternal) {
                result.insert(volume.url.standardizedFileURL)
            }
        }
        return result
    }
}
