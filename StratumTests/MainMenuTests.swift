import XCTest
import AppKit
@testable import Stratum

/// The tests run inside the app, so `NSApp.mainMenu` is the real menu bar.
@MainActor
final class MainMenuTests: XCTestCase {
    private struct Entry {
        let path: String
        let shortcut: String
    }

    private func entries(in menu: NSMenu, prefix: String = "") -> [Entry] {
        menu.items.flatMap { item -> [Entry] in
            let path = prefix + item.title
            var found: [Entry] = []
            if !item.keyEquivalent.isEmpty {
                let mods = item.keyEquivalentModifierMask.intersection([.command, .shift, .option, .control])
                var name = ""
                if mods.contains(.control) { name += "⌃" }
                if mods.contains(.option) { name += "⌥" }
                if mods.contains(.shift) { name += "⇧" }
                if mods.contains(.command) { name += "⌘" }
                found.append(Entry(path: path, shortcut: name + item.keyEquivalent))
            }
            if let submenu = item.submenu {
                found += entries(in: submenu, prefix: path + " > ")
            }
            return found
        }
    }

    /// Two menu items sharing a shortcut means only the first ever fires.
    func testNoTwoMenuItemsShareAShortcut() throws {
        let all = entries(in: try XCTUnwrap(NSApp.mainMenu))
        let clashes = Dictionary(grouping: all, by: \.shortcut).filter { $0.value.count > 1 }
        let report = clashes.map { "\($0.key): " + $0.value.map(\.path).joined(separator: " | ") }.sorted()
        XCTAssertTrue(clashes.isEmpty, "Shortcuts used twice:\n" + report.joined(separator: "\n"))
    }

    /// ⌘C and ⌘V once did nothing for files: the system Copy and Paste items held the shortcuts
    /// and only know about text. Stratum's own items must own them, and every basic must exist.
    func testEditShortcutsBelongToStratum() throws {
        let menu = try XCTUnwrap(NSApp.mainMenu)
        let systemActions: Set<Selector> = [
            #selector(NSText.cut(_:)), #selector(NSText.copy(_:)), #selector(NSText.paste(_:)),
            #selector(NSText.selectAll(_:)), Selector(("undo:")), Selector(("redo:"))
        ]
        func items(in menu: NSMenu) -> [NSMenuItem] {
            menu.items.flatMap { [$0] + ($0.submenu.map(items(in:)) ?? []) }
        }
        let system = items(in: menu).filter { $0.action.map(systemActions.contains) ?? false }
        XCTAssertEqual(system.map(\.title), [], "System text-only items are back in the menu")

        let shortcuts = Set(entries(in: menu).map(\.shortcut))
        for needed in ["⌘x", "⌘c", "⌘v", "⌘a", "⌘z", "⇧⌘z", "⌘f", "⌘o", "⌘,", "⌘w", "⌘t", "⌘n", "⌘q", "⌘m"] {
            XCTAssertTrue(shortcuts.contains(needed), "No menu item for \(needed)")
        }
    }

    /// Presses ⌘A through the real menu bar and checks that it reaches the file list.
    func testSelectAllShortcutSelectsEveryFile() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("menu-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["a.txt", "b.txt", "c.txt"] {
            try Data().write(to: dir.appendingPathComponent(name))
        }

        let state = WindowRegistry.shared.active
        let (oldURL, oldTour) = (state.currentURL, state.showWalkthrough)
        defer {
            state.showWalkthrough = oldTour
            state.navigate(to: oldURL)
        }
        state.showWalkthrough = false
        state.navigate(to: dir)
        for _ in 0..<100 where state.displayedItems.count != 3 {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(state.displayedItems.count, 3)

        let key = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0,
            context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0
        ))
        XCTAssertTrue(try XCTUnwrap(NSApp.mainMenu).performKeyEquivalent(with: key))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(state.selectedItemIDs.count, 3)
    }
}
