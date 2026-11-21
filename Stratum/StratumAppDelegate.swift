import AppKit
import SwiftUI

/// Receives "open this folder" requests from outside the app: Finder's right-click Quick Action,
/// `open -a Stratum ~/Projects`, or dropping a folder on the Dock icon.
///
/// Stratum is a single-instance app. If a second copy is started anyway (for example `open -n`),
/// it hands its folders to the copy that is already running and quits, so there is only ever one
/// Dock icon, and the running copy opens a window on the requested folder.
@MainActor
final class StratumAppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: StratumAppDelegate?
    private static let handoffName = Notification.Name("app.stratum.filemanager.openFolders")

    private var pending: [URL] = []
    private var isDuplicate = false
    private let launchDate = Date()

    override init() {
        super.init()
        Self.shared = self
        DistributedNotificationCenter.default().addObserver(
            forName: Self.handoffName, object: nil, queue: .main
        ) { [weak self] note in
            let paths = note.userInfo?["paths"] as? [String] ?? []
            MainActor.assumeIsolated {
                self?.pending += paths.map { URL(fileURLWithPath: $0) }
                self?.flushPending()
            }
        }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // The test runner launches the app as its host; that must not hand off to a real copy.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              let id = Bundle.main.bundleIdentifier else { return }
        let me = ProcessInfo.processInfo.processIdentifier
        if let other = NSRunningApplication.runningApplications(withBundleIdentifier: id).first(where: { $0.processIdentifier != me }) {
            isDuplicate = true
            other.activate()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Folders passed at launch arrive just before this; give them a moment to be handed off.
        guard isDuplicate else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        if isDuplicate {
            DistributedNotificationCenter.default().postNotificationName(
                Self.handoffName, object: nil, userInfo: ["paths": filenames], deliverImmediately: true
            )
        } else {
            pending += filenames.map { URL(fileURLWithPath: $0) }
            flushPending()
        }
        sender.reply(toOpenOrPrint: .success)
    }

    func flushPending() {
        guard !isDuplicate, !pending.isEmpty, WindowRegistry.shared.windowCount > 0 else { return }
        let urls = pending
        pending = []
        // While starting up, the folder goes into the first window; afterwards it gets a window of its own.
        let isStartingUp = Date().timeIntervalSince(launchDate) < 3
        for url in urls {
            if !isStartingUp, let open = WindowRegistry.shared.openWindow {
                open(WindowSeed(path: Self.folder(of: url).path))
            } else {
                WindowRegistry.shared.active.openFromOutside(url)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func folder(of url: URL) -> URL {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return exists && !isDir.boolValue ? url.deletingLastPathComponent() : url
    }
}
