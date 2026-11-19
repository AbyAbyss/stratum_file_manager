import SwiftUI
import AppKit

extension AppearanceSettingsView {
    // MARK: - 2. Custom Theme Surface Tint Editor

    var customSurfaceEditorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Customize Theme Surface Tints")
                        .font(.system(size: 14, weight: .bold))
                    Text("Fine-tune the active theme's underlying glass colors for the main window, sidebar, and cards.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let activePreset = appearance.allThemes.first(where: { $0.id == appearance.activeThemeID }) {
                    Button("Reset to \"\(activePreset.name)\" Preset") {
                        appearance.applyThemePreset(activePreset)
                        hexDraft = activePreset.accentHex
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(appearance.accentColor)
                }
            }

            HStack(spacing: 12) {
                surfaceColorPickerCard(
                    title: "Window Base Glass",
                    subtitle: "Main backdrop tint",
                    hex: $appearance.windowTintHex
                )
                surfaceColorPickerCard(
                    title: "Sidebar & Header Glass",
                    subtitle: "Navigation panel tint",
                    hex: $appearance.sidebarTintHex
                )
                surfaceColorPickerCard(
                    title: "Bento Card Glass",
                    subtitle: "Cards & tables tint",
                    hex: $appearance.cardTintHex
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(appearance.cardGlassFillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }

    func surfaceColorPickerCard(title: String, subtitle: String, hex: Binding<String>) -> some View {
        let colorBinding = Binding<Color>(
            get: {
                Color(nsColor: NSColor(hex: hex.wrappedValue) ?? .black)
            },
            set: { newColor in
                if let ns = NSColor(newColor).usingColorSpace(.sRGB) {
                    hex.wrappedValue = ns.toHexString()
                }
            }
        )

        return HStack(spacing: 10) {
            ColorPicker("", selection: colorBinding, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                Text("\(subtitle) · \(hex.wrappedValue)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.24))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }
}
