import SwiftUI
import AppKit
import QuickLookThumbnailing

final class KeyHandlingCollectionView: NSCollectionView {
    weak var coordinator: FastIconGridView.Coordinator?
    private var typeSelect = TypeSelectBuffer()

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        BrowserKeys.claimFocusIfUnused(self)
    }

    override func keyDown(with event: NSEvent) {
        guard let coordinator else {
            super.keyDown(with: event)
            return
        }
        if BrowserKeys.handle(event, appState: coordinator.appState) { return }
        if let prefix = typeSelect.prefix(adding: event) {
            coordinator.selectFirstItem(withPrefix: prefix)
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
