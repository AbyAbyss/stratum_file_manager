import Foundation
import GRDB

struct DirInsertRow: Sendable {
    let id: Int64
    let parentId: Int64?
    let name: String
    let depth: Int
    let isHidden: Bool
    let isPackage: Bool
    let mtime: Int64?
    let ownSize: Int64
    let fileCount: Int64
}

struct LargeFileInsertRow: Comparable, Sendable {
    let dirId: Int64
    let name: String
    let ext: String?
    let fileType: Int
    let size: Int64
    let mtime: Int64?

    static func < (lhs: LargeFileInsertRow, rhs: LargeFileInsertRow) -> Bool {
        if lhs.size != rhs.size { return lhs.size < rhs.size }
        if lhs.dirId != rhs.dirId { return lhs.dirId < rhs.dirId }
        return lhs.name < rhs.name
    }
}

struct ScanRowSummary: Sendable {
    let id: Int64
    let volumeUUID: String
    let volumeName: String
    let rootPath: String
    let startedAt: Date
    let completedAt: Date?
    let totalUsed: Int64?
    let totalFree: Int64?
    let dirCount: Int64?
    let fileCount: Int64?
    let skippedCount: Int64?
}

extension ScanDatabase {

    @discardableResult
    func insertScanStart(volumeUUID: String,
                         volumeName: String,
                         rootPath: String,
                         startedAt: Date) throws -> Int64 {
        try pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO scans (volume_uuid, volume_name, root_path, started_at)
                    VALUES (?, ?, ?, ?);
                    """,
                arguments: [volumeUUID, volumeName, rootPath, Int64(startedAt.timeIntervalSince1970)]
            )
            return db.lastInsertedRowID
        }
    }

    func completeScanRow(id: Int64,
                         completedAt: Date,
                         totalUsed: Int64,
                         totalFree: Int64,
                         dirCount: Int64,
                         fileCount: Int64,
                         skippedCount: Int64) throws {
        try pool.write { db in
            try db.execute(
                sql: """
                    UPDATE scans
                    SET completed_at  = ?,
                        total_used    = ?,
                        total_free    = ?,
                        dir_count     = ?,
                        file_count    = ?,
                        skipped_count = ?
                    WHERE id = ?;
                    """,
                arguments: [
                    Int64(completedAt.timeIntervalSince1970),
                    totalUsed,
                    totalFree,
                    dirCount,
                    fileCount,
                    skippedCount,
                    id
                ]
            )
        }
    }

    func latestCompletedScan() throws -> ScanRowSummary? {
        try pool.read { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT id, volume_uuid, volume_name, root_path,
                       started_at, completed_at, total_used, total_free,
                       dir_count, file_count, skipped_count
                FROM scans
                WHERE completed_at IS NOT NULL
                ORDER BY completed_at DESC
                LIMIT 1;
                """) else { return nil }

            let startedSec: Int64 = row["started_at"]
            let completedSec: Int64? = row["completed_at"]
            return ScanRowSummary(
                id: row["id"],
                volumeUUID: row["volume_uuid"],
                volumeName: row["volume_name"],
                rootPath: row["root_path"],
                startedAt: Date(timeIntervalSince1970: TimeInterval(startedSec)),
                completedAt: completedSec.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                totalUsed: row["total_used"],
                totalFree: row["total_free"],
                dirCount: row["dir_count"],
                fileCount: row["file_count"],
                skippedCount: row["skipped_count"]
            )
        }
    }

    func insertDirsBatch(_ rows: [DirInsertRow]) throws {
        guard !rows.isEmpty else { return }
        try pool.write { db in
            let stmt = try db.makeStatement(sql: """
                INSERT INTO dirs
                  (id, parent_id, name, depth, is_hidden, is_package, mtime, own_size, file_count)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
                """)
            for r in rows {
                try stmt.execute(arguments: [
                    r.id,
                    r.parentId,
                    r.name,
                    r.depth,
                    r.isHidden ? 1 : 0,
                    r.isPackage ? 1 : 0,
                    r.mtime,
                    r.ownSize,
                    r.fileCount
                ])
            }
        }
    }

    func writeFileTypeTotals(_ totals: [(type: FileTypeCategory, size: Int64, count: Int64)]) throws {
        try pool.write { db in
            try db.execute(sql: "DELETE FROM file_type_totals;")
            let stmt = try db.makeStatement(sql: """
                INSERT INTO file_type_totals (file_type, total_size, file_count)
                VALUES (?, ?, ?);
                """)
            for t in totals {
                try stmt.execute(arguments: [t.type.rawValue, t.size, t.count])
            }
        }
    }

    func writeLargeFiles(_ rows: [LargeFileInsertRow]) throws {
        try pool.write { db in
            try db.execute(sql: "DELETE FROM large_files;")
            let stmt = try db.makeStatement(sql: """
                INSERT INTO large_files (dir_id, name, ext, file_type, size, mtime)
                VALUES (?, ?, ?, ?, ?, ?);
                """)
            for r in rows {
                try stmt.execute(arguments: [
                    r.dirId, r.name, r.ext, r.fileType, r.size, r.mtime
                ])
            }
        }
    }

    func writeTopFolderSnapshots(scanId: Int64, rows: [(path: String, totalSize: Int64)]) throws {
        guard !rows.isEmpty else { return }
        try pool.write { db in
            let stmt = try db.makeStatement(sql: """
                INSERT OR REPLACE INTO snapshot_top_folders (scan_id, path, total_size)
                VALUES (?, ?, ?);
                """)
            for r in rows {
                try stmt.execute(arguments: [scanId, r.path, r.totalSize])
            }
        }
    }

    // MARK: - Read Queries

    func rootDirId() throws -> Int64? {
        try pool.read { db in
            try Int64.fetchOne(db, sql: "SELECT id FROM dirs WHERE parent_id IS NULL LIMIT 1;")
        }
    }

    func dirRow(id: Int64) throws -> DirRow? {
        try pool.read { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT id, parent_id, name, depth, is_hidden, is_package,
                       mtime, total_size, descendant_file_count
                FROM dirs WHERE id = ?;
                """, arguments: [id]) else { return nil }
            return Self.decodeDirRow(row)
        }
    }

    func children(of parentId: Int64, includeHidden: Bool = true) throws -> [DirRow] {
        try pool.read { db in
            let sql: String
            if includeHidden {
                sql = """
                    SELECT id, parent_id, name, depth, is_hidden, is_package,
                           mtime, total_size, descendant_file_count
                    FROM dirs
                    WHERE parent_id = ?
                    ORDER BY total_size DESC;
                    """
            } else {
                sql = """
                    SELECT id, parent_id, name, depth, is_hidden, is_package,
                           mtime, total_size, descendant_file_count
                    FROM dirs
                    WHERE parent_id = ? AND is_hidden = 0
                    ORDER BY total_size DESC;
                    """
            }
            let rows = try Row.fetchAll(db, sql: sql, arguments: [parentId])
            return rows.map(Self.decodeDirRow)
        }
    }

    func dirNameAndParent(id: Int64) throws -> (name: String, parentId: Int64?)? {
        try pool.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT name, parent_id FROM dirs WHERE id = ?;",
                arguments: [id]
            ) else { return nil }
            return (name: row["name"], parentId: row["parent_id"])
        }
    }

    /// Aggregates all top-level (non-nested) directories matching `GroupCatalog.entries`.
    /// Fixes wimys_crumb's 1-level parent check by walking the full ancestor chain via a recursive CTE
    /// starting only from the matched rows (`WHERE name = ?`), preventing `node_modules/pkg/node_modules`
    /// at any depth from double-counting `total_size`.
    func groupAggregates() throws -> [GroupRow] {
        try pool.read { db in
            var out: [GroupRow] = []
            for entry in GroupCatalog.entries {
                guard let row = try Row.fetchOne(db, sql: """
                    WITH RECURSIVE
                      matched AS (
                        SELECT id, parent_id, total_size, mtime
                        FROM dirs
                        WHERE name = ?
                      ),
                      ancestors(root_id, anc_id) AS (
                        SELECT m.id, m.parent_id
                        FROM matched m
                        WHERE m.parent_id IS NOT NULL
                        UNION ALL
                        SELECT a.root_id, d.parent_id
                        FROM ancestors a
                        JOIN dirs d ON d.id = a.anc_id
                        WHERE d.parent_id IS NOT NULL
                      ),
                      nested AS (
                        SELECT DISTINCT a.root_id
                        FROM ancestors a
                        JOIN matched m ON m.id = a.anc_id
                      )
                    SELECT COUNT(*)                       AS cnt,
                           COALESCE(SUM(m.total_size), 0) AS total,
                           AVG(CASE WHEN m.mtime IS NOT NULL
                                    THEN (strftime('%s','now') - m.mtime) / 86400.0
                                    ELSE NULL END)        AS avg_age
                    FROM matched m
                    WHERE m.id NOT IN (SELECT root_id FROM nested);
                    """, arguments: [entry.name]) else { continue }

                let count: Int = row["cnt"]
                guard count > 0 else { continue }
                let total: Int64 = row["total"]
                let avgAge: Double = row["avg_age"] ?? 0
                out.append(GroupRow(
                    name: entry.name,
                    tagline: entry.tagline,
                    count: count,
                    total: total,
                    avgAgeDays: max(0, avgAge),
                    devOnly: entry.devOnly
                ))
            }
            return out.sorted { $0.total > $1.total }
        }
    }

    /// All non-nested directory rows with a given name (e.g. "node_modules"), sorted largest first.
    func dirsWithName(_ name: String) throws -> [DirRow] {
        try pool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                WITH RECURSIVE
                  matched AS (
                    SELECT id, parent_id, name, depth, is_hidden, is_package,
                           mtime, total_size, descendant_file_count
                    FROM dirs
                    WHERE name = ?
                  ),
                  ancestors(root_id, anc_id) AS (
                    SELECT m.id, m.parent_id
                    FROM matched m
                    WHERE m.parent_id IS NOT NULL
                    UNION ALL
                    SELECT a.root_id, d.parent_id
                    FROM ancestors a
                    JOIN dirs d ON d.id = a.anc_id
                    WHERE d.parent_id IS NOT NULL
                  ),
                  nested AS (
                    SELECT DISTINCT a.root_id
                    FROM ancestors a
                    JOIN matched m ON m.id = a.anc_id
                  )
                SELECT id, parent_id, name, depth, is_hidden, is_package,
                       mtime, total_size, descendant_file_count
                FROM matched
                WHERE id NOT IN (SELECT root_id FROM nested)
                ORDER BY total_size DESC;
                """, arguments: [name])
            return rows.map(Self.decodeDirRow)
        }
    }

    func fileTypeTotals() throws -> [FileTypeTotal] {
        try pool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT file_type, total_size, file_count
                FROM file_type_totals
                ORDER BY total_size DESC;
                """)
            return rows.compactMap { row -> FileTypeTotal? in
                let raw: Int = row["file_type"]
                guard let cat = FileTypeCategory(rawValue: raw) else { return nil }
                return FileTypeTotal(
                    type: cat,
                    totalSize: row["total_size"],
                    fileCount: row["file_count"]
                )
            }
        }
    }

    func largeFiles(of type: FileTypeCategory? = nil, limit: Int = 500) throws -> [LargeFileRow] {
        try pool.read { db in
            let rows: [Row]
            if let type {
                rows = try Row.fetchAll(db, sql: """
                    SELECT id, dir_id, name, ext, file_type, size, mtime
                    FROM large_files
                    WHERE file_type = ?
                    ORDER BY size DESC
                    LIMIT ?;
                    """, arguments: [type.rawValue, limit])
            } else {
                rows = try Row.fetchAll(db, sql: """
                    SELECT id, dir_id, name, ext, file_type, size, mtime
                    FROM large_files
                    ORDER BY size DESC
                    LIMIT ?;
                    """, arguments: [limit])
            }
            return rows.map(Self.decodeLargeFileRow)
        }
    }

    /// Fast duplicate detection from the `large_files` table + same-size grouping.
    func duplicateLargeFiles(resolver: PathResolver) throws -> [DuplicateCluster] {
        let all = try largeFiles(limit: 2000)
        var byKey: [String: [LargeFileRow]] = [:]
        for f in all where f.size >= 1_000_000 {
            let key = "\(f.size):\(f.ext ?? "")"
            byKey[key, default: []].append(f)
        }
        var clusters: [DuplicateCluster] = []
        for (_, group) in byKey where group.count >= 2 {
            let paths = group.map { row -> String in
                let dirPath = resolver.fullPath(of: row.dirId)
                return dirPath == "/" ? "/\(row.name)" : "\(dirPath)/\(row.name)"
            }
            clusters.append(DuplicateCluster(
                fileName: group[0].name,
                fileSize: group[0].size,
                paths: paths
            ))
        }
        return clusters.sorted { $0.reclaimableBytes > $1.reclaimableBytes }
    }

    func patchAfterDelete(targets: [DeleteTarget], removedPaths: Set<String>) throws {
        let hit = targets.filter { removedPaths.contains($0.path) }
        guard !hit.isEmpty else { return }

        try pool.write { db in
            for t in hit {
                guard let dirId = t.dirId else { continue }
                if let fileName = t.fileName {
                    let row = try Row.fetchOne(db, sql: """
                        SELECT id, file_type, size FROM large_files
                        WHERE dir_id = ? AND name = ?
                        LIMIT 1;
                        """, arguments: [dirId, fileName])
                    let delta = (row?["size"] as Int64?) ?? t.size
                    let ftype: Int? = row?["file_type"]
                    if let rowId: Int64 = row?["id"] {
                        try db.execute(sql: "DELETE FROM large_files WHERE id = ?;", arguments: [rowId])
                    }
                    if let ftype {
                        try db.execute(sql: """
                            UPDATE file_type_totals
                            SET total_size = MAX(0, total_size - ?),
                                file_count = MAX(0, file_count - 1)
                            WHERE file_type = ?;
                            """, arguments: [delta, ftype])
                    }
                    try db.execute(sql: """
                        UPDATE dirs
                        SET own_size = MAX(0, own_size - ?),
                            file_count = MAX(0, file_count - 1)
                        WHERE id = ?;
                        """, arguments: [delta, dirId])
                    try Self.subtractFromAncestors(db: db, startId: dirId, delta: delta, fileCountDelta: 1)
                } else {
                    guard let row = try Row.fetchOne(db, sql: """
                        SELECT parent_id, total_size, descendant_file_count
                        FROM dirs WHERE id = ?;
                        """, arguments: [dirId]) else { continue }
                    let parentId: Int64? = row["parent_id"]
                    let delta: Int64 = row["total_size"]
                    let fcount: Int64 = row["descendant_file_count"]

                    let subtreeIds = try Self.collectSubtreeIds(db: db, rootId: dirId)
                    if !subtreeIds.isEmpty {
                        let placeholders = subtreeIds.map { _ in "?" }.joined(separator: ",")
                        try db.execute(
                            sql: "DELETE FROM large_files WHERE dir_id IN (\(placeholders));",
                            arguments: StatementArguments(subtreeIds)
                        )
                        try db.execute(
                            sql: "DELETE FROM dirs WHERE id IN (\(placeholders));",
                            arguments: StatementArguments(subtreeIds)
                        )
                    }
                    if let parentId {
                        try Self.subtractFromAncestors(db: db, startId: parentId, delta: delta, fileCountDelta: fcount)
                    }
                }
            }
        }
    }

    private static func collectSubtreeIds(db: Database, rootId: Int64) throws -> [Int64] {
        var result: [Int64] = []
        var frontier: [Int64] = [rootId]
        while !frontier.isEmpty {
            result.append(contentsOf: frontier)
            let placeholders = frontier.map { _ in "?" }.joined(separator: ",")
            frontier = try Int64.fetchAll(
                db,
                sql: "SELECT id FROM dirs WHERE parent_id IN (\(placeholders));",
                arguments: StatementArguments(frontier)
            )
        }
        return result
    }

    private static func subtractFromAncestors(db: Database, startId: Int64, delta: Int64, fileCountDelta: Int64) throws {
        var cur: Int64? = startId
        while let id = cur {
            try db.execute(sql: """
                UPDATE dirs
                SET total_size = MAX(0, total_size - ?),
                    descendant_file_count = MAX(0, descendant_file_count - ?)
                WHERE id = ?;
                """, arguments: [delta, fileCountDelta, id])
            cur = try Int64.fetchOne(db, sql: "SELECT parent_id FROM dirs WHERE id = ?;", arguments: [id])
        }
    }

    private static func decodeDirRow(_ row: Row) -> DirRow {
        let mtimeSec: Int64? = row["mtime"]
        let isHiddenInt: Int = row["is_hidden"]
        let isPackageInt: Int = row["is_package"]
        return DirRow(
            id: row["id"],
            parentId: row["parent_id"],
            name: row["name"],
            depth: row["depth"],
            isHidden: isHiddenInt != 0,
            isPackage: isPackageInt != 0,
            mtime: mtimeSec.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            totalSize: row["total_size"],
            descendantFileCount: row["descendant_file_count"]
        )
    }

    private static func decodeLargeFileRow(_ row: Row) -> LargeFileRow {
        let mtimeSec: Int64? = row["mtime"]
        let rawType: Int = row["file_type"]
        return LargeFileRow(
            id: row["id"],
            dirId: row["dir_id"],
            name: row["name"],
            size: row["size"],
            mtime: mtimeSec.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            ext: row["ext"],
            type: FileTypeCategory(rawValue: rawType) ?? .other
        )
    }
}
