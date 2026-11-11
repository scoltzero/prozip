import Foundation
import Darwin
import ProZipShared

// MARK: - Planned Extraction Items & Plan (doc/05-解压.md)

public struct PlannedExtractionItem: Sendable, Equatable {
    public let entry: ArchiveEntry
    public let relativeOutputPath: String
    public let destinationURL: URL
    public let conflictAction: ConflictResolution

    public init(
        entry: ArchiveEntry,
        relativeOutputPath: String,
        destinationURL: URL,
        conflictAction: ConflictResolution = .replace
    ) {
        self.entry = entry
        self.relativeOutputPath = relativeOutputPath
        self.destinationURL = destinationURL
        self.conflictAction = conflictAction
    }
}

public struct SkippedExtractionItem: Sendable, Equatable {
    public let entry: ArchiveEntry
    public let reason: String

    public init(entry: ArchiveEntry, reason: String) {
        self.entry = entry
        self.reason = reason
    }
}

public struct ExtractionPlan: Sendable, Equatable {
    public let rootDestinationURL: URL
    public let itemsToExtract: [PlannedExtractionItem]
    public let skippedEntries: [SkippedExtractionItem]
    public let strippedRootPrefix: String?

    public init(
        rootDestinationURL: URL,
        itemsToExtract: [PlannedExtractionItem],
        skippedEntries: [SkippedExtractionItem] = [],
        strippedRootPrefix: String? = nil
    ) {
        self.rootDestinationURL = rootDestinationURL
        self.itemsToExtract = itemsToExtract
        self.skippedEntries = skippedEntries
        self.strippedRootPrefix = strippedRootPrefix
    }
}

// MARK: - Archive Extraction Policy

public enum ArchiveExtractionPolicy {

    /// Derives the default extraction folder URL beside `archiveURL` named after the archive stem
    /// (e.g., `foo.tar.gz` -> `foo`, `sample.zip` -> `sample`, `bundle.7z.001` -> `bundle`).
    public static func defaultDestinationFolder(for archiveURL: URL, entries: [ArchiveEntry] = []) -> URL {
        let filename = archiveURL.lastPathComponent

        // Strip split suffixes (.001, .z01, .part1.rar, etc.)
        var stem = filename
        if let match = stem.range(of: #"\.(?:(?:part\d+)|(?:z\d{2})|(?:\d{3}))(?:\.rar)?$"#, options: [.regularExpression, .caseInsensitive]) {
            stem = String(stem[..<match.lowerBound])
        }

        // Multi-part archive extensions
        let compoundExtensions = [
            ".tar.gz", ".tar.bz2", ".tar.xz", ".tar.zst", ".tar.lz", ".tar.lzma",
            ".tgz", ".tbz", ".tbz2", ".txz"
        ]

        var stripped = false
        for ext in compoundExtensions {
            if stem.lowercased().hasSuffix(ext) {
                stem = String(stem.dropLast(ext.count))
                stripped = true
                break
            }
        }

        if !stripped {
            let ns = stem as NSString
            let ext = ns.pathExtension
            if !ext.isEmpty {
                stem = ns.deletingPathExtension
            }
        }

        if stem.isEmpty {
            stem = "Archive"
        }

        let parent = archiveURL.deletingLastPathComponent()
        return parent.appendingPathComponent(stem, isDirectory: true)
    }

    /// Validates that `url` and all existing ancestor directory components are not symbolic links,
    /// and ensures the destination location is writable.
    public static func validateDestinationDirectory(_ url: URL) throws {
        let standardizedPath = (url.standardizedFileURL.path as NSString).standardizingPath

        // On macOS /tmp, /var, /etc are symlinks to /private/tmp, /private/var, /private/etc.
        // Map these standard prefixes to their canonical roots before checking symlink components.
        var checkablePath = standardizedPath
        if checkablePath.hasPrefix("/tmp/") || checkablePath == "/tmp" {
            checkablePath = "/private" + checkablePath
        } else if checkablePath.hasPrefix("/var/") || checkablePath == "/var" {
            checkablePath = "/private" + checkablePath
        } else if checkablePath.hasPrefix("/etc/") || checkablePath == "/etc" {
            checkablePath = "/private" + checkablePath
        }

        let components = (checkablePath as NSString).pathComponents
        var currentPath = ""

        for comp in components {
            if comp == "/" {
                currentPath = "/"
                continue
            }
            currentPath = (currentPath as NSString).appendingPathComponent(comp)

            // System roots allowed
            if currentPath == "/private" ||
                currentPath == "/private/tmp" ||
                currentPath == "/private/var" ||
                currentPath == "/private/etc" {
                continue
            }

            var statBuf = stat()
            if lstat(currentPath, &statBuf) == 0 {
                if (statBuf.st_mode & S_IFMT) == S_IFLNK {
                    throw ProZipError.destinationIsSymlink(url.path)
                }
            }
        }

        // Parent directory writability check
        var existingAncestor = standardizedPath
        while !FileManager.default.fileExists(atPath: existingAncestor) {
            let parent = (existingAncestor as NSString).deletingLastPathComponent
            if parent == existingAncestor || parent.isEmpty { break }
            existingAncestor = parent
        }

        let isWritable = FileManager.default.isWritableFile(atPath: existingAncestor) || (access(existingAncestor, W_OK) == 0)
        guard isWritable else {
            throw ProZipError.destinationNotWritable(url.path)
        }
    }

    /// Rejects empty path, NUL bytes (\0), leading / or \, drive letters, or any component equal to .. or .
    public static func validateRelativeArchivePath(_ rawPath: String) throws -> String {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProZipError.unsafePath(rawPath)
        }

        guard !trimmed.contains("\0") else {
            throw ProZipError.unsafePath(rawPath)
        }

        guard !trimmed.hasPrefix("/") && !trimmed.hasPrefix("\\") else {
            throw ProZipError.unsafePath(rawPath)
        }

        if trimmed.range(of: #"^[a-zA-Z]:"#, options: .regularExpression) != nil {
            throw ProZipError.unsafePath(rawPath)
        }

        // Normalize separators
        let unified = trimmed.replacingOccurrences(of: "\\", with: "/")
        let rawComponents = unified.split(separator: "/", omittingEmptySubsequences: false)

        var sanitizedComponents: [String] = []
        for (idx, compSub) in rawComponents.enumerated() {
            let comp = String(compSub)
            if comp == ".." || comp == "." {
                throw ProZipError.unsafePath(rawPath)
            }
            if comp.isEmpty {
                // Trailing slash indicates directory, internal empty indicates consecutive slashes
                if idx == rawComponents.count - 1 {
                    continue
                } else if idx == 0 {
                    throw ProZipError.unsafePath(rawPath)
                }
                // Consecutive slashes: skip empty
                continue
            }
            sanitizedComponents.append(comp)
        }

        guard !sanitizedComponents.isEmpty else {
            throw ProZipError.unsafePath(rawPath)
        }

        return sanitizedComponents.joined(separator: "/")
    }

    /// Validates that a symbolic link target resolves safely within the extraction root directory.
    public static func validateSymlinkTarget(linkDestinationURL: URL, targetPath: String, extractionRootURL: URL) throws {
        let trimmed = targetPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProZipError.symlinkOutOfBounds(targetPath)
        }

        // Reject absolute paths and drive letters
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("\\") || trimmed.range(of: #"^[a-zA-Z]:"#, options: .regularExpression) != nil {
            throw ProZipError.symlinkOutOfBounds(targetPath)
        }

        let linkDir = linkDestinationURL.deletingLastPathComponent().standardizedFileURL
        let resolvedURL = linkDir.appendingPathComponent(trimmed).standardizedFileURL

        let rootPath = extractionRootURL.standardizedFileURL.path
        let resolvedPath = resolvedURL.path

        let isWithinRoot: Bool
        if resolvedPath == rootPath {
            isWithinRoot = true
        } else if rootPath.hasSuffix("/") {
            isWithinRoot = resolvedPath.hasPrefix(rootPath)
        } else {
            isWithinRoot = resolvedPath.hasPrefix(rootPath + "/")
        }

        guard isWithinRoot else {
            throw ProZipError.symlinkOutOfBounds(targetPath)
        }
    }

    /// Builds a comprehensive extraction plan containing planned items, conflict resolutions,
    /// single-root folder deduplication, and skipped items.
    public static func buildPlan(
        entries: [ArchiveEntry],
        archiveURL: URL,
        destinationURL: URL,
        options: ExtractionOptions
    ) throws -> ExtractionPlan {
        try validateDestinationDirectory(destinationURL)

        var candidateEntries: [ArchiveEntry] = []
        var skippedEntries: [SkippedExtractionItem] = []

        // Compute ancestor paths of explicitly selected entry IDs
        var explicitlySelectedAncestorPaths: Set<String> = []
        for entry in entries where options.explicitlySelectedEntryIDs.contains(entry.id) {
            var current = entry.path
            while !current.isEmpty {
                explicitlySelectedAncestorPaths.insert(current)
                let parent = (current as NSString).deletingLastPathComponent
                current = (parent == current || parent == ".") ? "" : parent
            }
        }

        // 1. Filter entries
        for entry in entries {
            if entry.type == .special {
                skippedEntries.append(SkippedExtractionItem(entry: entry, reason: "特殊文件默认不解压"))
                continue
            }

            let isExplicitlySelected = options.explicitlySelectedEntryIDs.contains(entry.id)
            let isInsideAppBundle = entry.path.split(separator: "/").contains { $0.hasSuffix(".app") }

            var hasSelectedAncestor = isExplicitlySelected
            if !hasSelectedAncestor {
                var current = entry.parentPath
                while !current.isEmpty {
                    if explicitlySelectedAncestorPaths.contains(current) {
                        hasSelectedAncestor = true
                        break
                    }
                    let parent = (current as NSString).deletingLastPathComponent
                    current = (parent == current || parent == ".") ? "" : parent
                }
            }

            if options.filterSystemAuxiliaryFiles && entry.isAuxiliary {
                if !hasSelectedAncestor && !isInsideAppBundle {
                    skippedEntries.append(SkippedExtractionItem(entry: entry, reason: "系统辅助文件"))
                    continue
                }
            }

            if options.filterDMGInstallerArtifacts && (entry.isDiskImageBackground || entry.isApplicationsShortcut) {
                if !hasSelectedAncestor {
                    skippedEntries.append(SkippedExtractionItem(entry: entry, reason: "DMG 安装辅助文件"))
                    continue
                }
            }

            candidateEntries.append(entry)
        }

        // 2. Single-root folder deduplication (B2: avoid foo/foo/...)
        var strippedRootPrefix: String? = nil
        var processedRelativePaths: [String: String] = [:] // entry.id -> relative path

        if options.stripSingleRootFolderIfMatching && !candidateEntries.isEmpty {
            let destName = destinationURL.lastPathComponent.lowercased()

            // Find top-level components of all candidate entries
            var topLevelDir: String? = nil
            var allShareSingleRoot = true

            for entry in candidateEntries {
                let comps = entry.path.split(separator: "/")
                guard let first = comps.first else {
                    allShareSingleRoot = false
                    break
                }
                let firstStr = String(first)
                if comps.count == 1 && !entry.isDirectory {
                    allShareSingleRoot = false
                    break
                }
                if let currentTop = topLevelDir {
                    if currentTop.lowercased() != firstStr.lowercased() {
                        allShareSingleRoot = false
                        break
                    }
                } else {
                    topLevelDir = firstStr
                }
            }

            if allShareSingleRoot, let singleRoot = topLevelDir, singleRoot.lowercased() == destName {
                strippedRootPrefix = singleRoot
            }
        }

        // Compute relative paths after potential prefix stripping
        var filteredCandidates: [ArchiveEntry] = []
        for entry in candidateEntries {
            if let prefix = strippedRootPrefix {
                if entry.path.caseInsensitiveCompare(prefix) == .orderedSame {
                    // Top-level root directory itself matches destination folder: skip extracting directory leaf
                    continue
                }

                let prefixWithSlash = prefix + "/"
                if entry.path.lowercased().hasPrefix(prefixWithSlash.lowercased()) {
                    let stripped = String(entry.path.dropFirst(prefixWithSlash.count))
                    processedRelativePaths[entry.id] = stripped
                    filteredCandidates.append(entry)
                } else {
                    processedRelativePaths[entry.id] = entry.path
                    filteredCandidates.append(entry)
                }
            } else {
                processedRelativePaths[entry.id] = entry.path
                filteredCandidates.append(entry)
            }
        }

        // 3. Validate relative paths and detect in-archive conflicts
        var recordedFiles: [String: String] = [:] // lowercasedPath -> originalPath
        var recordedDirs: [String: String] = [:]  // lowercasedPath -> originalPath

        for entry in filteredCandidates {
            guard let rawRelPath = processedRelativePaths[entry.id] else { continue }
            let validatedRelPath = try validateRelativeArchivePath(rawRelPath)
            processedRelativePaths[entry.id] = validatedRelPath

            let lowerRelPath = validatedRelPath.lowercased()

            if entry.isDirectory {
                if let fileConflict = recordedFiles[lowerRelPath] {
                    throw ProZipError.structureConflict("文件与目录结构冲突：\(fileConflict) vs \(entry.path)")
                }
                recordedDirs[lowerRelPath] = validatedRelPath
            } else {
                if let dirConflict = recordedDirs[lowerRelPath] {
                    throw ProZipError.structureConflict("文件与目录结构冲突：\(dirConflict) vs \(entry.path)")
                }
                if let existingFile = recordedFiles[lowerRelPath] {
                    if existingFile != validatedRelPath {
                        throw ProZipError.structureConflict("归档内包含大小写同名冲突：\(existingFile) vs \(validatedRelPath)")
                    }
                }
                recordedFiles[lowerRelPath] = validatedRelPath

            }

            // Directory entries also imply that every ancestor must be a directory.
            var ancestor = (validatedRelPath as NSString).deletingLastPathComponent
            while !ancestor.isEmpty && ancestor != "." {
                let lowerAncestor = ancestor.lowercased()
                if let fileConflict = recordedFiles[lowerAncestor] {
                    throw ProZipError.structureConflict("文件与目录结构冲突：\(fileConflict) vs \(entry.path)")
                }
                recordedDirs[lowerAncestor] = ancestor
                let next = (ancestor as NSString).deletingLastPathComponent
                if next == ancestor { break }
                ancestor = next
            }
        }

        // 4. On-disk conflict detection and plan construction
        var plannedItems: [PlannedExtractionItem] = []
        let fileManager = FileManager.default

        for entry in filteredCandidates {
            guard let relPath = processedRelativePaths[entry.id] else { continue }
            let itemDestURL = destinationURL.appendingPathComponent(relPath)
            try validateDestinationDirectory(entry.isDirectory ? itemDestURL : itemDestURL.deletingLastPathComponent())

            var isDir: ObjCBool = false
            let existsOnDisk = fileManager.fileExists(atPath: itemDestURL.path, isDirectory: &isDir)

            if existsOnDisk {
                if entry.isDirectory && !isDir.boolValue {
                    throw ProZipError.structureConflict("目标位置存在同名文件：\(itemDestURL.path)")
                }
                if !entry.isDirectory && isDir.boolValue {
                    throw ProZipError.structureConflict("目标位置存在同名目录：\(itemDestURL.path)")
                }
            }

            // Symlink target bounds validation
            if entry.type == .symlink {
                let target = entry.symlinkTarget ?? ""
                try validateSymlinkTarget(linkDestinationURL: itemDestURL, targetPath: target, extractionRootURL: destinationURL)
            }

            if existsOnDisk && !entry.isDirectory {
                switch options.conflictResolution {
                case .skip:
                    skippedEntries.append(SkippedExtractionItem(entry: entry, reason: "文件已存在，已跳过"))
                case .replace:
                    plannedItems.append(PlannedExtractionItem(
                        entry: entry,
                        relativeOutputPath: relPath,
                        destinationURL: itemDestURL,
                        conflictAction: .replace
                    ))
                case .keepBoth:
                    let uniqueURL = generateUniqueURL(for: itemDestURL)
                    let uniqueRelPath = (relPath as NSString).deletingLastPathComponent.isEmpty
                        ? uniqueURL.lastPathComponent
                        : "\((relPath as NSString).deletingLastPathComponent)/\(uniqueURL.lastPathComponent)"
                    plannedItems.append(PlannedExtractionItem(
                        entry: entry,
                        relativeOutputPath: uniqueRelPath,
                        destinationURL: uniqueURL,
                        conflictAction: .keepBoth
                    ))
                case .ask:
                    plannedItems.append(PlannedExtractionItem(
                        entry: entry,
                        relativeOutputPath: relPath,
                        destinationURL: itemDestURL,
                        conflictAction: .ask
                    ))
                }
            } else {
                plannedItems.append(PlannedExtractionItem(
                    entry: entry,
                    relativeOutputPath: relPath,
                    destinationURL: itemDestURL,
                    conflictAction: options.conflictResolution
                ))
            }
        }

        return ExtractionPlan(
            rootDestinationURL: destinationURL,
            itemsToExtract: plannedItems,
            skippedEntries: skippedEntries,
            strippedRootPrefix: strippedRootPrefix
        )
    }

    /// Generates a unique URL when keepBoth is requested (e.g. `file (2).txt`, `file (3).txt`).
    private static func generateUniqueURL(for url: URL) -> URL {
        let dir = url.deletingLastPathComponent()
        let filename = url.lastPathComponent
        let ns = filename as NSString
        let ext = ns.pathExtension
        let base = ext.isEmpty ? filename : ns.deletingPathExtension

        var counter = 2
        while true {
            let newName = ext.isEmpty ? "\(base) (\(counter))" : "\(base) (\(counter)).\(ext)"
            let candidate = dir.appendingPathComponent(newName)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            counter += 1
        }
    }
}
