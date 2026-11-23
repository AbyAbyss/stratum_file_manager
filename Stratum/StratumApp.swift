import SwiftUI
import AppKit

@main
struct StratumApp: App {
    @NSApplicationDelegateAdaptor(StratumAppDelegate.self) private var appDelegate
    @State private var registry = WindowRegistry.shared

    /// The window the user is working in; menu commands act on it.
    private var appState: AppState { registry.active }

    init() {
        UpdateController.shared.start()
    }

    var body: some Scene {
        WindowGroup(for: WindowSeed.self) { $seed in
            WindowRoot(seed: seed)
        } defaultValue: {
            WindowSeed()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1340, height: 840)
        .commands {
            CommandGroup(after: .appInfo) {
                if UpdateController.shared.isAvailable {
                    Button("Check for Updates…") {
                        UpdateController.shared.checkForUpdates()
                    }
                }
            }

            CommandGroup(replacing: .help) {
                Button("Welcome Tour") {
                    appState.startWalkthrough()
                }
            }

            CommandGroup(replacing: .newItem) {
                Button("New Tab") {
                    appState.addNewTab()
                }
                .keyboardShortcut("t", modifiers: [.command])

                Button("New Folder") {
                    appState.createNewFolder()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button("Open") {
                    appState.selectedItems.forEach { appState.openItem($0) }
                }
                .keyboardShortcut("o", modifiers: [.command])
                .disabled(appState.selectedItems.isEmpty)

                // Closes the tab, or the window when it is the last tab. Other windows stay open.
                Button(appState.tabs.count > 1 ? "Close Tab" : "Close Window") {
                    if appState.tabs.count > 1 {
                        appState.closeTab(appState.activeTabID)
                    } else {
                        NSApp.keyWindow?.performClose(nil)
                    }
                }
                .keyboardShortcut("w", modifiers: [.command])
            }

            // Must come after the group above: replacing .newItem discards anything added to it earlier.
            WindowCommands()

            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { appState.screen = .settings }
                    .keyboardShortcut(",", modifiers: [.command])
            }

            // Undo, Cut, Copy, Paste and Select All replace the system items rather than sit beside
            // them: a shortcut only ever fires the first item that has it, and the system items
            // know nothing about files. EditCommands sends each to the text field or to the files.
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    EditCommands.run(EditCommands.undo, in: appState) { appState.undoLastTrash() }
                }
                .keyboardShortcut("z", modifiers: [.command])

                Button("Redo") {
                    EditCommands.run(EditCommands.redo, in: appState)
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .pasteboard) {
                Button("Cut") {
                    EditCommands.run(#selector(NSText.cut(_:)), in: appState) { appState.cutSelectionToClipboard() }
                }
                .keyboardShortcut("x", modifiers: [.command])

                Button("Copy") {
                    EditCommands.run(#selector(NSText.copy(_:)), in: appState) { appState.copySelectionToClipboard() }
                }
                .keyboardShortcut("c", modifiers: [.command])

                Button("Paste") {
                    EditCommands.run(#selector(NSText.paste(_:)), in: appState) { appState.pasteIntoCurrentFolder(forceMove: false) }
                }
                .keyboardShortcut("v", modifiers: [.command])

                Button("Move Item Here") {
                    EditCommands.run(#selector(NSText.paste(_:)), in: appState) { appState.pasteIntoCurrentFolder(forceMove: true) }
                }
                .keyboardShortcut("v", modifiers: [.command, .option])

                Button("Select All") {
                    EditCommands.run(#selector(NSText.selectAll(_:)), in: appState) { appState.selectAllItems() }
                }
                .keyboardShortcut("a", modifiers: [.command])

                Divider()

                Button("Find") {
                    if appState.screen == .browser {
                        appState.showQuickFilter = true
                    } else {
                        appState.showCommandPalette = true
                    }
                }
                .keyboardShortcut("f", modifiers: [.command])

                Divider()

                Button("Duplicate") {
                    appState.duplicateSelection()
                }
                .keyboardShortcut("d", modifiers: [.command])
                .disabled(appState.selectedItems.isEmpty)

                Button("Compress Selected") {
                    appState.compressSelection()
                }
                .disabled(appState.selectedItems.isEmpty)

                Button("Batch Rename…") {
                    appState.showBatchRename = true
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(appState.selectedItems.isEmpty)

                Divider()

                Button("Move to Trash") {
                    appState.moveSelectionToTrash()
                }
                .keyboardShortcut(.delete, modifiers: [.command])
                .disabled(appState.selectedItems.isEmpty)
            }

            CommandMenu("View") {
                Button("as Icons") {
                    appState.viewMode = .grid
                }
                .keyboardShortcut("1", modifiers: [.command])

                Button("as List") {
                    appState.viewMode = .list
                }
                .keyboardShortcut("2", modifiers: [.command])

                Button("as Columns") {
                    appState.viewMode = .columns
                }
                .keyboardShortcut("3", modifiers: [.command])

                Divider()

                Button(appState.showSidebar ? "Hide Sidebar" : "Show Sidebar") {
                    appState.showSidebar.toggle()
                }
                .keyboardShortcut("s", modifiers: [.command, .control])

                Button(appState.isInspectorVisible ? "Hide Inspector" : "Show Inspector") {
                    appState.toggleInspector()
                }
                .keyboardShortcut("i", modifiers: [.command, .option])

                Button(appState.showHiddenFiles ? "Hide Hidden Files" : "Show Hidden Files") {
                    appState.showHiddenFiles.toggle()
                }
                .keyboardShortcut(".", modifiers: [.command, .shift])

                Button("Toggle Full Screen") {
                    NSApp.keyWindow?.toggleFullScreen(nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .control])

                Divider()

                Button("Quick Look") {
                    let urls = appState.selectedItems.map(\.url)
                    QuickLookCoordinator.shared.togglePreview(for: urls)
                }
                .keyboardShortcut("y", modifiers: [.command])
            }

            CommandMenu("Go") {
                Button("Back") {
                    appState.goBack()
                }
                .keyboardShortcut("[", modifiers: [.command])
                .disabled(!appState.canGoBack)

                Button("Forward") {
                    appState.goForward()
                }
                .keyboardShortcut("]", modifiers: [.command])
                .disabled(!appState.canGoForward)

                Button("Enclosing Folder") {
                    appState.goUp()
                }
                .keyboardShortcut(.upArrow, modifiers: [.command])

                Divider()

                Button("Command Palette…") {
                    appState.showCommandPalette.toggle()
                }
                .keyboardShortcut("k", modifiers: [.command])

                Button("Go to Folder…") {
                    appState.showGoToFolder = true
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])

                Divider()

                // Screens. ⌘1-3 are the view modes (as in Finder), so screens use ⌥⌘.
                Button("Browser") { appState.screen = .browser }
                    .keyboardShortcut("1", modifiers: [.command, .option])
                Button("Smart Organizer") { appState.screen = .organizer }
                    .keyboardShortcut("2", modifiers: [.command, .option])
                Button("Groups") { appState.screen = .groups }
                    .keyboardShortcut("3", modifiers: [.command, .option])
                Button("Storage Map") { appState.screen = .storage }
                    .keyboardShortcut("4", modifiers: [.command, .option])
                Button("Storage History") { appState.screen = .history }
                    .keyboardShortcut("5", modifiers: [.command, .option])
                Button("Settings") { appState.screen = .settings }

                Divider()

                Button("Copy Path") {
                    let paths = appState.selectedItems.isEmpty
                        ? appState.currentURL.path
                        : appState.selectedItems.map(\.id).joined(separator: "\n")
                    TerminalLauncher.copyPathToPasteboard(paths)
                    appState.showToast("Copied path to clipboard")
                }
                .keyboardShortcut("c", modifiers: [.command, .option])

                Button("Open in Terminal") {
                    let target = appState.selectedItems.first?.url ?? appState.currentURL
                    TerminalLauncher.openInTerminal(url: target)
                }
                .keyboardShortcut("t", modifiers: [.command, .option])
            }
        }
    }
}

/// One window's content. Each window owns its own `AppState`; the disk scan is shared.
struct WindowRoot: View {
    let seed: WindowSeed
    /// SwiftUI can hand a window a second default seed shortly after it opens. The window keeps
    /// the one it started with, or it would swap to a blank state mid-launch.
    @State private var firstSeed: WindowSeed?
    @State private var appearance = AppearanceManager.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let seed = firstSeed ?? seed
        let appState = WindowRegistry.shared.state(for: seed)
        MainWindowView(appState: appState, appearance: appearance)
            .frame(minWidth: WindowMetrics.minWidth, minHeight: WindowMetrics.minHeight)
            .onAppear {
                if firstSeed == nil { firstSeed = seed }
                WindowRegistry.shared.openWindow = { openWindow(value: $0) }
                // A folder passed at launch arrives before any window exists; open it now.
                StratumAppDelegate.shared?.flushPending()
            }
            .background(WindowAccessor(
                onFocus: { WindowRegistry.shared.activate(appState) },
                onClose: { WindowRegistry.shared.remove(seed) }
            ))
    }
}

/// File menu items for windows.
struct WindowCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(before: .newItem) {
            Button("New Window") {
                openWindow(value: WindowSeed(path: WindowRegistry.shared.active.currentURL.path))
            }
            .keyboardShortcut("n", modifiers: [.command])

            Button("Move Tab to New Window") {
                let state = WindowRegistry.shared.active
                guard state.tabs.count > 1, let tab = state.tabs.first(where: { $0.id == state.activeTabID }) else { return }
                openWindow(value: WindowSeed(path: tab.url.path))
                state.closeTab(tab.id)
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
            .disabled(WindowRegistry.shared.active.tabs.count < 2)
        }

        CommandGroup(before: .windowArrangement) {
            Button("Show Next Tab") { WindowRegistry.shared.active.selectAdjacentTab(offset: 1) }
                .keyboardShortcut(.tab, modifiers: [.control])
            Button("Show Previous Tab") { WindowRegistry.shared.active.selectAdjacentTab(offset: -1) }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
        }
    }
}

struct WindowAccessor: NSViewRepresentable {
    var onFocus: () -> Void = {}
    var onClose: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var tokens: [NSObjectProtocol] = []
        deinit { tokens.forEach(NotificationCenter.default.removeObserver) }
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.toolbar = nil

            let center = NotificationCenter.default
            context.coordinator.tokens = [
                center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { _ in
                    MainActor.assumeIsolated { onFocus() }
                },
                center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
                    MainActor.assumeIsolated { onClose() }
                }
            ]
            if window.isKeyWindow { onFocus() }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
