import SwiftUI
import AppKit
import QuickLookThumbnailing

struct FastListView: NSViewRepresentable {
    var appState: AppState
    var appearance: AppearanceManager

    func makeCoordinator() -> Coordinator {
        Coordinator(appState: appState)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let tableView = KeyHandlingTableView()
        tableView.coordinator = context.coordinator
        tableView.style = .plain
        tableView.backgroundColor = .clear
        tableView.headerView = NSTableHeaderView()
        tableView.rowHeight = appearance.density.rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.allowsMultipleSelection = true
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.selectionHighlightStyle = .regular
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        tableView.registerForDraggedTypes([.fileURL])
        tableView.setDraggingSourceOperationMask([.copy, .move], forLocal: false)

        let nameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Name"))
        nameCol.title = "Name"
        nameCol.minWidth = 220
        nameCol.width = 340
        nameCol.resizingMask = .autoresizingMask
        tableView.addTableColumn(nameCol)

        let modCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Modified"))
        modCol.title = "Modified"
        modCol.minWidth = 120
        modCol.width = 140
        modCol.resizingMask = .userResizingMask
        tableView.addTableColumn(modCol)

        let sizeCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Size"))
        sizeCol.title = "Size"
        sizeCol.minWidth = 75
        sizeCol.width = 90
        sizeCol.resizingMask = .userResizingMask
        tableView.addTableColumn(sizeCol)

        let kindCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Kind"))
        kindCol.title = "Kind"
        kindCol.minWidth = 110
        kindCol.width = 140
        kindCol.resizingMask = .userResizingMask
        tableView.addTableColumn(kindCol)

        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.target = context.coordinator
        tableView.doubleAction = #selector(Coordinator.handleDoubleClick(_:))
        tableView.menu = context.coordinator.buildContextMenu(for: tableView)

        context.coordinator.tableView = tableView
        scrollView.documentView = tableView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.appState = appState
        let newItems = appState.displayedItems
        let newRowHeight = appearance.density.rowHeight

        guard let tableView = context.coordinator.tableView else { return }

        if abs(tableView.rowHeight - newRowHeight) > 0.5 {
            tableView.rowHeight = newRowHeight
            tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<context.coordinator.items.count))
        }

        let oldItems = context.coordinator.items
        let itemsChanged = (oldItems.count != newItems.count) ||
            (oldItems.first?.id != newItems.first?.id) ||
            (oldItems.last?.id != newItems.last?.id) ||
            (oldItems != newItems)

        if itemsChanged {
            context.coordinator.items = newItems
            tableView.reloadData()
        }

        // Sync selection from AppState if needed
        context.coordinator.syncTableSelection(with: appState.selectedItemIDs)
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        var appState: AppState
        var items: [FileItem] = []
        weak var tableView: NSTableView?
        private var isUpdatingSelection = false

        init(appState: AppState) {
            self.appState = appState
            self.items = appState.displayedItems
            super.init()

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleAppearanceChange),
                name: .stratumAppearanceDidChange,
                object: nil
            )
        }

        @objc private func handleAppearanceChange() {
            tableView?.reloadData()
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            items.count
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let id = NSUserInterfaceItemIdentifier("StratumRow")
            if let reused = tableView.makeView(withIdentifier: id, owner: nil) as? StratumTableRowView {
                return reused
            }
            let rowView = StratumTableRowView()
            rowView.identifier = id
            return rowView
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard items.indices.contains(row), let colID = tableColumn?.identifier else { return nil }
            let item = items[row]

            switch colID.rawValue {
            case "Name":
                let cellID = NSUserInterfaceItemIdentifier("NameCell")
                let cell = (tableView.makeView(withIdentifier: cellID, owner: nil) as? NameTableCellView) ?? NameTableCellView(identifier: cellID)
                cell.configure(with: item)
                return cell

            case "Modified":
                let cellID = NSUserInterfaceItemIdentifier("ModCell")
                let cell = (tableView.makeView(withIdentifier: cellID, owner: nil) as? TextTableCellView) ?? TextTableCellView(identifier: cellID, alignment: .left, monospacedDigits: true)
                cell.label.stringValue = item.formattedModDate
                return cell

            case "Size":
                let cellID = NSUserInterfaceItemIdentifier("SizeCell")
                let cell = (tableView.makeView(withIdentifier: cellID, owner: nil) as? TextTableCellView) ?? TextTableCellView(identifier: cellID, alignment: .right, monospacedDigits: true)
                cell.label.stringValue = item.isFolderLike ? item.subtitleText : item.formattedSize
                return cell

            case "Kind":
                let cellID = NSUserInterfaceItemIdentifier("KindCell")
                let cell = (tableView.makeView(withIdentifier: cellID, owner: nil) as? TextTableCellView) ?? TextTableCellView(identifier: cellID, alignment: .left, monospacedDigits: false)
                cell.label.stringValue = item.kindDescription
                return cell

            default:
                return nil
            }
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isUpdatingSelection, let tableView else { return }
            isUpdatingSelection = true
            defer { isUpdatingSelection = false }

            var selectedIDs = Set<String>()
            for idx in tableView.selectedRowIndexes where items.indices.contains(idx) {
                selectedIDs.insert(items[idx].id)
            }
            if appState.selectedItemIDs != selectedIDs {
                appState.selectedItemIDs = selectedIDs
            }
        }

        func syncTableSelection(with selectedIDs: Set<String>) {
            guard !isUpdatingSelection, let tableView else { return }
            isUpdatingSelection = true
            defer { isUpdatingSelection = false }

            var indexSet = IndexSet()
            if !selectedIDs.isEmpty {
                for (i, item) in items.enumerated() where selectedIDs.contains(item.id) {
                    indexSet.insert(i)
                }
            }
            if tableView.selectedRowIndexes != indexSet {
                tableView.selectRowIndexes(indexSet, byExtendingSelection: false)
            }
        }

        @objc func handleDoubleClick(_ sender: Any?) {
            guard let tableView else { return }
            let clicked = tableView.clickedRow
            if items.indices.contains(clicked) {
                appState.openItem(items[clicked])
            }
        }

        // MARK: - Drag and Drop

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
            guard items.indices.contains(row) else { return nil }
            return items[row].url as NSURL
        }

        func tableView(_ tableView: NSTableView, validateDrop info: any NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
            if dropOperation == .on, items.indices.contains(row), !items[row].isFolderLike {
                tableView.setDropRow(-1, dropOperation: .on)
            }
            let isOptionPressed = NSEvent.modifierFlags.contains(.option)
            return isOptionPressed ? .copy : .move
        }

        func tableView(_ tableView: NSTableView, acceptDrop info: any NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
            let pb = info.draggingPasteboard
            guard let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
                  !urls.isEmpty else {
                return false
            }

            let targetFolder: URL
            if dropOperation == .on, items.indices.contains(row), items[row].isFolderLike {
                targetFolder = items[row].url
            } else {
                targetFolder = appState.currentURL
            }

            let isCopy = NSEvent.modifierFlags.contains(.option)
            appState.handleDroppedURLs(urls, into: targetFolder, isMove: !isCopy)
            return true
        }

        // MARK: - Rich Context Menu via StratumContextMenuBuilder

        func buildContextMenu(for tableView: NSTableView) -> NSMenu {
            let menu = NSMenu()
            menu.delegate = self
            return menu
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            guard let tableView else { return }
            let clickedRow = tableView.clickedRow
            if clickedRow >= 0 && !tableView.selectedRowIndexes.contains(clickedRow) {
                tableView.selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
            }

            let targetItems: [FileItem]
            if clickedRow >= 0 {
                targetItems = tableView.selectedRowIndexes.compactMap {
                    items.indices.contains($0) ? items[$0] : nil
                }
            } else {
                targetItems = []
            }

            StratumContextMenuBuilder.shared.populateMenu(
                menu,
                appState: appState,
                targetItems: targetItems,
                directoryURL: appState.currentURL
            )
        }
    }
}

// MARK: - Custom TableView & Cells

final class KeyHandlingTableView: NSTableView {
    weak var coordinator: FastListView.Coordinator?

    override func keyDown(with event: NSEvent) {
        guard let coordinator else {
            super.keyDown(with: event)
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Spacebar -> Quick Look
        if event.keyCode == 49 && flags.isEmpty {
            let urls = coordinator.appState.selectedItems.map(\.url)
            QuickLookCoordinator.shared.togglePreview(for: urls)
            return
        }
        // Return (36) or Cmd+Down (125) -> Open selected
        if (event.keyCode == 36 && flags.isEmpty) || (event.keyCode == 125 && flags == .command) {
            if let first = coordinator.appState.selectedItems.first {
                coordinator.appState.openItem(first)
            }
            return
        }
        // Cmd+Up (126) -> Go to parent folder
        if event.keyCode == 126 && flags == .command {
            coordinator.appState.goUp()
            return
        }
        // Cmd+Delete (51) -> Move to Trash
        if event.keyCode == 51 && flags == .command {
            coordinator.appState.moveSelectionToTrash()
            return
        }
        // "/" -> Quick filter bar
        if event.charactersIgnoringModifiers == "/" && flags.isEmpty {
            coordinator.appState.showQuickFilter = true
            return
        }
        super.keyDown(with: event)
    }
}

final class StratumTableRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        let insetRect = bounds.insetBy(dx: 6, dy: 1)
        let path = NSBezierPath(roundedRect: insetRect, xRadius: 8, yRadius: 8)
        let accent = AppearanceManager.shared.activeNSColor
        accent.withAlphaComponent(0.28).setFill()
        path.fill()
        accent.withAlphaComponent(0.65).setStroke()
        path.lineWidth = 1.0
        path.stroke()
    }
}

final class NameTableCellView: NSTableCellView {
    private let iconImageView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let tagPillField = NSTextField(labelWithString: "")
    private let tagDotView = NSView()
    private var thumbnailRequest: QLThumbnailGenerator.Request?
    private var currentItemID: String?

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.imageScaling = .scaleProportionallyUpOrDown

        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.font = .systemFont(ofSize: 13, weight: .medium)
        titleField.lineBreakMode = .byTruncatingMiddle
        titleField.textColor = .labelColor

        tagDotView.translatesAutoresizingMaskIntoConstraints = false
        tagDotView.wantsLayer = true
        tagDotView.layer?.cornerRadius = 4
        tagDotView.isHidden = true

        tagPillField.translatesAutoresizingMaskIntoConstraints = false
        tagPillField.font = .systemFont(ofSize: 10.5, weight: .medium)
        tagPillField.textColor = .secondaryLabelColor
        tagPillField.isHidden = true

        addSubview(iconImageView)
        addSubview(titleField)
        addSubview(tagDotView)
        addSubview(tagPillField)

        NSLayoutConstraint.activate([
            iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 18),
            iconImageView.heightAnchor.constraint(equalToConstant: 18),

            titleField.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 9),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleField.trailingAnchor.constraint(lessThanOrEqualTo: tagDotView.leadingAnchor, constant: -6),

            tagDotView.trailingAnchor.constraint(equalTo: tagPillField.leadingAnchor, constant: -5),
            tagDotView.centerYAnchor.constraint(equalTo: centerYAnchor),
            tagDotView.widthAnchor.constraint(equalToConstant: 8),
            tagDotView.heightAnchor.constraint(equalToConstant: 8),

            tagPillField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            tagPillField.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        IconPipeline.shared.cancelRequest(thumbnailRequest)
        thumbnailRequest = nil
        currentItemID = nil
        tagDotView.isHidden = true
        tagPillField.isHidden = true
    }

    @MainActor
    func configure(with item: FileItem) {
        currentItemID = item.id
        titleField.stringValue = item.name
        titleField.alphaValue = item.isHidden ? 0.6 : 1.0

        if let firstTag = item.tags.first, let nsColor = NSColor(hex: firstTag.hexColor) {
            tagDotView.isHidden = false
            tagDotView.layer?.backgroundColor = nsColor.cgColor
            tagPillField.isHidden = false
            tagPillField.stringValue = item.tags.count > 1 ? "\(firstTag.name) +\(item.tags.count - 1)" : firstTag.name
        } else {
            tagDotView.isHidden = true
            tagPillField.isHidden = true
        }

        if item.isFolderLike {
            if let sym = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil) {
                let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
                    .applying(.init(paletteColors: [AppearanceManager.shared.folderFrontNSColor]))
                iconImageView.image = sym.withSymbolConfiguration(config)
            } else {
                iconImageView.image = IconPipeline.shared.fastTypeIcon(forExtension: item.ext, isDirectory: true, isPackage: false)
            }
            return
        }

        // Tier 1: Immediate 0ms cached thumbnail or UTType icon
        let thumbSize = CGSize(width: 36, height: 36)
        if let cached = IconPipeline.shared.cachedThumbnail(for: item.id, size: thumbSize) {
            iconImageView.image = cached
            return
        }

        iconImageView.image = IconPipeline.shared.icon(for: item)

        // Tier 2: Async QLThumbnailGenerator if image/video/pdf
        if item.isImageOrVideo || item.kindCategory == .pdf {
            let expectedID = item.id
            thumbnailRequest = IconPipeline.shared.requestThumbnail(for: item, size: thumbSize) { [weak self] thumb in
                guard let self, self.currentItemID == expectedID, let thumb else { return }
                self.iconImageView.image = thumb
            }
        }
    }
}

final class TextTableCellView: NSTableCellView {
    let label = NSTextField(labelWithString: "")

    init(identifier: NSUserInterfaceItemIdentifier, alignment: NSTextAlignment, monospacedDigits: Bool) {
        super.init(frame: .zero)
        self.identifier = identifier
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = alignment
        label.font = monospacedDigits
            ? .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            : .systemFont(ofSize: 12, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
