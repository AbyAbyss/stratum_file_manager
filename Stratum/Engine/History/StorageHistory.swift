import Foundation

/// One day's storage totals for a scanned folder. Only sizes are kept (no file lists), so a
/// sample is a few kilobytes and a year of history stays around a megabyte or two.
struct StorageSample: Codable, Equatable, Sendable, Identifiable {
    /// Local calendar day, "yyyy-MM-dd". One sample is kept per day and scanned folder.
    var day: String
    var date: Date
    var rootPath: String
    /// Whole-disk figures at scan time.
    var diskUsed: Int64
    var diskFree: Int64
    /// Size of the scanned folder itself.
    var scannedBytes: Int64
    /// Folder sizes by path relative to the scanned folder ("Library", "Library/Caches").
    var folders: [String: Int64]
    /// File-type totals by `FileTypeCategory.rawValue`.
    var types: [Int: Int64]

    var id: String { "\(rootPath)|\(day)" }

    /// Folders smaller than this are left out to keep samples small.
    static let topLevelFloor: Int64 = 10 * 1_048_576
    static let secondLevelFloor: Int64 = 250 * 1_048_576

    static func dayString(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Reads the totals out of a finished scan: the top two folder levels and the file types.
    static func make(from db: ScanDatabase, summary: ScanRowSummary) throws -> StorageSample? {
        guard let rootId = try db.rootDirId() else { return nil }
        let top = try db.children(of: rootId)
        var folders: [String: Int64] = [:]
        for dir in top where dir.totalSize >= topLevelFloor {
            folders[dir.name] = dir.totalSize
            guard !dir.isPackage, dir.totalSize >= secondLevelFloor else { continue }
            for child in try db.children(of: dir.id) where child.totalSize >= secondLevelFloor {
                folders["\(dir.name)/\(child.name)"] = child.totalSize
            }
        }
        var types: [Int: Int64] = [:]
        for total in try db.fileTypeTotals() { types[total.type.rawValue] = total.totalSize }

        let date = summary.completedAt ?? summary.startedAt
        return StorageSample(
            day: dayString(for: date),
            date: date,
            rootPath: summary.rootPath,
            diskUsed: summary.totalUsed ?? 0,
            diskFree: summary.totalFree ?? 0,
            scannedBytes: try db.dirRow(id: rootId)?.totalSize ?? top.reduce(0) { $0 + $1.totalSize },
            folders: folders,
            types: types
        )
    }
}

/// The saved samples, shared by every window.
@Observable
@MainActor
final class StorageHistory {
    static let shared = StorageHistory()

    private(set) var samples: [StorageSample] = []
    private let fileURL: URL
    /// About two years of daily samples per scanned folder.
    static let maxSamplesPerRoot = 730

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Stratum", isDirectory: true)
            .appendingPathComponent("storage-history.json")
        if let data = try? Data(contentsOf: self.fileURL),
           let saved = try? JSONDecoder().decode([StorageSample].self, from: data) {
            samples = saved
        }
    }

    func samples(forRoot rootPath: String) -> [StorageSample] {
        samples.filter { $0.rootPath == rootPath }
    }

    /// Adds a sample, replacing an older one from the same day and folder.
    func record(_ sample: StorageSample) {
        if let index = samples.firstIndex(where: { $0.id == sample.id }) {
            guard samples[index].date <= sample.date, samples[index] != sample else { return }
            samples[index] = sample
        } else {
            samples.append(sample)
            samples.sort { $0.date < $1.date }
            let overflow = samples(forRoot: sample.rootPath).count - Self.maxSamplesPerRoot
            if overflow > 0 {
                let dropped = Set(samples(forRoot: sample.rootPath).prefix(overflow).map(\.id))
                samples.removeAll { dropped.contains($0.id) }
            }
        }
        save()
    }

    /// Reads a finished scan in the background and records its totals.
    func record(from db: ScanDatabase) {
        Task.detached(priority: .utility) {
            guard let summary = try? db.latestCompletedScan(),
                  let sample = try? StorageSample.make(from: db, summary: summary) else { return }
            await StorageHistory.shared.record(sample)
        }
    }

    func clear() {
        samples = []
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func save() {
        let snapshot = samples
        let url = fileURL
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }
}

/// How one folder or file type changed between two samples.
struct StorageChange: Identifiable, Equatable {
    var id: String
    var name: String
    var size: Int64
    var delta: Int64
}

extension StorageSample {
    /// Folder changes since `earlier`, biggest change first. `parent` nil lists the top level;
    /// otherwise the folders directly inside `parent`. A folder missing from one side was
    /// below the recording floor there and counts as zero.
    func folderChanges(since earlier: StorageSample?, parent: String? = nil) -> [StorageChange] {
        func level(_ folders: [String: Int64]) -> [String: Int64] {
            folders.filter { path, _ in
                if let parent { return path.hasPrefix(parent + "/") }
                return !path.contains("/")
            }
        }
        let now = level(folders)
        let before = earlier.map { level($0.folders) } ?? [:]
        return Self.changes(now: now, before: before, hasBaseline: earlier != nil) { path in
            parent.map { String(path.dropFirst($0.count + 1)) } ?? path
        }
    }

    func typeChanges(since earlier: StorageSample?) -> [(type: FileTypeCategory, size: Int64, delta: Int64)] {
        FileTypeCategory.allCases.compactMap { type in
            let size = types[type.rawValue] ?? 0
            let before = earlier?.types[type.rawValue] ?? 0
            guard size > 0 || before > 0 else { return nil }
            return (type, size, earlier == nil ? 0 : size - before)
        }
        .sorted { earlier == nil ? $0.size > $1.size : abs($0.delta) > abs($1.delta) }
    }

    private static func changes(
        now: [String: Int64], before: [String: Int64], hasBaseline: Bool, name: (String) -> String
    ) -> [StorageChange] {
        Set(now.keys).union(before.keys).map { path in
            let size = now[path] ?? 0
            return StorageChange(id: path, name: name(path), size: size, delta: hasBaseline ? size - (before[path] ?? 0) : 0)
        }
        .sorted { hasBaseline && $0.delta != $1.delta ? abs($0.delta) > abs($1.delta) : $0.size > $1.size }
    }
}
