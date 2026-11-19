import SwiftUI
import AppKit

extension AppearanceSettingsView {
    // MARK: - 4. Window Glass, Blur Material & Glow Section

    var windowMaterialSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Translucent Glass, Blur Material & Border Glow")
                .font(.system(size: 14, weight: .bold))

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("macOS Vibrancy Blur Material")
                        .font(.system(size: 13, weight: .medium))
                    Text("Controls how the desktop wallpaper refracts through the translucent glass window.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 4) {
                    ForEach(GlassBlurStyle.allCases) { style in
                        let isSelected = (appearance.blurStyle == style)
                        Button {
                            appearance.blurStyle = style
                        } label: {
                            Text(style.rawValue)
                                .font(.system(size: 11.5, weight: isSelected ? .bold : .medium))
                                .foregroundStyle(isSelected ? Color.black.opacity(0.88) : .secondary)
                                .padding(.horizontal, 10)
                                .frame(height: 26)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(isSelected ? appearance.accentColor : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.28))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                )
            }

            HStack(spacing: 12) {
                Text("Glass Translucency (\(Int(appearance.translucency))%)")
                    .font(.system(size: 13))
                Spacer()
                Text("Solid")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Slider(value: $appearance.translucency, in: 0...100)
                    .frame(width: 210)
                    .tint(appearance.accentColor)
                Text("Deep Glass")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Text("Card Neon Border Glow (\(Int(appearance.cardGlowIntensity))%)")
                    .font(.system(size: 13))
                Spacer()
                Text("Subtle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Slider(value: $appearance.cardGlowIntensity, in: 0...100)
                    .frame(width: 210)
                    .tint(appearance.accentColor)
                Text("Vivid")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Toggle(isOn: $appearance.enableBackgroundBlur) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Blur what's behind the window")
                        .font(.system(size: 13))
                    Text("Turns off automatically when Reduce Transparency is enabled in macOS.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .tint(appearance.accentColor)

            Toggle(isOn: $appearance.enableWallpaperWash) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ambient accent radial glow across window")
                        .font(.system(size: 13))
                    Text("A soft radial light bloom of your active accent illuminates the top-left glass.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .tint(appearance.accentColor)

            HStack {
                Text("Row density")
                    .font(.system(size: 13))
                Spacer()
                HStack(spacing: 2) {
                    ForEach(RowDensity.allCases, id: \.self) { density in
                        let isSelected = (appearance.density == density)
                        Button {
                            appearance.density = density
                        } label: {
                            Text(density.rawValue)
                                .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                                .foregroundStyle(isSelected ? Color.black.opacity(0.88) : .secondary)
                                .padding(.horizontal, 12)
                                .frame(height: 26)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(isSelected ? appearance.accentColor : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.black.opacity(0.28))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                        )
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
}
