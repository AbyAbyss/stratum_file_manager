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
