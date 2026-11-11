import Foundation
import SQLite3
import ProZipShared

// MARK: - EntryIndex Error

public enum EntryIndexError: LocalizedError, Equatable {
    case sqliteError(code: Int32, message: String)
    case databaseClosed
    case invalidData(String)

    public var errorDescription: String? {
        switch self {
        case .sqliteError(let code, let message):
            return "SQLite 错误 (\(code)): \(message)"
        case .databaseClosed:
            return "目录索引数据库已关闭"
        case .invalidData(let detail):
            return "无效条目数据：\(detail)"
        }
    }
}

// MARK: - EntryIndex Actor (doc/02-浏览与索引.md & data/entry-index.sql)

public actor EntryIndex {
    public let databaseURL: URL?
    public let isInMemory: Bool

    private var db: OpaquePointer?
    private static let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public static func defaultIndexURL(
        sessionID: String = UUID().uuidString,
        indexID: String = UUID().uuidString
    ) -> URL {
        let pid = ProcessInfo.processInfo.processIdentifier
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Caches")
        let dir = caches.appendingPathComponent("org.prozip.ProZip/Temporary/Sessions/\(pid)-\(sessionID)/Indexes", isDirectory: true)
        return dir.appendingPathComponent("index-\(indexID).sqlite")
    }

    public init(url: URL? = nil) throws {
        if let u = url, u.path == ":memory:" || u.absoluteString == ":memory:" {
            self.databaseURL = nil
            self.isInMemory = true
        } else if let u = url {
            self.databaseURL = u
            self.isInMemory = false
        } else {
            self.databaseURL = Self.defaultIndexURL()
            self.isInMemory = false
        }
        self.db = try Self.openAndInitialize(isInMemory: self.isInMemory, databaseURL: self.databaseURL)
    }

    public init(inMemory: Bool = false, fileURL: URL? = nil) throws {
        if inMemory {
            self.databaseURL = nil
            self.isInMemory = true
        } else {
            self.databaseURL = fileURL ?? Self.defaultIndexURL()
            self.isInMemory = false
        }
        self.db = try Self.openAndInitialize(isInMemory: self.isInMemory, databaseURL: self.databaseURL)
    }

    public static func inMemory() throws -> EntryIndex {
        try EntryIndex(url: URL(string: ":memory:"))
    }

    deinit {
        if let db = db {
            sqlite3_close_v2(db)
        }
    }

    // MARK: - Database Initialization

    private static func openAndInitialize(isInMemory: Bool, databaseURL: URL?) throws -> OpaquePointer {
        var dbHandle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let openResult: Int32

        if isInMemory {
            openResult = sqlite3_open_v2(":memory:", &dbHandle, flags, nil)
        } else if let u = databaseURL {
            let parentDir = u.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            openResult = sqlite3_open_v2(u.path, &dbHandle, flags, nil)
        } else {
            openResult = sqlite3_open_v2(":memory:", &dbHandle, flags, nil)
        }

        guard openResult == SQLITE_OK, let db = dbHandle else {
            let msg = dbHandle.map { String(cString: sqlite3_errmsg($0)) } ?? "Failed to allocate sqlite handle"
            if let h = dbHandle { sqlite3_close_v2(h) }
            throw EntryIndexError.sqliteError(code: openResult, message: msg)
        }

        let schemaSQL = """
        PRAGMA journal_mode=WAL;
        PRAGMA wal_autocheckpoint=100;

        CREATE TABLE IF NOT EXISTS entries (
            id TEXT PRIMARY KEY,
            path TEXT NOT NULL,
            is_auxiliary INTEGER NOT NULL,
            is_disk_image_background INTEGER NOT NULL,
            is_dmg_applications_shortcut INTEGER NOT NULL,
            payload BLOB NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_entries_path ON entries(path COLLATE NOCASE);
        CREATE INDEX IF NOT EXISTS idx_entries_path_exact ON entries(path COLLATE BINARY);

        CREATE TABLE IF NOT EXISTS directory_nodes (
            canonical_path TEXT PRIMARY KEY,
            parent_path TEXT NOT NULL,
            sort_name TEXT NOT NULL,
            is_directory INTEGER NOT NULL,
            is_virtual INTEGER NOT NULL,
            is_auxiliary INTEGER NOT NULL,
            is_disk_image_background INTEGER NOT NULL,
            is_dmg_applications_shortcut INTEGER NOT NULL,
            payload BLOB NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_directory_nodes_parent_exact
            ON directory_nodes(parent_path COLLATE BINARY, is_directory DESC, sort_name COLLATE NOCASE);
        """
        try executeStatic(sql: schemaSQL, on: db)
        return db
    }

    private static func executeStatic(sql: String, on db: OpaquePointer) throws {
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            let message = errMsg.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(db))
            sqlite3_free(errMsg)
            throw EntryIndexError.sqliteError(code: sqlite3_errcode(db), message: message)
        }
    }

    private func execute(sql: String) throws {
        guard let db = db else { throw EntryIndexError.databaseClosed }
        try Self.executeStatic(sql: sql, on: db)
    }

    // MARK: - Rebuild Index

    public func rebuild(with entries: [ArchiveEntry]) throws {
        guard let db = db else { throw EntryIndexError.databaseClosed }

        try execute(sql: "BEGIN IMMEDIATE TRANSACTION;")
        do {
            try execute(sql: "DELETE FROM entries; DELETE FROM directory_nodes;")

            let insertEntrySQL = """
            INSERT OR REPLACE INTO entries (
                id, path, is_auxiliary, is_disk_image_background, is_dmg_applications_shortcut, payload
            ) VALUES (?, ?, ?, ?, ?, ?);
            """

            let insertDirSQL = """
            INSERT INTO directory_nodes (
                canonical_path, parent_path, sort_name, is_directory, is_virtual,
                is_auxiliary, is_disk_image_background, is_dmg_applications_shortcut, payload
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(canonical_path) DO UPDATE SET
                parent_path = excluded.parent_path,
                sort_name = excluded.sort_name,
                is_directory = excluded.is_directory,
                is_virtual = excluded.is_virtual,
                is_auxiliary = excluded.is_auxiliary,
                is_disk_image_background = excluded.is_disk_image_background,
                is_dmg_applications_shortcut = excluded.is_dmg_applications_shortcut,
                payload = excluded.payload
            WHERE excluded.is_virtual = 0;
            """

            var entryStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, insertEntrySQL, -1, &entryStmt, nil) != SQLITE_OK {
                throw EntryIndexError.sqliteError(code: sqlite3_errcode(db), message: String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(entryStmt) }

            var dirStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, insertDirSQL, -1, &dirStmt, nil) != SQLITE_OK {
                throw EntryIndexError.sqliteError(code: sqlite3_errcode(db), message: String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(dirStmt) }

            let encoder = JSONEncoder()
            var synthesizedVirtualDirs = Set<String>()

            for entry in entries {
                let normalizedPath = entry.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                guard !normalizedPath.isEmpty else { continue }

                let payload = try encoder.encode(entry)

                // 1. Insert into entries table
                sqlite3_reset(entryStmt)
                sqlite3_clear_bindings(entryStmt)
                sqlite3_bind_text(entryStmt, 1, entry.id, -1, Self.SQLITE_TRANSIENT)
                sqlite3_bind_text(entryStmt, 2, normalizedPath, -1, Self.SQLITE_TRANSIENT)
                sqlite3_bind_int(entryStmt, 3, entry.isAuxiliary ? 1 : 0)
                sqlite3_bind_int(entryStmt, 4, entry.isDiskImageBackground ? 1 : 0)
                sqlite3_bind_int(entryStmt, 5, entry.isApplicationsShortcut ? 1 : 0)
                payload.withUnsafeBytes { rawBuffer in
                    guard let base = rawBuffer.baseAddress else { return }
                    _ = sqlite3_bind_blob(entryStmt, 6, base, Int32(rawBuffer.count), Self.SQLITE_TRANSIENT)
                }
                if sqlite3_step(entryStmt) != SQLITE_DONE {
                    throw EntryIndexError.sqliteError(code: sqlite3_errcode(db), message: String(cString: sqlite3_errmsg(db)))
                }

                // 2. Synthesize intermediate virtual directories
                let parts = normalizedPath.split(separator: "/").map(String.init)
                if parts.count > 1 {
                    for i in 0..<(parts.count - 1) {
                        let dirPath = parts[0...i].joined(separator: "/")
                        if synthesizedVirtualDirs.insert(dirPath).inserted {
                            let parentPath = i == 0 ? "" : parts[0..<i].joined(separator: "/")
                            let sortName = parts[i]
                            let virtualEntry = ArchiveEntry(path: dirPath, type: .directory)
                            let virtualPayload = try encoder.encode(virtualEntry)

                            sqlite3_reset(dirStmt)
                            sqlite3_clear_bindings(dirStmt)
                            sqlite3_bind_text(dirStmt, 1, dirPath, -1, Self.SQLITE_TRANSIENT)
                            sqlite3_bind_text(dirStmt, 2, parentPath, -1, Self.SQLITE_TRANSIENT)
                            sqlite3_bind_text(dirStmt, 3, sortName, -1, Self.SQLITE_TRANSIENT)
                            sqlite3_bind_int(dirStmt, 4, 1) // is_directory
                            sqlite3_bind_int(dirStmt, 5, 1) // is_virtual = 1
                            sqlite3_bind_int(dirStmt, 6, virtualEntry.isAuxiliary ? 1 : 0)
                            sqlite3_bind_int(dirStmt, 7, virtualEntry.isDiskImageBackground ? 1 : 0)
                            sqlite3_bind_int(dirStmt, 8, virtualEntry.isApplicationsShortcut ? 1 : 0)
                            virtualPayload.withUnsafeBytes { rawBuffer in
                                guard let base = rawBuffer.baseAddress else { return }
                                _ = sqlite3_bind_blob(dirStmt, 9, base, Int32(rawBuffer.count), Self.SQLITE_TRANSIENT)
                            }
                            if sqlite3_step(dirStmt) != SQLITE_DONE {
                                throw EntryIndexError.sqliteError(code: sqlite3_errcode(db), message: String(cString: sqlite3_errmsg(db)))
                            }
                        }
                    }
                }

                // 3. Insert real entry into directory_nodes (is_virtual = 0)
                let parentPath = entry.parentPath
                let sortName = entry.name

                sqlite3_reset(dirStmt)
                sqlite3_clear_bindings(dirStmt)
                sqlite3_bind_text(dirStmt, 1, normalizedPath, -1, Self.SQLITE_TRANSIENT)
                sqlite3_bind_text(dirStmt, 2, parentPath, -1, Self.SQLITE_TRANSIENT)
                sqlite3_bind_text(dirStmt, 3, sortName, -1, Self.SQLITE_TRANSIENT)
                sqlite3_bind_int(dirStmt, 4, entry.isDirectory ? 1 : 0)
                sqlite3_bind_int(dirStmt, 5, 0) // is_virtual = 0 for real entry
                sqlite3_bind_int(dirStmt, 6, entry.isAuxiliary ? 1 : 0)
                sqlite3_bind_int(dirStmt, 7, entry.isDiskImageBackground ? 1 : 0)
                sqlite3_bind_int(dirStmt, 8, entry.isApplicationsShortcut ? 1 : 0)
                payload.withUnsafeBytes { rawBuffer in
                    guard let base = rawBuffer.baseAddress else { return }
                    _ = sqlite3_bind_blob(dirStmt, 9, base, Int32(rawBuffer.count), Self.SQLITE_TRANSIENT)
                }
                if sqlite3_step(dirStmt) != SQLITE_DONE {
                    throw EntryIndexError.sqliteError(code: sqlite3_errcode(db), message: String(cString: sqlite3_errmsg(db)))
                }
            }

            try execute(sql: "COMMIT;")
        } catch {
            try? execute(sql: "ROLLBACK;")
            throw error
        }
    }

    // MARK: - Query Methods

    public func listDirectory(
        parentPath: String,
        includeAuxiliary: Bool = false,
        includeDiskImageBackground: Bool = false,
        includeApplicationsShortcut: Bool = false,
        limit: Int = 1000,
        offset: Int = 0
    ) throws -> [ArchiveEntry] {
        guard let db = db else { throw EntryIndexError.databaseClosed }
        let normalizedParent = parentPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        let sql = """
        SELECT payload FROM directory_nodes
        WHERE parent_path = ? COLLATE BINARY
          AND (? OR is_auxiliary = 0)
          AND (? OR is_disk_image_background = 0)
          AND (? OR is_dmg_applications_shortcut = 0)
        ORDER BY is_directory DESC, sort_name COLLATE NOCASE ASC, canonical_path COLLATE BINARY ASC
        LIMIT ? OFFSET ?;
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw EntryIndexError.sqliteError(code: sqlite3_errcode(db), message: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, normalizedParent, -1, Self.SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 2, includeAuxiliary ? 1 : 0)
        sqlite3_bind_int(stmt, 3, includeDiskImageBackground ? 1 : 0)
        sqlite3_bind_int(stmt, 4, includeApplicationsShortcut ? 1 : 0)
        sqlite3_bind_int(stmt, 5, Int32(limit))
        sqlite3_bind_int(stmt, 6, Int32(offset))

        var results: [ArchiveEntry] = []
        let decoder = JSONDecoder()

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let blob = sqlite3_column_blob(stmt, 0) else { continue }
            let bytesCount = sqlite3_column_bytes(stmt, 0)
            let data = Data(bytes: blob, count: Int(bytesCount))
            let entry = try decoder.decode(ArchiveEntry.self, from: data)
            results.append(entry)
        }
        return results
    }

    public func countDirectory(
        parentPath: String,
        includeAuxiliary: Bool = false,
        includeDiskImageBackground: Bool = false,
        includeApplicationsShortcut: Bool = false
    ) throws -> Int {
        guard let db = db else { throw EntryIndexError.databaseClosed }
        let normalizedParent = parentPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        let sql = """
        SELECT COUNT(*) FROM directory_nodes
        WHERE parent_path = ? COLLATE BINARY
          AND (? OR is_auxiliary = 0)
          AND (? OR is_disk_image_background = 0)
          AND (? OR is_dmg_applications_shortcut = 0);
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw EntryIndexError.sqliteError(code: sqlite3_errcode(db), message: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, normalizedParent, -1, Self.SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 2, includeAuxiliary ? 1 : 0)
        sqlite3_bind_int(stmt, 3, includeDiskImageBackground ? 1 : 0)
        sqlite3_bind_int(stmt, 4, includeApplicationsShortcut ? 1 : 0)

        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int64(stmt, 0))
        }
        return 0
    }

    public func search(
        keyword: String,
        includeAuxiliary: Bool = false,
        limit: Int = 500,
        offset: Int = 0
    ) throws -> [ArchiveEntry] {
        guard let db = db else { throw EntryIndexError.databaseClosed }

        // Escape \, %, and _ with \ so literal % and _ do not act as LIKE wildcards (Test A12)
        var escaped = ""
        for char in keyword {
            if char == "\\" || char == "%" || char == "_" {
                escaped.append("\\")
            }
            escaped.append(char)
        }
        let pattern = "%\(escaped)%"

        let sql = """
        SELECT payload FROM entries
        WHERE path LIKE ? ESCAPE '\\'
          AND (? OR is_auxiliary = 0)
        ORDER BY path COLLATE NOCASE ASC, id COLLATE BINARY ASC
        LIMIT ? OFFSET ?;
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw EntryIndexError.sqliteError(code: sqlite3_errcode(db), message: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, pattern, -1, Self.SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 2, includeAuxiliary ? 1 : 0)
        sqlite3_bind_int(stmt, 3, Int32(limit))
        sqlite3_bind_int(stmt, 4, Int32(offset))

        var results: [ArchiveEntry] = []
        let decoder = JSONDecoder()

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let blob = sqlite3_column_blob(stmt, 0) else { continue }
            let bytesCount = sqlite3_column_bytes(stmt, 0)
            let data = Data(bytes: blob, count: Int(bytesCount))
            let entry = try decoder.decode(ArchiveEntry.self, from: data)
            results.append(entry)
        }
        return results
    }

    public func entry(forPath path: String) throws -> ArchiveEntry? {
        guard let db = db else { throw EntryIndexError.databaseClosed }
        let normalized = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !normalized.isEmpty else { return nil }

        let decoder = JSONDecoder()

        // 1. Check entries table
        let sqlEntries = "SELECT payload FROM entries WHERE path = ? COLLATE BINARY LIMIT 1;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sqlEntries, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, normalized, -1, Self.SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW, let blob = sqlite3_column_blob(stmt, 0) {
                let bytesCount = sqlite3_column_bytes(stmt, 0)
                let data = Data(bytes: blob, count: Int(bytesCount))
                sqlite3_finalize(stmt)
                return try decoder.decode(ArchiveEntry.self, from: data)
            }
            sqlite3_finalize(stmt)
        }

        // 2. Check directory_nodes table (in case of virtual directory)
        let sqlDir = "SELECT payload FROM directory_nodes WHERE canonical_path = ? COLLATE BINARY LIMIT 1;"
        if sqlite3_prepare_v2(db, sqlDir, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, normalized, -1, Self.SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW, let blob = sqlite3_column_blob(stmt, 0) {
                let bytesCount = sqlite3_column_bytes(stmt, 0)
                let data = Data(bytes: blob, count: Int(bytesCount))
                sqlite3_finalize(stmt)
                return try decoder.decode(ArchiveEntry.self, from: data)
            }
            sqlite3_finalize(stmt)
        }

        return nil
    }

    public func subtreeEntries(under directoryPath: String) throws -> [ArchiveEntry] {
        guard let db = db else { throw EntryIndexError.databaseClosed }
        let normalized = directoryPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if normalized.isEmpty {
            return try allEntries(includeAuxiliary: true)
        }

        var escaped = ""
        for char in normalized {
            if char == "\\" || char == "%" || char == "_" {
                escaped.append("\\")
            }
            escaped.append(char)
        }
        let prefixPattern = "\(escaped)/%"

        let sql = """
        SELECT payload FROM entries
        WHERE path = ? COLLATE BINARY OR path LIKE ? ESCAPE '\\'
        ORDER BY path COLLATE NOCASE ASC;
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw EntryIndexError.sqliteError(code: sqlite3_errcode(db), message: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, normalized, -1, Self.SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, prefixPattern, -1, Self.SQLITE_TRANSIENT)

        var results: [ArchiveEntry] = []
        let decoder = JSONDecoder()

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let blob = sqlite3_column_blob(stmt, 0) else { continue }
            let bytesCount = sqlite3_column_bytes(stmt, 0)
            let data = Data(bytes: blob, count: Int(bytesCount))
            let entry = try decoder.decode(ArchiveEntry.self, from: data)
            results.append(entry)
        }
        return results
    }

    public func allEntries(includeAuxiliary: Bool = true) throws -> [ArchiveEntry] {
        guard let db = db else { throw EntryIndexError.databaseClosed }

        let sql = """
        SELECT payload FROM entries
        WHERE (? OR is_auxiliary = 0)
        ORDER BY path COLLATE NOCASE ASC;
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw EntryIndexError.sqliteError(code: sqlite3_errcode(db), message: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int(stmt, 1, includeAuxiliary ? 1 : 0)

        var results: [ArchiveEntry] = []
        let decoder = JSONDecoder()

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let blob = sqlite3_column_blob(stmt, 0) else { continue }
            let bytesCount = sqlite3_column_bytes(stmt, 0)
            let data = Data(bytes: blob, count: Int(bytesCount))
            let entry = try decoder.decode(ArchiveEntry.self, from: data)
            results.append(entry)
        }
        return results
    }

    public func close() {
        if let db = db {
            sqlite3_close_v2(db)
            self.db = nil
        }
    }
}
