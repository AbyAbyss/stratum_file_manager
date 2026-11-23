import AppKit

/// What the grid, list and column views need from their coordinators to handle keys.
@MainActor
protocol BrowserKeyTarget: AnyObject {
    var appState: AppState { get }
}

@MainActor
enum BrowserKeys {
    /// The keys all three browser views share. Returns true when the key was used.
    static func handle(_ event: NSEvent, appState: AppState) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])

        // Spacebar -> Quick Look
        if event.keyCode == 49 && flags.isEmpty {
            QuickLookCoordinator.shared.togglePreview(for: appState.selectedItems.map(\.url))
            return true
        }
        // Return (36) or Cmd+Down (125) -> Open selected
        if (event.keyCode == 36 && flags.isEmpty) || (event.keyCode == 125 && flags == .command) {
            if let first = appState.selectedItems.first {
                appState.openItem(first)
            }
            return true
        }
        // Cmd+Up (126) -> Go to parent folder
        if event.keyCode == 126 && flags == .command {
            appState.goUp()
            return true
        }
        // Cmd+Delete (51) -> Move to Trash
        if event.keyCode == 51 && flags == .command {
            appState.moveSelectionToTrash()
            return true
        }
        // "/" -> Quick filter bar
        if event.charactersIgnoringModifiers == "/" && flags.isEmpty {
            appState.showQuickFilter = true
            return true
        }
        // Escape (53) -> Clear the selection
        if event.keyCode == 53 && flags.isEmpty && !appState.selectedItemIDs.isEmpty {
            appState.selectedItemIDs = []
            return true
        }
        return false
    }

    /// Gives the keyboard to `view` when nothing else in its window has it, so arrow keys work in
    /// the file list without clicking it first.
    static func claimFocusIfUnused(_ view: NSView) {
        DispatchQueue.main.async { [weak view] in
            guard let view, let window = view.window, window.firstResponder === window else { return }
            window.makeFirstResponder(view)
        }
    }

    /// Hands the keyboard back to the file list, for example after typing in the filter field.
    static func focusFileList(in window: NSWindow?) {
        guard let window, let root = window.contentView,
              let list = root.firstDescendant(where: { $0 is KeyHandlingTableView || $0 is KeyHandlingCollectionView }) else { return }
        window.makeFirstResponder(list)
    }
}

extension NSView {
    func firstDescendant(where matches: (NSView) -> Bool) -> NSView? {
        for sub in subviews {
            if matches(sub) { return sub }
            if let found = sub.firstDescendant(where: matches) { return found }
        }
        return nil
    }
}

/// Typing a name selects the first item that starts with it. Letters typed within a second of
/// each other add up to one prefix.
@MainActor
struct TypeSelectBuffer {
    private var typed = ""
    private var lastKey = Date.distantPast

    /// The prefix to look for after this key, or nil when the key is not typing (arrows, shortcuts).
    mutating func prefix(adding event: NSEvent) -> String? {
        let flags = event.modifierFlags.intersection([.command, .option, .control])
        guard flags.isEmpty, let chars = event.characters, let scalar = chars.unicodeScalars.first,
              scalar.value >= 0x20, scalar.value != 0x7F, !(0xF700...0xF8FF).contains(scalar.value) else { return nil }
        let now = Date()
        if now.timeIntervalSince(lastKey) > 1 { typed = "" }
        lastKey = now
        typed += chars.lowercased()
        return typed
    }
}
