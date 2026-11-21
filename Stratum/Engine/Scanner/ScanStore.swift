import Foundation

struct ScanStore: Sendable {
    let root: URL
    let legacyWimysRoot: URL

    init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        self.root = appSupport
            .appendingPathComponent("Stratum", isDirectory: true)
            .appendingPathComponent("scans", isDirectory: true)
        self.legacyWimysRoot = appSupport
            .appendingPathComponent("wimys_crumb", isDirectory: true)
            .appendingPathComponent("scans", isDirectory: true)

        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    init(root: URL, legacyWimysRoot: URL) {
        self.root = root
        self.legacyWimysRoot = legacyWimysRoot
    }

    func inProgressURL(startedAt: Date) -> URL {
        root.appendingPathComponent("in-progress-\(Int(startedAt.timeIntervalSince1970)).sqlite")
    }

    func completedURL(volumeUUID: String, startedAt: Date) -> URL {
        root.appendingPathComponent("\(volumeUUID)-\(Int(startedAt.timeIntervalSince1970)).sqlite")
    }

    /// Lists completed scan DBs in Stratum's store plus any existing wimys_crumb scans, newest first.
    func listCompleted() -> [URL] {
        let fm = FileManager.default
        var all: [URL] = []

        for dir in [root, legacyWimysRoot] {
            if let entries = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) {
                let valid = entries.filter {
                    $0.pathExtension == "sqlite" && !$0.lastPathComponent.hasPrefix("in-progress-")
                }
                all.append(contentsOf: valid)
            }
        }

        return all.sorted { lhs, rhs in
            let a = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let b = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return a > b
        }
    }

    /// Every scan writes a full snapshot, so without this the store grows by one per refresh.
    /// Keeps the newest `keepPerVolume` snapshots of each volume and drops stray `-shm`/`-wal` files.
    func pruneOldSnapshots(keepPerVolume: Int = 2) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }

        // File names are "<volume>-<start timestamp>.sqlite".
        var byVolume: [String: [(started: Int, url: URL)]] = [:]
        for url in entries where url.pathExtension == "sqlite" && !url.lastPathComponent.hasPrefix("in-progress-") {
            let stem = url.deletingPathExtension().lastPathComponent
            guard let dash = stem.lastIndex(of: "-"), let started = Int(stem[stem.index(after: dash)...]) else { continue }
            byVolume[String(stem[..<dash]), default: []].append((started, url))
        }
        for snapshots in byVolume.values {
            for old in snapshots.sorted(by: { $0.started > $1.started }).dropFirst(keepPerVolume) {
                try? fm.removeItem(at: old.url)
            }
        }
        for url in entries where ["sqlite-shm", "sqlite-wal"].contains(url.pathExtension) {
            let database = url.deletingPathExtension().appendingPathExtension("sqlite")
            if !fm.fileExists(atPath: database.path) { try? fm.removeItem(at: url) }
        }
    }

    func pruneOrphans() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for url in entries where url.lastPathComponent.hasPrefix("in-progress-") {
            try? fm.removeItem(at: url)
            try? fm.removeItem(at: url.appendingPathExtension("shm"))
            try? fm.removeItem(at: url.appendingPathExtension("wal"))
        }
    }
}
