import SwiftUI
import AppKit

/// Draws the Stratum icon: three isometric plates (the "strata") on a night-green squircle.
///
/// One drawing routine feeds both the static `AppIcon` asset (Finder, Launchpad, Spotlight, the
/// DMG) and the accent-tinted Dock icon set at runtime, so they always match in shape and
/// size. Proportions follow Apple's macOS icon template: an 824pt squircle centred on a
/// 1024pt canvas, with a soft shadow underneath.
enum StratumAppIconGenerator {
    /// Brand colour of the static icon (the default emerald theme accent).
    static let brandAccent = NSColor(srgbRed: 0.267, green: 0.831, blue: 0.573, alpha: 1)

    /// Icon at `size` points square, drawn crisply at whatever resolution it is shown.
    static func makeIcon(accentColor: NSColor, size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            draw(in: ctx, canvas: rect.width, accentColor: accentColor)
            return true
        }
    }

    @MainActor
    static func applyCustomDockIcon(accentColor: NSColor) {
        NSApplication.shared.applicationIconImage = makeIcon(accentColor: accentColor, size: 512)
    }

    /// Renders the icon into `ctx` on a square `canvas`. The artwork is laid out in a 512-unit
    /// design space (squircle inset 28) and scaled so the squircle fills 80% of the canvas.
    static func draw(in ctx: CGContext, canvas: CGFloat, accentColor: NSColor) {
        let design: CGFloat = 512
        let bodyInDesign = design - 56
        let scale = (canvas * 0.8046875) / bodyInDesign          // 824 / 1024
        ctx.saveGState()
        ctx.translateBy(x: canvas / 2, y: canvas / 2)
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -design / 2, y: -design / 2)

        let insetRect = CGRect(x: 28, y: 28, width: bodyInDesign, height: bodyInDesign)
        let squircle = CGPath(roundedRect: insetRect, cornerWidth: 104, cornerHeight: 104, transform: nil)

        // Soft contact shadow under the whole icon
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -9), blur: 18, color: NSColor.black.withAlphaComponent(0.38).cgColor)
        ctx.addPath(squircle)
        ctx.setFillColor(NSColor(calibratedRed: 0.05, green: 0.08, blue: 0.07, alpha: 1).cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(squircle)
        ctx.clip()

        let bgColors = [
            NSColor(calibratedRed: 0.05, green: 0.08, blue: 0.07, alpha: 1.0).cgColor,
            NSColor(calibratedRed: 0.09, green: 0.14, blue: 0.12, alpha: 1.0).cgColor
        ] as CFArray
        if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: bgColors, locations: [0.0, 1.0]) {
            ctx.drawLinearGradient(
                grad,
                start: CGPoint(x: insetRect.minX, y: insetRect.maxY),
                end: CGPoint(x: insetRect.maxX, y: insetRect.minY),
                options: []
            )
        }

        // Radial accent glow in the centre
        let glowColors = [
            accentColor.withAlphaComponent(0.42).cgColor,
            accentColor.withAlphaComponent(0.0).cgColor
        ] as CFArray
        if let radial = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: glowColors, locations: [0.0, 1.0]) {
            ctx.drawRadialGradient(
                radial,
                startCenter: CGPoint(x: 256, y: 256), startRadius: 10,
                endCenter: CGPoint(x: 256, y: 256), endRadius: 210,
                options: []
            )
        }

        // Three isometric Stratum plates, the top one solid and highlighted
        let plates: [(yCenter: CGFloat, alpha: CGFloat, highlight: Bool)] = [
            (176, 0.42, false),
            (252, 0.75, false),
            (328, 1.00, true)
        ]
        for plate in plates {
            let w: CGFloat = 290, h: CGFloat = 152, cx: CGFloat = 256, cy = plate.yCenter
            let diamond = CGMutablePath()
            diamond.move(to: CGPoint(x: cx, y: cy + h * 0.5))
            diamond.addLine(to: CGPoint(x: cx + w * 0.5, y: cy))
            diamond.addLine(to: CGPoint(x: cx, y: cy - h * 0.5))
            diamond.addLine(to: CGPoint(x: cx - w * 0.5, y: cy))
            diamond.closeSubpath()

            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 20, color: NSColor.black.withAlphaComponent(0.45).cgColor)
            ctx.addPath(diamond)
            ctx.setFillColor((plate.highlight ? accentColor : accentColor.withAlphaComponent(plate.alpha)).cgColor)
            ctx.fillPath()
            ctx.restoreGState()

            ctx.addPath(diamond)
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(plate.highlight ? 0.85 : 0.35).cgColor)
            ctx.setLineWidth(plate.highlight ? 5 : 3)
            ctx.strokePath()
        }
        ctx.restoreGState()

        // Rim highlight on the squircle edge
        ctx.addPath(squircle)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.18).cgColor)
        ctx.setLineWidth(4)
        ctx.strokePath()

        ctx.restoreGState()
    }

    #if DEBUG
    /// Writes the asset-catalog PNGs to `directory` (run the app with `STRATUM_EXPORT_ICON=<dir>`).
    /// Each size is drawn natively, not downscaled, so small sizes stay crisp.
    static func exportIconSet(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for pixels in [16, 32, 64, 128, 256, 512, 1024] {
            guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0
            ), let gc = NSGraphicsContext(bitmapImageRep: rep) else { continue }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = gc
            draw(in: gc.cgContext, canvas: CGFloat(pixels), accentColor: brandAccent)
            NSGraphicsContext.restoreGraphicsState()
            try? rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("icon_\(pixels).png"))
        }
    }
    #endif
}
