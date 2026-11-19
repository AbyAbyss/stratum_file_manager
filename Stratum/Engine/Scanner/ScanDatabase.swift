import Foundation
import GRDB

final class ScanDatabase: Sendable {
    let url: URL
    let pool: DatabasePool

    init(url: URL) throws {
        self.url = url

        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: """
                PRAGMA synchronous = NORMAL;
                PRAGMA temp_store  = MEMORY;
                PRAGMA cache_size  = -65536;
                PRAGMA mmap_size   = 268435456;
                PRAGMA foreign_keys = ON;
                """)
        }

        self.pool = try DatabasePool(path: url.path, configuration: config)
        try Self.migrate(pool: pool)
    }

    private static func migrate(pool: DatabasePool) throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial_schema") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS scans (
                    id              INTEGER PRIMARY KEY,
                    volume_uuid     TEXT    NOT NULL,
                    volume_name     TEXT    NOT NULL,
                    root_path       TEXT    NOT NULL,
                    started_at      INTEGER NOT NULL,
                    completed_at    INTEGER,
                    total_used      INTEGER,
                    total_free      INTEGER,
                    dir_count       INTEGER,
                    file_count      INTEGER,
                    skipped_count   INTEGER
                );

                CREATE TABLE IF NOT EXISTS dirs (
                    id                      INTEGER PRIMARY KEY,
                    parent_id               INTEGER REFERENCES dirs(id),
                    name                    TEXT    NOT NULL,
                    depth                   INTEGER NOT NULL,
                    is_hidden               INTEGER NOT NULL DEFAULT 0,
                    is_package              INTEGER NOT NULL DEFAULT 0,
                    mtime                   INTEGER,
                    own_size                INTEGER NOT NULL DEFAULT 0,
                    total_size              INTEGER NOT NULL DEFAULT 0,
                    file_count              INTEGER NOT NULL DEFAULT 0,
                    descendant_file_count   INTEGER NOT NULL DEFAULT 0
                );

                CREATE INDEX IF NOT EXISTS idx_dirs_parent ON dirs(parent_id);
                CREATE INDEX IF NOT EXISTS idx_dirs_name   ON dirs(name);
                CREATE INDEX IF NOT EXISTS idx_dirs_size   ON dirs(total_size DESC);
                CREATE INDEX IF NOT EXISTS idx_dirs_depth  ON dirs(depth DESC);

                CREATE TABLE IF NOT EXISTS large_files (
                    id          INTEGER PRIMARY KEY,
                    dir_id      INTEGER NOT NULL REFERENCES dirs(id),
                    name        TEXT    NOT NULL,
                    ext         TEXT,
                    file_type   INTEGER NOT NULL,
                    size        INTEGER NOT NULL,
                    mtime       INTEGER
                );

                CREATE INDEX IF NOT EXISTS idx_large_files_type_size ON large_files(file_type, size DESC);
                CREATE INDEX IF NOT EXISTS idx_large_files_dir       ON large_files(dir_id);

                CREATE TABLE IF NOT EXISTS file_type_totals (
                    file_type   INTEGER PRIMARY KEY,
                    total_size  INTEGER NOT NULL,
                    file_count  INTEGER NOT NULL
                );

                CREATE TABLE IF NOT EXISTS snapshot_top_folders (
                    scan_id     INTEGER NOT NULL REFERENCES scans(id),
                    path        TEXT    NOT NULL,
                    total_size  INTEGER NOT NULL,
                    PRIMARY KEY (scan_id, path)
                );
                """)
        }

        try migrator.migrate(pool)
    }
}
