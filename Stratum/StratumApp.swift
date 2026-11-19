import SwiftUI
import AppKit

@main
struct StratumApp: App {
    @State private var appState = AppState()
    @State private var appearance = AppearanceManager.shared

    var body: some Scene {
        WindowGroup {
            MainWindowView(appState: appState, appearance: appearance)
                .frame(minWidth: 980, minHeight: 640)
                .background(WindowAccessor())
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1340, height: 840)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") {
                    appState.addNewTab()
                }
                .keyboardShortcut("t", modifiers: [.command])

                Button("New Folder") {
                    appState.createNewFolder()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button("Close Tab") {
                    appState.closeTab(appState.activeTabID)
                }
                .keyboardShortcut("w", modifiers: [.command])
            }

            CommandGroup(replacing: .undoRedo) {
                Button("Undo Move to Trash") {
                    appState.undoLastTrash()
                }
                .keyboardShortcut("z", modifiers: [.command])
                .disabled(TransferQueueEngine.shared.trashHistory.isEmpty)
            }

            CommandGroup(after: .pasteboard) {
                Button("Copy Selected Items") {
                    appState.copySelectionToClipboard()
                }
                .keyboardShortcut("c", modifiers: [.command])
                .disabled(appState.selectedItems.isEmpty)

                Button("Paste Item") {
                    appState.pasteIntoCurrentFolder(forceMove: false)
                }
                .keyboardShortcut("v", modifiers: [.command])

                Button("Move Item Here") {
                    appState.pasteIntoCurrentFolder(forceMove: true)
                }
                .keyboardShortcut("v", modifiers: [.command, .option])

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

                Button(appState.showInspector ? "Hide Inspector" : "Show Inspector") {
                    appState.showInspector.toggle()
                }
                .keyboardShortcut("i", modifiers: [.command, .option])

                Button(appState.showHiddenFiles ? "Hide Hidden Files" : "Show Hidden Files") {
                    appState.showHiddenFiles.toggle()
                }
                .keyboardShortcut(".", modifiers: [.command, .shift])

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

struct WindowAccessor: NSViewRepresentable {
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
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
