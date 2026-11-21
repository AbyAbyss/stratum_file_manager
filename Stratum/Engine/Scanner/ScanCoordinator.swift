import Foundation
import SwiftUI
import AppKit
import CoreServices

@Observable
@MainActor
final class ScanCoordinator {
    static let shared = ScanCoordinator()

    var isScanning: Bool = false
    var isBackgroundRefreshing: Bool = false
    /// True from the moment a foreground scan starts until its fresh results are loaded.
    /// Everything the screens show before that belongs to the previous scan, so they must
    /// show a scanning state instead of results while this is true.
    /// Written only by ScanCoordinator and its extensions.
    var isResultsStale: Bool = false
    var showsScanState: Bool { isScanning || isResultsStale }
    var autoRefreshEnabled: Bool = UserDefaults.standard.object(forKey: "stratum.autoRefreshEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(autoRefreshEnabled, forKey: "stratum.autoRefreshEnabled")
            if autoRefreshEnabled {
                setupFSWatcher(for: scannedRootPath)
            } else {
                stopFSWatcher()
            }
        }
    }

    // Safety & Scan Preferences (persisted)
    var protectActiveProjects: Bool = UserDefaults.standard.object(forKey: "stratum.protectActiveProjects") as? Bool ?? true {
        didSet { UserDefaults.standard.set(protectActiveProjects, forKey: "stratum.protectActiveProjects") }
    }
    var confirmLargeDeletes: Bool = UserDefaults.standard.object(forKey: "stratum.confirmLargeDeletes") as? Bool ?? true {
        didSet { UserDefaults.standard.set(confirmLargeDeletes, forKey: "stratum.confirmLargeDeletes") }
    }
    var allowDeletingHidden: Bool = UserDefaults.standard.object(forKey: "stratum.allowDeletingHidden") as? Bool ?? false {
        didSet {
            UserDefaults.standard.set(allowDeletingHidden, forKey: "stratum.allowDeletingHidden")
            refreshAllQueries(animated: true)
        }
    }
    var onlyOnPower: Bool = UserDefaults.standard.object(forKey: "stratum.onlyOnPower") as? Bool ?? true {
        didSet { UserDefaults.standard.set(onlyOnPower, forKey: "stratum.onlyOnPower") }
    }

    var progress: ScanProgress = ScanProgress(fraction: 0, filesScanned: 0, currentPath: "", etaSeconds: nil)
    var lastScanDate: Date? = nil
    var scannedRootPath: String = "/"
    var backgroundRefreshCount: Int = 0
    var scannedFileCount: Int64 = 0
    var scannedDirCount: Int64 = 0
    var snapshotCount: Int = 0
    var snapshotTotalBytes: Int64 = 0

    var groups: [GroupRow] = []
    var selectedGroupName: String = "node_modules" {
        didSet { reloadSelectedGroupInstances() }
    }
    var groupInstances: [GroupInstanceRow] = []
    var groupInstancesByName: [String: [GroupInstanceRow]] = [:]

    // Storage Map data
    var currentTreemapDirId: Int64? = nil
    var treemapBreadcrumb: [DirRow] = []
    var treemapChildren: [DirRow] = []
    var treemapCustomPaths: [Int64: String] = [:]
    var fileTypeTotals: [FileTypeTotal] = []
    var largeFiles: [LargeFileRow] = []
    var duplicateClusters: [DuplicateCluster] = []

    var activeDB: ScanDatabase?
    var pathResolver: PathResolver?
    let store = ScanStore()
    var scanTask: Task<Void, Never>?

    // Smart Background Auto-Refresh state
    var fsEventStream: FSEventStreamRef?
    var watchedPath: String = ""
    var debounceWorkItem: DispatchWorkItem?
    var periodicTimer: Timer?
    var lastCompletedScanTime: Date = .distantPast
    var lastObservedAvailableBytes: Int64 = 0
    var pendingSmartRefresh: Bool = false

    init() {
        store.pruneOrphans()
        refreshSnapshotStats()
        loadLatestOrStartDefaultScan()
        startSmartPeriodicMonitor()
    }

    func instances(forGroup groupName: String) -> [GroupInstanceRow] {
        if let cached = groupInstancesByName[groupName], !cached.isEmpty {
            return cached
        }
        if groupName == selectedGroupName {
            return groupInstances
        }
        return []
    }

    /// Fast in-memory calculation of reclaimable bytes (Quick Wins + Duplicates) located under `folderPath`.
    func reclaimableBytes(underPath folderPath: String) -> Int64 {
        let norm = folderPath == "/" ? "/" : (folderPath.hasSuffix("/") ? String(folderPath.dropLast()) : folderPath)
        var total: Int64 = 0
        for (_, instances) in groupInstancesByName {
            for inst in instances {
                if norm == "/" || inst.fullPath == norm || inst.fullPath.hasPrefix(norm + "/") {
                    total += inst.dirRow.totalSize
                }
            }
        }
        for cluster in duplicateClusters {
            for dupPath in cluster.paths.dropFirst() {
                if norm == "/" || dupPath == norm || dupPath.hasPrefix(norm + "/") {
                    total += cluster.fileSize
                }
            }
        }
        return total
    }

    var totalQuickWinsBytes: Int64 {
        let groupSum = groups.reduce(Int64(0)) { $0 + $1.total }
        let dupSum = duplicateClusters.reduce(Int64(0)) { $0 + $1.reclaimableBytes }
        return groupSum + dupSum
    }

    func refreshSnapshotStats() {
        let storeRef = self.store
        DispatchQueue.global(qos: .utility).async { [weak self] in
            storeRef.pruneOldSnapshots()
            let urls = storeRef.listCompleted()
            var bytes: Int64 = 0
            for url in urls {
                if let sz = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                    bytes += Int64(sz)
                }
            }
            Task { @MainActor in
                self?.snapshotCount = urls.count
                self?.snapshotTotalBytes = bytes
            }
        }
    }

    func clearAllScanData(appState: AppState? = nil) {
        let storeRef = self.store
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let urls = storeRef.listCompleted()
            let fm = FileManager.default
            for url in urls {
                try? fm.removeItem(at: url)
                try? fm.removeItem(at: url.appendingPathExtension("shm"))
                try? fm.removeItem(at: url.appendingPathExtension("wal"))
            }
            storeRef.pruneOrphans()
            Task { @MainActor in
                guard let self else { return }
                self.refreshSnapshotStats()
                appState?.showToast("Cleared \(urls.count) scan snapshots — rescanning…")
                let targetURL = URL(fileURLWithPath: self.scannedRootPath)
                self.startScan(at: FileManager.default.fileExists(atPath: targetURL.path) ? targetURL : FileManager.default.homeDirectoryForCurrentUser)
            }
        }
    }

    func exportScanSummary(appState: AppState? = nil) {
        let panel = NSSavePanel()
        panel.title = "Export Stratum Storage Summary"
        panel.nameFieldStringValue = "stratum-storage-report-\(Int(Date().timeIntervalSince1970)).json"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destURL = panel.url else { return }

        let report: [String: Any] = [
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "scannedRootPath": scannedRootPath,
            "scannedFiles": scannedFileCount,
            "scannedDirectories": scannedDirCount,
            "totalQuickWinsReclaimableBytes": totalQuickWinsBytes,
            "fileTypes": fileTypeTotals.map { [
                "category": $0.type.displayName,
                "totalBytes": $0.totalSize,
                "formattedSize": BulkDirectoryReader.fastFormatBytes($0.totalSize),
                "fileCount": $0.fileCount
            ] },
            "cleanupGroups": groups.map { [
                "name": $0.name,
                "folderCount": $0.count,
                "totalBytes": $0.total,
                "formattedSize": BulkDirectoryReader.fastFormatBytes($0.total)
            ] },
            "topSubfolders": treemapChildren.prefix(25).map { [
                "name": $0.name,
                "path": fullPath(for: $0.id),
                "totalBytes": $0.totalSize,
                "formattedSize": BulkDirectoryReader.fastFormatBytes($0.totalSize)
            ] }
        ]

        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: destURL, options: .atomic)
            appState?.showToast("Exported storage report to \(destURL.lastPathComponent)")
        }
    }

    func loadLatestOrStartDefaultScan() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let completed = self.store.listCompleted()
            if let newest = completed.first, let db = try? ScanDatabase(url: newest) {
                let summary = try? db.latestCompletedScan()
                let resolver = PathResolver(db: db, rootPathPrefix: summary?.rootPath)
                Task { @MainActor in
                    self.activeDB = db
                    self.pathResolver = resolver
                    // Fall back to the snapshot file's age so the UI can always say how old the data is.
                    let fileDate = try? newest.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                    self.lastScanDate = summary?.completedAt ?? summary?.startedAt ?? fileDate
                    self.lastCompletedScanTime = self.lastScanDate ?? .distantPast
                    self.scannedRootPath = summary?.rootPath ?? "/"
                    self.scannedFileCount = summary?.fileCount ?? 0
                    self.scannedDirCount = summary?.dirCount ?? 0
                    self.refreshAllQueries()
                    self.refreshSnapshotStats()
                    self.setupFSWatcher(for: self.scannedRootPath)
                    if let last = self.lastScanDate, Date().timeIntervalSince(last) > 180 {
                        self.scheduleSmartBackgroundRefresh(delay: 2.0, force: true)
                    }
                }
            } else {
                Task { @MainActor in
                    let home = FileManager.default.homeDirectoryForCurrentUser
                    self.startScan(at: home.appendingPathComponent("Desktop"), name: "Desktop")
                }
            }
        }
    }

    /// Background refreshes are being skipped because the Mac is on battery
    /// ("Only while on power" in Settings > Scanning).
    var isAutoRefreshPausedOnBattery: Bool {
        autoRefreshEnabled && onlyOnPower && PowerSource.isOnBattery
    }

    /// Foreground scan (user explicitly clicked Scan or switched scope) or silent background refresh (`silent: true`).
    func startScan(at url: URL, name: String? = nil, silent: Bool = false) {
        if silent {
            guard autoRefreshEnabled, !isScanning, !isBackgroundRefreshing else { return }
            if isAutoRefreshPausedOnBattery {
                // Catch up once power is back: the periodic monitor retries while this is set.
                pendingSmartRefresh = true
                return
            }
            isBackgroundRefreshing = true
        } else {
            scanTask?.cancel()
            isScanning = true
            isResultsStale = true
            isBackgroundRefreshing = false
        }

        let vals = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
            .volumeUUIDStringKey,
            .volumeNameKey
        ])
        let total = Int64(vals?.volumeTotalCapacity ?? 500_000_000_000)
        let avail = max(vals?.volumeAvailableCapacityForImportantUsage ?? 0, Int64(vals?.volumeAvailableCapacity ?? 100_000_000_000))
        self.lastObservedAvailableBytes = avail
        let volUUID = vals?.volumeUUIDString ?? "stratum-vol"
        let volName = name ?? vals?.volumeName ?? url.lastPathComponent

        let vol = VolumeInfo(
            id: volUUID,
            name: volName,
            totalCapacity: total,
            availableCapacity: avail,
            url: url
        )

        let scanStore = self.store
        let taskPriority: TaskPriority = silent ? .utility : .userInitiated

        scanTask = Task(priority: taskPriority) { [weak self] in
            do {
                let outcome = try await ScanEngine.scan(volume: vol, store: scanStore) { prog in
                    guard !silent else { return }
                    Task { @MainActor in
                        self?.progress = prog
                    }
                }
                guard let self, !Task.isCancelled else { return }
                if let db = try? ScanDatabase(url: outcome.dbURL) {
                    let summary = try? db.latestCompletedScan()
                    let rootPath = summary?.rootPath ?? url.path
                    let newResolver = PathResolver(db: db, rootPathPrefix: rootPath)

                    self.activeDB = db
                    self.pathResolver = newResolver
                    self.lastScanDate = Date()
                    self.lastCompletedScanTime = Date()
                    self.scannedFileCount = summary?.fileCount ?? 0
                    self.scannedDirCount = summary?.dirCount ?? 0
                    if self.scannedRootPath != url.path {
                        self.scannedRootPath = url.path
                        self.currentTreemapDirId = nil
                        self.treemapCustomPaths.removeAll()
                        self.setupFSWatcher(for: url.path)
                    } else if self.watchedPath != url.path {
                        self.setupFSWatcher(for: url.path)
                    }
                    if silent {
                        self.backgroundRefreshCount += 1
                    }
                    self.refreshAllQueries(animated: true)
                    self.refreshSnapshotStats()
                } else if !silent {
                    self.isResultsStale = false
                }
                self.isScanning = false
                self.isBackgroundRefreshing = false
            } catch {
                // A cancelled scan was replaced by a newer one that owns these flags now.
                guard !Task.isCancelled else { return }
                self?.isScanning = false
                self?.isBackgroundRefreshing = false
                self?.isResultsStale = false
            }
        }
    }

}
