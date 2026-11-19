import XCTest
@testable import Stratum

final class ProtectActiveProjectsTests: XCTestCase {
    private let now = Date()

    private func row(_ name: String, modifiedDaysAgo days: Double?) -> GroupInstanceRow {
        let dir = DirRow(
            id: Int64(abs(name.hashValue % 10_000)), parentId: nil, name: "node_modules", depth: 3,
            isHidden: false, isPackage: false,
            mtime: days.map { now.addingTimeInterval(-$0 * 86_400) },
            totalSize: 1_000, descendantFileCount: 10
        )
        return GroupInstanceRow(dirRow: dir, fullPath: "/p/\(name)/node_modules", parentProjectName: name)
    }

    func testFoldersOlderThanTheWindowAreCleanableAndNewerOnesAreKept() {
        let cutoff = now.addingTimeInterval(-14 * 86_400)
        let split = ScanCoordinator.splitByRecency(
            [row("old", modifiedDaysAgo: 90), row("fresh", modifiedDaysAgo: 2), row("edge", modifiedDaysAgo: 20)],
            cutoff: cutoff
        )
        XCTAssertEqual(split.stale.map(\.parentProjectName), ["old", "edge"])
        XCTAssertEqual(split.recent.map(\.parentProjectName), ["fresh"])
    }

    func testUnknownModificationDateIsTreatedAsRecent() {
        let split = ScanCoordinator.splitByRecency([row("mystery", modifiedDaysAgo: nil)], cutoff: now)
        XCTAssertTrue(split.stale.isEmpty)
        XCTAssertEqual(split.recent.count, 1)
    }

    func testPowerSourceCheckDoesNotCrash() {
        _ = PowerSource.isOnBattery
    }
}
