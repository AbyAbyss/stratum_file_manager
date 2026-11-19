import AppKit

/// Receives "open this folder" requests from outside the app: Finder's right-click Quick Action,
/// `open -a Stratum ~/Projects`, or dropping a folder on the Dock icon. They go to the window the
/// user is in; requests that arrive before any window exists (a cold launch) wait for one.
final class StratumAppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static weak var shared: StratumAppDelegate?
    private var pending: [URL] = []

    @MainActor
    override init() {
        super.init()
        Self.shared = self
    }

    @MainActor
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        pending += filenames.map { URL(fileURLWithPath: $0) }
        flushPending()
        sender.reply(toOpenOrPrint: .success)
    }

    @MainActor
    func flushPending() {
        guard !pending.isEmpty, WindowRegistry.shared.windowCount > 0 else { return }
        let urls = pending
        pending = []
        urls.forEach { WindowRegistry.shared.active.openFromOutside($0) }
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
    }
}
