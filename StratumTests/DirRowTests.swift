import XCTest
@testable import Stratum

final class DirRowTests: XCTestCase {
    private func row(size: Int64) -> DirRow {
        DirRow(id: 7, parentId: 1, name: "Projects", depth: 2, isHidden: false, isPackage: false,
               mtime: nil, totalSize: size, descendantFileCount: 40)
    }

    func testRemovingBytesSubtractsFromTotalAndKeepsOtherFields() {
        let updated = row(size: 1_000).removingBytes(250)
        XCTAssertEqual(updated.totalSize, 750)
        XCTAssertEqual(updated.id, 7)
        XCTAssertEqual(updated.name, "Projects")
        XCTAssertEqual(updated.descendantFileCount, 40)
    }

    func testRemovingMoreThanTheTotalClampsAtZero() {
        XCTAssertEqual(row(size: 100).removingBytes(5_000).totalSize, 0)
    }
}
