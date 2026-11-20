import SwiftUI
import AppKit

typealias StratumThemeMode = AppThemeOverride

@Observable
@MainActor
final class AppearanceManager {
    static let shared = AppearanceManager()

    var activeThemeID: String {
        didSet {
            UserDefaults.standard.set(activeThemeID, forKey: "stratum.activeThemeID")
        }
    }

    var customThemes: [StratumThemePreset] = [] {
        didSet {
            if let data = try? JSONEncoder().encode(customThemes) {
                UserDefaults.standard.set(data, forKey: "stratum.customThemes")
            }
        }
    }

    var allThemes: [StratumThemePreset] {
        Self.builtInThemes + customThemes
    }

    var themeOverride: AppThemeOverride {
        didSet {
            UserDefaults.standard.set(themeOverride.rawValue, forKey: "stratum.themeOverride")
            applyWindowAppearance()
        }
    }

    var accentMode: AccentMode {
        didSet {
            UserDefaults.standard.set(accentMode.rawValue, forKey: "stratum.accentMode")
            if accentMode == .wallpaper {
                sampleWallpaperColor()
            }
            refreshColors()
        }
    }

    var customHex: String {
        didSet {
            UserDefaults.standard.set(customHex, forKey: "stratum.customHex")
            refreshColors()
        }
    }

    var windowTintHex: String {
        didSet {
            UserDefaults.standard.set(windowTintHex, forKey: "stratum.windowTintHex")
            refreshColors()
        }
    }

    var sidebarTintHex: String {
        didSet {
            UserDefaults.standard.set(sidebarTintHex, forKey: "stratum.sidebarTintHex")
            refreshColors()
        }
    }

    var cardTintHex: String {
        didSet {
            UserDefaults.standard.set(cardTintHex, forKey: "stratum.cardTintHex")
            refreshColors()
        }
    }

    var cardGlowIntensity: Double {
        didSet {
            UserDefaults.standard.set(cardGlowIntensity, forKey: "stratum.cardGlowIntensity")
        }
    }

    var blurStyle: GlassBlurStyle {
        didSet {
            UserDefaults.standard.set(blurStyle.rawValue, forKey: "stratum.blurStyle")
        }
    }

    var tintFolders: Bool {
        didSet {
            UserDefaults.standard.set(tintFolders, forKey: "stratum.tintFolders")
            refreshColors()
        }
    }

    var allowPerFolderAccent: Bool {
        didSet {
            UserDefaults.standard.set(allowPerFolderAccent, forKey: "stratum.allowPerFolderAccent")
        }
    }

    var translucency: Double {
        didSet {
            UserDefaults.standard.set(translucency, forKey: "stratum.translucency")
        }
    }

    var enableBlur: Bool {
        didSet {
            UserDefaults.standard.set(enableBlur, forKey: "stratum.enableBlur")
        }
    }

    var enableWallpaperWash: Bool {
        didSet {
            UserDefaults.standard.set(enableWallpaperWash, forKey: "stratum.enableWallpaperWash")
        }
    }

    var density: RowDensity {
        didSet {
            UserDefaults.standard.set(density.rawValue, forKey: "stratum.density")
        }
    }

    private(set) var sampledWallpaperHex: String = "#44D492"
    private(set) var systemAccentNSColor: NSColor = .controlAccentColor
    private(set) var reduceTransparency: Bool = false
    private(set) var increaseContrast: Bool = false

    // MARK: - Bindable Bridges for Settings & Views

    var themeMode: AppThemeOverride {
        get { themeOverride }
        set { themeOverride = newValue }
    }

    /// Picks Light, Dark or Match system. Each theme carries its own dark or light tints, so a
    /// mode that doesn't suit the current theme switches to the first theme that does; without
    /// that, Light over a dark theme gives a muddy grey-green window.
    func selectMode(_ mode: AppThemeOverride) {
        let systemIsDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if let match = Self.themeToSwitchTo(for: mode, activeID: activeThemeID, themes: allThemes, systemIsDark: systemIsDark) {
            applyThemePreset(match)
        }
        themeOverride = mode
    }

    /// The theme to move to when `mode` doesn't suit the active one, or nil to keep it.
    static func themeToSwitchTo(for mode: AppThemeOverride, activeID: String, themes: [StratumThemePreset], systemIsDark: Bool) -> StratumThemePreset? {
        let wantsDark = mode == .system ? systemIsDark : mode == .dark
        guard let current = themes.first(where: { $0.id == activeID }),
              (current.mode != .light) != wantsDark else { return nil }
        return themes.first { ($0.mode != .light) == wantsDark }
    }

    var accentSource: AccentMode {
        get { accentMode }
        set { accentMode = newValue }
    }

    var selectedSwatchIndex: Int {
        get {
            Self.swatches.firstIndex(where: { $0.hex.caseInsensitiveCompare(customHex) == .orderedSame }) ?? 0
        }
        set {
            if Self.swatches.indices.contains(newValue) {
                customHex = Self.swatches[newValue].hex
            }
        }
    }

    var tintFoldersWithAccent: Bool {
        get { tintFolders }
        set { tintFolders = newValue }
    }

    var enableBackgroundBlur: Bool {
        get { enableBlur }
        set { enableBlur = newValue }
    }

    var activeHexString: String { accentHexString }
    var activeAccentName: String { accentDisplayName }
    var selectionTintColor: Color { selectionFillColor }
    var faintTintColor: Color { accentFaintColor }

    func sampleDesktopWallpaperColor() {
        sampleWallpaperColor()
    }

    func restoreDefaults() {
        resetToDefaults()
    }

    init() {
        let d = UserDefaults.standard
        if let savedCustomData = d.data(forKey: "stratum.customThemes"),
           let decoded = try? JSONDecoder().decode([StratumThemePreset].self, from: savedCustomData) {
            self.customThemes = decoded
        } else {
            self.customThemes = []
        }

        let defaultPreset = Self.builtInThemes[0]
        self.activeThemeID = d.string(forKey: "stratum.activeThemeID") ?? defaultPreset.id
        self.themeOverride = AppThemeOverride(rawValue: d.string(forKey: "stratum.themeOverride") ?? defaultPreset.mode.rawValue) ?? defaultPreset.mode
        self.accentMode = AccentMode(rawValue: d.string(forKey: "stratum.accentMode") ?? "swatch") ?? .swatch
        self.customHex = d.string(forKey: "stratum.customHex") ?? defaultPreset.accentHex
        self.windowTintHex = d.string(forKey: "stratum.windowTintHex") ?? defaultPreset.windowTintHex
        self.sidebarTintHex = d.string(forKey: "stratum.sidebarTintHex") ?? defaultPreset.sidebarTintHex
        self.cardTintHex = d.string(forKey: "stratum.cardTintHex") ?? defaultPreset.cardTintHex
        self.cardGlowIntensity = d.object(forKey: "stratum.cardGlowIntensity") as? Double ?? defaultPreset.cardGlowIntensity
        self.blurStyle = GlassBlurStyle(rawValue: d.string(forKey: "stratum.blurStyle") ?? defaultPreset.blurStyle.rawValue) ?? defaultPreset.blurStyle
        self.tintFolders = d.object(forKey: "stratum.tintFolders") as? Bool ?? true
        self.allowPerFolderAccent = d.object(forKey: "stratum.allowPerFolderAccent") as? Bool ?? true
        self.translucency = d.object(forKey: "stratum.translucency") as? Double ?? defaultPreset.translucency
        self.enableBlur = d.object(forKey: "stratum.enableBlur") as? Bool ?? true
        self.enableWallpaperWash = d.object(forKey: "stratum.enableWallpaperWash") as? Bool ?? true
        self.density = RowDensity(rawValue: d.string(forKey: "stratum.density") ?? "Comfortable") ?? .comfortable

        self.reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        self.increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast

        NotificationCenter.default.addObserver(
            forName: NSColor.systemColorsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.systemAccentNSColor = .controlAccentColor
                self?.refreshColors()
            }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
                self.increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                if self?.accentMode == .wallpaper {
                    self?.sampleWallpaperColor()
                }
            }
        }

        if accentMode == .wallpaper {
            sampleWallpaperColor()
        }
    }

    // MARK: - Apply & Save Theme Presets

    func applyThemePreset(_ preset: StratumThemePreset) {
        withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
            activeThemeID = preset.id
            themeOverride = preset.mode
            windowTintHex = preset.windowTintHex
            sidebarTintHex = preset.sidebarTintHex
            cardTintHex = preset.cardTintHex
            customHex = preset.accentHex
            accentMode = .swatch
            translucency = preset.translucency
            cardGlowIntensity = preset.cardGlowIntensity
            blurStyle = preset.blurStyle
            enableBlur = true
        }
    }

    func saveCurrentAsCustomTheme(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "Custom Glass Theme \(customThemes.count + 1)" : trimmed
        let id = "custom-\(UUID().uuidString.prefix(8))"
        let newTheme = StratumThemePreset(
            id: id,
            name: finalName,
            subtitle: "Custom \(activeHexString) glass theme · \(Int(translucency))% translucency",
            mode: themeOverride,
            windowTintHex: windowTintHex,
            sidebarTintHex: sidebarTintHex,
            cardTintHex: cardTintHex,
            accentHex: activeHexString,
            translucency: translucency,
            cardGlowIntensity: cardGlowIntensity,
            blurStyle: blurStyle,
            isBuiltIn: false
        )
        customThemes.append(newTheme)
        activeThemeID = newTheme.id
    }

    func updateActiveCustomTheme() {
        guard let idx = customThemes.firstIndex(where: { $0.id == activeThemeID }) else { return }
        customThemes[idx].mode = themeOverride
        customThemes[idx].windowTintHex = windowTintHex
        customThemes[idx].sidebarTintHex = sidebarTintHex
        customThemes[idx].cardTintHex = cardTintHex
        customThemes[idx].accentHex = activeHexString
        customThemes[idx].translucency = translucency
        customThemes[idx].cardGlowIntensity = cardGlowIntensity
        customThemes[idx].blurStyle = blurStyle
        customThemes[idx].subtitle = "Custom \(activeHexString) glass theme · \(Int(translucency))% translucency"
    }

    func deleteCustomTheme(_ preset: StratumThemePreset) {
        customThemes.removeAll(where: { $0.id == preset.id })
        if activeThemeID == preset.id, let first = Self.builtInThemes.first {
            applyThemePreset(first)
        }
    }

    func resetToDefaults() {
        applyThemePreset(Self.builtInThemes[0])
        tintFolders = true
        allowPerFolderAccent = true
        enableWallpaperWash = true
        density = .comfortable
    }

    func refreshColors() {
        NotificationCenter.default.post(name: .stratumAppearanceDidChange, object: nil)
    }

    func applyWindowAppearance() {
        let appearance: NSAppearance?
        switch themeOverride {
        case .system:
            appearance = nil
        case .dark:
            appearance = NSAppearance(named: .darkAqua)
        case .light:
            appearance = NSAppearance(named: .aqua)
        }
        NSApp?.appearance = appearance
        for window in NSApp?.windows ?? [] {
            window.appearance = appearance
            window.isOpaque = false
            window.backgroundColor = .clear
        }
    }

    var activeNSColor: NSColor {
        switch accentMode {
        case .system:
            return systemAccentNSColor.usingColorSpace(.sRGB) ?? .controlAccentColor
        case .wallpaper:
            return NSColor(hex: sampledWallpaperHex) ?? .controlAccentColor
        case .swatch, .custom:
            return NSColor(hex: customHex) ?? .controlAccentColor
        }
    }

    var accentColor: Color {
        Color(nsColor: activeNSColor)
    }

    var accentHexString: String {
        activeNSColor.toHexString()
    }

    var accentDisplayName: String {
        if let activePreset = allThemes.first(where: { $0.id == activeThemeID }),
           activePreset.accentHex.caseInsensitiveCompare(activeHexString) == .orderedSame {
            return activePreset.name
        }
        switch accentMode {
        case .system:
            return "System accent"
        case .wallpaper:
            return "From wallpaper"
        case .swatch:
            return Self.swatches.first(where: { $0.hex.caseInsensitiveCompare(customHex) == .orderedSame })?.name ?? "Custom"
        case .custom:
            return "Custom"
        }
    }

    // MARK: - Glass & Surface Colors

    var windowSurfaceNSColor: NSColor {
        NSColor(hex: windowTintHex) ?? NSColor(srgbRed: 0.05, green: 0.07, blue: 0.10, alpha: 1.0)
    }

    var sidebarSurfaceNSColor: NSColor {
        NSColor(hex: sidebarTintHex) ?? NSColor(srgbRed: 0.06, green: 0.08, blue: 0.12, alpha: 1.0)
    }

    var cardSurfaceNSColor: NSColor {
        NSColor(hex: cardTintHex) ?? NSColor(srgbRed: 0.09, green: 0.12, blue: 0.17, alpha: 1.0)
    }

    var windowGlassColor: Color {
        Color(nsColor: windowSurfaceNSColor).opacity(contentBackgroundOpacity)
    }

    var sidebarGlassColor: Color {
        Color(nsColor: sidebarSurfaceNSColor).opacity(sidebarBackgroundOpacity)
    }

    var cardGlassFillColor: Color {
        Color(nsColor: cardSurfaceNSColor).opacity(cardBackgroundOpacity)
    }

    var glowFraction: Double {
        min(1.0, max(0.0, cardGlowIntensity / 100.0))
    }

    var selectionFillColor: Color {
        accentColor.opacity(increaseContrast ? 0.36 : 0.20)
    }

    var selectionBorderColor: Color {
        accentColor.opacity(increaseContrast ? 0.92 : (0.48 + 0.35 * glowFraction))
    }

    var accentSoftColor: Color {
        accentColor.opacity(0.18)
    }

    var accentFaintColor: Color {
        accentColor.opacity(0.11)
    }

    var folderFrontNSColor: NSColor {
        if tintFolders {
            return activeNSColor.blended(withFraction: 0.22, of: .white) ?? activeNSColor
        }
        return NSColor(hex: "#8E8A9E") ?? .secondaryLabelColor
    }

    var folderBackNSColor: NSColor {
        if tintFolders {
            return activeNSColor.blended(withFraction: 0.28, of: .black) ?? activeNSColor
        }
        return NSColor(hex: "#6E6A80") ?? .tertiaryLabelColor
    }

    var folderFrontColor: Color {
        Color(nsColor: folderFrontNSColor)
    }

    var folderBackColor: Color {
        Color(nsColor: folderBackNSColor)
    }

    var contentBackgroundOpacity: Double {
        if reduceTransparency || !enableBlur {
            return 0.98
        }
        let clamped = min(100, max(0, translucency))
        // Maps 0% translucency -> 0.96 opacity, 80% translucency -> 0.56 opacity, 100% -> 0.42 opacity
        return max(0.40, 0.96 - (clamped * 0.0052))
    }

    var sidebarBackgroundOpacity: Double {
        if reduceTransparency || !enableBlur {
            return 0.98
        }
        let clamped = min(100, max(0, translucency))
        return max(0.32, 0.92 - (clamped * 0.0058))
    }

    var cardBackgroundOpacity: Double {
        if reduceTransparency || !enableBlur {
            return 0.94
        }
        let clamped = min(100, max(0, translucency))
        return max(0.42, 0.88 - (clamped * 0.0042))
    }

    func sampleWallpaperColor() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first,
              let url = NSWorkspace.shared.desktopImageURL(for: screen) else {
            return
        }
        DispatchQueue.global(qos: .utility).async {
            guard let image = NSImage(contentsOf: url),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                return
            }
            let width = 32
            let height = 32
            var rawData = [UInt8](repeating: 0, count: width * height * 4)
            guard let context = CGContext(
                data: &rawData,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }

            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

            var bestR: Double = 0.18
            var bestG: Double = 0.42
            var bestB: Double = 1.0
            var totalWeight: Double = 0.0
            var weightedR: Double = 0
            var weightedG: Double = 0
            var weightedB: Double = 0

            for i in stride(from: 0, to: rawData.count, by: 4) {
                let r = Double(rawData[i]) / 255.0
                let g = Double(rawData[i + 1]) / 255.0
                let b = Double(rawData[i + 2]) / 255.0
                let maxC = max(r, g, b)
                let minC = min(r, g, b)
                let sat = maxC > 0 ? (maxC - minC) / maxC : 0
                let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
                let weight = (sat + 0.15) * (1.0 - abs(lum - 0.5))
                weightedR += r * weight
                weightedG += g * weight
                weightedB += b * weight
                totalWeight += weight
            }

            if totalWeight > 0 {
                bestR = weightedR / totalWeight
                bestG = weightedG / totalWeight
                bestB = weightedB / totalWeight
            }

            let nsColor = NSColor(srgbRed: bestR, green: bestG, blue: bestB, alpha: 1.0)
            var h: CGFloat = 0, s: CGFloat = 0, br: CGFloat = 0, a: CGFloat = 0
            nsColor.getHue(&h, saturation: &s, brightness: &br, alpha: &a)
            let adjusted = NSColor(
                hue: h,
                saturation: min(0.85, max(0.48, s * 1.25)),
                brightness: min(0.88, max(0.55, br)),
                alpha: 1.0
            )
            let hex = adjusted.toHexString()
            Task { @MainActor in
                AppearanceManager.shared.sampledWallpaperHex = hex
                AppearanceManager.shared.refreshColors()
            }
        }
    }
}

extension Notification.Name {
    static let stratumAppearanceDidChange = Notification.Name("stratumAppearanceDidChange")
}
