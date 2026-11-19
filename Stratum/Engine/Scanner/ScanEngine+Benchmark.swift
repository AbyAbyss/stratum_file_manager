import Foundation
import Darwin

extension ScanEngine {
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
