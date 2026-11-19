import SwiftUI
import AppKit

enum AppThemeOverride: String, CaseIterable, Codable, Sendable {
    case system = "auto"
    case dark = "dark"
    case light = "light"

    var label: String {
        switch self {
        case .system: return "Match system"
        case .dark: return "Dark"
        case .light: return "Light"
        }
    }
}

enum AccentMode: String, CaseIterable, Codable, Sendable {
    case system = "system"
    case wallpaper = "wallpaper"
    case swatch = "swatch"
    case custom = "custom"
}

enum RowDensity: String, CaseIterable, Codable, Sendable {
    case compact = "Compact"
    case comfortable = "Comfortable"
    case spacious = "Spacious"

    var rowHeight: CGFloat {
        switch self {
        case .compact: return 24
        case .comfortable: return 30
        case .spacious: return 36
        }
    }
}

enum GlassBlurStyle: String, CaseIterable, Codable, Identifiable, Sendable {
    case hudGlass = "HUD Deep Glass"
    case sidebarVibrancy = "Desktop Vibrancy"
    case frostedPopover = "Frosted Crystal"
    case ultraDarkAcrylic = "Obsidian Acrylic"

    var id: String { rawValue }

    var nsMaterial: NSVisualEffectView.Material {
        switch self {
        case .hudGlass: return .hudWindow
        case .sidebarVibrancy: return .sidebar
        case .frostedPopover: return .popover
        case .ultraDarkAcrylic: return .underWindowBackground
        }
    }
}

struct StratumThemePreset: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var name: String
    var subtitle: String
    var mode: AppThemeOverride
    var windowTintHex: String
    var sidebarTintHex: String
    var cardTintHex: String
    var accentHex: String
    var translucency: Double       // 0...100 (higher = more translucent glass)
    var cardGlowIntensity: Double  // 0...100
    var blurStyle: GlassBlurStyle
    var isBuiltIn: Bool
}

struct AccentSwatch: Identifiable, Sendable {
    var id: String { name }
    let name: String
    let hex: String
}
