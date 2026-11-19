import Foundation
import Darwin

enum TransferKind: String, Sendable {
    case copy = "Copying"
    case move = "Moving"
    case compress = "Compressing"
}

enum ConflictPolicy: String, CaseIterable, Sendable {
    case keepBoth = "Keep Both"
    case replace = "Replace"
    case skip = "Skip"
}

struct TransferConflictRecord: Identifiable, Sendable {
    let id = UUID()
    let originalName: String
    let resolvedURL: URL
    let existingURL: URL
    let resolution: ConflictPolicy
    let timestamp: Date
}

struct TrashHistoryRecord: Identifiable, Sendable {
    let id = UUID()
    let itemCount: Int
    let freedBytes: Int64
    let sourceFolderName: String
    let trashURLs: [URL: URL]
    let timestamp: Date
}

struct TransferJob: Identifiable, Sendable {
    let id: UUID
    let kind: TransferKind
    let sourceURLs: [URL]
    let destinationDirectory: URL
    var totalBytes: Int64
    var copiedBytes: Int64
    var bytesPerSecond: Double
    var speedSamples: [Double] // 10 normalized bars 0.15...1.0
    var isPaused: Bool
    var isCompleted: Bool
    var isCancelled: Bool
    var errorMessage: String?

    var progressFraction: Double {
        guard totalBytes > 0 else { return isCompleted ? 1.0 : 0.0 }
        return min(1.0, max(0.0, Double(copiedBytes) / Double(totalBytes)))
    }

    var progressPercent: Int {
        Int(round(progressFraction * 100))
    }

    var titleText: String {
        switch kind {
        case .copy:
            return "Copying \(sourceURLs.count) \(sourceURLs.count == 1 ? "item" : "items")"
        case .move:
            return "Moving \(sourceURLs.count) \(sourceURLs.count == 1 ? "item" : "items")"
        case .compress:
            let name = sourceURLs.first?.deletingPathExtension().lastPathComponent ?? "Archive"
            return "Compressing \(name).zip"
        }
    }

    var subtitleText: String {
        "to \(destinationDirectory.lastPathComponent)"
    }

    var etaSeconds: Int? {
        guard bytesPerSecond > 1024, totalBytes > copiedBytes else { return nil }
        return max(1, Int(Double(totalBytes - copiedBytes) / bytesPerSecond))
    }
}

final class TransferControlBox: @unchecked Sendable {
    let condition = NSCondition()
    var isPaused: Bool = false
    var isCancelled: Bool = false
    var baseCompletedBytes: Int64 = 0
    var currentFileCopiedBytes: Int64 = 0
    var onProgressSample: ((Int64) -> Void)?

    func setPaused(_ paused: Bool) {
        condition.lock()
        isPaused = paused
        if !paused {
            condition.broadcast()
        }
        condition.unlock()
    }

    func cancel() {
        condition.lock()
        isCancelled = true
        isPaused = false
        condition.broadcast()
        condition.unlock()
    }

    /// Blocks while paused; returns true if cancelled.
    func waitIfPausedOrCheckCancelled() -> Bool {
        condition.lock()
        defer { condition.unlock() }
        while isPaused && !isCancelled {
            condition.wait()
        }
        return isCancelled
    }
}

// C callback for Darwin copyfile_state_t
private let stratumCopyfileStatusCallback: copyfile_callback_t = { what, stage, state, srcPath, dstPath, ctx in
    guard let ctx else { return Int32(COPYFILE_CONTINUE) }
    let box = Unmanaged<TransferControlBox>.fromOpaque(ctx).takeUnretainedValue()

    if box.waitIfPausedOrCheckCancelled() {
        return Int32(COPYFILE_QUIT)
    }

    if what == COPYFILE_COPY_DATA && (stage == COPYFILE_PROGRESS || stage == COPYFILE_FINISH) {
        var copied: off_t = 0
        if copyfile_state_get(state, UInt32(COPYFILE_STATE_COPIED), &copied) == 0 {
            box.currentFileCopiedBytes = Int64(copied)
            box.onProgressSample?(box.baseCompletedBytes + Int64(copied))
        }
    }
    return Int32(COPYFILE_CONTINUE)
}

@Observable
@MainActor
final class TransferQueueEngine {
    static let shared = TransferQueueEngine()

    var jobs: [TransferJob] = []
    var conflicts: [TransferConflictRecord] = []
    var trashHistory: [TrashHistoryRecord] = []
    var defaultConflictPolicy: ConflictPolicy = .keepBoth

    private var controlBoxes: [UUID: TransferControlBox] = [:]
    private let workerQueue = DispatchQueue(label: "app.stratum.transfer-worker", qos: .userInitiated)

    var activeJob: TransferJob? {
        jobs.first(where: { !$0.isCompleted && !$0.isCancelled })
    }

    @discardableResult
    func enqueueTransfer(
        kind: TransferKind,
        sourceURLs: [URL],
        to destinationDirectory: URL,
        conflictPolicy: ConflictPolicy? = nil,
        onCompletion: (@MainActor () -> Void)? = nil
    ) -> UUID {
        let policy = conflictPolicy ?? defaultConflictPolicy
        let jobID = UUID()
        let job = TransferJob(
            id: jobID,
            kind: kind,
            sourceURLs: sourceURLs,
            destinationDirectory: destinationDirectory,
            totalBytes: 0,
            copiedBytes: 0,
            bytesPerSecond: 0,
            speedSamples: [0.3, 0.45, 0.6, 0.55, 0.7, 0.68, 0.8, 0.75, 0.88, 0.82],
            isPaused: false,
            isCompleted: false,
            isCancelled: false,
            errorMessage: nil
        )
        jobs.insert(job, at: 0)

        let controlBox = TransferControlBox()
        controlBoxes[jobID] = controlBox

        workerQueue.async { [weak self] in
            Self.executeJob(
                jobID: jobID,
                kind: kind,
                sourceURLs: sourceURLs,
                destinationDirectory: destinationDirectory,
                conflictPolicy: policy,
                controlBox: controlBox,
                engine: self,
                onCompletion: onCompletion
            )
        }
        return jobID
    }

    func togglePause(jobID: UUID) {
        guard let idx = jobs.firstIndex(where: { $0.id == jobID }),
              let box = controlBoxes[jobID] else { return }
        let nextPaused = !jobs[idx].isPaused
        jobs[idx].isPaused = nextPaused
        box.setPaused(nextPaused)
    }

    func cancel(jobID: UUID) {
        if let idx = jobs.firstIndex(where: { $0.id == jobID }) {
            jobs[idx].isCancelled = true
            jobs[idx].isPaused = false
        }
        controlBoxes[jobID]?.cancel()
    }

    func recordTrashOutcome(_ outcome: DeleteService.Outcome) {
        guard !outcome.removed.isEmpty else { return }
        let rec = TrashHistoryRecord(
            itemCount: outcome.removed.count,
            freedBytes: outcome.freedBytes,
            sourceFolderName: outcome.sourceFolderName,
            trashURLs: outcome.trashURLs,
            timestamp: outcome.timestamp
        )
        trashHistory.insert(rec, at: 0)
    }

    func undoTrashRecord(_ record: TrashHistoryRecord, onRestored: @escaping @MainActor () -> Void) {
        let urls = record.trashURLs
        let id = record.id
        workerQueue.async { [weak self] in
            _ = DeleteService.restoreFromTrash(urls)
            Task { @MainActor in
                self?.trashHistory.removeAll(where: { $0.id == id })
                onRestored()
            }
        }
    }

    // MARK: - Background Worker Execution

    nonisolated private static func executeJob(
        jobID: UUID,
        kind: TransferKind,
        sourceURLs: [URL],
        destinationDirectory: URL,
        conflictPolicy: ConflictPolicy,
        controlBox: TransferControlBox,
        engine: TransferQueueEngine?,
        onCompletion: (@MainActor () -> Void)?
    ) {
        let fm = FileManager.default

        // 1. Calculate total size and expand file list
        let totalSize = computeTotalBytes(for: sourceURLs)
        Task { @MainActor in
            if let idx = engine?.jobs.firstIndex(where: { $0.id == jobID }) {
                engine?.jobs[idx].totalBytes = max(1, totalSize)
            }
        }

        let startTime = DispatchTime.now()
        var lastUIUpdate = startTime
        var lastSampleBytes: Int64 = 0

        controlBox.onProgressSample = { currentTotal in
            let now = DispatchTime.now()
            let dtNs = now.uptimeNanoseconds - lastUIUpdate.uptimeNanoseconds
            guard dtNs >= 80_000_000 else { return } // Throttle UI updates to ~12.5 Hz
            let dtSec = Double(dtNs) / 1_000_000_000.0
            let deltaBytes = max(0, currentTotal - lastSampleBytes)
            let speed = dtSec > 0 ? Double(deltaBytes) / dtSec : 0
            lastUIUpdate = now
            lastSampleBytes = currentTotal

            Task { @MainActor in
                guard let engine, let idx = engine.jobs.firstIndex(where: { $0.id == jobID }) else { return }
                engine.jobs[idx].copiedBytes = currentTotal
                engine.jobs[idx].bytesPerSecond = speed
                var samples = engine.jobs[idx].speedSamples
                let norm = min(1.0, max(0.18, speed / (500.0 * 1024 * 1024)))
                samples.append(norm)
                if samples.count > 10 { samples.removeFirst() }
                engine.jobs[idx].speedSamples = samples
            }
        }

        if kind == .compress {
            let zipName = (sourceURLs.first?.deletingPathExtension().lastPathComponent ?? "Archive") + ".zip"
            let targetZip = resolveDestination(
                for: zipName,
                in: destinationDirectory,
                policy: .keepBoth,
                engine: engine
            ).resolvedURL
            if let targetZip {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                var args = ["-c", "-k", "--sequesterRsrc"]
                if sourceURLs.count == 1 {
                    args.append("--keepParent")
                    args.append(sourceURLs[0].path)
                } else {
                    args.append(contentsOf: sourceURLs.map(\.path))
                }
                args.append(targetZip.path)
                proc.arguments = args
                try? proc.run()
                proc.waitUntilExit()
            }
            Task { @MainActor in
                if let idx = engine?.jobs.firstIndex(where: { $0.id == jobID }) {
                    engine?.jobs[idx].copiedBytes = max(1, totalSize)
                    engine?.jobs[idx].isCompleted = true
                }
                onCompletion?()
            }
            return
        }

        // 2. Copy or Move each source URL using Darwin <copyfile.h>
        for srcURL in sourceURLs {
            if controlBox.waitIfPausedOrCheckCancelled() {
                break
            }
            if ProtectedPaths.isProtected(srcURL.path) && kind == .move {
                continue
            }

            let resolution = resolveDestination(
                for: srcURL.lastPathComponent,
                in: destinationDirectory,
                policy: conflictPolicy,
                engine: engine
            )
            guard let dstURL = resolution.resolvedURL else {
                // Skipped due to conflict policy
                continue
            }

            if resolution.hadConflict && conflictPolicy == .replace {
                _ = DeleteService.moveToTrash([DeleteTargetItem(path: dstURL.path)])
            }

            // If moving on the same volume, rename() is atomic and O(1)
            if kind == .move {
                if Darwin.rename(srcURL.path, dstURL.path) == 0 {
                    let itemBytes = computeTotalBytes(for: [dstURL])
                    controlBox.baseCompletedBytes += itemBytes
                    controlBox.onProgressSample?(controlBox.baseCompletedBytes)
                    continue
                }
            }

            let ok = copyTreeWithCopyfile(
                from: srcURL,
                to: dstURL,
                controlBox: controlBox
            )

            if ok && kind == .move && !controlBox.isCancelled {
                // Source copied across volumes; safely remove original if not protected
                if !ProtectedPaths.isProtected(srcURL.path) {
                    try? fm.removeItem(at: srcURL)
                }
            }
        }

        let wasCancelled = controlBox.isCancelled
        Task { @MainActor in
            if let idx = engine?.jobs.firstIndex(where: { $0.id == jobID }) {
                if !wasCancelled {
                    engine?.jobs[idx].copiedBytes = engine?.jobs[idx].totalBytes ?? totalSize
                    engine?.jobs[idx].isCompleted = true
                } else {
                    engine?.jobs[idx].isCancelled = true
                }
            }
            onCompletion?()
        }
    }

    nonisolated private static func copyTreeWithCopyfile(
        from srcURL: URL,
        to dstURL: URL,
        controlBox: TransferControlBox
    ) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: srcURL.path, isDirectory: &isDir) else {
            return false
        }

        if !isDir.boolValue {
            return copySingleFileWithCopyfile(from: srcURL, to: dstURL, controlBox: controlBox)
        }

        // Create root directory
        try? FileManager.default.createDirectory(at: dstURL, withIntermediateDirectories: true)

        guard let enumerator = FileManager.default.enumerator(
            at: srcURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ) else {
            return false
        }

        let baseSrcPath = srcURL.standardizedFileURL.path
        while let next = enumerator.nextObject() as? URL {
            if controlBox.waitIfPausedOrCheckCancelled() {
                try? FileManager.default.removeItem(at: dstURL)
                return false
            }
            let entryStdPath = next.standardizedFileURL.path
            guard entryStdPath.hasPrefix(baseSrcPath) else { continue }
            let relPath = String(entryStdPath.dropFirst(baseSrcPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let targetChildURL = dstURL.appendingPathComponent(relPath)

            let vals = try? next.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if vals?.isDirectory == true && vals?.isSymbolicLink != true {
                try? FileManager.default.createDirectory(at: targetChildURL, withIntermediateDirectories: true)
            } else {
                if !copySingleFileWithCopyfile(from: next, to: targetChildURL, controlBox: controlBox) {
                    if controlBox.isCancelled {
                        try? FileManager.default.removeItem(at: dstURL)
                    }
                    return false
                }
            }
        }
        return true
    }

    nonisolated private static func copySingleFileWithCopyfile(
        from srcURL: URL,
        to dstURL: URL,
        controlBox: TransferControlBox
    ) -> Bool {
        guard let state = copyfile_state_alloc() else { return false }
        defer { copyfile_state_free(state) }

        let ctxPtr = Unmanaged.passUnretained(controlBox).toOpaque()
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CB), UnsafeRawPointer(bitPattern: unsafeBitCast(stratumCopyfileStatusCallback, to: UInt.self)))
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CTX), ctxPtr)

        controlBox.currentFileCopiedBytes = 0

        // Try COPYFILE_CLONE | COPYFILE_ALL first (instant APFS clone on same volume, falls back automatically to data copy)
        let flags = copyfile_flags_t(UInt32(COPYFILE_ALL) | UInt32(COPYFILE_CLONE))
        let rc = copyfile(srcURL.path, dstURL.path, state, flags)
        if rc != 0 {
            if controlBox.isCancelled {
                try? FileManager.default.removeItem(at: dstURL)
            }
            return false
        }

        let fileSize = (try? srcURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? Int(controlBox.currentFileCopiedBytes)
        controlBox.baseCompletedBytes += Int64(max(Int(controlBox.currentFileCopiedBytes), fileSize))
        controlBox.onProgressSample?(controlBox.baseCompletedBytes)
        return true
    }

    nonisolated private static func resolveDestination(
        for fileName: String,
        in directory: URL,
        policy: ConflictPolicy,
        engine: TransferQueueEngine?
    ) -> (resolvedURL: URL?, hadConflict: Bool) {
        let initialURL = directory.appendingPathComponent(fileName)
        let fm = FileManager.default
        guard fm.fileExists(atPath: initialURL.path) else {
            return (initialURL, false)
        }

        switch policy {
        case .skip:
            let record = TransferConflictRecord(
                originalName: fileName,
                resolvedURL: initialURL,
                existingURL: initialURL,
                resolution: .skip,
                timestamp: Date()
            )
            Task { @MainActor in engine?.conflicts.insert(record, at: 0) }
            return (nil, true)

        case .replace:
            let record = TransferConflictRecord(
                originalName: fileName,
                resolvedURL: initialURL,
                existingURL: initialURL,
                resolution: .replace,
                timestamp: Date()
            )
            Task { @MainActor in engine?.conflicts.insert(record, at: 0) }
            return (initialURL, true)

        case .keepBoth:
            let nsName = fileName as NSString
            let ext = nsName.pathExtension
            let stem = nsName.deletingPathExtension
            var counter = 2
            var candidateURL = initialURL
            while fm.fileExists(atPath: candidateURL.path) {
                let newName = ext.isEmpty ? "\(stem) \(counter)" : "\(stem) \(counter).\(ext)"
                candidateURL = directory.appendingPathComponent(newName)
                counter += 1
            }
            let record = TransferConflictRecord(
                originalName: fileName,
                resolvedURL: candidateURL,
                existingURL: initialURL,
                resolution: .keepBoth,
                timestamp: Date()
            )
            Task { @MainActor in engine?.conflicts.insert(record, at: 0) }
            return (candidateURL, true)
        }
    }

    nonisolated private static func computeTotalBytes(for urls: [URL]) -> Int64 {
        var total: Int64 = 0
        let fm = FileManager.default
        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if !isDir.boolValue {
                let sz = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                total += Int64(sz)
            } else if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isSymbolicLinkKey]) {
                while let child = enumerator.nextObject() as? URL {
                    let vals = try? child.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])
                    if vals?.isSymbolicLink != true {
                        total += Int64(vals?.fileSize ?? 0)
                    }
                }
            }
        }
        return total
    }
}
