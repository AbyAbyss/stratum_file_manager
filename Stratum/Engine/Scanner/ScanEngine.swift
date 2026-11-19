import Foundation
import Darwin

enum ScanEngine {

    static let excludedRootSubtrees: Set<String> = [
        "/System/Volumes",
        "/dev",
        "/Volumes",
        "/net",
        "/home",
        "/cores",
    ]

    static let packageExtensions: Set<String> = [
        "app", "framework", "bundle", "plugin", "kext", "xcodeproj",
        "xcworkspace", "playground", "photoslibrary", "musiclibrary", "tvlibrary", "xcarchive"
    ]

    struct Outcome: Sendable {
        let dbURL: URL
        let scanId: Int64
        let dirCount: Int64
        let fileCount: Int64
        let skippedCount: Int64
        let maxDepth: Int
        let durationSeconds: Double
    }

    struct BenchmarkComparison: Sendable {
        let enumeratorDurationMs: Double
        let bulkWalkerDurationMs: Double
        let speedupFactor: Double
        let filesVisited: Int64
        let totalBytesCounted: Int64
    }

    private static let scanWorkerQueue = DispatchQueue(
        label: "app.stratum.scan-engine-worker",
        qos: .userInitiated,
        attributes: .concurrent
    )

    static func scan(
        volume: VolumeInfo,
        store: ScanStore,
        onProgress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws -> Outcome {
        let cancelFlag = ScanCancelFlag()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                scanWorkerQueue.async {
                    do {
                        let outcome = try runBulkWalk(
                            volume: volume,
                            store: store,
                            cancelFlag: cancelFlag,
                            onProgress: onProgress
                        )
                        continuation.resume(returning: outcome)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            cancelFlag.cancel()
        }
    }

    // MARK: - Upgraded getattrlistbulk Walker

    private final class ScanCancelFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var _cancelled = false
        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return _cancelled
        }
        func cancel() {
            lock.lock()
            _cancelled = true
            lock.unlock()
        }
    }

    private struct Frame {
        let id: Int64
        let parentId: Int64?
        let path: String
        let name: String
        let depth: Int
        let isHidden: Bool
        let isPackage: Bool
        let mtime: Int64?
        var ownSize: Int64
        var fileCount: Int64
    }

    private static func runBulkWalk(
        volume: VolumeInfo,
        store: ScanStore,
        cancelFlag: ScanCancelFlag,
        onProgress: @Sendable (ScanProgress) -> Void
    ) throws -> Outcome {
        let startedAt = Date()
        let startNs = DispatchTime.now().uptimeNanoseconds
        let inProgressURL = store.inProgressURL(startedAt: startedAt)
        let finalURL = store.completedURL(volumeUUID: volume.id, startedAt: startedAt)

        var didComplete = false
        defer {
            if !didComplete {
                try? FileManager.default.removeItem(at: inProgressURL)
                try? FileManager.default.removeItem(at: inProgressURL.appendingPathExtension("shm"))
                try? FileManager.default.removeItem(at: inProgressURL.appendingPathExtension("wal"))
            }
        }

        var scanId: Int64 = 0
        var dirCount: Int64 = 0
        var fileCount: Int64 = 0
        var skippedCount: Int64 = 0
        var maxDepth: Int = 0

        do {
            let db = try ScanDatabase(url: inProgressURL)
            let rootURL = volume.url.standardizedFileURL
            let rootPath = rootURL.path

            var rootDev: dev_t = 0
            var rootStat = stat()
            if lstat(rootPath, &rootStat) == 0 {
                rootDev = rootStat.st_dev
            }

            scanId = try db.insertScanStart(
                volumeUUID: volume.id,
                volumeName: volume.name,
                rootPath: rootPath,
                startedAt: startedAt
            )

            var nextDirId: Int64 = 1
            let rootId = nextDirId
            nextDirId += 1
            dirCount += 1

            let rootMtime: Int64? = rootStat.st_mtimespec.tv_sec > 0 ? Int64(rootStat.st_mtimespec.tv_sec) : nil

            // Explicit DFS stack of directories to visit using getattrlistbulk
            var workStack: [Frame] = [
                Frame(
                    id: rootId,
                    parentId: nil,
                    path: rootPath,
                    name: "/",
                    depth: 0,
                    isHidden: false,
                    isPackage: false,
                    mtime: rootMtime,
                    ownSize: 0,
                    fileCount: 0
                )
            ]

            var dirBatch: [DirInsertRow] = []
            dirBatch.reserveCapacity(10_000)

            var typeSize = [Int64](repeating: 0, count: FileTypeCategory.allCases.count)
            var typeCount = [Int64](repeating: 0, count: FileTypeCategory.allCases.count)

            var heaps: [BoundedMinHeap<LargeFileInsertRow>] = (0..<FileTypeCategory.allCases.count)
                .map { _ in BoundedMinHeap<LargeFileInsertRow>(capacity: 500) }
            let largeFileMinSize: Int64 = 1_048_576 // 1 MB

            // Hardlink inode deduplication table
            var seenHardlinkInodes = Set<UInt64>()

            // Reusable 64KB buffer for getattrlistbulk
            let bufferSize = 64 * 1024
            let rawBuffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 8)
            defer { rawBuffer.deallocate() }

            var attrList = attrlist()
            attrList.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
            attrList.commonattr =
                attrgroup_t(bitPattern: Int32(bitPattern: UInt32(ATTR_CMN_RETURNED_ATTRS))) |
                attrgroup_t(ATTR_CMN_NAME) |
                attrgroup_t(ATTR_CMN_DEVID) |
                attrgroup_t(ATTR_CMN_OBJTYPE) |
                attrgroup_t(ATTR_CMN_MODTIME) |
                attrgroup_t(ATTR_CMN_FLAGS) |
                attrgroup_t(ATTR_CMN_FILEID)
            attrList.fileattr = attrgroup_t(
                ATTR_FILE_LINKCOUNT |
                ATTR_FILE_TOTALSIZE |
                ATTR_FILE_ALLOCSIZE
            )

            let startTick = DispatchTime.now()
            var lastProgressTick = startTick
            let usedEstimate = max(Int64(1), volume.used)
            var bytesVisited: Int64 = 0

            while var currentFrame = workStack.popLast() {
                if cancelFlag.isCancelled {
                    throw CancellationError()
                }

                let fd = Darwin.open(currentFrame.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
                if fd < 0 {
                    skippedCount += 1
                    dirBatch.append(Self.makeDirInsertRow(from: currentFrame))
                    if dirBatch.count >= 10_000 {
                        try db.insertDirsBatch(dirBatch)
                        dirBatch.removeAll(keepingCapacity: true)
                    }
                    continue
                }

                var childDirFrames: [Frame] = []
                var childPkgRows: [DirInsertRow] = []

                while true {
                    let count = getattrlistbulk(fd, &attrList, rawBuffer, bufferSize, 0)
                    if count <= 0 { break }

                    var cursor = UnsafeRawPointer(rawBuffer)
                    for _ in 0..<count {
                        let entryLength = Int(cursor.loadUnaligned(as: UInt32.self))
                        guard entryLength > 0 else { break }
                        let nextEntry = cursor.advanced(by: entryLength)

                        var field = cursor.advanced(by: 4)
                        let returned = field.loadUnaligned(as: attribute_set_t.self)
                        field = field.advanced(by: MemoryLayout<attribute_set_t>.size)

                        var nameStr = ""
                        if (returned.commonattr & attrgroup_t(ATTR_CMN_NAME)) != 0 {
                            let nameRef = field.loadUnaligned(as: attrreference_t.self)
                            let namePtr = field.advanced(by: Int(nameRef.attr_dataoffset)).assumingMemoryBound(to: CChar.self)
                            nameStr = String(cString: namePtr)
                            field = field.advanced(by: MemoryLayout<attrreference_t>.size)
                        }

                        var devID: dev_t = rootDev
                        if (returned.commonattr & attrgroup_t(ATTR_CMN_DEVID)) != 0 {
                            devID = field.loadUnaligned(as: dev_t.self)
                            field = field.advanced(by: MemoryLayout<dev_t>.size)
                        }

                        var objType: fsobj_type_t = 0
                        if (returned.commonattr & attrgroup_t(ATTR_CMN_OBJTYPE)) != 0 {
                            objType = field.loadUnaligned(as: fsobj_type_t.self)
                            field = field.advanced(by: MemoryLayout<fsobj_type_t>.size)
                        }

                        var modSec: Int64? = nil
                        if (returned.commonattr & attrgroup_t(ATTR_CMN_MODTIME)) != 0 {
                            let ts = field.loadUnaligned(as: timespec.self)
                            modSec = Int64(ts.tv_sec)
                            field = field.advanced(by: MemoryLayout<timespec>.size)
                        }

                        var flags: UInt32 = 0
                        if (returned.commonattr & attrgroup_t(ATTR_CMN_FLAGS)) != 0 {
                            flags = field.loadUnaligned(as: UInt32.self)
                            field = field.advanced(by: MemoryLayout<UInt32>.size)
                        }

                        var fileID: UInt64 = 0
                        if (returned.commonattr & attrgroup_t(ATTR_CMN_FILEID)) != 0 {
                            fileID = field.loadUnaligned(as: UInt64.self)
                            field = field.advanced(by: MemoryLayout<UInt64>.size)
                        }

                        // Note: <sys/attr.h> bit order is ATTR_FILE_LINKCOUNT (0x1),
                        // ATTR_FILE_TOTALSIZE (0x2), ATTR_FILE_ALLOCSIZE (0x4).
                        var linkCount: UInt32 = 1
                        if (returned.fileattr & attrgroup_t(ATTR_FILE_LINKCOUNT)) != 0 {
                            linkCount = field.loadUnaligned(as: UInt32.self)
                            field = field.advanced(by: MemoryLayout<UInt32>.size)
                        }

                        var totalSize: Int64 = 0
                        if (returned.fileattr & attrgroup_t(ATTR_FILE_TOTALSIZE)) != 0 {
                            totalSize = field.loadUnaligned(as: Int64.self)
                            field = field.advanced(by: MemoryLayout<Int64>.size)
                        }

                        var allocSize: Int64 = 0
                        if (returned.fileattr & attrgroup_t(ATTR_FILE_ALLOCSIZE)) != 0 {
                            allocSize = field.loadUnaligned(as: Int64.self)
                            field = field.advanced(by: MemoryLayout<Int64>.size)
                        }

                        cursor = nextEntry

                        if nameStr.isEmpty || nameStr == "." || nameStr == ".." {
                            continue
                        }

                        // Skip cross-device mounts or symlinks
                        if rootDev != 0 && devID != rootDev {
                            continue
                        }
                        if objType == fsobj_type_t(VLNK.rawValue) {
                            continue
                        }

                        let childPath = currentFrame.path == "/" ? "/\(nameStr)" : "\(currentFrame.path)/\(nameStr)"
                        if excludedRootSubtrees.contains(childPath) {
                            continue
                        }

                        let isHidden = nameStr.utf8.first == UInt8(ascii: ".") || (flags & UInt32(UF_HIDDEN)) != 0
                        let isDataless = (flags & UInt32(SF_DATALESS)) != 0
                        let extLower = Self.extractLowerExtension(from: nameStr)

                        if objType == fsobj_type_t(VDIR.rawValue) {
                            let childDepth = currentFrame.depth + 1
                            if childDepth > maxDepth { maxDepth = childDepth }
                            let childId = nextDirId
                            nextDirId += 1
                            dirCount += 1

                            let isPkg = (!extLower.isEmpty && packageExtensions.contains(extLower))

                            if isPkg {
                                // Package fix: sum interior allocated bytes into this leaf package row
                                // and classify as .apps if .app so Apps category & leaf DirRow have real size!
                                let pkgStats = sumPackageContentsFast(
                                    at: childPath,
                                    rootDev: rootDev,
                                    seenHardlinks: &seenHardlinkInodes
                                )
                                fileCount += pkgStats.fileCount
                                bytesVisited += pkgStats.totalBytes

                                let pkgCat: FileTypeCategory = (extLower == "app") ? .apps : .other
                                typeSize[pkgCat.rawValue] += pkgStats.totalBytes
                                typeCount[pkgCat.rawValue] += max(1, pkgStats.fileCount)

                                childPkgRows.append(
                                    DirInsertRow(
                                        id: childId,
                                        parentId: currentFrame.id,
                                        name: nameStr,
                                        depth: childDepth,
                                        isHidden: isHidden,
                                        isPackage: true,
                                        mtime: modSec,
                                        ownSize: pkgStats.totalBytes,
                                        fileCount: pkgStats.fileCount
                                    )
                                )
                            } else {
                                childDirFrames.append(
                                    Frame(
                                        id: childId,
                                        parentId: currentFrame.id,
                                        path: childPath,
                                        name: nameStr,
                                        depth: childDepth,
                                        isHidden: isHidden,
                                        isPackage: false,
                                        mtime: modSec,
                                        ownSize: 0,
                                        fileCount: 0
                                    )
                                )
                            }
                        } else if objType == fsobj_type_t(VREG.rawValue) {
                            // Cloud stub safety: never materialize dataless stubs; count 0 physical bytes
                            if isDataless {
                                continue
                            }

                            // Hardlink deduplication: if linkCount > 1, count inode only once
                            if linkCount > 1 && fileID != 0 {
                                if !seenHardlinkInodes.insert(fileID).inserted {
                                    continue
                                }
                            }

                            let physicalBytes = allocSize > 0 ? allocSize : totalSize
                            currentFrame.ownSize += physicalBytes
                            currentFrame.fileCount += 1
                            fileCount += 1
                            bytesVisited += physicalBytes

                            let cat = FileTypeClassifier.category(forExtension: extLower)
                            typeSize[cat.rawValue] += physicalBytes
                            typeCount[cat.rawValue] += 1

                            if physicalBytes >= largeFileMinSize {
                                let row = LargeFileInsertRow(
                                    dirId: currentFrame.id,
                                    name: nameStr,
                                    ext: extLower.isEmpty ? nil : extLower,
                                    fileType: cat.rawValue,
                                    size: physicalBytes,
                                    mtime: modSec
                                )
                                heaps[cat.rawValue].consider(row)
                            }
                        }
                    }
                }

                Darwin.close(fd)

                // Record current directory frame BEFORE any child package rows
                dirBatch.append(Self.makeDirInsertRow(from: currentFrame))
                if !childPkgRows.isEmpty {
                    dirBatch.append(contentsOf: childPkgRows)
                }
                if dirBatch.count >= 10_000 {
                    try db.insertDirsBatch(dirBatch)
                    dirBatch.removeAll(keepingCapacity: true)
                }

                // Push child directories onto stack
                for child in childDirFrames.reversed() {
                    workStack.append(child)
                }

                // Throttled progress callback (~10 Hz)
                let now = DispatchTime.now()
                if now.uptimeNanoseconds - lastProgressTick.uptimeNanoseconds >= 100_000_000 {
                    lastProgressTick = now
                    let fraction = min(0.99, Double(bytesVisited) / Double(usedEstimate))
                    let elapsed = Double(now.uptimeNanoseconds - startTick.uptimeNanoseconds) / 1_000_000_000.0
                    let eta: Int? = (fraction > 0.05 && elapsed > 0.5)
                        ? max(1, Int((elapsed / fraction) * (1.0 - fraction)))
                        : nil
                    onProgress(ScanProgress(
                        fraction: fraction,
                        filesScanned: fileCount,
                        currentPath: currentFrame.path,
                        etaSeconds: eta
                    ))
                }
            }

            if !dirBatch.isEmpty {
                try db.insertDirsBatch(dirBatch)
                dirBatch.removeAll(keepingCapacity: false)
            }

            let totalsPayload: [(type: FileTypeCategory, size: Int64, count: Int64)] =
                FileTypeCategory.allCases.map { cat in
                    (cat, typeSize[cat.rawValue], typeCount[cat.rawValue])
                }
            try db.writeFileTypeTotals(totalsPayload)

            var allLarge: [LargeFileInsertRow] = []
            for h in heaps {
                allLarge.append(contentsOf: h.items.sorted(by: >))
            }
            try db.writeLargeFiles(allLarge)

            try Aggregator.finalize(
                db: db,
                scanId: scanId,
                volume: volume,
                maxDepth: maxDepth,
                dirCount: dirCount,
                fileCount: fileCount,
                skippedCount: skippedCount
            )
        }

        // Move in-progress DB to completed URL
        let fm = FileManager.default
        if fm.fileExists(atPath: finalURL.path) {
            try? fm.removeItem(at: finalURL)
        }
        try fm.moveItem(at: inProgressURL, to: finalURL)
        didComplete = true

        let endNs = DispatchTime.now().uptimeNanoseconds
        let durationSec = Double(endNs - startNs) / 1_000_000_000.0

        onProgress(ScanProgress(
            fraction: 1.0,
            filesScanned: fileCount,
            currentPath: volume.url.path,
            etaSeconds: 0
        ))

        return Outcome(
            dbURL: finalURL,
            scanId: scanId,
            dirCount: dirCount,
            fileCount: fileCount,
            skippedCount: skippedCount,
            maxDepth: maxDepth,
            durationSeconds: durationSec
        )
    }

    /// Fast interior package summation using `getattrlistbulk` so `.app` and `.photoslibrary`
    /// leaf rows have accurate `own_size` and `file_count` without creating thousands of interior DB rows.
    private static func sumPackageContentsFast(
        at packagePath: String,
        rootDev: dev_t,
        seenHardlinks: inout Set<UInt64>
    ) -> (totalBytes: Int64, fileCount: Int64) {
        var totalBytes: Int64 = 0
        var totalFiles: Int64 = 0
        var stack: [String] = [packagePath]

        let bufSize = 32 * 1024
        let buf = UnsafeMutableRawPointer.allocate(byteCount: bufSize, alignment: 8)
        defer { buf.deallocate() }

        var attrList = attrlist()
        attrList.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        attrList.commonattr =
            attrgroup_t(bitPattern: Int32(bitPattern: UInt32(ATTR_CMN_RETURNED_ATTRS))) |
            attrgroup_t(ATTR_CMN_NAME) |
            attrgroup_t(ATTR_CMN_OBJTYPE) |
            attrgroup_t(ATTR_CMN_FLAGS) |
            attrgroup_t(ATTR_CMN_FILEID)
        attrList.fileattr = attrgroup_t(
            ATTR_FILE_LINKCOUNT |
            ATTR_FILE_TOTALSIZE |
            ATTR_FILE_ALLOCSIZE
        )

        while let dirPath = stack.popLast() {
            let fd = Darwin.open(dirPath, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
            if fd < 0 { continue }

            while true {
                let count = getattrlistbulk(fd, &attrList, buf, bufSize, 0)
                if count <= 0 { break }
                var cursor = UnsafeRawPointer(buf)
                for _ in 0..<count {
                    let len = Int(cursor.loadUnaligned(as: UInt32.self))
                    guard len > 0 else { break }
                    let next = cursor.advanced(by: len)

                    var field = cursor.advanced(by: 4)
                    let returned = field.loadUnaligned(as: attribute_set_t.self)
                    field = field.advanced(by: MemoryLayout<attribute_set_t>.size)

                    var nameStr = ""
                    if (returned.commonattr & attrgroup_t(ATTR_CMN_NAME)) != 0 {
                        let ref = field.loadUnaligned(as: attrreference_t.self)
                        let ptr = field.advanced(by: Int(ref.attr_dataoffset)).assumingMemoryBound(to: CChar.self)
                        nameStr = String(cString: ptr)
                        field = field.advanced(by: MemoryLayout<attrreference_t>.size)
                    }

                    var objType: fsobj_type_t = 0
                    if (returned.commonattr & attrgroup_t(ATTR_CMN_OBJTYPE)) != 0 {
                        objType = field.loadUnaligned(as: fsobj_type_t.self)
                        field = field.advanced(by: MemoryLayout<fsobj_type_t>.size)
                    }

                    var flags: UInt32 = 0
                    if (returned.commonattr & attrgroup_t(ATTR_CMN_FLAGS)) != 0 {
                        flags = field.loadUnaligned(as: UInt32.self)
                        field = field.advanced(by: MemoryLayout<UInt32>.size)
                    }

                    var fileID: UInt64 = 0
                    if (returned.commonattr & attrgroup_t(ATTR_CMN_FILEID)) != 0 {
                        fileID = field.loadUnaligned(as: UInt64.self)
                        field = field.advanced(by: MemoryLayout<UInt64>.size)
                    }

                    var linkCount: UInt32 = 1
                    if (returned.fileattr & attrgroup_t(ATTR_FILE_LINKCOUNT)) != 0 {
                        linkCount = field.loadUnaligned(as: UInt32.self)
                        field = field.advanced(by: MemoryLayout<UInt32>.size)
                    }

                    var totalSize: Int64 = 0
                    if (returned.fileattr & attrgroup_t(ATTR_FILE_TOTALSIZE)) != 0 {
                        totalSize = field.loadUnaligned(as: Int64.self)
                        field = field.advanced(by: MemoryLayout<Int64>.size)
                    }

                    var allocSize: Int64 = 0
                    if (returned.fileattr & attrgroup_t(ATTR_FILE_ALLOCSIZE)) != 0 {
                        allocSize = field.loadUnaligned(as: Int64.self)
                        field = field.advanced(by: MemoryLayout<Int64>.size)
                    }

                    cursor = next
                    if nameStr.isEmpty || nameStr == "." || nameStr == ".." { continue }

                    if objType == fsobj_type_t(VDIR.rawValue) {
                        stack.append("\(dirPath)/\(nameStr)")
                    } else if objType == fsobj_type_t(VREG.rawValue) {
                        if (flags & UInt32(SF_DATALESS)) != 0 { continue }
                        if linkCount > 1 && fileID != 0 {
                            if !seenHardlinks.insert(fileID).inserted { continue }
                        }
                        totalBytes += (allocSize > 0 ? allocSize : totalSize)
                        totalFiles += 1
                    }
                }
            }
            Darwin.close(fd)
        }
        return (totalBytes, totalFiles)
    }

    private static func makeDirInsertRow(from f: Frame) -> DirInsertRow {
        DirInsertRow(
            id: f.id,
            parentId: f.parentId,
            name: f.name,
            depth: f.depth,
            isHidden: f.isHidden,
            isPackage: f.isPackage,
            mtime: f.mtime,
            ownSize: f.ownSize,
            fileCount: f.fileCount
        )
    }

    private static func extractLowerExtension(from name: String) -> String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
        let after = name.index(after: dot)
        guard after < name.endIndex else { return "" }
        return String(name[after...]).lowercased()
    }

    // MARK: - Benchmark: FileManager.enumerator vs getattrlistbulk

    static func benchmarkEnumeratorVsBulkWalker(at rootURL: URL) -> BenchmarkComparison {
        // 1. Legacy FileManager.enumerator
        let t0 = DispatchTime.now().uptimeNanoseconds
        var enumFiles: Int64 = 0
        var enumBytes: Int64 = 0
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey]
        if let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants]
        ) {
            while let next = enumerator.nextObject() as? URL {
                if let vals = try? next.resourceValues(forKeys: Set(keys)), vals.isRegularFile == true {
                    enumFiles += 1
                    enumBytes += Int64(vals.totalFileAllocatedSize ?? vals.fileSize ?? 0)
                }
            }
        }
        let t1 = DispatchTime.now().uptimeNanoseconds
        let enumMs = Double(t1 - t0) / 1_000_000.0

        // 2. Upgraded getattrlistbulk walker
        let t2 = DispatchTime.now().uptimeNanoseconds
        var seen = Set<UInt64>()
        let bulkStats = sumPackageContentsFast(at: rootURL.path, rootDev: 0, seenHardlinks: &seen)
        let t3 = DispatchTime.now().uptimeNanoseconds
        let bulkMs = max(0.01, Double(t3 - t2) / 1_000_000.0)

        return BenchmarkComparison(
            enumeratorDurationMs: enumMs,
            bulkWalkerDurationMs: bulkMs,
            speedupFactor: enumMs / bulkMs,
            filesVisited: max(enumFiles, bulkStats.fileCount),
            totalBytesCounted: bulkStats.totalBytes
        )
    }
}
