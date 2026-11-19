import SwiftUI
import AppKit
import QuickLookThumbnailing

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
        cardView.resetMotion()
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
