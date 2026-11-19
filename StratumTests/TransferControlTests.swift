import XCTest
@testable import Stratum

final class TransferControlTests: XCTestCase {
    func testPausingAndResumingFlipsTheFlag() {
        let box = TransferControlBox()
        XCTAssertFalse(box.isPaused)
        box.setPaused(true)
        XCTAssertTrue(box.isPaused)
        box.setPaused(false)
        XCTAssertFalse(box.isPaused)
    }

    func testCancellingClearsPauseSoAPausedJobCanStop() {
        let box = TransferControlBox()
        box.setPaused(true)
        box.cancel()
        XCTAssertFalse(box.isPaused)
        XCTAssertTrue(box.isCancelled)
    }
}
