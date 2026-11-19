import SwiftUI
import AppKit

/// One theme in the gallery: a miniature window in its colours, its name, and whether it is
/// light or dark. Selecting applies it; custom themes can be deleted.
struct SettingsThemeCard: View {
    var preset: StratumThemePreset
    var isSelected: Bool
    var onSelect: () -> Void
    var onDelete: (() -> Void)?
    @State private var hovering = false

    var body: some View {
        let accent = Color(nsColor: NSColor(hex: preset.accentHex) ?? .systemGreen)
        let window = Color(nsColor: NSColor(hex: preset.windowTintHex) ?? .black)
        let sidebar = Color(nsColor: NSColor(hex: preset.sidebarTintHex) ?? .darkGray)
        let card = Color(nsColor: NSColor(hex: preset.cardTintHex) ?? .darkGray)

        return Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10) {
                // Miniature window
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 2).fill(accent.opacity(0.3)).frame(height: 8)
                            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(accent.opacity(0.8), lineWidth: 0.8))
                        Capsule().fill(Color.gray.opacity(0.45)).frame(width: 22, height: 4)
                        Capsule().fill(Color.gray.opacity(0.3)).frame(width: 18, height: 4)
                        Spacer(minLength: 0)
                    }
                    .padding(7)
                    .frame(width: 46)
                    .background(sidebar)

                    VStack(spacing: 5) {
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(card)
                                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(accent.opacity(0.85), lineWidth: 1))
                            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(card)
                        }
                        .frame(height: 28)
                        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(card)
                            .overlay(alignment: .leading) { Capsule().fill(accent).frame(width: 38, height: 4).padding(.leading, 7) }
                            .frame(height: 15)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(window)
                }
                .frame(height: 78)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.primary.opacity(0.14), lineWidth: 1))

                HStack(spacing: 6) {
                    Circle().fill(accent).frame(width: 9, height: 9)
                    Text(preset.name)
                        .font(.system(size: 13, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    if let onDelete, hovering || isSelected {
                        Button(action: onDelete) {
                            Image(systemName: "trash").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .stratumHelp("Delete custom theme")
                    } else if isSelected {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 14)).foregroundStyle(accent)
                    }
                }
                Text(preset.mode == .light ? "Light" : "Dark")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .offset(y: -6)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(isSelected ? accent.opacity(0.12) : Color.primary.opacity(hovering ? 0.06 : 0.035))
                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(isSelected ? accent : Color.primary.opacity(0.08), lineWidth: isSelected ? 2 : 1))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(hovering && !isSelected ? 1.015 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: hovering)
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: isSelected)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(preset.name) theme, \(preset.mode == .light ? "light" : "dark")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
