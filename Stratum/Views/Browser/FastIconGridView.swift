import SwiftUI
import AppKit
import QuickLookThumbnailing

struct FastIconGridView: NSViewRepresentable {
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

        let layout = NSCollectionViewFlowLayout()
        layout.sectionInset = NSEdgeInsets(top: 6, left: 16, bottom: 16, right: 16)
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8

        let collectionView = KeyHandlingCollectionView()
        collectionView.coordinator = context.coordinator
        collectionView.collectionViewLayout = layout
        collectionView.backgroundColors = [.clear]
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.allowsEmptySelection = true
        collectionView.registerForDraggedTypes([.fileURL])
        collectionView.setDraggingSourceOperationMask([.copy, .move], forLocal: false)

        collectionView.register(
            StratumGridCollectionItem.self,
            forItemWithIdentifier: StratumGridCollectionItem.reuseID
        )
        collectionView.register(
            StratumGridHeaderView.self,
            forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
            withIdentifier: StratumGridHeaderView.reuseID
        )

        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator
        collectionView.menu = context.coordinator.buildContextMenu()

        context.coordinator.collectionView = collectionView
        scrollView.documentView = collectionView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.appState = appState
        context.coordinator.updateData(
            folders: appState.displayedFolders,
            files: appState.displayedFiles,
            all: appState.displayedItems,
            grouped: appState.groupByKind,
            iconScale: appState.iconScale,
            selectedIDs: appState.selectedItemIDs
        )
    }

    @MainActor
    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout, NSMenuDelegate {
        struct Section {
            let title: String
            let items: [FileItem]
        }

        var appState: AppState
        weak var collectionView: NSCollectionView?
        var sections: [Section] = []
        var iconScale: Double = 3.0
        private var isSyncingSelection = false
        private var lastGrouped: Bool = true
        private var lastAllIDs: [String] = []

        init(appState: AppState) {
            self.appState = appState
            super.init()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleAppearanceChange),
                name: .stratumAppearanceDidChange,
                object: nil
            )
        }

        @objc private func handleAppearanceChange() {
            collectionView?.reloadData()
        }

        func updateData(
            folders: [FileItem],
            files: [FileItem],
            all: [FileItem],
            grouped: Bool,
            iconScale: Double,
            selectedIDs: Set<String>
        ) {
            guard let collectionView else { return }
            let scaleChanged = abs(self.iconScale - iconScale) > 0.05
            self.iconScale = iconScale

            let newIDs = all.map(\.id)
            let dataChanged = (newIDs != lastAllIDs) || (grouped != lastGrouped)

            if dataChanged {
                lastAllIDs = newIDs
                lastGrouped = grouped
                var built: [Section] = []
                if grouped {
                    if !folders.isEmpty {
                        built.append(Section(title: "Folders · \(folders.count)", items: folders))
                    }
                    if !files.isEmpty {
                        let appCount = files.filter(\.isAppOrPackage).count
                        let secTitle = (appCount > files.count / 2) ? "Applications · \(files.count)" : "Files · \(files.count)"
                        built.append(Section(title: secTitle, items: files))
                    }
                } else {
                    built.append(Section(title: "", items: all))
                }
                self.sections = built
                collectionView.reloadData()
            } else if scaleChanged {
                collectionView.collectionViewLayout?.invalidateLayout()
                collectionView.reloadData()
            }

            syncSelection(selectedIDs)
        }

        func syncSelection(_ selectedIDs: Set<String>) {
            guard !isSyncingSelection, let collectionView else { return }
            isSyncingSelection = true
            defer { isSyncingSelection = false }

            var indexPaths = Set<IndexPath>()
            if !selectedIDs.isEmpty {
                for (secIdx, sec) in sections.enumerated() {
                    for (itemIdx, item) in sec.items.enumerated() where selectedIDs.contains(item.id) {
                        indexPaths.insert(IndexPath(item: itemIdx, section: secIdx))
                    }
                }
            }
            if collectionView.selectionIndexPaths != indexPaths {
                collectionView.selectionIndexPaths = indexPaths
            }
        }

        func item(at indexPath: IndexPath) -> FileItem? {
            guard sections.indices.contains(indexPath.section),
                  sections[indexPath.section].items.indices.contains(indexPath.item) else {
                return nil
            }
            return sections[indexPath.section].items[indexPath.item]
        }

        // MARK: - NSCollectionViewDataSource

        func numberOfSections(in collectionView: NSCollectionView) -> Int {
            sections.count
        }

        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
            guard sections.indices.contains(section) else { return 0 }
            return sections[section].items.count
        }

        func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let cell = collectionView.makeItem(withIdentifier: StratumGridCollectionItem.reuseID, for: indexPath)
            if let gridItem = cell as? StratumGridCollectionItem, let fileItem = item(at: indexPath) {
                gridItem.configure(with: fileItem, scale: iconScale) { [weak self] opened in
                    self?.appState.openItem(opened)
                }
            }
            return cell
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            viewForSupplementaryElementOfKind kind: NSCollectionView.SupplementaryElementKind,
            at indexPath: IndexPath
        ) -> NSView {
            let header = collectionView.makeSupplementaryView(
                ofKind: kind,
                withIdentifier: StratumGridHeaderView.reuseID,
                for: indexPath
            )
            if let stratumHeader = header as? StratumGridHeaderView,
               sections.indices.contains(indexPath.section) {
                stratumHeader.titleLabel.stringValue = sections[indexPath.section].title
            }
            return header
        }

        // MARK: - NSCollectionViewDelegateFlowLayout

        func collectionView(
            _ collectionView: NSCollectionView,
            layout collectionViewLayout: NSCollectionViewLayout,
            sizeForItemAt indexPath: IndexPath
        ) -> NSSize {
            let factor = 0.8 + (iconScale * 0.1) // 0.9 .. 1.3
            return NSSize(width: round(142 * factor), height: round(122 * factor))
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            layout collectionViewLayout: NSCollectionViewLayout,
            referenceSizeForHeaderInSection section: Int
        ) -> NSSize {
            guard sections.indices.contains(section), !sections[section].title.isEmpty else {
                return .zero
            }
            return NSSize(width: collectionView.bounds.width, height: 26)
        }

        func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
            propagateSelectionFromCollectionView()
        }

        func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
            propagateSelectionFromCollectionView()
        }

        private func propagateSelectionFromCollectionView() {
            guard !isSyncingSelection, let collectionView else { return }
            isSyncingSelection = true
            defer { isSyncingSelection = false }

            var ids = Set<String>()
            for ip in collectionView.selectionIndexPaths {
                if let it = item(at: ip) {
                    ids.insert(it.id)
                }
            }
            if appState.selectedItemIDs != ids {
                appState.selectedItemIDs = ids
            }
        }

        // MARK: - Drag and Drop

        func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> (any NSPasteboardWriting)? {
            guard let it = item(at: indexPath) else { return nil }
            return it.url as NSURL
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            validateDrop draggingInfo: any NSDraggingInfo,
            proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
            dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>
        ) -> NSDragOperation {
            let isOptionPressed = NSEvent.modifierFlags.contains(.option)
            return isOptionPressed ? .copy : .move
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            acceptDrop draggingInfo: any NSDraggingInfo,
            indexPath: IndexPath,
            dropOperation: NSCollectionView.DropOperation
        ) -> Bool {
            let pb = draggingInfo.draggingPasteboard
            guard let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
                  !urls.isEmpty else {
                return false
            }

            let targetFolder: URL
            if dropOperation == .on, let targetItem = item(at: indexPath), targetItem.isFolderLike {
                targetFolder = targetItem.url
            } else {
                targetFolder = appState.currentURL
            }

            let isCopy = NSEvent.modifierFlags.contains(.option)
            appState.handleDroppedURLs(urls, into: targetFolder, isMove: !isCopy)
            return true
        }

        // MARK: - Rich Context Menu via StratumContextMenuBuilder

        func buildContextMenu() -> NSMenu {
            let menu = NSMenu()
            menu.delegate = self
            return menu
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            guard let collectionView else { return }

            // Hit-test item under right-click cursor
            var clickedIndexPath: IndexPath? = nil
            if let win = collectionView.window {
                let winPt = win.mouseLocationOutsideOfEventStream
                let localPt = collectionView.convert(winPt, from: nil)
                clickedIndexPath = collectionView.indexPathForItem(at: localPt)
            }

            let targetItems: [FileItem]
            if let ip = clickedIndexPath, let hitItem = item(at: ip) {
                if !collectionView.selectionIndexPaths.contains(ip) {
                    collectionView.selectionIndexPaths = [ip]
                    appState.selectedItemIDs = [hitItem.id]
                    targetItems = [hitItem]
                } else {
                    targetItems = appState.selectedItems
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

final class KeyHandlingCollectionView: NSCollectionView {
    weak var coordinator: FastIconGridView.Coordinator?

    override func keyDown(with event: NSEvent) {
        guard let coordinator else {
            super.keyDown(with: event)
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if event.keyCode == 49 && flags.isEmpty {
            QuickLookCoordinator.shared.togglePreview(for: coordinator.appState.selectedItems.map(\.url))
            return
        }
        if (event.keyCode == 36 && flags.isEmpty) || (event.keyCode == 125 && flags == .command) {
            if let first = coordinator.appState.selectedItems.first {
                coordinator.appState.openItem(first)
            }
            return
        }
        if event.keyCode == 126 && flags == .command {
            coordinator.appState.goUp()
            return
        }
        if event.keyCode == 51 && flags == .command {
            coordinator.appState.moveSelectionToTrash()
            return
        }
        if event.charactersIgnoringModifiers == "/" && flags.isEmpty {
            coordinator.appState.showQuickFilter = true
            return
        }
        super.keyDown(with: event)
    }
}

final class StratumGridHeaderView: NSView {
    static let reuseID = NSUserInterfaceItemIdentifier("StratumGridHeaderView")
    let titleLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class StratumGridCollectionItem: NSCollectionViewItem {
    static let reuseID = NSUserInterfaceItemIdentifier("StratumGridCollectionItem")

    private let cardView = GridTileGraphicView()
    private var thumbnailRequest: QLThumbnailGenerator.Request?
    private var currentItem: FileItem?
    private var onDoubleClick: ((FileItem) -> Void)?

    override func loadView() {
        self.view = cardView
        cardView.onDoubleClick = { [weak self] in
            guard let self, let item = self.currentItem else { return }
            self.onDoubleClick?(item)
        }
    }

    override var isSelected: Bool {
        didSet {
            cardView.isSelectedTile = isSelected
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        IconPipeline.shared.cancelRequest(thumbnailRequest)
        thumbnailRequest = nil
        currentItem = nil
        cardView.thumbnailImage = nil
    }

    @MainActor
    func configure(with item: FileItem, scale: Double, onDoubleClick: @escaping (FileItem) -> Void) {
        self.currentItem = item
        self.onDoubleClick = onDoubleClick
        cardView.fileItem = item
        cardView.isSelectedTile = isSelected

        if item.isImageOrVideo {
            let thumbSize = CGSize(width: 184, height: 124)
            if let cached = IconPipeline.shared.cachedThumbnail(for: item.id, size: thumbSize) {
                cardView.thumbnailImage = cached
            } else {
                let expectedID = item.id
                thumbnailRequest = IconPipeline.shared.requestThumbnail(for: item, size: thumbSize) { [weak self] img in
                    guard let self, self.currentItem?.id == expectedID else { return }
                    self.cardView.thumbnailImage = img
                }
            }
        }
    }
}

final class GridTileGraphicView: NSView {
    var fileItem: FileItem? { didSet { needsDisplay = true } }
    var isSelectedTile: Bool = false { didSet { needsDisplay = true } }
    var thumbnailImage: NSImage? { didSet { needsDisplay = true } }
    var onDoubleClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if event.clickCount == 2 {
            onDoubleClick?()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let item = fileItem else { return }
        let appearance = AppearanceManager.shared
        let accent = appearance.activeNSColor

        let cardRect = bounds.insetBy(dx: 2, dy: 2)
        let cardPath = NSBezierPath(roundedRect: cardRect, xRadius: 12, yRadius: 12)

        if isSelectedTile {
            accent.withAlphaComponent(0.26).setFill()
            cardPath.fill()
            accent.withAlphaComponent(0.70).setStroke()
            cardPath.lineWidth = 1.0
            cardPath.stroke()
        }

        // Graphic area at top of tile
        let graphicCenterY = bounds.maxY - 45
        let centerX = bounds.midX

        if item.isFolderLike {
            drawFolderGraphic(centerX: centerX, centerY: graphicCenterY, appearance: appearance)
        } else if item.isAppOrPackage {
            drawAppIconGraphic(item: item, centerX: centerX, centerY: graphicCenterY)
        } else if item.isImageOrVideo {
            drawImageGraphic(item: item, centerX: centerX, centerY: graphicCenterY)
        } else {
            drawPaperGraphic(item: item, centerX: centerX, centerY: graphicCenterY)
        }

        // Draw Finder tag dots in top-right of tile if present
        if !item.tags.isEmpty {
            let dotSize: CGFloat = 8
            for (idx, tag) in item.tags.prefix(3).enumerated() {
                let dotX = bounds.maxX - 18 - CGFloat(idx) * 10
                let dotY = bounds.maxY - 16
                let dotRect = NSRect(x: dotX, y: dotY, width: dotSize, height: dotSize)
                let color = NSColor(hex: tag.hexColor) ?? .systemBlue
                color.setFill()
                let dotPath = NSBezierPath(ovalIn: dotRect)
                dotPath.fill()
                NSColor.black.withAlphaComponent(0.35).setStroke()
                dotPath.lineWidth = 1.0
                dotPath.stroke()
            }
        }

        // Draw filename pill
        let nameFont = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        let pStyle = NSMutableParagraphStyle()
        pStyle.alignment = .center
        pStyle.lineBreakMode = .byTruncatingMiddle

        let nameColor: NSColor = isSelectedTile ? .white : .labelColor
        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: nameFont,
            .foregroundColor: nameColor,
            .paragraphStyle: pStyle
        ]

        let maxNameWidth = bounds.width - 18
        let measured = (item.name as NSString).size(withAttributes: nameAttrs)
        let pillW = min(maxNameWidth, ceil(measured.width) + 14)
        let pillH: CGFloat = 19
        let pillRect = NSRect(x: centerX - pillW / 2, y: 24, width: pillW, height: pillH)

        if isSelectedTile {
            let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: 6, yRadius: 6)
            accent.setFill()
            pillPath.fill()
        }

        let textRect = NSRect(x: pillRect.minX + 5, y: pillRect.minY + 1.5, width: pillRect.width - 10, height: pillH - 2)
        (item.name as NSString).draw(in: textRect, withAttributes: nameAttrs)

        // Draw subtitle (item count or file size)
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: pStyle
        ]
        let subRect = NSRect(x: 6, y: 6, width: bounds.width - 12, height: 15)
        (item.subtitleText as NSString).draw(in: subRect, withAttributes: subAttrs)
    }

    private func drawAppIconGraphic(item: FileItem, centerX: CGFloat, centerY: CGFloat) {
        let iconSize: CGFloat = 68
        let iconRect = NSRect(
            x: centerX - iconSize / 2,
            y: centerY - iconSize / 2,
            width: iconSize,
            height: iconSize
        )
        let appIcon = IconPipeline.shared.icon(for: item)

        NSGraphicsContext.current?.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowOffset = NSSize(width: 0, height: -4)
        shadow.shadowBlurRadius = 10
        shadow.set()

        appIcon.draw(
            in: iconRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0,
            respectFlipped: true,
            hints: [.interpolation: NSNumber(value: NSImageInterpolation.high.rawValue)]
        )
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    private func drawFolderGraphic(centerX: CGFloat, centerY: CGFloat, appearance: AppearanceManager) {
        let w: CGFloat = 78
        let h: CGFloat = 62
        let left = centerX - w / 2
        let bottom = centerY - h / 2

        // Back tab (top-left)
        let tabRect = NSRect(x: left, y: bottom + h - 18, width: 34, height: 18)
        let tabPath = NSBezierPath(roundedRect: tabRect, xRadius: 6, yRadius: 6)
        appearance.folderBackNSColor.setFill()
        tabPath.fill()

        // Front folder body
        let bodyRect = NSRect(x: left, y: bottom, width: w, height: h - 9)
        let bodyPath = NSBezierPath(roundedRect: bodyRect, xRadius: 9, yRadius: 9)
        appearance.folderFrontNSColor.setFill()
        bodyPath.fill()

        // Subtle top rim highlight matching prototype
        NSColor.white.withAlphaComponent(0.32).setStroke()
        bodyPath.lineWidth = 1.0
        bodyPath.stroke()
    }

    private func drawImageGraphic(item: FileItem, centerX: CGFloat, centerY: CGFloat) {
        let w: CGFloat = 92
        let h: CGFloat = 62
        let frameRect = NSRect(x: centerX - w / 2, y: centerY - h / 2, width: w, height: h)
        let clipPath = NSBezierPath(roundedRect: frameRect, xRadius: 7, yRadius: 7)

        NSGraphicsContext.current?.saveGraphicsState()
        clipPath.addClip()

        if let thumb = thumbnailImage {
            thumb.draw(in: frameRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        } else {
            let tint = NSColor(hex: item.badgeTintHex) ?? .systemBlue
            tint.withAlphaComponent(0.45).setFill()
            frameRect.fill()
        }

        if item.isVideo {
            let playSize: CGFloat = 24
            let playRect = NSRect(x: centerX - playSize / 2, y: centerY - playSize / 2, width: playSize, height: playSize)
            let circle = NSBezierPath(ovalIn: playRect)
            NSColor.black.withAlphaComponent(0.7).setFill()
            circle.fill()

            let tri = NSBezierPath()
            tri.move(to: NSPoint(x: centerX - 3, y: centerY - 5))
            tri.line(to: NSPoint(x: centerX - 3, y: centerY + 5))
            tri.line(to: NSPoint(x: centerX + 5, y: centerY))
            tri.close()
            NSColor.white.setFill()
            tri.fill()
        }

        NSGraphicsContext.current?.restoreGraphicsState()

        NSColor(calibratedWhite: 0.95, alpha: 0.95).setStroke()
        clipPath.lineWidth = 2.0
        clipPath.stroke()
    }

    private func drawPaperGraphic(item: FileItem, centerX: CGFloat, centerY: CGFloat) {
        let w: CGFloat = 48
        let h: CGFloat = 62
        let sheetRect = NSRect(x: centerX - w / 2, y: centerY - h / 2, width: w, height: h)
        let sheetPath = NSBezierPath(roundedRect: sheetRect, xRadius: 5, yRadius: 5)
        (NSColor(hex: "#EFEDF6") ?? .white).setFill()
        sheetPath.fill()

        // Simulated text lines on paper
        let lineColor = NSColor(hex: "#C9C5D8") ?? .lightGray
        lineColor.setFill()
        let lineWidths: [CGFloat] = [0.80, 1.0, 0.60]
        for (i, frac) in lineWidths.enumerated() {
            let lw = (w - 14) * frac
            let ly = sheetRect.maxY - 12 - CGFloat(i) * 7
            let lr = NSRect(x: sheetRect.minX + 7, y: ly, width: lw, height: 3)
            NSBezierPath(roundedRect: lr, xRadius: 1.5, yRadius: 1.5).fill()
        }

        // Protruding extension badge at bottom-left
        let badgeColor = NSColor(hex: item.badgeTintHex) ?? .darkGray
        let extText = item.displayExt
        let badgeFont = NSFont.systemFont(ofSize: 9, weight: .bold)
        let pStyle = NSMutableParagraphStyle()
        pStyle.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: badgeFont,
            .foregroundColor: NSColor.white,
            .paragraphStyle: pStyle
        ]
        let textSize = (extText as NSString).size(withAttributes: attrs)
        let badgeW = max(24, ceil(textSize.width) + 10)
        let badgeH: CGFloat = 14
        let badgeRect = NSRect(x: sheetRect.minX - 6, y: sheetRect.minY + 7, width: badgeW, height: badgeH)
        let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: 4, yRadius: 4)
        badgeColor.setFill()
        badgePath.fill()

        let badgeTextRect = NSRect(x: badgeRect.minX, y: badgeRect.minY + 1, width: badgeRect.width, height: badgeH - 2)
        (extText as NSString).draw(in: badgeTextRect, withAttributes: attrs)
    }
}
