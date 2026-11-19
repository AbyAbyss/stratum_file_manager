import XCTest
@testable import Stratum

final class Milestone1Tests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StratumTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }

    func testBulkDirectoryReaderAttributesAndTags() throws {
        let subFolder = tempDir.appendingPathComponent("Assets", isDirectory: true)
        try FileManager.default.createDirectory(at: subFolder, withIntermediateDirectories: false)
        try Data("hello".utf8).write(to: subFolder.appendingPathComponent("inside.txt"))

        let pdfFile = tempDir.appendingPathComponent("Brand Guidelines v4.pdf")
        let pdfBytes = Data(repeating: 0x41, count: 4096)
        try pdfBytes.write(to: pdfFile)

        let hiddenFile = tempDir.appendingPathComponent(".secret")
        try Data("hidden".utf8).write(to: hiddenFile)

        // Write Finder tags to pdfFile
        let tags = [FinderTag(name: "Client", colorIndex: 7), FinderTag(name: "Final", colorIndex: 2)]
        BulkDirectoryReader.writeFinderTags(tags, toPath: pdfFile.path)

        // Read with showHidden = false
        let visibleItems = BulkDirectoryReader.shared.readDirectorySync(
            at: tempDir,
            showHidden: false,
            sortField: .name,
            ascending: true
        )
        XCTAssertEqual(visibleItems.count, 2)
        XCTAssertEqual(visibleItems[0].name, "Assets")
        XCTAssertTrue(visibleItems[0].isFolderLike)
        XCTAssertEqual(visibleItems[0].childItemCount, 1)

        XCTAssertEqual(visibleItems[1].name, "Brand Guidelines v4.pdf")
        XCTAssertFalse(visibleItems[1].isFolderLike)
        XCTAssertGreaterThanOrEqual(visibleItems[1].size, 4096)
        XCTAssertEqual(visibleItems[1].kindCategory, .pdf)
        XCTAssertEqual(visibleItems[1].tags.map(\.name), ["Client", "Final"])

        // Read with showHidden = true
        let allItems = BulkDirectoryReader.shared.readDirectorySync(
            at: tempDir,
            showHidden: true,
            sortField: .name,
            ascending: true
        )
        XCTAssertEqual(allItems.count, 3)
    }

    func testNaturalSortOrdering() {
        XCTAssertTrue(BulkDirectoryReader.fastNaturalLessThan("Hero Shot 2.jpg", "Hero Shot 10.jpg"))
        XCTAssertFalse(BulkDirectoryReader.fastNaturalLessThan("Hero Shot 10.jpg", "Hero Shot 2.jpg"))
        XCTAssertTrue(BulkDirectoryReader.fastNaturalLessThan("a.txt", "B.txt"))
    }

    func testStreamingFirst200FastBatchUnder16ms() async throws {
        // Create 2,500 files using low-level POSIX open/close so setup is instant
        let basePath = tempDir.path
        for i in 0..<2500 {
            let p = "\(basePath)/File_\(i).txt"
            let fd = Darwin.open(p, O_CREAT | O_WRONLY, 0o644)
            if fd >= 0 { Darwin.close(fd) }
        }

        let start = DispatchTime.now()
        var firstBatchLatencyMs: Double = 0
        var firstBatchCount = 0
        var finalCount = 0

        let stream = BulkDirectoryReader.shared.streamDirectory(
            at: tempDir,
            showHidden: false,
            sortField: .name,
            ascending: true
        )

        for await batch in stream {
            if batch.isInitialFastBatch {
                let elapsedNs = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
                firstBatchLatencyMs = Double(elapsedNs) / 1_000_000.0
                firstBatchCount = batch.items.count
            }
            if batch.isComplete {
                finalCount = batch.items.count
            }
        }

        let totalElapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0
        print("First 200 items latency: \(String(format: "%.2f", firstBatchLatencyMs)) ms; Total 2500 items: \(String(format: "%.2f", totalElapsedMs)) ms")

        XCTAssertEqual(firstBatchCount, 200)
        XCTAssertEqual(finalCount, 2500)
        // Shared CI machines are several times slower and noisier than a Mac, so the strict
        // one-frame budget only applies locally; CI still catches a regression to "seconds".
        let budgetMs = ProcessInfo.processInfo.environment["CI"] != nil ? 100.0 : 16.0
        XCTAssertLessThan(firstBatchLatencyMs, budgetMs, "First 200 items must stream in <\(budgetMs)ms")
    }

    func testFSEventsCoalescing() throws {
        let exp = expectation(description: "Coalesced FSEvents notification")
        final class Counter: @unchecked Sendable {
            var count = 0
        }
        let counter = Counter()

        let watcher = DirectoryWatcher(debounceInterval: 0.150) {
            counter.count += 1
            if counter.count == 1 {
                exp.fulfill()
            }
        }
        watcher.watch(url: tempDir)

        // Burst-create 25 files rapidly
        for i in 0..<25 {
            let u = tempDir.appendingPathComponent("burst_\(i).txt")
            try Data("x".utf8).write(to: u)
        }

        wait(for: [exp], timeout: 3.0)
        watcher.stop()
        XCTAssertEqual(counter.count, 1, "25 rapid file writes should coalesce into a single callback")
    }
}
