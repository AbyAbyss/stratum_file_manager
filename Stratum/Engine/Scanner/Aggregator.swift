import Foundation
import GRDB

enum Aggregator {
    static func finalize(
        db: ScanDatabase,
        scanId: Int64,
        volume: VolumeInfo,
        maxDepth: Int,
        dirCount: Int64,
        fileCount: Int64,
        skippedCount: Int64
    ) throws {
        try db.pool.write { conn in
            for d in stride(from: maxDepth, through: 0, by: -1) {
                try conn.execute(sql: """
                    UPDATE dirs SET
                      total_size = own_size + COALESCE(
                        (SELECT SUM(total_size) FROM dirs c WHERE c.parent_id = dirs.id), 0),
                      descendant_file_count = file_count + COALESCE(
                        (SELECT SUM(descendant_file_count) FROM dirs c WHERE c.parent_id = dirs.id), 0)
                    WHERE depth = ?;
                    """, arguments: [d])
            }
        }

        if let rootId = try db.rootDirId() {
            let tops = try db.children(of: rootId)
            let rows = tops.map { (path: $0.name, totalSize: $0.totalSize) }
            try db.writeTopFolderSnapshots(scanId: scanId, rows: rows)
        }

        try db.completeScanRow(
            id: scanId,
            completedAt: Date(),
            totalUsed: volume.used,
            totalFree: volume.availableCapacity,
            dirCount: dirCount,
            fileCount: fileCount,
            skippedCount: skippedCount
        )
    }
}
