import XCTest
import Darwin
@testable import Stratum

final class ScanEngineTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("StratumScanTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        tempRoot = base
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
    }

    func testPackageSizingHardlinkDedupeAndNestedGroups() async throws {
        let fm = FileManager.default

        // 1. Create a fake .app package with interior files (fixes wimys_crumb Bug #1 where packages had 0 size)
        let appDir = tempRoot.appendingPathComponent("SampleApp.app/Contents/MacOS", isDirectory: true)
        try fm.createDirectory(at: appDir, withIntermediateDirectories: true)
        let appBinary = appDir.appendingPathComponent("SampleApp")
        let appPayload = Data(repeating: 0x5A, count: 128 * 1024)
        try appPayload.write(to: appBinary)

        // 2. Create a file and a hardlink to it (verifies hardlink inode deduplication)
        let hardlinkDir = tempRoot.appendingPathComponent("Hardlinks", isDirectory: true)
        try fm.createDirectory(at: hardlinkDir, withIntermediateDirectories: true)
        let origFile = hardlinkDir.appendingPathComponent("original.bin")
        let linkFile = hardlinkDir.appendingPathComponent("linked.bin")
        let linkPayload = Data(repeating: 0x33, count: 256 * 1024)
        try linkPayload.write(to: origFile)
        let linkRc = Darwin.link(origFile.path, linkFile.path)
        XCTAssertEqual(linkRc, 0)

        // 3. Create nested node_modules 2 and 3 levels deep (fixes wimys_crumb Bug #2)
        let outerNM = tempRoot.appendingPathComponent("Storefront/node_modules", isDirectory: true)
        let nestedNM2 = outerNM.appendingPathComponent("pkg-a/node_modules", isDirectory: true)
        let nestedNM3 = outerNM.appendingPathComponent("scope/pkg-b/node_modules", isDirectory: true)
        try fm.createDirectory(at: nestedNM2, withIntermediateDirectories: true)
        try fm.createDirectory(at: nestedNM3, withIntermediateDirectories: true)

        try Data(repeating: 0x11, count: 64 * 1024).write(to: outerNM.appendingPathComponent("index.js"))
        try Data(repeating: 0x22, count: 64 * 1024).write(to: nestedNM2.appendingPathComponent("dep2.js"))
        try Data(repeating: 0x44, count: 64 * 1024).write(to: nestedNM3.appendingPathComponent("dep3.js"))

        // Run ScanEngine on tempRoot
        let vol = VolumeInfo(
            id: "test-vol-\(UUID().uuidString)",
            name: "TestVol",
            totalCapacity: 100_000_000,
            availableCapacity: 50_000_000,
            url: tempRoot
        )
        let store = ScanStore()
        let outcome = try await ScanEngine.scan(volume: vol, store: store) { _ in }
        defer {
            for suffix in ["", "-shm", "-wal"] {
                try? fm.removeItem(atPath: outcome.dbURL.path + suffix)
            }
        }

        let db = try ScanDatabase(url: outcome.dbURL)
        let rootId = try XCTUnwrap(try db.rootDirId())
        let topChildren = try db.children(of: rootId)

        // Verify SampleApp.app is a single leaf package row with non-zero totalSize >= 128 KB
        let appRow = try XCTUnwrap(topChildren.first(where: { $0.name == "SampleApp.app" }))
        XCTAssertTrue(appRow.isPackage)
        XCTAssertGreaterThanOrEqual(appRow.totalSize, 128 * 1024)
        let appSubdirs = try db.children(of: appRow.id)
        XCTAssertTrue(appSubdirs.isEmpty, "Package interior directories should not pollute dirs table")

        // Verify Hardlinks directory did not double-count the 256 KB hardlinked inode
        let hlRow = try XCTUnwrap(topChildren.first(where: { $0.name == "Hardlinks" }))
        XCTAssertEqual(hlRow.descendantFileCount, 1, "Hardlinked inode should be counted once")
        XCTAssertLessThan(hlRow.totalSize, 400 * 1024, "Hardlinked file bytes must not be doubled")

        // Verify nested node_modules (2 and 3 levels deep) are excluded from groupAggregates and dirsWithName
        let groups = try db.groupAggregates()
        let nmGroup = try XCTUnwrap(groups.first(where: { $0.name == "node_modules" }))
        XCTAssertEqual(nmGroup.count, 1, "Nested node_modules at depth +2 and +3 must be excluded")

        let nmInstances = try db.dirsWithName("node_modules")
        XCTAssertEqual(nmInstances.count, 1)

        // Verify patchAfterDelete subtracts deleted group size up the ancestor chain
        let resolver = PathResolver(db: db, rootPathPrefix: tempRoot.path)
        let nmPath = resolver.fullPath(of: nmInstances[0].id)
        let rootBefore = try XCTUnwrap(try db.dirRow(id: rootId)).totalSize

        let delTarget = DeleteTarget(
            dirId: nmInstances[0].id,
            fileName: nil,
            path: nmPath,
            size: nmInstances[0].totalSize,
            mtime: nmInstances[0].mtime,
            isProtected: false
        )
        try db.patchAfterDelete(targets: [delTarget], removedPaths: [nmPath])

        let rootAfter = try XCTUnwrap(try db.dirRow(id: rootId)).totalSize
        XCTAssertEqual(rootAfter, max(0, rootBefore - nmInstances[0].totalSize))
    }

    func testBenchmarkEnumeratorVsGetattrlistbulkWalker() throws {
        let fm = FileManager.default
        let benchDir = tempRoot.appendingPathComponent("BenchmarkTree", isDirectory: true)
        try fm.createDirectory(at: benchDir, withIntermediateDirectories: true)

        let payload = Data(repeating: 0xAA, count: 512)
        for folderIdx in 0..<20 {
            let sub = benchDir.appendingPathComponent("module_\(folderIdx)", isDirectory: true)
            try fm.createDirectory(at: sub, withIntermediateDirectories: true)
            for fileIdx in 0..<60 {
                try payload.write(to: sub.appendingPathComponent("file_\(fileIdx).swift"))
            }
        }

        let cmp = ScanEngine.benchmarkEnumeratorVsBulkWalker(at: benchDir)
        print(String(
            format: "[Benchmark] FileManager.enumerator: %.2f ms vs getattrlistbulk: %.2f ms (%.2fx speedup, %lld files)",
            cmp.enumeratorDurationMs,
            cmp.bulkWalkerDurationMs,
            cmp.speedupFactor,
            cmp.filesVisited
        ))

        XCTAssertEqual(cmp.filesVisited, 1200)
        XCTAssertLessThan(cmp.bulkWalkerDurationMs, cmp.enumeratorDurationMs)
    }
}
