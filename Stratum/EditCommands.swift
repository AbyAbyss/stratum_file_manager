import AppKit

/// Routes the Edit menu. ⌘C, ⌘V, ⌘X, ⌘A and ⌘Z mean one thing while typing in a text field and
/// another while browsing files, and each shortcut can belong to only one menu item, so that one
/// item decides here which meaning applies.
@MainActor
enum EditCommands {
    static let undo = Selector(("undo:"))
    static let redo = Selector(("redo:"))

    private static var isEditingText: Bool {
        NSApp.keyWindow?.firstResponder is NSText
    }

    /// Sends `textAction` to the text field being edited. With no text field in use, runs `files`,
    /// but only while the file browser is what the user is looking at.
    static func run(_ textAction: Selector, in appState: AppState, files: () -> Void = {}) {
        if isEditingText {
            NSApp.sendAction(textAction, to: nil, from: nil)
            return
        }
        let browserInFront = appState.screen == .browser
            && !appState.showCommandPalette
            && !appState.showWalkthrough
            && NSApp.keyWindow?.sheetParent == nil
        if browserInFront { files() }
    }
}
