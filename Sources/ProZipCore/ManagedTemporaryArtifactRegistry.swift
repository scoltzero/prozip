import Foundation
import SQLite3
import Darwin
import ProZipShared

// MARK: - Artifact Purpose & Publication State (data/publish-registry.sql & doc/04 section 3)

public enum ArtifactPurpose: String, Codable, Sendable {
    case shelfResultSaving
    case streamExtraction
    case fontInstallation
    case applicationInstallation
    case finderQuickCompression
    case archiveCreation
    case archiveEditing
    case previewMaterialization
    case ownershipUncertain
    case recoveryAvailable
}

public enum PublicationState: String, Codable, Sendable {
    case prepared
    case backingUp
    case committed
    case rollingBack
    case recoveryUncertain
}

// MARK: - File Identity (data/publish-registry.sql)

public struct FileIdentity: Codable, Equatable, Sendable {
    public let deviceID: Int64
    public let inode: UInt64
    public let fileType: UInt32
    public let birthSeconds: Int64
    public let birthNanoseconds: Int64
    public let sizeBytes: Int64

    public init(
        deviceID: Int64,
        inode: UInt64,
        fileType: UInt32,
        birthSeconds: Int64,
        birthNanoseconds: Int64,
        sizeBytes: Int64
    ) {
        self.deviceID = deviceID
        self.inode = inode
        self.fileType = fileType
        self.birthSeconds = birthSeconds
        self.birthNanoseconds = birthNanoseconds
        self.sizeBytes = sizeBytes
    }

    public static func capture(at url: URL) throws -> FileIdentity {
        var statInfo = stat()
        let path = url.path
        if stat(path, &statInfo) != 0 {
            let err = errno
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(err),
                userInfo: [NSLocalizedDescriptionKey: "stat 失败 (\(path)): \(String(cString: strerror(err)))"]
            )
        }

        #if os(macOS) || os(iOS)
        let birthSec = Int64(statInfo.st_birthtimespec.tv_sec)
        let birthNsec = Int64(statInfo.st_birthtimespec.tv_nsec)
        #else
        let birthSec = Int64(statInfo.st_mtimespec.tv_sec)
        let birthNsec = Int64(statInfo.st_mtimespec.tv_nsec)
        #endif

        return FileIdentity(
            deviceID: Int64(statInfo.st_dev),
            inode: UInt64(statInfo.st_ino),
            fileType: UInt32(statInfo.st_mode) & UInt32(S_IFMT),
            birthSeconds: birthSec,
            birthNanoseconds: birthNsec,
            sizeBytes: Int64(statInfo.st_size)
        )
    }
}

// MARK: - Publication Plan

public struct PublicationPlan: Codable, Sendable {
    public let targetPath: String
    public let partialPath: String
    public let backupPath: String?
    public let allowOverwrite: Bool
    public let artifactID: String?

    public init(
        targetPath: String,
        partialPath: String,
        backupPath: String? = nil,
        allowOverwrite: Bool = true,
        artifactID: String? = nil
    ) {
        self.targetPath = targetPath
        self.partialPath = partialPath
        self.backupPath = backupPath
        self.allowOverwrite = allowOverwrite
        self.artifactID = artifactID
    }
}

// MARK: - Records for Inspection

public struct TemporaryArtifactRecord: Sendable {
    public let artifactID: String
    public let operationID: String
    public let sessionID: String
    public let processID: Int64
    public let purpose: ArtifactPurpose
    public let path: String
    public let kind: String
    public let state: String
    public let identity: FileIdentity?
    public let reservedAt: Date
    public let updatedAt: Date
    public let lastError: String?
}

public struct PublicationRecord: Sendable {
    public let transactionID: String
    public let sessionID: String
    public let processID: Int64
    public let state: PublicationState
    public let parentPath: String
    public let plan: PublicationPlan
    public let reservedAt: Date
    public let updatedAt: Date
    public let lastError: String?
}

// MARK: - Registry Error

public enum RegistryError: LocalizedError, Equatable {
    case sqliteError(code: Int32, message: String)
    case databaseClosed
    case artifactNotFound(String)
    case publicationNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .sqliteError(let code, let message):
            return "临时登记表 SQLite 错误 (\(code)): \(message)"
        case .databaseClosed:
            return "临时产物登记表已关闭"
        case .artifactNotFound(let id):
            return "未找到登记的临时产物：\(id)"
        case .publicationNotFound(let id):
            return "未找到登记的发布事务：\(id)"
        }
    }
}

// MARK: - ManagedTemporaryArtifactRegistry Actor (data/publish-registry.sql & doc/04 & doc/10)

public actor ManagedTemporaryArtifactRegistry {
    public static let shared: ManagedTemporaryArtifactRegistry = {
        do {
            return try ManagedTemporaryArtifactRegistry()
        } catch {
            return try! ManagedTemporaryArtifactRegistry.inMemory()
        }
    }()

    public let databaseURL: URL?
    public let isInMemory: Bool

    private var db: OpaquePointer?
    private static let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public static func defaultRegistryURL() -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Caches")
        let dir = caches.appendingPathComponent("org.prozip.ProZip/Temporary", isDirectory: true)
        return dir.appendingPathComponent("temporary-artifacts.sqlite")
    }

    public init(url: URL? = nil) throws {
        if let u = url, u.path == ":memory:" || u.absoluteString == ":memory:" {
            self.databaseURL = nil
            self.isInMemory = true
        } else if let u = url {
            self.databaseURL = u
            self.isInMemory = false
        } else {
            self.databaseURL = Self.defaultRegistryURL()
            self.isInMemory = false
        }
        self.db = try Self.openAndInitialize(isInMemory: self.isInMemory, databaseURL: self.databaseURL)
    }

    public init(inMemory: Bool = false, fileURL: URL? = nil) throws {
        if inMemory {
            self.databaseURL = nil
            self.isInMemory = true
        } else {
            self.databaseURL = fileURL ?? Self.defaultRegistryURL()
            self.isInMemory = false
        }
        self.db = try Self.openAndInitialize(isInMemory: self.isInMemory, databaseURL: self.databaseURL)
    }

    public static func inMemory() throws -> ManagedTemporaryArtifactRegistry {
        try ManagedTemporaryArtifactRegistry(url: URL(string: ":memory:"))
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
            throw RegistryError.sqliteError(code: openResult, message: msg)
        }

        let schemaSQL = """
        PRAGMA journal_mode=WAL;
        PRAGMA synchronous=FULL;
        PRAGMA fullfsync=ON;
        PRAGMA checkpoint_fullfsync=ON;
        PRAGMA foreign_keys=ON;
        PRAGMA wal_autocheckpoint=100;

        CREATE TABLE IF NOT EXISTS temporary_artifacts (
            artifact_id TEXT PRIMARY KEY,
            operation_id TEXT NOT NULL,
            session_id TEXT NOT NULL,
            process_id INTEGER NOT NULL,
            purpose TEXT NOT NULL,
            path TEXT NOT NULL UNIQUE,
            kind TEXT NOT NULL,
            ownership_token TEXT NOT NULL,
            state TEXT NOT NULL,
            volume_uuid TEXT,
            bookmark BLOB,
            device_id INTEGER,
            inode INTEGER,
            file_type INTEGER,
            birth_seconds INTEGER,
            birth_nanoseconds INTEGER,
            size_bytes INTEGER,
            reserved_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            retry_count INTEGER NOT NULL DEFAULT 0,
            last_error TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_temporary_artifacts_session
            ON temporary_artifacts(session_id, process_id, state);

        CREATE TABLE IF NOT EXISTS archive_publications (
            transaction_id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            process_id INTEGER NOT NULL,
            ownership_token TEXT NOT NULL,
            state TEXT NOT NULL,
            parent_path TEXT NOT NULL,
            volume_uuid TEXT,
            bookmark BLOB,
            plan BLOB NOT NULL,
            reserved_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            last_error TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_archive_publications_session
            ON archive_publications(session_id, process_id, state);

        PRAGMA user_version=2;
        """
        try executeStatic(sql: schemaSQL, on: db)
        return db
    }

    private static func executeStatic(sql: String, on db: OpaquePointer) throws {
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            let message = errMsg.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(db))
            sqlite3_free(errMsg)
            throw RegistryError.sqliteError(code: sqlite3_errcode(db), message: message)
        }
    }

    // MARK: - Artifact Management

    private static let managedTempSessionPrefix = "managed-temp:"

    public func createManagedTemporaryDirectory(purpose: String = "misc") throws -> URL {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("org.prozip.ProZip-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let artifactPurpose: ArtifactPurpose
        switch purpose {
        case "quicklook", "preview", "entry-export": artifactPurpose = .previewMaterialization
        case "application-installation": artifactPurpose = .applicationInstallation
        case "creation-draft": artifactPurpose = .archiveEditing
        default: artifactPurpose = .streamExtraction
        }
        _ = try registerArtifact(
            at: base,
            purpose: artifactPurpose,
            sessionID: "\(Self.managedTempSessionPrefix)\(purpose):\(UUID().uuidString)"
        )
        return base
    }

    public func registerArtifact(
        at url: URL,
        purpose: ArtifactPurpose,
        sessionID: String,
        operationID: String = UUID().uuidString
    ) throws -> String {
        guard let db = db else { throw RegistryError.databaseClosed }

        let artifactID = UUID().uuidString
        let pid = Int64(ProcessInfo.processInfo.processIdentifier)
        let path = url.path
        let ownershipToken = sessionID
        let now = Date().timeIntervalSinceReferenceDate

        let identity = try? FileIdentity.capture(at: url)
        let isDir = identity?.fileType == UInt32(S_IFDIR)
        let kind = isDir ? "directory" : "file"
        let state = identity != nil ? "active" : "reserved"

        let volumeUUID = (try? url.resourceValues(forKeys: [.volumeUUIDStringKey]))?.volumeUUIDString
        let bookmark = try? url.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)

        let sql = """
        INSERT INTO temporary_artifacts (
            artifact_id, operation_id, session_id, process_id, purpose,
            path, kind, ownership_token, state, volume_uuid, bookmark,
            device_id, inode, file_type, birth_seconds, birth_nanoseconds, size_bytes,
            reserved_at, updated_at, retry_count, last_error
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, NULL)
        ON CONFLICT(path) DO UPDATE SET
            artifact_id = excluded.artifact_id,
            operation_id = excluded.operation_id,
            session_id = excluded.session_id,
            process_id = excluded.process_id,
            purpose = excluded.purpose,
            kind = excluded.kind,
            ownership_token = excluded.ownership_token,
            state = excluded.state,
            volume_uuid = excluded.volume_uuid,
            bookmark = excluded.bookmark,
            device_id = excluded.device_id,
            inode = excluded.inode,
            file_type = excluded.file_type,
            birth_seconds = excluded.birth_seconds,
            birth_nanoseconds = excluded.birth_nanoseconds,
            size_bytes = excluded.size_bytes,
            updated_at = excluded.updated_at;
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw RegistryError.sqliteError(code: sqlite3_errcode(db), message: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, artifactID, -1, Self.SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, operationID, -1, Self.SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, sessionID, -1, Self.SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 4, pid)
        sqlite3_bind_text(stmt, 5, purpose.rawValue, -1, Self.SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 6, path, -1, Self.SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 7, kind, -1, Self.SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 8, ownershipToken, -1, Self.SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 9, state, -1, Self.SQLITE_TRANSIENT)

        if let vUUID = volumeUUID {
            sqlite3_bind_text(stmt, 10, vUUID, -1, Self.SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 10)
        }

        if let bm = bookmark {
            bm.withUnsafeBytes { raw in
                if let base = raw.baseAddress {
                    _ = sqlite3_bind_blob(stmt, 11, base, Int32(raw.count), Self.SQLITE_TRANSIENT)
                } else {
                    _ = sqlite3_bind_null(stmt, 11)
                }
            }
        } else {
            sqlite3_bind_null(stmt, 11)
        }

        if let id = identity {
            sqlite3_bind_int64(stmt, 12, id.deviceID)
            sqlite3_bind_int64(stmt, 13, Int64(bitPattern: id.inode))
            sqlite3_bind_int64(stmt, 14, Int64(id.fileType))
            sqlite3_bind_int64(stmt, 15, id.birthSeconds)
            sqlite3_bind_int64(stmt, 16, id.birthNanoseconds)
            sqlite3_bind_int64(stmt, 17, id.sizeBytes)
        } else {
            sqlite3_bind_null(stmt, 12)
            sqlite3_bind_null(stmt, 13)
            sqlite3_bind_null(stmt, 14)
            sqlite3_bind_null(stmt, 15)
            sqlite3_bind_null(stmt, 16)
            sqlite3_bind_null(stmt, 17)
        }

        sqlite3_bind_double(stmt, 18, now)
        sqlite3_bind_double(stmt, 19, now)

        if sqlite3_step(stmt) != SQLITE_DONE {
            throw RegistryError.sqliteError(code: sqlite3_errcode(db), message: String(cString: sqlite3_errmsg(db)))
        }

        return artifactID
    }

    public func updateArtifactIdentity(artifactID: String, at url: URL) throws {
        guard let db = db else { throw RegistryError.databaseClosed }
        let identity = try FileIdentity.capture(at: url)
        let isDir = identity.fileType == UInt32(S_IFDIR)
        let kind = isDir ? "directory" : "file"
        let now = Date().timeIntervalSinceReferenceDate

        let sql = """
        UPDATE temporary_artifacts SET
            device_id = ?,
            inode = ?,
            file_type = ?,
            birth_seconds = ?,
            birth_nanoseconds = ?,
            size_bytes = ?,
            kind = ?,
            state = 'active',
            updated_at = ?
        WHERE artifact_id = ?;
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw RegistryError.sqliteError(code: sqlite3_errcode(db), message: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, identity.deviceID)
        sqlite3_bind_int64(stmt, 2, Int64(bitPattern: identity.inode))
        sqlite3_bind_int64(stmt, 3, Int64(identity.fileType))
        sqlite3_bind_int64(stmt, 4, identity.birthSeconds)
        sqlite3_bind_int64(stmt, 5, identity.birthNanoseconds)
        sqlite3_bind_int64(stmt, 6, identity.sizeBytes)
        sqlite3_bind_text(stmt, 7, kind, -1, Self.SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 8, now)
        sqlite3_bind_text(stmt, 9, artifactID, -1, Self.SQLITE_TRANSIENT)

        if sqlite3_step(stmt) != SQLITE_DONE {
            throw RegistryError.sqliteError(code: sqlite3_errcode(db), message: String(cString: sqlite3_errmsg(db)))
        }
    }

    public func safelyRemoveArtifact(artifactID: String) throws {
        guard let db = db else { throw RegistryError.databaseClosed }

        let sql = """
        SELECT path, device_id, inode, birth_seconds FROM temporary_artifacts WHERE artifact_id = ?;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw RegistryError.sqliteError(code: sqlite3_errcode(db), message: String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_text(stmt, 1, artifactID, -1, Self.SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            sqlite3_finalize(stmt)
            return
        }

        guard let pathCStr = sqlite3_column_text(stmt, 0) else {
            sqlite3_finalize(stmt)
            return
        }
        let path = String(cString: pathCStr)

        let hasDev = sqlite3_column_type(stmt, 1) != SQLITE_NULL
        let recordedDev = hasDev ? sqlite3_column_int64(stmt, 1) : nil

        let hasIno = sqlite3_column_type(stmt, 2) != SQLITE_NULL
        let recordedIno = hasIno ? UInt64(bitPattern: sqlite3_column_int64(stmt, 2)) : nil

        let hasBirth = sqlite3_column_type(stmt, 3) != SQLITE_NULL
        let recordedBirth = hasBirth ? sqlite3_column_int64(stmt, 3) : nil

        sqlite3_finalize(stmt)

        let fileManager = FileManager.default
        let url = URL(fileURLWithPath: path)

        if fileManager.fileExists(atPath: path) {
            if let recDev = recordedDev, let recIno = recordedIno, let recBirth = recordedBirth {
                let currentIdentity: FileIdentity
                do {
                    currentIdentity = try FileIdentity.capture(at: url)
                } catch {
                    try updateArtifactState(artifactID: artifactID, state: "ownershipUncertain", error: error.localizedDescription)
                    throw ProZipError.artifactIdentityMismatch(path)
                }

                if currentIdentity.deviceID != recDev || currentIdentity.inode != recIno || currentIdentity.birthSeconds != recBirth {
                    try updateArtifactState(artifactID: artifactID, state: "ownershipUncertain", error: "Identity mismatch")
                    throw ProZipError.artifactIdentityMismatch(path)
                }
            }

            try fileManager.removeItem(at: url)
        }

        try updateArtifactState(artifactID: artifactID, state: "cleaned", error: nil)
    }

    private func updateArtifactState(artifactID: String, state: String, error: String? = nil) throws {
        guard let db = db else { throw RegistryError.databaseClosed }
        let now = Date().timeIntervalSinceReferenceDate
        let sql = """
        UPDATE temporary_artifacts SET state = ?, last_error = ?, updated_at = ? WHERE artifact_id = ?;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw RegistryError.sqliteError(code: sqlite3_errcode(db), message: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, state, -1, Self.SQLITE_TRANSIENT)
        if let err = error {
            sqlite3_bind_text(stmt, 2, err, -1, Self.SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 2)
        }
        sqlite3_bind_double(stmt, 3, now)
        sqlite3_bind_text(stmt, 4, artifactID, -1, Self.SQLITE_TRANSIENT)

        if sqlite3_step(stmt) != SQLITE_DONE {
            throw RegistryError.sqliteError(code: sqlite3_errcode(db), message: String(cString: sqlite3_errmsg(db)))
        }
    }

    // MARK: - Publications Management (archive_publications)

    private func recordPublication(
        txID: String,
        sessionID: String,
        state: PublicationState,
        parentPath: String,
        plan: PublicationPlan
    ) throws {
        guard let db = db else { throw RegistryError.databaseClosed }
        let pid = Int64(ProcessInfo.processInfo.processIdentifier)
        let now = Date().timeIntervalSinceReferenceDate
        let planData = try JSONEncoder().encode(plan)

        let sql = """
        INSERT INTO archive_publications (
            transaction_id, session_id, process_id, ownership_token,
            state, parent_path, volume_uuid, bookmark, plan, reserved_at, updated_at, last_error
        ) VALUES (?, ?, ?, ?, ?, ?, NULL, NULL, ?, ?, ?, NULL)
        ON CONFLICT(transaction_id) DO UPDATE SET
            state = excluded.state,
            plan = excluded.plan,
            updated_at = excluded.updated_at,
            last_error = excluded.last_error;
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw RegistryError.sqliteError(code: sqlite3_errcode(db), message: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, txID, -1, Self.SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, sessionID, -1, Self.SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 3, pid)
        sqlite3_bind_text(stmt, 4, sessionID, -1, Self.SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 5, state.rawValue, -1, Self.SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 6, parentPath, -1, Self.SQLITE_TRANSIENT)
        planData.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            _ = sqlite3_bind_blob(stmt, 7, base, Int32(raw.count), Self.SQLITE_TRANSIENT)
        }
        sqlite3_bind_double(stmt, 8, now)
        sqlite3_bind_double(stmt, 9, now)

        if sqlite3_step(stmt) != SQLITE_DONE {
            throw RegistryError.sqliteError(code: sqlite3_errcode(db), message: String(cString: sqlite3_errmsg(db)))
        }
    }

    private func updatePublicationState(
        txID: String,
        state: PublicationState,
        plan: PublicationPlan? = nil,
        error: String? = nil
    ) throws {
        guard let db = db else { throw RegistryError.databaseClosed }
        let now = Date().timeIntervalSinceReferenceDate
        let planData = try plan.map { try JSONEncoder().encode($0) }

        let sql = """
        UPDATE archive_publications SET
            state = ?,
            plan = COALESCE(?, plan),
            last_error = ?,
            updated_at = ?
        WHERE transaction_id = ?;
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw RegistryError.sqliteError(code: sqlite3_errcode(db), message: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, state.rawValue, -1, Self.SQLITE_TRANSIENT)

        if let pd = planData {
            pd.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                _ = sqlite3_bind_blob(stmt, 2, base, Int32(raw.count), Self.SQLITE_TRANSIENT)
            }
        } else {
            sqlite3_bind_null(stmt, 2)
        }

        if let err = error {
            sqlite3_bind_text(stmt, 3, err, -1, Self.SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 3)
        }

        sqlite3_bind_double(stmt, 4, now)
        sqlite3_bind_text(stmt, 5, txID, -1, Self.SQLITE_TRANSIENT)

        if sqlite3_step(stmt) != SQLITE_DONE {
            throw RegistryError.sqliteError(code: sqlite3_errcode(db), message: String(cString: sqlite3_errmsg(db)))
        }
    }

    private func deletePublication(txID: String) throws {
        guard let db = db else { throw RegistryError.databaseClosed }
        let sql = "DELETE FROM archive_publications WHERE transaction_id = ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw RegistryError.sqliteError(code: sqlite3_errcode(db), message: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, txID, -1, Self.SQLITE_TRANSIENT)
        if sqlite3_step(stmt) != SQLITE_DONE {
            throw RegistryError.sqliteError(code: sqlite3_errcode(db), message: String(cString: sqlite3_errmsg(db)))
        }
    }

    // MARK: - Atomic Publication Transaction (doc/04 section 3 & doc/10 section 7)

    public func publishAtomically(
        targetURL: URL,
        sessionID: String = UUID().uuidString,
        allowOverwrite: Bool = true,
        writer: @Sendable (URL) async throws -> Void,
        verifier: @Sendable (URL) async throws -> Void
    ) async throws -> URL {
        let fileManager = FileManager.default
        let parentDir = targetURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        if fileManager.fileExists(atPath: targetURL.path) && !allowOverwrite {
            throw ProZipError.structureConflict("目标文件已存在且未开启覆盖：\(targetURL.path)")
        }

        let txUUID = UUID().uuidString
        let targetName = targetURL.lastPathComponent
        let partialURL = parentDir.appendingPathComponent("\(targetName).prozip-partial-\(txUUID)")

        let partialArtifactID = try registerArtifact(
            at: partialURL,
            purpose: .archiveCreation,
            sessionID: sessionID,
            operationID: txUUID
        )

        var plan = PublicationPlan(
            targetPath: targetURL.path,
            partialPath: partialURL.path,
            backupPath: nil,
            allowOverwrite: allowOverwrite,
            artifactID: partialArtifactID
        )

        try recordPublication(
            txID: txUUID,
            sessionID: sessionID,
            state: .prepared,
            parentPath: parentDir.path,
            plan: plan
        )

        var backupArtifactID: String?
        var backupURL: URL?

        do {
            try await writer(partialURL)
            try updateArtifactIdentity(artifactID: partialArtifactID, at: partialURL)
            try Task.checkCancellation()
            try await verifier(partialURL)
            try Task.checkCancellation()

            if fileManager.fileExists(atPath: targetURL.path) {
                guard allowOverwrite else {
                    throw ProZipError.structureConflict("目标文件已存在且未开启覆盖：\(targetURL.path)")
                }

                let bURL = parentDir.appendingPathComponent("\(targetName).prozip-backup-\(UUID().uuidString)")
                backupURL = bURL
                let bID = try registerArtifact(
                    at: bURL,
                    purpose: .recoveryAvailable,
                    sessionID: sessionID,
                    operationID: txUUID
                )
                backupArtifactID = bID

                plan = PublicationPlan(
                    targetPath: targetURL.path,
                    partialPath: partialURL.path,
                    backupPath: bURL.path,
                    allowOverwrite: allowOverwrite,
                    artifactID: partialArtifactID
                )
                try updatePublicationState(txID: txUUID, state: .backingUp, plan: plan)

                try fileManager.moveItem(at: targetURL, to: bURL)
                try updateArtifactIdentity(artifactID: bID, at: bURL)

                try fileManager.moveItem(at: partialURL, to: targetURL)
                try updatePublicationState(txID: txUUID, state: .committed, plan: plan)

                if let bID = backupArtifactID {
                    try? safelyRemoveArtifact(artifactID: bID)
                }
                try? updateArtifactState(artifactID: partialArtifactID, state: "committed")
            } else {
                try fileManager.moveItem(at: partialURL, to: targetURL)
                try updatePublicationState(txID: txUUID, state: .committed, plan: plan)
                try? updateArtifactState(artifactID: partialArtifactID, state: "committed")
            }

            try? deletePublication(txID: txUUID)
            return targetURL
        } catch {
            try? updatePublicationState(txID: txUUID, state: .rollingBack, plan: plan, error: error.localizedDescription)

            if fileManager.fileExists(atPath: partialURL.path) {
                try? safelyRemoveArtifact(artifactID: partialArtifactID)
            }

            if let bURL = backupURL, fileManager.fileExists(atPath: bURL.path) {
                do {
                    if fileManager.fileExists(atPath: targetURL.path) {
                        try fileManager.removeItem(at: targetURL)
                    }
                    try fileManager.moveItem(at: bURL, to: targetURL)
                    if let bID = backupArtifactID {
                        try? updateArtifactState(artifactID: bID, state: "restored")
                    }
                    try? deletePublication(txID: txUUID)
                } catch let rollbackError {
                    try? updatePublicationState(txID: txUUID, state: .recoveryUncertain, plan: plan, error: rollbackError.localizedDescription)
                    throw ProZipError.publicationRollbackFailed("无法恢复备份压缩包：\(rollbackError.localizedDescription)")
                }
            } else {
                try? deletePublication(txID: txUUID)
            }

            throw error
        }
    }

    // MARK: - Startup Crash Recovery (doc/10 section 7)

    public func performStartupRecovery() throws -> (rolledBackCount: Int, cleanedArtifactsCount: Int, uncertainPaths: [String]) {
        guard let db = db else { throw RegistryError.databaseClosed }

        var rolledBackCount = 0
        var cleanedArtifactsCount = 0
        var uncertainPaths: [String] = []
        let fm = FileManager.default

        // 1. Scan archive_publications
        let pubSQL = "SELECT transaction_id, state, plan FROM archive_publications;"
        var pubStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, pubSQL, -1, &pubStmt, nil) == SQLITE_OK {
            struct PubItem {
                let txID: String
                let state: PublicationState
                let plan: PublicationPlan
            }
            var items: [PubItem] = []
            let decoder = JSONDecoder()

            while sqlite3_step(pubStmt) == SQLITE_ROW {
                guard let txCStr = sqlite3_column_text(pubStmt, 0),
                      let stateCStr = sqlite3_column_text(pubStmt, 1),
                      let planBlob = sqlite3_column_blob(pubStmt, 2) else { continue }
                let txID = String(cString: txCStr)
                guard let state = PublicationState(rawValue: String(cString: stateCStr)) else { continue }
                let planBytes = sqlite3_column_bytes(pubStmt, 2)
                let planData = Data(bytes: planBlob, count: Int(planBytes))
                if let plan = try? decoder.decode(PublicationPlan.self, from: planData) {
                    items.append(PubItem(txID: txID, state: state, plan: plan))
                }
            }
            sqlite3_finalize(pubStmt)

            for item in items {
                switch item.state {
                case .prepared, .backingUp, .rollingBack:
                    // Remove partial file
                    if fm.fileExists(atPath: item.plan.partialPath) {
                        if let artID = item.plan.artifactID {
                            try? safelyRemoveArtifact(artifactID: artID)
                        } else {
                            try? fm.removeItem(atPath: item.plan.partialPath)
                        }
                        cleanedArtifactsCount += 1
                    }

                    // Restore backup if present
                    if let backupPath = item.plan.backupPath, fm.fileExists(atPath: backupPath) {
                        do {
                            if fm.fileExists(atPath: item.plan.targetPath) {
                                try fm.removeItem(atPath: item.plan.targetPath)
                            }
                            try fm.moveItem(atPath: backupPath, toPath: item.plan.targetPath)
                            rolledBackCount += 1
                            try deletePublication(txID: item.txID)
                        } catch {
                            uncertainPaths.append(backupPath)
                            try? updatePublicationState(txID: item.txID, state: .recoveryUncertain, plan: item.plan, error: error.localizedDescription)
                        }
                    } else {
                        rolledBackCount += 1
                        try deletePublication(txID: item.txID)
                    }

                case .committed:
                    if let backupPath = item.plan.backupPath, fm.fileExists(atPath: backupPath) {
                        try? fm.removeItem(atPath: backupPath)
                        cleanedArtifactsCount += 1
                    }
                    try deletePublication(txID: item.txID)

                case .recoveryUncertain:
                    if let backupPath = item.plan.backupPath, fm.fileExists(atPath: backupPath) {
                        uncertainPaths.append(backupPath)
                    }
                    if fm.fileExists(atPath: item.plan.partialPath) {
                        uncertainPaths.append(item.plan.partialPath)
                    }
                }
            }
        }

        // 2. Scan temporary_artifacts from dead processes
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let artSQL = "SELECT artifact_id, process_id, path FROM temporary_artifacts WHERE state NOT IN ('cleaned', 'committed', 'restored', 'ownershipUncertain');"
        var artStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, artSQL, -1, &artStmt, nil) == SQLITE_OK {
            var deadTargets: [(artifactID: String, path: String)] = []
            while sqlite3_step(artStmt) == SQLITE_ROW {
                guard let artCStr = sqlite3_column_text(artStmt, 0),
                      let pathCStr = sqlite3_column_text(artStmt, 2) else { continue }
                let pid = sqlite3_column_int64(artStmt, 1)
                let isDead = Self.isProcessDead(pid: pid, currentPID: currentPID)
                if isDead {
                    deadTargets.append((String(cString: artCStr), String(cString: pathCStr)))
                }
            }
            sqlite3_finalize(artStmt)

            for target in deadTargets {
                do {
                    try safelyRemoveArtifact(artifactID: target.artifactID)
                    cleanedArtifactsCount += 1
                } catch ProZipError.artifactIdentityMismatch(let path) {
                    uncertainPaths.append(path)
                } catch {
                    // Ignored
                }
            }
        }

        return (rolledBackCount, cleanedArtifactsCount, uncertainPaths)
    }

    // MARK: - Maintenance & Capacity

    public func totalCleanableBytes() -> Int64 {
        guard let db = db else { return 0 }
        let sql = """
        SELECT session_id, process_id, purpose, path, reserved_at
        FROM temporary_artifacts
        WHERE state NOT IN ('cleaned', 'committed', 'restored', 'ownershipUncertain')
          AND operation_id NOT IN (SELECT transaction_id FROM archive_publications);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }

        var total: Int64 = 0
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let now = Date().timeIntervalSinceReferenceDate
        let openPaths = Self.openProcessFilePaths()

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let sessionCStr = sqlite3_column_text(stmt, 0),
                  let purposeCStr = sqlite3_column_text(stmt, 2),
                  let pathCStr = sqlite3_column_text(stmt, 3) else { continue }
            let sessionID = String(cString: sessionCStr)
            let pid = sqlite3_column_int64(stmt, 1)
            let purpose = String(cString: purposeCStr)
            let path = String(cString: pathCStr)
            let reservedAt = sqlite3_column_double(stmt, 4)

            guard let diskBytes = Self.artifactDiskBytes(at: path) else { continue }

            if Self.isArtifactCleanable(
                pid: pid,
                currentPID: currentPID,
                sessionID: sessionID,
                purpose: purpose,
                path: path,
                diskBytes: diskBytes,
                reservedAt: reservedAt,
                now: now,
                openPaths: openPaths
            ) {
                total += diskBytes
            }
        }
        return total
    }

    public func cleanAllTemporaryFiles() throws -> Int64 {
        guard let db = db else { throw RegistryError.databaseClosed }
        let sql = """
        SELECT artifact_id, session_id, process_id, purpose, path, reserved_at
        FROM temporary_artifacts
        WHERE state NOT IN ('cleaned', 'committed', 'restored', 'ownershipUncertain')
          AND operation_id NOT IN (SELECT transaction_id FROM archive_publications);
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw RegistryError.sqliteError(code: sqlite3_errcode(db), message: String(cString: sqlite3_errmsg(db)))
        }

        struct Candidate {
            let artifactID: String
            let sessionID: String
            let pid: Int64
            let purpose: String
            let path: String
            let reservedAt: Double
        }

        var candidates: [Candidate] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idCStr = sqlite3_column_text(stmt, 0),
                  let sessionCStr = sqlite3_column_text(stmt, 1),
                  let purposeCStr = sqlite3_column_text(stmt, 3),
                  let pathCStr = sqlite3_column_text(stmt, 4) else { continue }
            candidates.append(Candidate(
                artifactID: String(cString: idCStr),
                sessionID: String(cString: sessionCStr),
                pid: sqlite3_column_int64(stmt, 2),
                purpose: String(cString: purposeCStr),
                path: String(cString: pathCStr),
                reservedAt: sqlite3_column_double(stmt, 5)
            ))
        }
        sqlite3_finalize(stmt)

        let currentPID = ProcessInfo.processInfo.processIdentifier
        let now = Date().timeIntervalSinceReferenceDate
        let openPaths = Self.openProcessFilePaths()
        var freedBytes: Int64 = 0

        for candidate in candidates {
            let diskBytes = Self.artifactDiskBytes(at: candidate.path)
            if let bytes = diskBytes {
                guard Self.isArtifactCleanable(
                    pid: candidate.pid,
                    currentPID: currentPID,
                    sessionID: candidate.sessionID,
                    purpose: candidate.purpose,
                    path: candidate.path,
                    diskBytes: bytes,
                    reservedAt: candidate.reservedAt,
                    now: now,
                    openPaths: openPaths
                ) else { continue }
                do {
                    try safelyRemoveArtifact(artifactID: candidate.artifactID)
                    freedBytes += bytes
                } catch {
                    // Skip if identity mismatch or deletion error
                }
            } else if Self.isProcessDead(pid: candidate.pid, currentPID: currentPID) ||
                      (candidate.pid == Int64(currentPID)
                       && candidate.sessionID.hasPrefix(Self.managedTempSessionPrefix)
                       && candidate.purpose == ArtifactPurpose.previewMaterialization.rawValue) {
                try? safelyRemoveArtifact(artifactID: candidate.artifactID)
            }
        }
        return freedBytes
    }

    private static func isProcessDead(pid: Int64, currentPID: Int32) -> Bool {
        guard pid != Int64(currentPID), pid > 0, pid <= Int64(Int32.max) else { return false }
        return kill(pid_t(pid), 0) != 0 && errno == ESRCH
    }

    private static func isArtifactCleanable(
        pid: Int64,
        currentPID: Int32,
        sessionID: String,
        purpose: String,
        path: String,
        diskBytes: Int64,
        reservedAt: Double,
        now: Double,
        openPaths: Set<String>
    ) -> Bool {
        if isProcessDead(pid: pid, currentPID: currentPID) {
            return true
        }
        guard pid == Int64(currentPID),
              sessionID.hasPrefix(managedTempSessionPrefix),
              purpose == ArtifactPurpose.previewMaterialization.rawValue else {
            return false
        }
        if diskBytes == 0 && (now - reservedAt) < 5.0 {
            return false
        }
        return !isPathOpen(path, in: openPaths)
    }

    /// Computes on-disk payload bytes without following symbolic links. Returns `nil` when `path` no longer exists.
    private static func artifactDiskBytes(at path: String) -> Int64? {
        var rootStat = stat()
        guard lstat(path, &rootStat) == 0 else { return nil }
        let mode = rootStat.st_mode & S_IFMT
        if mode != S_IFDIR {
            return mode == S_IFREG ? Int64(rootStat.st_size) : 0
        }

        let dirURL = URL(fileURLWithPath: path, isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: dirURL,
            includingPropertiesForKeys: nil,
            options: []
        ) else {
            return 0
        }

        var sum: Int64 = 0
        for case let childURL as URL in enumerator {
            var childStat = stat()
            if lstat(childURL.path, &childStat) == 0, (childStat.st_mode & S_IFMT) == S_IFREG {
                sum += Int64(childStat.st_size)
            }
        }
        return sum
    }

    /// Captures canonical file paths currently held open by the calling process via `/dev/fd` + `F_GETPATH`.
    private static func openProcessFilePaths() -> Set<String> {
        guard let fdEntries = try? FileManager.default.contentsOfDirectory(atPath: "/dev/fd") else {
            return []
        }
        var paths: Set<String> = []
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        for name in fdEntries {
            guard let fd = Int32(name) else { continue }
            if fcntl(fd, F_GETPATH, &buffer) != -1 {
                let rawPath = String(cString: buffer)
                if !rawPath.isEmpty {
                    paths.insert(URL(fileURLWithPath: rawPath).resolvingSymlinksInPath().path)
                }
            }
        }
        return paths
    }

    private static func isPathOpen(_ path: String, in openPaths: Set<String>) -> Bool {
        guard !openPaths.isEmpty else { return false }
        let canonical = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        let prefix = canonical.hasSuffix("/") ? canonical : canonical + "/"
        return openPaths.contains { $0 == canonical || $0.hasPrefix(prefix) }
    }

    public func close() {
        if let db = db {
            sqlite3_close_v2(db)
            self.db = nil
        }
    }
}
