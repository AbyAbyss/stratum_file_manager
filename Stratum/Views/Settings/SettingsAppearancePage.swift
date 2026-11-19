import SwiftUI
import AppKit

/// Appearance: a live preview, then theme, accent colour, window glass, and advanced tints.
struct SettingsAppearancePage: View {
    @Bindable var appState: AppState
    @Bindable var appearance: AppearanceManager

    @State private var hexDraft = ""
    @State private var customThemeName = ""
    @State private var showAdvanced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsLivePreview(appearance: appearance)

            themeGroup
            accentGroup
            windowGroup
            advancedSection

            SettingsButton(title: "Restore default look", systemImage: "arrow.counterclockwise", appearance: appearance) {
                appearance.restoreDefaults()
                hexDraft = appearance.activeHexString
                appState.showToast("Restored the default look")
            }
        }
        .onAppear { hexDraft = appearance.activeHexString }
        .onChange(of: appearance.activeHexString) { _, newValue in hexDraft = newValue }
    }

    // MARK: Theme

    private var themeGroup: some View {
        SettingsGroup("Theme", footer: "A theme sets the window, sidebar and card tints, the accent, the blur and the translucency together. Change any of them below to make it your own, then save it.", appearance: appearance) {
            SettingsRow("Mode", detail: "Follow macOS, or choose light or dark.") {
                SettingsSegmented(
                    options: [(AppThemeOverride.system, "Match system"), (.light, "Light"), (.dark, "Dark")],
                    selection: $appearance.themeMode,
                    appearance: appearance
                )
            }
            SettingsDivider()
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190, maximum: 280), spacing: 14)], spacing: 14) {
                ForEach(appearance.allThemes) { preset in
                    SettingsThemeCard(
                        preset: preset,
                        isSelected: appearance.activeThemeID == preset.id,
                        onSelect: {
                            appearance.applyThemePreset(preset)
                            hexDraft = preset.accentHex
                        },
                        onDelete: preset.isBuiltIn ? nil : { appearance.deleteCustomTheme(preset) }
                    )
                }
            }
            .padding(16)
            SettingsDivider()
            HStack(spacing: 10) {
                SettingsTextField(placeholder: "Name your own theme, e.g. Midnight Emerald", text: $customThemeName, onSubmit: saveCustomTheme)
                SettingsButton(title: "Save current look", systemImage: "plus", kind: .primary, appearance: appearance, action: saveCustomTheme)
                if let custom = appearance.customThemes.first(where: { $0.id == appearance.activeThemeID }) {
                    SettingsButton(title: "Update “\(custom.name)”", systemImage: nil, appearance: appearance) {
                        appearance.updateActiveCustomTheme()
                        appState.showToast("Updated “\(custom.name)”")
                    }
                }
            }
            .padding(16)
        }
    }

    private func saveCustomTheme() {
        let name = customThemeName.trimmingCharacters(in: .whitespacesAndNewlines)
        appearance.saveCurrentAsCustomTheme(named: name)
        appState.showToast("Saved theme “\(name.isEmpty ? "Custom Glass Theme" : name)”")
        customThemeName = ""
    }

    // MARK: Accent

    private var accentGroup: some View {
        SettingsGroup("Accent colour", footer: "Used for selections, buttons, progress bars and highlights.", appearance: appearance) {
            HStack(spacing: 12) {
                accentModeTile(
                    title: "macOS accent",
                    detail: "Follows System Settings",
                    isSelected: appearance.accentSource == .system,
                    preview: AnyView(Circle().fill(Color(nsColor: .controlAccentColor)))
                ) {
                    appearance.accentSource = .system
                }
                accentModeTile(
                    title: "From wallpaper",
                    detail: "Matched to your desktop picture",
                    isSelected: appearance.accentSource == .wallpaper,
                    preview: AnyView(Circle().fill(AngularGradient(colors: [.purple, .blue, .teal, .orange, .pink, .purple], center: .center)))
                ) {
                    appearance.sampleDesktopWallpaperColor()
                    appearance.accentSource = .wallpaper
                    appState.showToast("Picked \(appearance.activeHexString) from your wallpaper")
                }
            }
            .padding(16)
            SettingsDivider()
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 38), spacing: 12)], spacing: 12) {
                ForEach(Array(AppearanceManager.swatches.enumerated()), id: \.element.id) { index, swatch in
                    swatchButton(index: index, swatch: swatch)
                }
            }
            .padding(16)
            SettingsDivider()
            SettingsRow("Custom colour", detail: "Pick any colour, or type a hex code.") {
                HStack(spacing: 8) {
                    ColorPicker("", selection: customAccentBinding, supportsOpacity: false)
                        .labelsHidden()
                        .accessibilityLabel("Custom accent colour")
                    SettingsTextField(placeholder: "#44D492", text: $hexDraft, monospaced: true, onSubmit: applyHexDraft)
                        .frame(width: 104)
                    SettingsButton(title: "Apply", systemImage: nil, appearance: appearance, action: applyHexDraft)
                }
            }
            SettingsDivider()
            SettingsToggleRow(title: "Tint folders with the accent", detail: "Folder icons take the accent instead of neutral grey.", isOn: $appearance.tintFoldersWithAccent, appearance: appearance)
            SettingsDivider()
            SettingsToggleRow(title: "Allow a different accent per folder", detail: "Set one from a folder's context menu, handy for telling projects apart.", isOn: $appearance.allowPerFolderAccent, appearance: appearance)
        }
    }

    private func accentModeTile(title: String, detail: String, isSelected: Bool, preview: AnyView, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                preview.frame(width: 30, height: 30).overlay(Circle().strokeBorder(Color.primary.opacity(0.18), lineWidth: 1))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13.5, weight: .semibold))
                    Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if isSelected { Image(systemName: "checkmark.circle.fill").foregroundStyle(appearance.accentColor) }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(isSelected ? appearance.accentColor : Color.primary.opacity(0.1), lineWidth: isSelected ? 2 : 1))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func swatchButton(index: Int, swatch: AccentSwatch) -> some View {
        let color = Color(nsColor: NSColor(hex: swatch.hex) ?? .systemGreen)
        let isSelected = appearance.accentSource == .swatch && appearance.activeHexString.caseInsensitiveCompare(swatch.hex) == .orderedSame
        return Button {
            appearance.selectedSwatchIndex = index
            appearance.accentSource = .swatch
        } label: {
            Circle()
                .fill(color)
                .frame(width: 30, height: 30)
                .overlay(Circle().strokeBorder(isSelected ? Color.primary : Color.primary.opacity(0.15), lineWidth: isSelected ? 2.5 : 1))
                .overlay { if isSelected { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white).shadow(radius: 2) } }
                .shadow(color: isSelected ? color.opacity(0.5) : .clear, radius: 6)
                .frame(width: 38, height: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .stratumHelp(swatch.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var customAccentBinding: Binding<Color> {
        Binding(
            get: { appearance.accentColor },
            set: { newColor in
                guard let ns = NSColor(newColor).usingColorSpace(.sRGB) else { return }
                appearance.customHex = ns.toHexString()
                appearance.accentSource = .custom
                hexDraft = appearance.customHex
            }
        )
    }

    private func applyHexDraft() {
        let cleaned = hexDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard NSColor(hex: cleaned) != nil else {
            appState.showToast("That isn't a valid hex colour (use #RRGGBB)")
            return
        }
        appearance.customHex = cleaned.hasPrefix("#") ? cleaned.uppercased() : "#\(cleaned.uppercased())"
        appearance.accentSource = .custom
        hexDraft = appearance.customHex
    }

    // MARK: Window and glass

    private var windowGroup: some View {
        SettingsGroup("Window & glass", appearance: appearance) {
            SettingsRow("Blur material", detail: "How the desktop shows through the window.") {
                Picker("Blur material", selection: $appearance.blurStyle) {
                    ForEach(GlassBlurStyle.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .frame(width: 190)
            }
            SettingsDivider()
            SettingsSliderRow(title: "Translucency", valueText: "\(Int(appearance.translucency))%", lowLabel: "Solid", highLabel: "Deep glass", value: $appearance.translucency, appearance: appearance)
            SettingsDivider()
            SettingsSliderRow(title: "Card border glow", valueText: "\(Int(appearance.cardGlowIntensity))%", lowLabel: "Subtle", highLabel: "Vivid", value: $appearance.cardGlowIntensity, appearance: appearance)
            SettingsDivider()
            SettingsToggleRow(title: "Blur what's behind the window", detail: "Turns off by itself when Reduce Transparency is on in macOS.", isOn: $appearance.enableBackgroundBlur, appearance: appearance)
            SettingsDivider()
            SettingsToggleRow(title: "Ambient accent glow", detail: "A soft bloom of the accent in the top-left corner of the window.", isOn: $appearance.enableWallpaperWash, appearance: appearance)
            SettingsDivider()
            SettingsRow("Row density", detail: "How much space file rows take.") {
                SettingsSegmented(options: RowDensity.allCases.map { ($0, $0.rawValue) }, selection: $appearance.density, appearance: appearance)
            }
        }
    }

    // MARK: Advanced

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showAdvanced.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .rotationEffect(.degrees(showAdvanced ? 90 : 0))
                    Text("Advanced: surface tints").font(.system(size: 13, weight: .semibold))
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showAdvanced {
                SettingsGroup(footer: "Fine-tune the colours the active theme is built from.", appearance: appearance) {
                    tintRow("Window glass", detail: "The main backdrop", hex: $appearance.windowTintHex)
                    SettingsDivider()
                    tintRow("Sidebar & header glass", detail: "The navigation panel", hex: $appearance.sidebarTintHex)
                    SettingsDivider()
                    tintRow("Card glass", detail: "Cards and tables", hex: $appearance.cardTintHex)
                    if let preset = appearance.allThemes.first(where: { $0.id == appearance.activeThemeID }) {
                        SettingsDivider()
                        SettingsRow("Reset these to “\(preset.name)”") {
                            SettingsButton(title: "Reset", systemImage: "arrow.counterclockwise", appearance: appearance) {
                                appearance.applyThemePreset(preset)
                                hexDraft = preset.accentHex
                            }
                        }
                    }
                }
                .transition(.opacity.combined(with: .offset(y: -6)))
            }
        }
    }

    private func tintRow(_ title: String, detail: String, hex: Binding<String>) -> some View {
        let color = Binding<Color>(
            get: { Color(nsColor: NSColor(hex: hex.wrappedValue) ?? .black) },
            set: { newColor in
                if let ns = NSColor(newColor).usingColorSpace(.sRGB) { hex.wrappedValue = ns.toHexString() }
            }
        )
        return SettingsRow(title, detail: "\(detail) · \(hex.wrappedValue)") {
            ColorPicker("", selection: color, supportsOpacity: false)
                .labelsHidden()
                .accessibilityLabel(title)
        }
    }
}
