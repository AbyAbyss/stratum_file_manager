import SwiftUI
import AppKit

@MainActor
final class StratumContextMenuBuilder: NSObject {
    static let shared = StratumContextMenuBuilder()

    weak var currentAppState: AppState?
    private var contextTargetItems: [FileItem] = []
    private var contextDirectoryURL: URL?

    func populateMenu(
        _ menu: NSMenu,
        appState: AppState,
        targetItems: [FileItem],
        directoryURL: URL
    ) {
        menu.removeAllItems()
        self.currentAppState = appState
        self.contextTargetItems = targetItems
        self.contextDirectoryURL = directoryURL

        guard let first = targetItems.first else {
            populateBackgroundMenu(menu, appState: appState, directoryURL: directoryURL)
            return
        }

        let countSuffix = targetItems.count > 1 ? " (\(targetItems.count) items)" : ""

        // 1. Open & Open With
        menu.addItem(makeItem("Open\(countSuffix)", symbol: "arrow.up.right.square", action: #selector(ctxOpenSelected)))

        // Open With submenu
        let openWithMenu = NSMenu(title: "Open With")
        let appURLs = NSWorkspace.shared.urlsForApplications(toOpen: first.url)
        for appURL in appURLs.prefix(12) {
            let appName = appURL.deletingPathExtension().lastPathComponent
            let item = NSMenuItem(title: appName, action: #selector(ctxOpenWithApp(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = appURL
            let icon = NSWorkspace.shared.icon(forFile: appURL.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            openWithMenu.addItem(item)
        }
        if !openWithMenu.items.isEmpty {
            let openWithRoot = NSMenuItem(title: "Open With", action: nil, keyEquivalent: "")
            openWithRoot.image = NSImage(systemSymbolName: "arrow.up.forward.app", accessibilityDescription: nil)
            openWithRoot.submenu = openWithMenu
            menu.addItem(openWithRoot)
        }

        if first.isFolderLike {
            menu.addItem(makeItem("Open in New Tab", symbol: "plus.square.on.square", action: #selector(ctxOpenInNewTab)))
            menu.addItem(makeItem("Open in Smart Organizer", symbol: "wand.and.stars", action: #selector(ctxOpenInSmartOrganizer)))
            let pinned = appState.isPinned(first.url)
            menu.addItem(makeItem(pinned ? "Unpin from Sidebar" : "Pin to Sidebar Favorites", symbol: pinned ? "pin.slash" : "pin", action: #selector(ctxTogglePin)))
        }

        menu.addItem(makeItem("Quick Look", symbol: "eye", action: #selector(ctxQuickLook)))
        menu.addItem(makeItem(appState.isInspectorVisible ? "Hide Inspector" : "Show in Inspector", symbol: "info.circle", action: #selector(ctxToggleInspector)))

        menu.addItem(.separator())

        // 2. Edit & File Organization
        menu.addItem(makeItem("Cut (Move)\(countSuffix)", symbol: "scissors", action: #selector(ctxCutItems)))
        menu.addItem(makeItem("Copy\(countSuffix)", symbol: "doc.on.doc", action: #selector(ctxCopyItems)))
        if !appState.clipboardURLs.isEmpty {
            menu.addItem(makeItem("Paste into \(first.isFolderLike ? first.name : directoryURL.lastPathComponent)", symbol: "doc.on.clipboard", action: #selector(ctxPasteIntoContext)))
        }
        menu.addItem(makeItem("Duplicate\(countSuffix)", symbol: "plus.square.on.square", action: #selector(ctxDuplicateItems)))
        menu.addItem(makeItem("New Folder with Selection (\(targetItems.count))", symbol: "folder.badge.plus", action: #selector(ctxNewFolderWithSelection)))
        menu.addItem(makeItem(targetItems.count > 1 ? "Batch Rename (\(targetItems.count))…" : "Rename…", symbol: "pencil", action: #selector(ctxBatchRename)))
        menu.addItem(makeItem("Compress to ZIP\(countSuffix)", symbol: "archivebox", action: #selector(ctxCompressItems)))
        menu.addItem(makeItem("Park on Drop Shelf", symbol: "tray.and.arrow.down", action: #selector(ctxParkOnShelf)))

        menu.addItem(.separator())

        // 3. Tags Submenu
        let tagsMenu = NSMenu(title: "Tags")
        for preset in FinderTag.presets {
            let hasTag = first.tags.contains(where: { $0.name.caseInsensitiveCompare(preset.name) == .orderedSame })
            let tagItem = NSMenuItem(title: preset.name, action: #selector(ctxToggleTag(_:)), keyEquivalent: "")
            tagItem.target = self
            tagItem.representedObject = preset
            tagItem.image = preset.menuDotImage
            tagItem.state = hasTag ? .on : .off
            tagsMenu.addItem(tagItem)
        }
        if !first.tags.isEmpty {
            tagsMenu.addItem(.separator())
            let clearItem = NSMenuItem(title: "Clear All Tags", action: #selector(ctxClearAllTags), keyEquivalent: "")
            clearItem.target = self
            tagsMenu.addItem(clearItem)
        }
        let tagsRoot = NSMenuItem(title: "Tags", action: nil, keyEquivalent: "")
        tagsRoot.image = NSImage(systemSymbolName: "tag", accessibilityDescription: nil)
        tagsRoot.submenu = tagsMenu
        menu.addItem(tagsRoot)

        menu.addItem(.separator())

        // 4. Developer & Path Tools
        menu.addItem(makeItem("Copy Path", symbol: "link", action: #selector(ctxCopyPath)))
        menu.addItem(makeItem("Copy Filename", symbol: "textformat", action: #selector(ctxCopyFilename)))
        menu.addItem(makeItem("Copy Shell-Escaped Path", symbol: "terminal", action: #selector(ctxCopyEscapedPath)))
        menu.addItem(makeItem("Open in Terminal", symbol: "apple.terminal", action: #selector(ctxOpenInTerminal)))

        if first.isFolderLike {
            menu.addItem(makeItem("Scan Folder in Storage Map", symbol: "chart.pie", action: #selector(ctxScanInStorageMap)))
            menu.addItem(makeItem("Scan Folder for Dev Caches", symbol: "circle.grid.2x1", action: #selector(ctxScanInGroups)))
        } else {
            menu.addItem(makeItem("Copy SHA-256 Checksum", symbol: "number.square", action: #selector(ctxComputeSHA256)))
            menu.addItem(makeItem("Toggle Executable (chmod +x)", symbol: "bolt.horizontal.circle", action: #selector(ctxToggleExecutable)))
        }

        menu.addItem(makeItem("Share…", symbol: "square.and.arrow.up", action: #selector(ctxShare)))
        menu.addItem(makeItem("Reveal in macOS Finder", symbol: "macwindow", action: #selector(ctxRevealInFinder)))

        menu.addItem(.separator())

        // 5. Trash & Permanent Delete
        menu.addItem(makeItem("Move to Trash\(countSuffix)", symbol: "trash", action: #selector(ctxMoveToTrash)))
        menu.addItem(makeItem("Delete Immediately…", symbol: "trash.slash", action: #selector(ctxDeleteImmediately)))
    }

    private func populateBackgroundMenu(_ menu: NSMenu, appState: AppState, directoryURL: URL) {
        menu.addItem(makeItem("New Folder", symbol: "folder.badge.plus", action: #selector(ctxNewFolder)))

        let newFileMenu = NSMenu(title: "New File")
        newFileMenu.addItem(makeItem("Markdown Document (.md)", symbol: "doc.text", action: #selector(ctxNewMarkdownFile)))
        newFileMenu.addItem(makeItem("Plain Text (.txt)", symbol: "doc.plaintext", action: #selector(ctxNewTextFile)))
        newFileMenu.addItem(makeItem("Python Script (.py)", symbol: "chevron.left.forwardslash.chevron.right", action: #selector(ctxNewPythonFile)))
        newFileMenu.addItem(makeItem("Shell Script (.sh)", symbol: "terminal", action: #selector(ctxNewShellFile)))
        newFileMenu.addItem(makeItem("JSON Config (.json)", symbol: "curlybraces", action: #selector(ctxNewJSONFile)))
        newFileMenu.addItem(makeItem("Swift Source (.swift)", symbol: "swift", action: #selector(ctxNewSwiftFile)))
        let newFileRoot = NSMenuItem(title: "New File", action: nil, keyEquivalent: "")
        newFileRoot.image = NSImage(systemSymbolName: "doc.badge.plus", accessibilityDescription: nil)
        newFileRoot.submenu = newFileMenu
        menu.addItem(newFileRoot)

        menu.addItem(.separator())

        menu.addItem(makeItem("Paste", symbol: "doc.on.clipboard", action: #selector(ctxPasteHere)))
        if !appState.clipboardURLs.isEmpty {
            menu.addItem(makeItem("Move Copied Items Here", symbol: "arrow.right.doc.on.clipboard", action: #selector(ctxMoveHere)))
        }
        if !appState.shelfURLs.isEmpty {
            menu.addItem(makeItem("Drop \(appState.shelfURLs.count) Shelf Items Here", symbol: "tray.and.arrow.up", action: #selector(ctxDropShelfHere)))
        }

        menu.addItem(.separator())

        menu.addItem(makeItem("Select All", symbol: "checkmark.circle", action: #selector(ctxSelectAll)))

        // Sort submenu
        let sortMenu = NSMenu(title: "Sort By")
        for field in SortField.allCases {
            let item = NSMenuItem(title: field.rawValue, action: #selector(ctxSelectSortField(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = field.rawValue
            item.state = (appState.sortField == field) ? .on : .off
            sortMenu.addItem(item)
        }
        sortMenu.addItem(.separator())
        let ascItem = NSMenuItem(title: "Ascending", action: #selector(ctxToggleSortDirection), keyEquivalent: "")
        ascItem.target = self
        ascItem.state = appState.sortAscending ? .on : .off
        sortMenu.addItem(ascItem)
        let grpItem = NSMenuItem(title: "Group by Kind", action: #selector(ctxToggleGroupByKind), keyEquivalent: "")
        grpItem.target = self
        grpItem.state = appState.groupByKind ? .on : .off
        sortMenu.addItem(grpItem)

        let sortRoot = NSMenuItem(title: "Sort By", action: nil, keyEquivalent: "")
        sortRoot.image = NSImage(systemSymbolName: "arrow.up.arrow.down", accessibilityDescription: nil)
        sortRoot.submenu = sortMenu
        menu.addItem(sortRoot)

        menu.addItem(makeItem(appState.showHiddenFiles ? "Hide Hidden Files (⌘⇧.)" : "Show Hidden Files (⌘⇧.)", symbol: appState.showHiddenFiles ? "eye.slash" : "eye", action: #selector(ctxToggleHiddenFiles)))

        let pinned = appState.isPinned(directoryURL)
        menu.addItem(makeItem(pinned ? "Unpin Folder from Sidebar" : "Pin Folder to Sidebar Favorites", symbol: pinned ? "pin.slash" : "pin", action: #selector(ctxTogglePinFolderBg)))

        menu.addItem(.separator())

        menu.addItem(makeItem("Copy Folder Path", symbol: "link", action: #selector(ctxCopyCurrentFolderPath)))
        menu.addItem(makeItem("Open Folder in Terminal", symbol: "apple.terminal", action: #selector(ctxOpenCurrentInTerminal)))
        menu.addItem(makeItem("Scan Folder in Storage Map", symbol: "chart.pie", action: #selector(ctxScanCurrentInStorageMap)))
        menu.addItem(makeItem("Reveal Folder in Finder", symbol: "macwindow", action: #selector(ctxRevealCurrentInFinder)))
    }

    private func makeItem(_ title: String, symbol: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return item
    }

    // MARK: - Actions

    @objc private func ctxOpenSelected() {
        guard let appState = currentAppState else { return }
        for item in contextTargetItems {
            appState.openItem(item)
        }
    }

    @objc private func ctxOpenWithApp(_ sender: NSMenuItem) {
        guard let appURL = sender.representedObject as? URL else { return }
        let urls = contextTargetItems.map(\.url)
        NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
    }

    @objc private func ctxOpenInNewTab() {
        guard let appState = currentAppState, let first = contextTargetItems.first, first.isFolderLike else { return }
        appState.addNewTab(at: first.url)
    }

    @objc private func ctxOpenInSmartOrganizer() {
        guard let appState = currentAppState, let first = contextTargetItems.first else { return }
        appState.openInSmartOrganizer(first.url)
    }

    @objc private func ctxTogglePin() {
        guard let appState = currentAppState, let first = contextTargetItems.first, first.isFolderLike else { return }
        appState.togglePinFolder(first.url)
    }

    @objc private func ctxTogglePinFolderBg() {
        guard let appState = currentAppState, let dir = contextDirectoryURL else { return }
        appState.togglePinFolder(dir)
    }

    @objc private func ctxQuickLook() {
        QuickLookCoordinator.shared.togglePreview(for: contextTargetItems.map(\.url))
    }

    @objc private func ctxToggleInspector() {
        currentAppState?.toggleInspector()
    }

    @objc private func ctxCutItems() {
        guard let appState = currentAppState else { return }
        appState.selectedItemIDs = Set(contextTargetItems.map(\.id))
        appState.cutSelectionToClipboard()
    }

    @objc private func ctxCopyItems() {
        guard let appState = currentAppState else { return }
        appState.selectedItemIDs = Set(contextTargetItems.map(\.id))
        appState.copySelectionToClipboard()
    }

    @objc private func ctxPasteIntoContext() {
        guard let appState = currentAppState else { return }
        if let first = contextTargetItems.first, first.isFolderLike {
            appState.handleDroppedURLs(appState.clipboardURLs, into: first.url, isMove: appState.clipboardIsMove)
        } else {
            appState.pasteIntoCurrentFolder(forceMove: false)
        }
    }

    @objc private func ctxDuplicateItems() {
        guard let appState = currentAppState else { return }
        appState.selectedItemIDs = Set(contextTargetItems.map(\.id))
        appState.duplicateSelection()
    }

    @objc private func ctxNewFolderWithSelection() {
        guard let appState = currentAppState else { return }
        appState.selectedItemIDs = Set(contextTargetItems.map(\.id))
        appState.createNewFolderWithSelection()
    }

    @objc private func ctxBatchRename() {
        guard let appState = currentAppState else { return }
        appState.selectedItemIDs = Set(contextTargetItems.map(\.id))
        appState.showBatchRename = true
    }

    @objc private func ctxCompressItems() {
        guard let appState = currentAppState else { return }
        appState.selectedItemIDs = Set(contextTargetItems.map(\.id))
        appState.compressSelection()
    }

    @objc private func ctxParkOnShelf() {
        currentAppState?.addToShelf(contextTargetItems.map(\.url))
    }

    @objc private func ctxToggleTag(_ sender: NSMenuItem) {
        guard let appState = currentAppState, let tag = sender.representedObject as? FinderTag else { return }
        for item in contextTargetItems {
            appState.toggleTag(tag, on: item)
        }
    }

    @objc private func ctxClearAllTags() {
        guard let appState = currentAppState else { return }
        for item in contextTargetItems {
            appState.clearAllTags(on: item)
        }
    }

    @objc private func ctxCopyPath() {
        let paths = contextTargetItems.map(\.id).joined(separator: "\n")
        guard !paths.isEmpty else { return }
        TerminalLauncher.copyPathToPasteboard(paths)
        currentAppState?.showToast("Copied path to clipboard")
    }

    @objc private func ctxCopyFilename() {
        let names = contextTargetItems.map(\.name).joined(separator: "\n")
        guard !names.isEmpty else { return }
        TerminalLauncher.copyPathToPasteboard(names)
        currentAppState?.showToast("Copied filename to clipboard")
    }

    @objc private func ctxCopyEscapedPath() {
        let escaped = contextTargetItems.map { "'" + $0.id.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: " ")
        guard !escaped.isEmpty else { return }
        TerminalLauncher.copyPathToPasteboard(escaped)
        currentAppState?.showToast("Copied shell-escaped path")
    }

    @objc private func ctxOpenInTerminal() {
        if let first = contextTargetItems.first {
            TerminalLauncher.openInTerminal(url: first.url)
        } else if let dir = contextDirectoryURL {
            TerminalLauncher.openInTerminal(url: dir)
        }
    }

    @objc private func ctxScanInStorageMap() {
        guard let appState = currentAppState, let first = contextTargetItems.first else { return }
        appState.scanFolder(first.url, inScreen: .storage)
    }

    @objc private func ctxScanInGroups() {
        guard let appState = currentAppState, let first = contextTargetItems.first else { return }
        appState.scanFolder(first.url, inScreen: .groups)
    }

    @objc private func ctxComputeSHA256() {
        guard let appState = currentAppState, let first = contextTargetItems.first else { return }
        appState.computeSHA256(for: first.url)
    }

    @objc private func ctxToggleExecutable() {
        guard let appState = currentAppState, let first = contextTargetItems.first else { return }
        appState.toggleExecutableBit(for: first.url)
    }

    @objc private func ctxShare() {
        let urls = contextTargetItems.map(\.url)
        guard !urls.isEmpty, let window = NSApp.keyWindow, let contentView = window.contentView else { return }
        let picker = NSSharingServicePicker(items: urls)
        picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
    }

    @objc private func ctxRevealInFinder() {
        let urls = contextTargetItems.map(\.url)
        if !urls.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }
    }

    @objc private func ctxMoveToTrash() {
        guard let appState = currentAppState else { return }
        appState.moveURLsToTrash(contextTargetItems.map { (url: $0.url, size: $0.size) })
    }

    @objc private func ctxDeleteImmediately() {
        guard let appState = currentAppState else { return }
        appState.selectedItemIDs = Set(contextTargetItems.map(\.id))
        appState.deleteSelectionImmediately()
    }

    // Background Menu Actions

    @objc private func ctxNewFolder() {
        currentAppState?.createNewFolder()
    }

    @objc private func ctxNewMarkdownFile() {
        currentAppState?.createNewFile(baseName: "Untitled", ext: "md", contents: "# Untitled\n\n")
    }

    @objc private func ctxNewTextFile() {
        currentAppState?.createNewFile(baseName: "Untitled", ext: "txt", contents: "")
    }

    @objc private func ctxNewPythonFile() {
        currentAppState?.createNewFile(baseName: "script", ext: "py", contents: "#!/usr/bin/env python3\n\ndef main():\n    pass\n\nif __name__ == \"__main__\":\n    main()\n")
    }

    @objc private func ctxNewShellFile() {
        currentAppState?.createNewFile(baseName: "script", ext: "sh", contents: "#!/usr/bin/env zsh\nset -euo pipefail\n\n")
    }

    @objc private func ctxNewJSONFile() {
        currentAppState?.createNewFile(baseName: "config", ext: "json", contents: "{\n  \n}\n")
    }

    @objc private func ctxNewSwiftFile() {
        currentAppState?.createNewFile(baseName: "File", ext: "swift", contents: "import Foundation\n\n")
    }

    @objc private func ctxPasteHere() {
        currentAppState?.pasteIntoCurrentFolder(forceMove: false)
    }

    @objc private func ctxMoveHere() {
        currentAppState?.pasteIntoCurrentFolder(forceMove: true)
    }

    @objc private func ctxDropShelfHere() {
        guard let appState = currentAppState, let dir = contextDirectoryURL else { return }
        appState.dropAllShelfItems(into: dir)
    }

    @objc private func ctxSelectAll() {
        currentAppState?.selectAllItems()
    }

    @objc private func ctxSelectSortField(_ sender: NSMenuItem) {
        guard let appState = currentAppState,
              let raw = sender.representedObject as? String,
              let field = SortField(rawValue: raw) else { return }
        appState.sortField = field
    }

    @objc private func ctxToggleSortDirection() {
        currentAppState?.sortAscending.toggle()
    }

    @objc private func ctxToggleGroupByKind() {
        currentAppState?.groupByKind.toggle()
    }

    @objc private func ctxToggleHiddenFiles() {
        currentAppState?.showHiddenFiles.toggle()
    }

    @objc private func ctxCopyCurrentFolderPath() {
        guard let dir = contextDirectoryURL else { return }
        TerminalLauncher.copyPathToPasteboard(dir.path)
        currentAppState?.showToast("Copied folder path")
    }

    @objc private func ctxOpenCurrentInTerminal() {
        guard let dir = contextDirectoryURL else { return }
        TerminalLauncher.openInTerminal(url: dir)
    }

    @objc private func ctxScanCurrentInStorageMap() {
        guard let appState = currentAppState, let dir = contextDirectoryURL else { return }
        appState.scanFolder(dir, inScreen: .storage)
    }

    @objc private func ctxRevealCurrentInFinder() {
        guard let dir = contextDirectoryURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([dir])
    }
}
