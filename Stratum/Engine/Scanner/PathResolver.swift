import Foundation

final class PathResolver: @unchecked Sendable {
    private let db: ScanDatabase
    private let rootPathPrefix: String
    private let capacity: Int
    private var cache: [Int64: String] = [:]
    private var order: [Int64] = []

    init(db: ScanDatabase, rootPathPrefix: String? = nil, capacity: Int = 1000) {
        self.db = db
        if let rootPathPrefix {
            self.rootPathPrefix = rootPathPrefix
        } else {
            self.rootPathPrefix = (try? db.latestCompletedScan()?.rootPath) ?? "/"
        }
        self.capacity = capacity
    }

    func fullPath(of dirId: Int64) -> String {
        if let hit = cache[dirId] {
            if let idx = order.firstIndex(of: dirId) {
                order.remove(at: idx)
                order.append(dirId)
            }
            return hit
        }

        var parts: [String] = []
        var current: Int64? = dirId
        while let id = current {
            guard let row = try? db.dirNameAndParent(id: id) else { break }
            parts.insert(row.name, at: 0)
            current = row.parentId
        }

        let joined: String
        if parts.first == "/" {
            let rel = parts.dropFirst().joined(separator: "/")
            if rootPathPrefix == "/" {
                joined = "/" + rel
            } else {
                let base = rootPathPrefix.hasSuffix("/") ? String(rootPathPrefix.dropLast()) : rootPathPrefix
                joined = rel.isEmpty ? base : "\(base)/\(rel)"
            }
        } else {
            joined = "/" + parts.joined(separator: "/")
        }

        cache[dirId] = joined
        order.append(dirId)
        if order.count > capacity {
            let evict = order.removeFirst()
            cache.removeValue(forKey: evict)
        }
        return joined
    }

    func clear() {
        cache.removeAll(keepingCapacity: true)
        order.removeAll(keepingCapacity: true)
    }
}
