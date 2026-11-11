import Foundation
import ProZipShared

// MARK: - Windows Name Repair Policy (doc/04 section 2.5 & doc/07 section 3)

public struct WindowsNameIssue: Identifiable, Equatable, Sendable {
    public var id: String { originalPath }
    public let originalPath: String
    public var suggestedPath: String
    public let reason: String

    public init(originalPath: String, suggestedPath: String, reason: String) {
        self.originalPath = originalPath
        self.suggestedPath = suggestedPath
        self.reason = reason
    }
}

public enum WindowsNameRepairPolicy {

    private static let reservedDeviceNames: Set<String> = [
        "CON", "PRN", "AUX", "NUL",
        "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
        "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"
    ]

    private static let illegalWindowsCharacters = CharacterSet(charactersIn: #"<>:"/\|?*"#)

    /// Repairs an individual path component (filename or directory name) for Windows compatibility.
    /// Replaces illegal chars and control characters with '_', strips trailing dots/spaces,
    /// and prefixes reserved device names with '_'.
    public static func repairComponent(_ component: String) -> String {
        guard !component.isEmpty else { return "_" }

        // 1. Replace illegal characters and control chars with '_'
        var sanitizedScalars: [UnicodeScalar] = []
        for scalar in component.unicodeScalars {
            if illegalWindowsCharacters.contains(scalar) || scalar.value < 32 || scalar.value == 127 {
                sanitizedScalars.append("_")
            } else {
                sanitizedScalars.append(scalar)
            }
        }
        var cleaned = String(String.UnicodeScalarView(sanitizedScalars))

        // 2. Strip trailing dots and trailing spaces
        while cleaned.hasSuffix(".") || cleaned.hasSuffix(" ") {
            cleaned.removeLast()
        }

        if cleaned.isEmpty {
            cleaned = "_"
        }

        // 3. Check Windows reserved device names (CON, PRN, AUX, NUL, COM1-9, LPT1-9)
        let baseName: String
        let ext: String
        if let dotIndex = cleaned.firstIndex(of: ".") {
            baseName = String(cleaned[..<dotIndex])
            ext = String(cleaned[dotIndex...])
        } else {
            baseName = cleaned
            ext = ""
        }

        if reservedDeviceNames.contains(baseName.uppercased()) {
            cleaned = "_\(baseName)\(ext)"
        }

        return cleaned
    }

    /// Repairs an entire slash-separated archive path component by component.
    public static func repairPath(_ path: String) -> String {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        let repairedComponents = components.map { comp -> String in
            let str = String(comp)
            return str.isEmpty ? str : repairComponent(str)
        }
        return repairedComponents.joined(separator: "/")
    }

    /// Inspects a list of archive paths and returns a list of detected Windows compatibility issues.
    public static func scan(paths: [String]) -> [WindowsNameIssue] {
        var issues: [WindowsNameIssue] = []

        for path in paths {
            let components = path.split(separator: "/").map(String.init)
            var reasons: [String] = []

            for comp in components {
                // Check illegal chars
                if comp.unicodeScalars.contains(where: { illegalWindowsCharacters.contains($0) }) {
                    reasons.append("包含 Windows 非法字符 (<>:\"/\\|?*)")
                }
                // Check control chars
                if comp.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) {
                    reasons.append("包含控制字符")
                }
                // Check trailing dots/spaces
                if comp.hasSuffix(".") || comp.hasSuffix(" ") {
                    reasons.append("结尾包含空格或点")
                }
                // Check reserved device names
                let base = comp.split(separator: ".").first.map(String.init) ?? comp
                if reservedDeviceNames.contains(base.uppercased()) {
                    reasons.append("使用了 Windows 保留设备名（\(base)）")
                }
            }

            if !reasons.isEmpty {
                let repaired = repairPath(path)
                let combinedReason = Array(Set(reasons)).joined(separator: "；")
                issues.append(WindowsNameIssue(
                    originalPath: path,
                    suggestedPath: repaired,
                    reason: combinedReason
                ))
            }
        }

        return issues
    }
}

// MARK: - Archive Entry Rename Policy (doc/07 section 3)

public enum ArchiveEntryRenamePolicy {

    /// Validates a proposed new name for an entry, ensuring it contains no forbidden characters,
    /// no path separators, does not collide with siblings, and stays within length limits.
    public static func validateNewName(
        _ newName: String,
        currentEntry: ArchiveEntry,
        siblingEntries: [ArchiveEntry],
        checkWindowsCompatibility: Bool = false
    ) throws -> String {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProZipError.unsafePath("名称不能为空")
        }

        guard !trimmed.contains("/") && !trimmed.contains("\\") else {
            throw ProZipError.unsafePath("名称不能包含路径分隔符（/ 或 \\）：\(newName)")
        }

        guard trimmed != "." && trimmed != ".." else {
            throw ProZipError.unsafePath("名称不能为相对路径符号（. 或 ..）：\(newName)")
        }

        guard !trimmed.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 0 || $0.value == 127 }) else {
            throw ProZipError.unsafePath("名称包含控制字符：\(newName)")
        }

        // Case-insensitive collision check against sibling items (excluding current entry)
        let collision = siblingEntries.contains { sibling in
            sibling.id != currentEntry.id &&
            sibling.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }

        if collision {
            throw ProZipError.structureConflict("同目录下已存在同名项目：\(trimmed)")
        }

        let parent = currentEntry.parentPath
        let newPath = parent.isEmpty ? trimmed : "\(parent)/\(trimmed)"

        guard newPath.utf8.count <= 1024 else {
            throw ProZipError.unsafePath("ZIP 项目路径过长（超过 1024 字节上限）")
        }

        if checkWindowsCompatibility {
            let issues = WindowsNameRepairPolicy.scan(paths: [trimmed])
            if let issue = issues.first {
                throw ProZipError.unsafePath("名称不兼容 Windows 规范：\(issue.reason)")
            }
        }

        return newPath
    }
}
