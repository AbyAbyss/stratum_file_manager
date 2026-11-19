import SwiftUI
import AppKit

enum StratumAppIconGenerator {
    @MainActor
    static func applyCustomDockIcon(accentColor: NSColor) {
        let size = NSSize(width: 512, height: 512)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            // macOS Squircle Background
            let insetRect = rect.insetBy(dx: 28, dy: 28)
            let squircle = NSBezierPath(roundedRect: insetRect, xRadius: 104, yRadius: 104)

            ctx.saveGState()
            squircle.addClip()

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

            // Radial accent glow in center
            let glowColors = [
                accentColor.withAlphaComponent(0.42).cgColor,
                accentColor.withAlphaComponent(0.0).cgColor
            ] as CFArray
            if let radial = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: glowColors, locations: [0.0, 1.0]) {
                ctx.drawRadialGradient(
                    radial,
                    startCenter: CGPoint(x: 256, y: 256),
                    startRadius: 10,
                    endCenter: CGPoint(x: 256, y: 256),
                    endRadius: 210,
                    options: []
                )
            }

            // Draw 3 Isometric Stratum Plates
            let plateOffsets: [(yCenter: CGFloat, alpha: CGFloat, highlight: Bool)] = [
                (176, 0.42, false),
                (252, 0.75, false),
                (328, 1.00, true)
            ]

            for plate in plateOffsets {
                let w: CGFloat = 290
                let h: CGFloat = 152
                let cx: CGFloat = 256
                let cy: CGFloat = plate.yCenter

                let diamond = NSBezierPath()
                diamond.move(to: CGPoint(x: cx, y: cy + h * 0.5))
                diamond.line(to: CGPoint(x: cx + w * 0.5, y: cy))
                diamond.line(to: CGPoint(x: cx, y: cy - h * 0.5))
                diamond.line(to: CGPoint(x: cx - w * 0.5, y: cy))
                diamond.close()

                ctx.saveGState()
                ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 20, color: NSColor.black.withAlphaComponent(0.45).cgColor)

                if plate.highlight {
                    accentColor.setFill()
                } else {
                    accentColor.withAlphaComponent(plate.alpha).setFill()
                }
                diamond.fill()
                ctx.restoreGState()

                NSColor.white.withAlphaComponent(plate.highlight ? 0.85 : 0.35).setStroke()
                diamond.lineWidth = plate.highlight ? 5.0 : 3.0
                diamond.stroke()
            }

            ctx.restoreGState()

            // Outer squircle rim highlight
            NSColor.white.withAlphaComponent(0.18).setStroke()
            squircle.lineWidth = 4.0
            squircle.stroke()

            return true
        }

        NSApplication.shared.applicationIconImage = image
    }
}
