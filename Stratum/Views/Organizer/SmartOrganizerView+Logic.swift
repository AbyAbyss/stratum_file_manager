import SwiftUI
import AppKit
import CryptoKit

extension SmartOrganizerView {
    // MARK: - Logic Helpers

    func reloadTargetFolder() {
        let url = targetFolderURL
        let trackedPaths = Self.trackedOrganizedFolderPaths()
        DispatchQueue.global(qos: .userInitiated).async {
            let items = BulkDirectoryReader.shared.readDirectorySync(at: url, showHidden: false)
            let filesOnly = items.filter { !$0.isFolderLike && !$0.isPackage }

            // Only show category folders that the user explicitly clicked to create in Stratum
            var existing: [ExistingOrganizedFolder] = []
            for def in Self.categoryDefinitions {
                let subURL = url.appendingPathComponent(def.folderName, isDirectory: true)
                guard trackedPaths.contains(subURL.path) else { continue }
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: subURL.path, isDirectory: &isDir), isDir.boolValue {
                    let subItems = BulkDirectoryReader.shared.readDirectorySync(at: subURL, showHidden: false)
                        .filter { !$0.isFolderLike }
                    if !subItems.isEmpty {
                        existing.append(
                            ExistingOrganizedFolder(
                                folderName: def.folderName,
                                folderURL: subURL,
                                icon: def.icon,
                                tintHex: def.tintHex,
                                items: subItems
                            )
                        )
                    }
                }
            }

            Task { @MainActor in
                withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                    self.looseFiles = filesOnly
                    self.organizedFolders = existing
                }
            }
        }
    }

    func organizeBuckets(_ buckets: [OrganizerBucket]) {
        let baseDir = targetFolderURL
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            var moveRecords: [OrganizeMoveRecord] = []
            var createdFolderPaths: [String] = []

            for bucket in buckets where !bucket.items.isEmpty {
                let categoryDir = baseDir.appendingPathComponent(bucket.folderName, isDirectory: true)
                try? fm.createDirectory(at: categoryDir, withIntermediateDirectories: true)
                createdFolderPaths.append(categoryDir.path)

                for file in bucket.items {
                    var destURL = categoryDir.appendingPathComponent(file.name)
                    var counter = 2
                    while fm.fileExists(atPath: destURL.path) {
                        let base = (file.name as NSString).deletingPathExtension
                        let ext = (file.name as NSString).pathExtension
                        let newName = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
                        destURL = categoryDir.appendingPathComponent(newName)
                        counter += 1
                    }
                    if (try? fm.moveItem(at: file.url, to: destURL)) != nil {
                        moveRecords.append(OrganizeMoveRecord(fromURL: file.url, toURL: destURL))
                    }
                }
            }

            Task { @MainActor in
                for path in createdFolderPaths {
                    Self.recordOrganizedFolderPath(path)
                }
                self.lastOrganizeMoves = moveRecords
                self.reloadTargetFolder()
                self.appState.reloadCurrentDirectory(preserveSelection: false)
                ScanCoordinator.shared.notifyFileSystemMutation(near: baseDir)
                self.appState.showToast("Moved \(moveRecords.count) \(moveRecords.count == 1 ? "file" : "files") into \(buckets.map(\.folderName).joined(separator: ", "))/")
            }
        }
    }

    func unpackOrganizedFolder(_ org: ExistingOrganizedFolder) {
        let baseDir = targetFolderURL
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            var unpackedCount = 0
            for file in org.items {
                var destURL = baseDir.appendingPathComponent(file.name)
                var counter = 2
                while fm.fileExists(atPath: destURL.path) {
                    let base = (file.name as NSString).deletingPathExtension
                    let ext = (file.name as NSString).pathExtension
                    let newName = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
                    destURL = baseDir.appendingPathComponent(newName)
                    counter += 1
                }
                if (try? fm.moveItem(at: file.url, to: destURL)) != nil {
                    unpackedCount += 1
                }
            }
            // If folder is now empty, remove the empty category folder
            let remaining = (try? fm.contentsOfDirectory(atPath: org.folderURL.path)) ?? []
            if remaining.isEmpty {
                try? fm.removeItem(at: org.folderURL)
            }

            Task { @MainActor in
                Self.removeOrganizedFolderPath(org.folderURL.path)
                self.reloadTargetFolder()
                self.appState.reloadCurrentDirectory(preserveSelection: false)
                ScanCoordinator.shared.notifyFileSystemMutation(near: baseDir)
                self.appState.showToast("Unpacked \(unpackedCount) \(unpackedCount == 1 ? "file" : "files") from \(org.folderName)/ back into \(baseDir.lastPathComponent)")
            }
        }
    }

    func undoLastOrganize() {
        let moves = lastOrganizeMoves
        guard !moves.isEmpty else { return }
        lastOrganizeMoves = []
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            var restored = 0
            var touchedFolders = Set<URL>()
            for record in moves.reversed() {
                touchedFolders.insert(record.toURL.deletingLastPathComponent())
                if (try? fm.moveItem(at: record.toURL, to: record.fromURL)) != nil {
                    restored += 1
                }
            }
            var removedPaths: [String] = []
            for dirURL in touchedFolders {
                let remaining = (try? fm.contentsOfDirectory(atPath: dirURL.path)) ?? []
                if remaining.isEmpty {
                    try? fm.removeItem(at: dirURL)
                    removedPaths.append(dirURL.path)
                }
            }
            Task { @MainActor in
                for path in removedPaths {
                    Self.removeOrganizedFolderPath(path)
                }
                self.reloadTargetFolder()
                self.appState.reloadCurrentDirectory(preserveSelection: false)
                self.appState.showToast("Restored \(restored) \(restored == 1 ? "file" : "files") to \(self.targetFolderURL.lastPathComponent)")
            }
        }
    }

    func scanForExactDuplicates() {
        isScanningDuplicates = true
        let rootURL = targetFolderURL
        DispatchQueue.global(qos: .userInitiated).async {
            let pool = AppState.collectCrossMacCandidatePool(including: rootURL)
                .filter { !$0.isFolderLike && !$0.isPackage && !$0.isDataless && $0.size >= 4096 && $0.size <= 250 * 1024 * 1024 }

            var bySize: [Int64: [FileItem]] = [:]
            for item in pool {
                bySize[item.size, default: []].append(item)
            }

            var byHash: [String: [FileItem]] = [:]
            for (_, sameSizeItems) in bySize where sameSizeItems.count > 1 {
                for file in sameSizeItems {
                    guard let data = try? Data(contentsOf: file.url, options: .mappedIfSafe) else { continue }
                    let digest = SHA256.hash(data: data)
                    let hex = digest.map { String(format: "%02x", $0) }.joined()
                    byHash[hex, default: []].append(file)
                }
            }

            var clusters: [VerifiedDuplicateCluster] = []
            for (hex, items) in byHash where items.count > 1 {
                let sorted = items.sorted { $0.modificationDate > $1.modificationDate }
                if let first = sorted.first {
                    clusters.append(
                        VerifiedDuplicateCluster(
                            id: hex,
                            hashHex: hex,
                            fileName: first.name,
                            sizeBytes: first.size,
                            items: sorted
                        )
                    )
                }
            }
            clusters.sort { $0.reclaimableBytes > $1.reclaimableBytes }

            Task { @MainActor in
                withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                    self.duplicateClusters = clusters
                    self.isScanningDuplicates = false
                }
            }
        }
    }

    func autoSelectRedundantDuplicates() {
        var redundant = Set<String>()
        for cluster in duplicateClusters {
            for copy in cluster.items.dropFirst() {
                redundant.insert(copy.id)
            }
        }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.80)) {
            selectedDuplicatePaths = redundant
        }
    }

    func trashSelectedDuplicates() {
        var targets: [(url: URL, size: Int64)] = []
        for cluster in duplicateClusters {
            for file in cluster.items where selectedDuplicatePaths.contains(file.id) {
                targets.append((url: file.url, size: file.size))
            }
        }
        guard !targets.isEmpty else { return }
        appState.moveURLsToTrash(targets)
        selectedDuplicatePaths.removeAll()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            scanForExactDuplicates()
        }
    }
}
