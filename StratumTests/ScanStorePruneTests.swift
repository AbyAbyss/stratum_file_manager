import XCTest
@testable import Stratum

final class ScanStorePruneTests: XCTestCase {
    func testKeepsNewestSnapshotsPerVolumeAndDropsStraySidecars() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("stratum-prune-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let names = [
            "VOL-A-100.sqlite", "VOL-A-200.sqlite", "VOL-A-300.sqlite", "VOL-A-100.sqlite-wal",
            "VOL-B-50.sqlite", "VOL-B-50.sqlite-shm",
            "gone-7.sqlite-shm", "in-progress-900.sqlite",
        ]
        for name in names { try Data().write(to: root.appendingPathComponent(name)) }

        ScanStore(root: root, legacyWimysRoot: root.appendingPathComponent("none")).pruneOldSnapshots(keepPerVolume: 2)

        let left = Set(try fm.contentsOfDirectory(atPath: root.path))
        XCTAssertEqual(left, ["VOL-A-200.sqlite", "VOL-A-300.sqlite", "VOL-B-50.sqlite", "VOL-B-50.sqlite-shm", "in-progress-900.sqlite"])
    }
}
