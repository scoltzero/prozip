import AppKit
import UniformTypeIdentifiers
import ProZipShared

@MainActor
public enum FileURLDrop {
    public static func loadURLs(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        var paths: Set<String> = []
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            let url: URL? = await withCheckedContinuation { continuation in
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let url: URL?
                    if let value = item as? URL { url = value }
                    else if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                    else if let value = item as? String { url = URL(string: value) }
                    else { url = nil }
                    continuation.resume(returning: url?.isFileURL == true ? url : nil)
                }
            }
            if let url, paths.insert(url.standardizedFileURL.path).inserted { urls.append(url) }
        }
        return urls
    }

    public nonisolated static func validateSources(_ sources: [URL]) throws {
        let files = try FinderActionRequest(action: .sendToProZip, files: sources).files
        for source in files {
            let exists = FileManager.default.fileExists(atPath: source.path) || (try? FileManager.default.destinationOfSymbolicLink(atPath: source.path)) != nil
            guard source.isFileURL, exists else {
                throw ProZipError.invalidArchive("来源文件不存在：\(source.lastPathComponent)")
            }
        }
    }
}
