import Foundation

struct DeleteTargetItem: Identifiable, Hashable, Sendable {
    var id: String { path }
    let path: String
    let name: String
    let size: Int64
    let dirId: Int64?
    var isProtected: Bool {
        ProtectedPaths.isProtected(path)
    }

    init(path: String, name: String? = nil, size: Int64 = 0, dirId: Int64? = nil) {
        self.path = path
        self.name = name ?? (path as NSString).lastPathComponent
        self.size = size
        self.dirId = dirId
    }

    init(path: String, sizeBytes: Int64) {
        self.init(path: path, name: nil, size: sizeBytes, dirId: nil)
    }
}

enum DeleteService {
    struct Outcome: Sendable {
        let removed: [DeleteTargetItem]
        let freedBytes: Int64
        let skipped: [DeleteTargetItem]
        /// Original URL -> URL inside macOS Trash (for Undo restoration)
        let trashURLs: [URL: URL]
        let timestamp: Date
        let sourceFolderName: String

        var removedPaths: Set<String> {
            Set(removed.map(\.path))
        }

        var failed: [(path: String, reason: String)] {
            skipped.map { ($0.path, $0.isProtected ? "Protected system path" : "Could not move to Trash") }
        }
    }

    /// Moves items to the macOS Trash after verifying `ProtectedPaths.isProtected`.
    /// Never performs a permanent delete unless explicitly added later.
    static func moveToTrash(
        _ targets: [DeleteTargetItem],
        additionalProtectedPaths: [String] = []
    ) -> Outcome {
        var removed: [DeleteTargetItem] = []
        var skipped: [DeleteTargetItem] = []
        var trashURLs: [URL: URL] = [:]
        var freed: Int64 = 0
        let firstParent = targets.first.map { (($0.path as NSString).deletingLastPathComponent as NSString).lastPathComponent } ?? "Folder"

        for target in targets {
            if ProtectedPaths.isProtected(target.path, additional: additionalProtectedPaths) {
                skipped.append(target)
                continue
            }
            let url = URL(fileURLWithPath: target.path)
            var resultingURL: NSURL? = nil
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
                removed.append(target)
                freed += target.size
                if let ns = resultingURL {
                    trashURLs[url] = ns as URL
                }
            } catch {
                skipped.append(target)
            }
        }

        return Outcome(
            removed: removed,
            freedBytes: freed,
            skipped: skipped,
            trashURLs: trashURLs,
            timestamp: Date(),
            sourceFolderName: firstParent
        )
    }

    /// Restores items from the Trash back to their original paths.
    @discardableResult
    static func restoreFromTrash(_ trashURLs: [URL: URL]) -> Int {
        var restoredCount = 0
        for (originalURL, trashedURL) in trashURLs {
            do {
                try FileManager.default.moveItem(at: trashedURL, to: originalURL)
                restoredCount += 1
            } catch {
                continue
            }
        }
        return restoredCount
    }
}
