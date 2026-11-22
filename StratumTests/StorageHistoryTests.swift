import XCTest
@testable import Stratum

@MainActor
final class StorageHistoryTests: XCTestCase {
    private func sample(day: String, at seconds: TimeInterval, root: String = "/home", used: Int64 = 100,
                        folders: [String: Int64] = [:], types: [Int: Int64] = [:]) -> StorageSample {
        StorageSample(day: day, date: Date(timeIntervalSince1970: seconds), rootPath: root, diskUsed: used,
                      diskFree: 0, scannedBytes: 0, folders: folders, types: types)
    }

    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("stratum-history-\(UUID().uuidString).json")
    }

    func testKeepsOneSamplePerDayAndFolder() {
        let history = StorageHistory(fileURL: tempFile())
        history.record(sample(day: "2026-11-20", at: 100, used: 10))
        history.record(sample(day: "2026-11-20", at: 200, used: 12))   // later scan the same day replaces
        history.record(sample(day: "2026-11-20", at: 150, used: 99))   // an older one does not
        history.record(sample(day: "2026-11-21", at: 300, used: 14))
        history.record(sample(day: "2026-11-21", at: 300, root: "/other", used: 1))

        XCTAssertEqual(history.samples(forRoot: "/home").map(\.diskUsed), [12, 14])
        XCTAssertEqual(history.samples(forRoot: "/other").count, 1)
    }

    func testDropsOldestBeyondTheCap() {
        let history = StorageHistory(fileURL: tempFile())
        for i in 0..<(StorageHistory.maxSamplesPerRoot + 3) {
            history.record(sample(day: "d\(i)", at: TimeInterval(i), used: Int64(i)))
        }
        let kept = history.samples(forRoot: "/home")
        XCTAssertEqual(kept.count, StorageHistory.maxSamplesPerRoot)
        XCTAssertEqual(kept.first?.diskUsed, 3)
    }

    func testFolderAndTypeChanges() {
        let before = sample(day: "a", at: 0, folders: ["Library": 100, "Library/Caches": 40, "Movies": 50, "Old": 30],
                            types: [0: 10, 2: 5])
        let now = sample(day: "b", at: 1, folders: ["Library": 160, "Library/Caches": 90, "Movies": 45, "New": 20],
                         types: [0: 10, 2: 25])

        let top = now.folderChanges(since: before)
        XCTAssertEqual(top.map(\.name), ["Library", "Old", "New", "Movies"])
        XCTAssertEqual(top.map(\.delta), [60, -30, 20, -5])

        let inside = now.folderChanges(since: before, parent: "Library")
        XCTAssertEqual(inside.map(\.name), ["Caches"])
        XCTAssertEqual(inside.first?.delta, 50)

        // Without a baseline there is nothing to compare: sizes only, biggest first.
        XCTAssertEqual(now.folderChanges(since: nil).map(\.name), ["Library", "Movies", "New"])
        XCTAssertTrue(now.folderChanges(since: nil).allSatisfy { $0.delta == 0 })

        let types = now.typeChanges(since: before)
        XCTAssertEqual(types.first?.type, .code)
        XCTAssertEqual(types.first?.delta, 20)
    }
}
