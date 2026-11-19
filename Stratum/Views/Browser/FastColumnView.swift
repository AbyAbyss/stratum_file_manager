import SwiftUI
import AppKit

struct FastColumnView: View {
    @Bindable var appState: AppState
    var appearance: AppearanceManager

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                // Quick Column Jump Strip when multiple columns exist
                if appState.columnPanes.count > 1 {
                    HStack(spacing: 6) {
                        Button {
                            if let firstID = appState.columnPanes.first?.id {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    proxy.scrollTo(firstID, anchor: .leading)
                                }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "chevron.left.2")
                                    .font(.system(size: 9.5, weight: .bold))
                                Text("Root")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .background(
                                Capsule()
                                    .fill(Color.primary.opacity(0.05))
                                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.09), lineWidth: 1))
                            )
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("Scroll all the way left to the root column")

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(Array(appState.columnPanes.enumerated()), id: \.element.id) { idx, pane in
                                    let isLast = (idx == appState.columnPanes.count - 1)
                                    Button {
                                        withAnimation(.easeOut(duration: 0.2)) {
                                            proxy.scrollTo(pane.id, anchor: isLast ? .trailing : .center)
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "folder.fill")
                                                .font(.system(size: 10))
                                                .foregroundStyle(isLast ? appearance.accentColor : .secondary)
                                            Text(pane.displayTitle)
                                                .font(.system(size: 11, weight: isLast ? .semibold : .regular))
                                                .foregroundStyle(isLast ? .primary : .secondary)
                                        }
                                        .padding(.horizontal, 8)
                                        .frame(height: 22)
                                        .background(
                                            Capsule()
                                                .fill(isLast ? appearance.selectionFillColor : Color.primary.opacity(0.04))
                                                .overlay(
                                                    Capsule()
                                                        .strokeBorder(
                                                            isLast ? appearance.selectionBorderColor : Color.primary.opacity(0.07),
                                                            lineWidth: 1
                                                        )
                                                )
                                        )
                                        .contentShape(Capsule())
                                    }
                                    .buttonStyle(.plain)

                                    if !isLast {
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        }

                        Spacer()

                        Text("\(appState.columnPanes.count) columns · scroll horizontally or click any column pill")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.025))
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color.primary.opacity(0.06))
                            .frame(height: 1)
                    }
                }

                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(spacing: 0) {
                        ForEach(appState.columnPanes) { pane in
                            let isActiveLeaf = (pane.directoryURL.standardizedFileURL == appState.currentURL.standardizedFileURL)
                            VStack(spacing: 0) {
                                // Column Folder Header
                                HStack(spacing: 6) {
                                    Image(systemName: pane.directoryURL.path == "/" ? "internaldrive.fill" : "folder.fill")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(isActiveLeaf ? appearance.accentColor : .secondary)
                                    Text(pane.displayTitle)
                                        .font(.system(size: 11.5, weight: isActiveLeaf ? .semibold : .medium))
                                        .foregroundStyle(isActiveLeaf ? .primary : .secondary)
                                        .lineLimit(1)
                                    Spacer()
                                    Text("\(pane.items.count)")
                                        .font(.system(size: 10.5).monospacedDigit())
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 12)
                                .frame(height: 28)
                                .background(isActiveLeaf ? appearance.faintTintColor : Color.primary.opacity(0.02))
                                .overlay(alignment: .bottom) {
                                    Rectangle()
                                        .fill(isActiveLeaf ? appearance.selectionBorderColor : Color.primary.opacity(0.06))
                                        .frame(height: 1)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if !isActiveLeaf {
                                        appState.navigate(to: pane.directoryURL)
                                    }
                                }

                                ColumnSingleListView(
                                    pane: pane,
                                    appState: appState,
                                    appearance: appearance
                                )
                            }
                            .frame(width: 240)
                            .id(pane.id)

                            Divider()
                                .opacity(0.35)
                        }
                    }
                }
            }
            .onAppear {
                if appState.columnPanes.isEmpty {
                    appState.rebuildColumns(for: appState.currentURL)
                } else if let lastID = appState.columnPanes.last?.id {
                    DispatchQueue.main.async {
                        proxy.scrollTo(lastID, anchor: .trailing)
                    }
                }
            }
            .onChange(of: appState.columnPanes.map(\.id)) { oldIDs, newIDs in
                guard let lastID = newIDs.last, lastID != oldIDs.last else { return }
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(lastID, anchor: .trailing)
                    }
                }
            }
        }
    }
}

private struct ColumnSingleListView: NSViewRepresentable {
    let pane: AppState.ColumnPane
    var appState: AppState
    var appearance: AppearanceManager

    func makeCoordinator() -> Coordinator {
        Coordinator(pane: pane, appState: appState)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true

        let tableView = NSTableView()
        tableView.style = .plain
        tableView.backgroundColor = .clear
        tableView.headerView = nil
        tableView.rowHeight = appearance.density.rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.selectionHighlightStyle = .regular
        tableView.registerForDraggedTypes([.fileURL])
        tableView.setDraggingSourceOperationMask([.copy, .move], forLocal: false)

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ColumnItem"))
        col.resizingMask = .autoresizingMask
        tableView.addTableColumn(col)

        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.target = context.coordinator
        tableView.doubleAction = #selector(Coordinator.handleDoubleClick(_:))
        tableView.menu = context.coordinator.buildContextMenu()

        context.coordinator.tableView = tableView
        scroll.documentView = tableView
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.appState = appState
        let oldItems = context.coordinator.pane.items
        context.coordinator.pane = pane

        guard let tableView = context.coordinator.tableView else { return }
        if oldItems != pane.items {
            tableView.reloadData()
        }
        context.coordinator.syncSelection()
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        var pane: AppState.ColumnPane
        var appState: AppState
        weak var tableView: NSTableView?
        private var isSyncing = false

        init(pane: AppState.ColumnPane, appState: AppState) {
            self.pane = pane
            self.appState = appState
            super.init()
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            pane.items.count
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let id = NSUserInterfaceItemIdentifier("ColRow")
            if let r = tableView.makeView(withIdentifier: id, owner: nil) as? StratumTableRowView {
                return r
            }
            let r = StratumTableRowView()
            r.identifier = id
            return r
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard pane.items.indices.contains(row) else { return nil }
            let item = pane.items[row]
            let id = NSUserInterfaceItemIdentifier("ColCell")
            let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? ColumnItemCellView) ?? ColumnItemCellView(identifier: id)
            cell.configure(with: item)
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isSyncing, let tableView else { return }
            let row = tableView.selectedRow
            guard pane.items.indices.contains(row) else { return }
            let item = pane.items[row]
            appState.selectItemInColumn(item, paneDirectoryURL: pane.directoryURL)
        }

        func syncSelection() {
            guard let tableView else { return }
            isSyncing = true
            defer { isSyncing = false }

            let isLeafColumn = (pane.directoryURL.standardizedFileURL == appState.currentURL.standardizedFileURL)
            let targetID = isLeafColumn ? (appState.selectedItemIDs.first ?? pane.selectedItemID) : pane.selectedItemID

            if let targetID, let idx = pane.items.firstIndex(where: { $0.id == targetID }) {
                if tableView.selectedRow != idx {
                    tableView.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
                    tableView.scrollRowToVisible(idx)
                }
            } else if tableView.selectedRow != -1 {
                tableView.deselectAll(nil)
            }
        }

        @objc func handleDoubleClick(_ sender: Any?) {
            guard let tableView else { return }
            let row = tableView.clickedRow
            if pane.items.indices.contains(row) {
                appState.openItem(pane.items[row])
            }
        }

        // MARK: - Drag and Drop

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
            guard pane.items.indices.contains(row) else { return nil }
            return pane.items[row].url as NSURL
        }

        func tableView(_ tableView: NSTableView, validateDrop info: any NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
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
            if dropOperation == .on, pane.items.indices.contains(row), pane.items[row].isFolderLike {
                targetFolder = pane.items[row].url
            } else {
                targetFolder = pane.directoryURL
            }
            let isCopy = NSEvent.modifierFlags.contains(.option)
            appState.handleDroppedURLs(urls, into: targetFolder, isMove: !isCopy)
            return true
        }

        // MARK: - Rich Context Menu

        func buildContextMenu() -> NSMenu {
            let menu = NSMenu()
            menu.delegate = self
            return menu
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            guard let tableView else { return }
            let clickedRow = tableView.clickedRow
            let targetItems: [FileItem]
            if clickedRow >= 0 && pane.items.indices.contains(clickedRow) {
                let item = pane.items[clickedRow]
                targetItems = [item]
            } else {
                targetItems = []
            }

            StratumContextMenuBuilder.shared.populateMenu(
                menu,
                appState: appState,
                targetItems: targetItems,
                directoryURL: pane.directoryURL
            )
        }
    }
}

private final class ColumnItemCellView: NSTableCellView {
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let tagDotView = NSView()
    private let chevronLabel = NSTextField(labelWithString: "›")

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        iconView.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .systemFont(ofSize: 13, weight: .regular)
        nameLabel.lineBreakMode = .byTruncatingMiddle

        tagDotView.translatesAutoresizingMaskIntoConstraints = false
        tagDotView.wantsLayer = true
        tagDotView.layer?.cornerRadius = 3.5
        tagDotView.isHidden = true

        chevronLabel.translatesAutoresizingMaskIntoConstraints = false
        chevronLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        chevronLabel.textColor = .tertiaryLabelColor

        addSubview(iconView)
        addSubview(nameLabel)
        addSubview(tagDotView)
        addSubview(chevronLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 7),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: tagDotView.leadingAnchor, constant: -4),

            tagDotView.trailingAnchor.constraint(equalTo: chevronLabel.leadingAnchor, constant: -5),
            tagDotView.centerYAnchor.constraint(equalTo: centerYAnchor),
            tagDotView.widthAnchor.constraint(equalToConstant: 7),
            tagDotView.heightAnchor.constraint(equalToConstant: 7),

            chevronLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            chevronLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @MainActor
    func configure(with item: FileItem) {
        nameLabel.stringValue = item.name
        chevronLabel.isHidden = !item.isFolderLike

        if let firstTag = item.tags.first, let nsColor = NSColor(hex: firstTag.hexColor) {
            tagDotView.isHidden = false
            tagDotView.layer?.backgroundColor = nsColor.cgColor
        } else {
            tagDotView.isHidden = true
        }

        if item.isFolderLike {
            if let sym = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil) {
                let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
                    .applying(.init(paletteColors: [AppearanceManager.shared.folderFrontNSColor]))
                iconView.image = sym.withSymbolConfiguration(config)
            }
        } else {
            iconView.image = IconPipeline.shared.icon(for: item)
        }
    }
}
