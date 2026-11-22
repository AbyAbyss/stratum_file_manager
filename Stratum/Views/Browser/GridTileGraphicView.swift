import SwiftUI
import AppKit
import QuickLookThumbnailing

final class GridTileGraphicView: NSView {
    var fileItem: FileItem? { didSet { needsDisplay = true } }
    var isSelectedTile: Bool = false {
        didSet {
            needsDisplay = true
            guard isSelectedTile != oldValue else { return }
            // Selecting pops the tile; the hover wash gives way to the selection fill.
            animateHoverWash(visible: isHovered && !isSelectedTile)
            if isSelectedTile { popSelection() } else { animateScale(to: isHovered ? Self.hoverScale : 1) }
        }
    }
    var thumbnailImage: NSImage? { didSet { needsDisplay = true } }
    var onDoubleClick: (() -> Void)?

    // MARK: Hover and selection motion
    // Layer-based so it never touches the drawing code below. Skipped under Reduce Motion.

    private static let hoverScale: CGFloat = 1.03
    private let hoverLayer = CALayer()
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUpMotionLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUpMotionLayer()
    }

    private func setUpMotionLayer() {
        wantsLayer = true
        hoverLayer.opacity = 0
        hoverLayer.cornerRadius = 12
        hoverLayer.cornerCurve = .continuous
        hoverLayer.borderWidth = 1
        layer?.addSublayer(hoverLayer)
        refreshHoverColors()
    }

    private func refreshHoverColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            hoverLayer.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
            hoverLayer.borderColor = NSColor.labelColor.withAlphaComponent(0.12).cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshHoverColors()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hoverLayer.frame = bounds.insetBy(dx: 2, dy: 2)
        CATransaction.commit()
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
        animateHoverWash(visible: hovered && !isSelectedTile)
        animateScale(to: hovered && !isSelectedTile ? Self.hoverScale : 1)
    }

    private func animateHoverWash(visible: Bool) {
        let target: Float = visible ? 1 : 0
        let from = hoverLayer.presentation()?.opacity ?? hoverLayer.opacity
        hoverLayer.opacity = target
        guard !reduceMotion else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = from
        fade.toValue = target
        fade.duration = 0.16
        hoverLayer.add(fade, forKey: "hoverFade")
    }

    /// Scale about the tile centre. NSView layers anchor at the origin, so translate around it.
    private func scaleTransform(_ scale: CGFloat) -> CATransform3D {
        var t = CATransform3DMakeTranslation(bounds.midX, bounds.midY, 0)
        t = CATransform3DScale(t, scale, scale, 1)
        return CATransform3DTranslate(t, -bounds.midX, -bounds.midY, 0)
    }

    private func animateScale(to scale: CGFloat) {
        guard let layer else { return }
        let from = layer.presentation()?.transform ?? layer.transform
        let target = scaleTransform(scale)
        layer.transform = target
        guard !reduceMotion else { return }
        let spring = CASpringAnimation(keyPath: "transform")
        spring.fromValue = NSValue(caTransform3D: from)
        spring.toValue = NSValue(caTransform3D: target)
        spring.damping = 16
        spring.stiffness = 260
        spring.mass = 1
        spring.duration = spring.settlingDuration
        layer.add(spring, forKey: "scale")
    }

    private func popSelection() {
        guard let layer, !reduceMotion else { return }
        let spring = CASpringAnimation(keyPath: "transform")
        spring.fromValue = NSValue(caTransform3D: scaleTransform(0.94))
        spring.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        spring.damping = 12
        spring.stiffness = 320
        spring.mass = 1
        spring.duration = spring.settlingDuration
        layer.transform = CATransform3DIdentity
        layer.add(spring, forKey: "scale")
    }

    /// Cells are reused: drop any in-flight motion so a recycled tile never starts mid-hover.
    func resetMotion() {
        isHovered = false
        hoverLayer.removeAllAnimations()
        hoverLayer.opacity = 0
        layer?.removeAllAnimations()
        layer?.transform = CATransform3DIdentity
    }

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

        // The graphic fills the space above the two text lines and scales with the tile, so the
        // size slider resizes the icon instead of pushing it into the name.
        let textTop: CGFloat = 46
        let graphicArea = bounds.height - textTop - 12
        let graphicScale = max(0.5, graphicArea / 64)
        let graphicCenterY = textTop + 2 + graphicArea / 2
        let centerX = bounds.midX

        NSGraphicsContext.saveGraphicsState()
        let zoom = NSAffineTransform()
        zoom.translateX(by: centerX, yBy: graphicCenterY)
        zoom.scale(by: graphicScale)
        zoom.translateX(by: -centerX, yBy: -graphicCenterY)
        zoom.concat()
        if item.isFolderLike {
            drawFolderGraphic(centerX: centerX, centerY: graphicCenterY, appearance: appearance)
        } else if item.isAppOrPackage {
            drawAppIconGraphic(item: item, centerX: centerX, centerY: graphicCenterY)
        } else if item.isImageOrVideo {
            drawImageGraphic(item: item, centerX: centerX, centerY: graphicCenterY)
        } else {
            drawPaperGraphic(item: item, centerX: centerX, centerY: graphicCenterY)
        }
        NSGraphicsContext.restoreGraphicsState()

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
