import AppKit

/// Receives "open this folder" requests from outside the app: Finder's right-click Quick Action,
/// `open -a Stratum ~/Projects`, or dropping a folder on the Dock icon. Requests that arrive
/// before the window exists (a cold launch) are queued until the app state is attached.
final class StratumAppDelegate: NSObject, NSApplicationDelegate {
    private weak var appState: AppState?
    private var pending: [URL] = []

    @MainActor
    func attach(_ state: AppState) {
        appState = state
        flush()
    }

    @MainActor
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        pending += filenames.map { URL(fileURLWithPath: $0) }
        flush()
        sender.reply(toOpenOrPrint: .success)
    }

    @MainActor
    private func flush() {
        guard let appState, !pending.isEmpty else { return }
        let urls = pending
        pending = []
        urls.forEach { appState.openFromOutside($0) }
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
    }
}
