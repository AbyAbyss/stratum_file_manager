import Foundation
import SwiftUI
import AppKit
import CoreServices

extension ScanCoordinator {
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
    static let activeProjectWindow: TimeInterval = 14 * 86_400

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
