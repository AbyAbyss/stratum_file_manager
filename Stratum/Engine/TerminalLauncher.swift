import AppKit
import Quartz

enum TerminalLauncher {
    static let candidateBundleIDs: [(name: String, bundleID: String)] = [
        ("Ghostty", "com.mitchellh.ghostty"),
        ("iTerm", "com.googlecode.iterm2"),
        ("Warp", "dev.warp.Warp-Stable"),
        ("Terminal", "com.apple.Terminal")
    ]

    @MainActor
    static func openInTerminal(url: URL) {
        let dirURL: URL
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue {
            dirURL = url.deletingLastPathComponent()
        } else {
            dirURL = url
        }

        let preferredBundleID = UserDefaults.standard.string(forKey: "stratum.preferredTerminal") ?? "com.apple.Terminal"
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: preferredBundleID) {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([dirURL], withApplicationAt: appURL, configuration: config)
            return
        }

        if let fallbackURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([dirURL], withApplicationAt: fallbackURL, configuration: config)
        }
    }

    @MainActor
    static func copyPathToPasteboard(_ path: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(path, forType: .string)
    }
}

@MainActor
final class QuickLookCoordinator: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookCoordinator()

    var urls: [URL] = []

    func togglePreview(for urls: [URL]) {
        guard !urls.isEmpty else { return }
        self.urls = urls
        guard let panel = QLPreviewPanel.shared() else { return }
        if QLPreviewPanel.sharedPreviewPanelExists() && panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.dataSource = self
            panel.delegate = self
            panel.makeKeyAndOrderFront(nil)
            panel.reloadData()
        }
    }

    func updateIfVisible(with urls: [URL]) {
        guard !urls.isEmpty else { return }
        self.urls = urls
        if QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared(), panel.isVisible {
            panel.dataSource = self
            panel.reloadData()
        }
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated {
            urls.count
        }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        MainActor.assumeIsolated {
            guard urls.indices.contains(index) else { return nil }
            return urls[index] as NSURL
        }
    }
}
