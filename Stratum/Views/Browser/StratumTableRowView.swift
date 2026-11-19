import SwiftUI
import AppKit
import QuickLookThumbnailing

/// Row view shared by the list and column browsers. Selection and hover are drawn as layers
/// underneath the cell content so they can fade; the default instant selection fill is
/// suppressed. Rows configured during scrolling/reuse apply their state immediately.
final class StratumTableRowView: NSTableRowView {
    private let washLayer = CALayer()
    private let selectionLayer = CALayer()
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    /// False until the row has been on screen for a runloop turn, so reused rows don't fade in.
    private var isSettled = false
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUpLayers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUpLayers()
    }

    private func setUpLayers() {
        wantsLayer = true
        for layer in [washLayer, selectionLayer] {
            layer.cornerRadius = 8
            layer.cornerCurve = .continuous
            layer.opacity = 0
            self.layer?.insertSublayer(layer, at: 0)
        }
        selectionLayer.borderWidth = 1
        refreshColors()
    }

    private func refreshColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let accent = AppearanceManager.shared.activeNSColor
            selectionLayer.backgroundColor = accent.withAlphaComponent(0.28).cgColor
            selectionLayer.borderColor = accent.withAlphaComponent(0.65).cgColor
            washLayer.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let rect = bounds.insetBy(dx: 6, dy: 1)
        washLayer.frame = rect
        selectionLayer.frame = rect
        CATransaction.commit()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        isSettled = false
        DispatchQueue.main.async { [weak self] in self?.isSettled = true }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        isHovered = false
        isSettled = false
        for layer in [washLayer, selectionLayer] {
            layer.removeAllAnimations()
            layer.opacity = 0
        }
    }

    // The default instant fill is replaced by `selectionLayer`.
    override func drawSelection(in dirtyRect: NSRect) {}

    override var isSelected: Bool {
        didSet {
            guard isSelected != oldValue else { return }
            setLayer(selectionLayer, visible: isSelected, duration: 0.14)
            setLayer(washLayer, visible: isHovered && !isSelected, duration: 0.12)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }

    private func setHovered(_ hovered: Bool) {
        guard hovered != isHovered else { return }
        isHovered = hovered
        setLayer(washLayer, visible: hovered && !isSelected, duration: 0.12)
    }

    private func setLayer(_ layer: CALayer, visible: Bool, duration: CFTimeInterval) {
        let target: Float = visible ? 1 : 0
        let from = layer.presentation()?.opacity ?? layer.opacity
        layer.opacity = target
        guard isSettled, window != nil, !reduceMotion, from != target else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = from
        fade.toValue = target
        fade.duration = duration
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(fade, forKey: "fade")
    }
}
