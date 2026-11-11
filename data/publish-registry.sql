-- ArcZip 1.2.3 ManagedTemporaryArtifactRegistry schema
-- extracted from __cstring 0xc57120-0xc578f0 (db: Temporary/temporary-artifacts.sqlite)
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

-- publication states: prepared | backingUp | committed | rollingBack | recoveryUncertain
-- artifact purposes: shelfResultSaving | streamExtraction | fontInstallation |
--                   applicationInstallation | finderQuickCompression |
--                   ownershipUncertain | recoveryAvailable
-- guard: path identity = (device_id, inode, birth_seconds, birth_nanoseconds, size_bytes)
--        mismatch => do not delete; re-verify
