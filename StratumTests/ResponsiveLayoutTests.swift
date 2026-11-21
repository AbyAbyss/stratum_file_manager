import XCTest
@testable import Stratum

final class ResponsiveLayoutTests: XCTestCase {
    func testToolbarShedsControlsAsTheWindowNarrows() {
        XCTAssertEqual(ToolbarDensity(toolbarWidth: 1340), .full)
        XCTAssertEqual(ToolbarDensity(toolbarWidth: 1150), .regular)
        XCTAssertEqual(ToolbarDensity(toolbarWidth: 1000), .compact)
        XCTAssertEqual(ToolbarDensity(toolbarWidth: 720), .minimal)
        XCTAssertLessThan(ToolbarDensity.minimal, .full)
    }

    func testMinimumWindowFitsOneSidePanelBesideTheListing() {
        XCTAssertGreaterThanOrEqual(WindowMetrics.minWidth, WindowMetrics.sidebarMinWidth + WindowMetrics.browserListMinWidth)
        XCTAssertGreaterThanOrEqual(WindowMetrics.minWidth, WindowMetrics.inspectorMinWidth + WindowMetrics.browserListMinWidth)
    }
}
