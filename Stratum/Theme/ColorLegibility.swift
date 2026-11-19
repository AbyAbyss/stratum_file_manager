import SwiftUI
import AppKit

extension Color {
    /// A tint for small text sitting on a faint tint of itself (badges, tags).
    /// Unchanged in dark appearance; darkened in light appearance, where pale yellows and
    /// mints otherwise fall below readable contrast on a light surface.
    static func stratumLabel(_ tint: Color) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let base = NSColor(tint)
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? base : (base.blended(withFraction: 0.5, of: .black) ?? base)
        })
    }
}
