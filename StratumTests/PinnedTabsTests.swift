import XCTest
@testable import Stratum

final class PinnedTabsTests: XCTestCase {
    private func tab(_ name: String, pinned: Bool) -> BrowserTab {
        let url = URL(fileURLWithPath: "/tmp/\(name)", isDirectory: true)
        return BrowserTab(id: UUID(), url: url, history: [], historyIndex: 0, selectedIDs: [], isPinned: pinned)
    }

    func testPinnedTabsMoveToTheFrontAndKeepTheirOrder() {
        let tabs = [tab("a", pinned: false), tab("b", pinned: true), tab("c", pinned: false), tab("d", pinned: true)]
        XCTAssertEqual(BrowserTab.pinnedFirst(tabs).map(\.title), ["b", "d", "a", "c"])
    }

    func testOrderingWithNothingPinnedChangesNothing() {
        let tabs = [tab("a", pinned: false), tab("b", pinned: false)]
        XCTAssertEqual(BrowserTab.pinnedFirst(tabs).map(\.title), ["a", "b"])
    }

    func testTabsAreUnpinnedByDefault() {
        let t = BrowserTab(id: UUID(), url: URL(fileURLWithPath: "/tmp"), history: [], historyIndex: 0, selectedIDs: [])
        XCTAssertFalse(t.isPinned)
    }
}

final class FinderIntegrationTests: XCTestCase {
    func testInstallAndUninstallRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("svc-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let integration = FinderIntegration(servicesDirectory: dir, bundleIdentifier: "app.test")
        XCTAssertFalse(integration.isInstalled)
        try integration.install()
        XCTAssertTrue(integration.isInstalled)
        let wflow = try String(contentsOf: integration.workflowURL.appendingPathComponent("Contents/document.wflow"), encoding: .utf8)
        XCTAssertTrue(wflow.contains("open -b \"app.test\""))
        XCTAssertTrue(wflow.contains("rm -rf \"\(integration.workflowURL.path)\""), "removes itself when the app is gone")
        try integration.uninstall()
        XCTAssertFalse(integration.isInstalled)
    }
}

@MainActor
final class WindowRegistryTests: XCTestCase {
    func testEachWindowGetsItsOwnStateAndTheSameWindowKeepsIt() {
        let registry = WindowRegistry.shared
        let a = WindowSeed(), b = WindowSeed(path: NSTemporaryDirectory())
        let stateA = registry.state(for: a), stateB = registry.state(for: b)
        XCTAssertFalse(stateA === stateB)
        XCTAssertTrue(registry.state(for: a) === stateA)
        XCTAssertFalse(stateB.isPrimaryWindow)
        registry.remove(a); registry.remove(b)
    }
}

@MainActor
final class ThemeModeTests: XCTestCase {
    private let themes = AppearanceManager.builtInThemes

    func testLightOverADarkThemeSwitchesToALightTheme() throws {
        let match = try XCTUnwrap(AppearanceManager.themeToSwitchTo(for: .light, activeID: "cyberpunk-matrix", themes: themes, systemIsDark: true))
        XCTAssertEqual(match.mode, .light)
    }

    func testDarkOverALightThemeSwitchesToADarkTheme() throws {
        let match = try XCTUnwrap(AppearanceManager.themeToSwitchTo(for: .dark, activeID: "paper-white", themes: themes, systemIsDark: false))
        XCTAssertNotEqual(match.mode, .light)
    }

    func testMatchingThemeIsKept() {
        XCTAssertNil(AppearanceManager.themeToSwitchTo(for: .light, activeID: "paper-white", themes: themes, systemIsDark: true))
        XCTAssertNil(AppearanceManager.themeToSwitchTo(for: .system, activeID: "paper-white", themes: themes, systemIsDark: false))
    }
}
