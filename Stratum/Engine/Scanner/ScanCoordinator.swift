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
    private(set) var isResultsStale: Bool = false
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

    private var activeDB: ScanDatabase?
    private var pathResolver: PathResolver?
    private let store = ScanStore()
    private var scanTask: Task<Void, Never>?

    // Smart Background Auto-Refresh state
    private var fsEventStream: FSEventStreamRef?
    private var watchedPath: String = ""
    private var debounceWorkItem: DispatchWorkItem?
    private var periodicTimer: Timer?
    private var lastCompletedScanTime: Date = .distantPast
    private var lastObservedAvailableBytes: Int64 = 0
    private var pendingSmartRefresh: Bool = false

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

    /// Foreground scan (user explicitly clicked Scan or switched scope) or silent background refresh (`silent: true`).
    func startScan(at url: URL, name: String? = nil, silent: Bool = false) {
        if silent {
            guard autoRefreshEnabled, !isScanning, !isBackgroundRefreshing else { return }
            if onlyOnPower && PowerSource.isOnBattery { return }
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

    // MARK: - Smart Zero-Lag Background Refresh Engine

    func notifyFileSystemMutation(near url: URL? = nil) {
        guard autoRefreshEnabled else { return }
        if let url {
            let stdMutated = url.standardizedFileURL.path
            let stdRoot = URL(fileURLWithPath: scannedRootPath).standardizedFileURL.path
            if stdRoot == "/" || stdMutated.hasPrefix(stdRoot) || stdRoot.hasPrefix(stdMutated) {
                scheduleSmartBackgroundRefresh(delay: 1.8, force: true)
                return
            }
        }
        scheduleSmartBackgroundRefresh(delay: 2.5, force: false)
    }

    func scheduleSmartBackgroundRefresh(delay: TimeInterval = 3.5, force: Bool = false) {
        guard autoRefreshEnabled else { return }
        debounceWorkItem?.cancel()

        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.autoRefreshEnabled else { return }
                guard !self.isScanning, !self.isBackgroundRefreshing else {
                    self.pendingSmartRefresh = true
                    return
                }
                let elapsed = Date().timeIntervalSince(self.lastCompletedScanTime)
                if !force && elapsed < 15.0 {
                    return
                }
                let rootURL = URL(fileURLWithPath: self.scannedRootPath)
                guard FileManager.default.fileExists(atPath: rootURL.path) else { return }
                self.startScan(at: rootURL, silent: true)
            }
        }
        debounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func startSmartPeriodicMonitor() {
        periodicTimer?.invalidate()
        periodicTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.autoRefreshEnabled, !self.isScanning, !self.isBackgroundRefreshing else { return }
                let rootURL = URL(fileURLWithPath: self.scannedRootPath)
                let vals = try? rootURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
                let avail = max(vals?.volumeAvailableCapacityForImportantUsage ?? 0, Int64(vals?.volumeAvailableCapacity ?? 0))

                let byteDelta = abs(avail - self.lastObservedAvailableBytes)
                let age = Date().timeIntervalSince(self.lastCompletedScanTime)

                if self.pendingSmartRefresh || (self.lastObservedAvailableBytes > 0 && byteDelta > 24 * 1024 * 1024 && age > 20) {
                    self.pendingSmartRefresh = false
                    self.lastObservedAvailableBytes = avail
                    self.startScan(at: rootURL, silent: true)
                }
            }
        }
    }

    private func setupFSWatcher(for path: String) {
        guard autoRefreshEnabled, !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return }
        if watchedPath == path, fsEventStream != nil { return }
        stopFSWatcher()
        watchedPath = path

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { (_, clientCallBackInfo, numEvents, _, eventFlags, _) in
            guard let info = clientCallBackInfo else { return }
            let coordinator = Unmanaged<ScanCoordinator>.fromOpaque(info).takeUnretainedValue()
            var hasMeaningfulChange = false
            let mask: FSEventStreamEventFlags = UInt32(
                kFSEventStreamEventFlagItemCreated |
                kFSEventStreamEventFlagItemRemoved |
                kFSEventStreamEventFlagItemRenamed |
                kFSEventStreamEventFlagItemModified |
                kFSEventStreamEventFlagRootChanged
            )
            for i in 0..<numEvents {
                if (eventFlags[i] & mask) != 0 {
                    hasMeaningfulChange = true
                    break
                }
            }
            if hasMeaningfulChange {
                Task { @MainActor in
                    coordinator.scheduleSmartBackgroundRefresh(delay: 4.0, force: false)
                }
            }
        }

        let pathsToWatch = [path] as CFArray
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagNoDefer |
            kFSEventStreamCreateFlagWatchRoot
        )

        if let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            3.0,
            flags
        ) {
            fsEventStream = stream
            FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
            FSEventStreamStart(stream)
        }
    }

    private func stopFSWatcher() {
        if let stream = fsEventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            fsEventStream = nil
        }
        watchedPath = ""
    }

    // MARK: - Queries & Animated State Updates

    func refreshAllQueries(animated: Bool = true) {
        guard let db = activeDB, let resolver = pathResolver else {
            isResultsStale = false
            return
        }
        let includeHidden = allowDeletingHidden
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let loadedGroups = (try? db.groupAggregates()) ?? []
            var allInstancesMap: [String: [GroupInstanceRow]] = [:]
            for grp in loadedGroups {
                let rows = (try? db.dirsWithName(grp.name)) ?? []
                allInstancesMap[grp.name] = rows.map { r in
                    let full = resolver.fullPath(of: r.id)
                    let parentURL = URL(fileURLWithPath: full).deletingLastPathComponent()
                    let proj = parentURL.lastPathComponent.isEmpty ? full : parentURL.lastPathComponent
                    return GroupInstanceRow(dirRow: r, fullPath: full, parentProjectName: proj)
                }
            }

            let types = (try? db.fileTypeTotals()) ?? []
            let large = (try? db.largeFiles(limit: 200)) ?? []
            let dupes = (try? db.duplicateLargeFiles(resolver: resolver)) ?? []
            let rootId = try? db.rootDirId()
            let rootRow = rootId.flatMap { try? db.dirRow(id: $0) }
            let topKids = rootId.flatMap { try? db.children(of: $0, includeHidden: includeHidden) } ?? []
            let computedFiles = types.reduce(Int64(0)) { $0 + $1.fileCount }

            Task { @MainActor in
                guard let self else { return }
                let applyChanges = {
                    self.groups = loadedGroups
                    self.groupInstancesByName = allInstancesMap
                    if let firstGroup = loadedGroups.first, !loadedGroups.contains(where: { $0.name == self.selectedGroupName }) {
                        self.selectedGroupName = firstGroup.name
                    }
                    self.groupInstances = allInstancesMap[self.selectedGroupName] ?? []
                    self.fileTypeTotals = types
                    if self.scannedFileCount == 0 && computedFiles > 0 {
                        self.scannedFileCount = computedFiles
                    }
                    self.largeFiles = large
                    self.duplicateClusters = dupes
                    if self.currentTreemapDirId == nil {
                        self.currentTreemapDirId = rootId
                        if let rootRow {
                            self.treemapBreadcrumb = [rootRow]
                        }
                        self.treemapChildren = topKids
                    } else if let curId = self.currentTreemapDirId, curId >= 0 {
                        let kids = (try? db.children(of: curId, includeHidden: includeHidden)) ?? []
                        if !kids.isEmpty {
                            self.treemapChildren = kids
                        }
                    }
                }

                if animated {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                        applyChanges()
                        self.isResultsStale = false
                    }
                } else {
                    applyChanges()
                    self.isResultsStale = false
                }
            }
        }
    }

    func reloadSelectedGroupInstances() {
        if let cached = groupInstancesByName[selectedGroupName], !cached.isEmpty {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                groupInstances = cached
            }
            return
        }
        guard let db = activeDB, let resolver = pathResolver else { return }
        let targetName = selectedGroupName
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let rows = (try? db.dirsWithName(targetName)) ?? []
            let instances: [GroupInstanceRow] = rows.map { r in
                let full = resolver.fullPath(of: r.id)
                let parentURL = URL(fileURLWithPath: full).deletingLastPathComponent()
                let proj = parentURL.lastPathComponent.isEmpty ? full : parentURL.lastPathComponent
                return GroupInstanceRow(dirRow: r, fullPath: full, parentProjectName: proj)
            }
            Task { @MainActor in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    self?.groupInstancesByName[targetName] = instances
                    self?.groupInstances = instances
                }
            }
        }
    }

    func drillIntoTreemapDir(_ dir: DirRow) {
        guard let db = activeDB else { return }
        let dirFullPath = fullPath(for: dir.id)
        let includeHidden = allowDeletingHidden

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var kids = (dir.id >= 0) ? ((try? db.children(of: dir.id, includeHidden: includeHidden)) ?? []) : []

            // If this folder has no child directories in SQLite (or is a leaf folder with files),
            // synthesize fast items from disk so drilling down works at any depth with zero lag.
            var customMap: [Int64: String] = [:]
            if kids.isEmpty {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: dirFullPath, isDirectory: &isDir), isDir.boolValue {
                    let diskItems = BulkDirectoryReader.shared.readDirectorySync(
                        at: URL(fileURLWithPath: dirFullPath),
                        showHidden: includeHidden,
                        sortField: .size,
                        ascending: false
                    )
                    var syntheticList: [DirRow] = []
                    for (idx, item) in diskItems.prefix(40).enumerated() where item.size > 0 || item.isFolderLike {
                        let synId = -(abs(dir.id) * 100 + Int64(idx + 1))
                        let estimatedSize: Int64
                        if item.size > 0 {
                            estimatedSize = item.size
                        } else if item.isFolderLike {
                            let sub = BulkDirectoryReader.shared.readDirectorySync(at: item.url, showHidden: false)
                            estimatedSize = max(4096, sub.reduce(Int64(0)) { $0 + $1.size })
                        } else {
                            estimatedSize = 4096
                        }
                        customMap[synId] = item.id
                        syntheticList.append(
                            DirRow(
                                id: synId,
                                parentId: dir.id,
                                name: item.name,
                                depth: dir.depth + 1,
                                isHidden: item.isHidden,
                                isPackage: item.isPackage || !item.isFolderLike,
                                mtime: item.modificationDate,
                                totalSize: estimatedSize,
                                descendantFileCount: 1
                            )
                        )
                    }
                    kids = syntheticList.sorted { $0.totalSize > $1.totalSize }
                }
            }

            Task { @MainActor in
                guard let self else { return }
                withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                    for (k, v) in customMap {
                        self.treemapCustomPaths[k] = v
                    }
                    self.currentTreemapDirId = dir.id
                    if let existingIdx = self.treemapBreadcrumb.firstIndex(where: { $0.id == dir.id }) {
                        self.treemapBreadcrumb = Array(self.treemapBreadcrumb.prefix(through: existingIdx))
                    } else {
                        self.treemapBreadcrumb.append(dir)
                    }
                    self.treemapChildren = kids
                }
            }
        }
    }

    func navigateTreemapUp() {
        guard treemapBreadcrumb.count > 1 else { return }
        let parentDir = treemapBreadcrumb[treemapBreadcrumb.count - 2]
        drillIntoTreemapDir(parentDir)
    }

    func fullPath(for dirId: Int64) -> String {
        if let custom = treemapCustomPaths[dirId] {
            return custom
        }
        return pathResolver?.fullPath(of: dirId) ?? scannedRootPath
    }

    /// Moves one Storage-map item to the Trash and updates the map straight away, instead of
    /// leaving the tile and the folder totals stale until the next background scan.
    func trashStorageItem(_ dir: DirRow, path: String, appState: AppState) {
        let target = DeleteTargetItem(path: path, sizeBytes: dir.totalSize)
        let patch = DeleteTarget(
            dirId: dir.id >= 0 ? dir.id : nil,   // negative ids are synthesized from disk: no DB row
            fileName: nil,
            path: path,
            size: dir.totalSize,
            mtime: dir.mtime,
            isProtected: ProtectedPaths.isProtected(path)
        )
        let db = activeDB
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcome = DeleteService.moveToTrash([target])
            if !outcome.removed.isEmpty, let db {
                try? db.patchAfterDelete(targets: [patch], removedPaths: outcome.removedPaths)
            }
            Task { @MainActor in
                guard let self else { return }
                TransferQueueEngine.shared.recordTrashOutcome(outcome)
                guard outcome.removed.first != nil else {
                    if let reason = outcome.failed.first?.reason { appState.showToast("Cannot move to Trash: \(reason)") }
                    return
                }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    self.treemapChildren.removeAll { $0.id == dir.id }
                    self.treemapBreadcrumb = self.treemapBreadcrumb.map { $0.removingBytes(dir.totalSize) }
                }
                self.refreshAllQueries(animated: true)
                appState.refreshVolumes()
                self.scheduleSmartBackgroundRefresh(delay: 2.0, force: true)
                appState.showToast("Moved \(dir.name) to Trash (\(BulkDirectoryReader.fastFormatBytes(outcome.freedBytes)) freed, ⌘Z to undo)")
            }
        }
    }

    /// Folders modified within this window count as "active" for Protect active projects.
    private static let activeProjectWindow: TimeInterval = 14 * 86_400

    /// Splits folders around `cutoff`. A folder with no known modification date counts as
    /// recent: when unsure, leave it alone.
    nonisolated static func splitByRecency(
        _ rows: [GroupInstanceRow],
        cutoff: Date
    ) -> (stale: [GroupInstanceRow], recent: [GroupInstanceRow]) {
        var stale: [GroupInstanceRow] = [], recent: [GroupInstanceRow] = []
        for row in rows {
            if let modified = row.dirRow.mtime, modified < cutoff { stale.append(row) } else { recent.append(row) }
        }
        return (stale, recent)
    }

    func trashGroupInstances(_ requested: [GroupInstanceRow], appState: AppState) {
        guard !requested.isEmpty, let db = activeDB else { return }

        // Protect active projects guards bulk cleanups. A single folder trashed on purpose
        // is not a sweep, so it always goes through.
        var instances = requested
        var skippedRecent = 0
        if protectActiveProjects && requested.count > 1 {
            let split = Self.splitByRecency(requested, cutoff: Date().addingTimeInterval(-Self.activeProjectWindow))
            instances = split.stale
            skippedRecent = split.recent.count
            guard !instances.isEmpty else {
                appState.showToast("Left \(skippedRecent) folders alone: all were used in the last 14 days. Turn off Protect active projects in Settings to include them.")
                return
            }
        }
        let totalToFree = instances.reduce(Int64(0)) { $0 + $1.dirRow.totalSize }

        // Optional safety confirmation if > 1 GB and confirmLargeDeletes is enabled
        if confirmLargeDeletes && totalToFree >= 1_000_000_000 {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Move \(instances.count) build/cache folders (\(BulkDirectoryReader.fastFormatBytes(totalToFree))) to Trash?"
            alert.informativeText = "Items are moved to the macOS Trash first and can be restored with Undo (⌘Z)."
            alert.addButton(withTitle: "Move to Trash")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        let deleteItems = instances.map { DeleteTargetItem(path: $0.fullPath, sizeBytes: $0.dirRow.totalSize) }
        let patchTargets = instances.map {
            DeleteTarget(
                dirId: $0.dirRow.id,
                fileName: nil,
                path: $0.fullPath,
                size: $0.dirRow.totalSize,
                mtime: $0.dirRow.mtime,
                isProtected: ProtectedPaths.isProtected($0.fullPath)
            )
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcome = DeleteService.moveToTrash(deleteItems)
            if !outcome.removed.isEmpty {
                try? db.patchAfterDelete(targets: patchTargets, removedPaths: outcome.removedPaths)
            }
            Task { @MainActor in
                TransferQueueEngine.shared.recordTrashOutcome(outcome)
                self?.refreshAllQueries(animated: true)
                appState.refreshVolumes()
                self?.scheduleSmartBackgroundRefresh(delay: 2.0, force: true)
                let skipNote = skippedRecent > 0 ? " · \(skippedRecent) recent left alone" : ""
                appState.showToast("Moved \(outcome.removed.count) \(outcome.removed.count == 1 ? "folder" : "folders") to Trash (\(BulkDirectoryReader.fastFormatBytes(outcome.freedBytes)) freed)\(skipNote)")
            }
        }
    }
}
