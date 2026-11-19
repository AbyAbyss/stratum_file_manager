import SwiftUI
import AppKit
import QuickLookThumbnailing

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
