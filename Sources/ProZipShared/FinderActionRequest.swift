import Foundation

public enum FinderAction: String, CaseIterable, Sendable {
    case browseArchive, extractHere, extractTo, compressDefault, compressConfigured, sendToProZip
}

/// The Finder extension hands local file references to the main app; it does not execute file operations.
public struct FinderActionRequest: Equatable, Sendable {
    public let action: FinderAction
    public let files: [URL]

    public init(action: FinderAction, files: [URL]) throws {
        self.action = action
        self.files = try Self.validated(files)
        guard url.absoluteString.utf8.count <= 1024 * 1024 else { throw Self.invalidRequest }
    }

    public init(url: URL) throws {
        guard url.absoluteString.utf8.count <= 1024 * 1024,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "prozip", components.host == "finder-action",
              components.path.isEmpty || components.path == "/",
              components.user == nil, components.password == nil, components.port == nil,
              components.fragment == nil else { throw Self.invalidRequest }
        let items = components.queryItems ?? []
        let actions = items.filter { $0.name == "action" }
        guard items.allSatisfy({ $0.name == "action" || $0.name == "file" }),
              actions.count == 1, let rawAction = actions[0].value,
              let action = FinderAction(rawValue: rawAction) else { throw Self.invalidRequest }
        let fileItems = items.filter { $0.name == "file" }
        guard (1...1000).contains(fileItems.count) else { throw Self.invalidRequest }
        let files = try fileItems.map { item -> URL in
            guard let value = item.value, let file = URL(string: value) else { throw Self.invalidRequest }
            return file
        }
        try self.init(action: action, files: files)
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = "prozip"
        components.host = "finder-action"
        components.queryItems = [URLQueryItem(name: "action", value: action.rawValue)] + files.map {
            URLQueryItem(name: "file", value: $0.absoluteString)
        }
        return components.url!
    }

    private static var invalidRequest: ProZipError { .invalidArchive("访达请求文件无效") }

    private static func validated(_ files: [URL]) throws -> [URL] {
        guard (1...1000).contains(files.count) else { throw invalidRequest }
        var seen = Set<URL>()
        var result: [URL] = []
        for file in files {
            // Foundation's file path accessor can truncate an embedded NUL before validation.
            guard let components = URLComponents(url: file, resolvingAgainstBaseURL: false),
                  !components.percentEncodedPath.lowercased().contains("%00"),
                  file.isFileURL, file.path.hasPrefix("/"), !file.path.contains("\0"),
                  file.user == nil, file.password == nil, file.port == nil,
                  file.query == nil, file.fragment == nil,
                  file.host == nil || file.host?.isEmpty == true || file.host?.lowercased() == "localhost" else {
                throw invalidRequest
            }
            let normalized = file.standardizedFileURL
            if seen.insert(normalized).inserted { result.append(normalized) }
        }
        return result
    }
}
