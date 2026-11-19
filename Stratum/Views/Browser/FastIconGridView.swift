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
