-- ArcZip 1.2.3 EntryIndex schema (extracted from __cstring 0xc54e50-0xc558c0)
PRAGMA journal_mode=WAL;

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

-- write path
-- BEGIN IMMEDIATE TRANSACTION;
-- DELETE FROM entries; DELETE FROM directory_nodes;
-- INSERT OR REPLACE INTO entries(...) VALUES(...);
-- INSERT INTO directory_nodes(...) VALUES(...)
--   ON CONFLICT(canonical_path) DO UPDATE SET ... WHERE excluded.is_virtual = 0;
-- COMMIT;

-- queries
-- SELECT payload FROM entries WHERE path LIKE ? ESCAPE '\' ORDER BY path COLLATE NOCASE LIMIT ? OFFSET ?;
-- SELECT payload FROM directory_nodes WHERE parent_path = ? COLLATE BINARY
--   AND (? OR is_auxiliary = 0) AND (? OR is_disk_image_background = 0)
--   AND (? OR is_dmg_applications_shortcut = 0)
--   ORDER BY is_directory DESC, sort_name COLLATE NOCASE LIMIT ? OFFSET ?;
-- SELECT payload FROM entries WHERE path = ? COLLATE BINARY
--    OR (path >= ? COLLATE BINARY AND path < ? COLLATE BINARY) ORDER BY path COLLATE NOCASE;
