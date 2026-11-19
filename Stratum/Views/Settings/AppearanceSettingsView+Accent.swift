import SwiftUI
import AppKit

extension AppearanceSettingsView {
    // MARK: - 3. Accent Color Section

    var accentColorSection: some View {
        let isWallpaperAuto = (appearance.accentSource == .wallpaper)
        let accentPickerBinding = Binding<Color>(
            get: { appearance.accentColor },
            set: { newColor in
                if let ns = NSColor(newColor).usingColorSpace(.sRGB) {
                    let newHex = ns.toHexString()
                    appearance.customHex = newHex
                    appearance.accentSource = .custom
                    hexDraft = newHex
                }
            }
        )

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Accent & Neon Glow Color")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Text("\(appearance.activeAccentName) · ")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                + Text(appearance.activeHexString)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(appearance.accentColor)
            }

            Button {
                appearance.sampleDesktopWallpaperColor()
                appearance.accentSource = .wallpaper
                hexDraft = appearance.activeHexString
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        LinearGradient(
                            colors: [
                                Color(nsColor: NSColor(hex: "#0D1520") ?? .blue),
                                Color(nsColor: NSColor(hex: "#192A3E") ?? .purple),
                                appearance.accentColor
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        Circle()
                            .strokeBorder(appearance.accentColor, lineWidth: 5)
                            .frame(width: 34, height: 34)
                            .offset(x: -14, y: 8)
                    }
                    .frame(width: 72, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
                    )

                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)

                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [appearance.accentColor.opacity(0.85), appearance.accentColor],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 68, height: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto, from wallpaper")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Samples your desktop picture and builds a harmonious neon glass accent.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    ZStack {
                        Circle()
                            .fill(isWallpaperAuto ? appearance.accentColor : Color.clear)
                            .overlay(
                                Circle()
                                    .strokeBorder(isWallpaperAuto ? appearance.accentColor : Color.primary.opacity(0.25), lineWidth: 1.5)
                            )
                        if isWallpaperAuto {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.black)
                        }
                    }
                    .frame(width: 22, height: 22)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.24))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(isWallpaperAuto ? appearance.accentColor : Color.primary.opacity(0.10), lineWidth: 1.5)
                        )
                )
            }
            .buttonStyle(.plain)

            HStack {
                Text("Or pick an accent swatch (overrides or customizes the active theme's accent)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Use macOS System Accent") {
                    appearance.accentSource = .system
                    hexDraft = appearance.activeHexString
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(appearance.accentSource == .system ? appearance.accentColor : .secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 6)], spacing: 10) {
                ForEach(Array(AppearanceManager.swatches.enumerated()), id: \.element.id) { idx, swatch in
                    let isSelected = (appearance.activeHexString.caseInsensitiveCompare(swatch.hex) == .orderedSame)
                    let sColor = Color(nsColor: NSColor(hex: swatch.hex) ?? .systemGreen)

                    Button {
                        appearance.selectedSwatchIndex = idx
                        appearance.accentSource = .swatch
                        hexDraft = swatch.hex
                    } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(sColor)
                                    .frame(width: 30, height: 30)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(isSelected ? Color.white : Color.primary.opacity(0.22), lineWidth: isSelected ? 2.5 : 1)
                                    )
                                    .shadow(color: isSelected ? sColor.opacity(0.55) : .clear, radius: 6)
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.black.opacity(0.85))
                                }
                            }
                            Text(swatch.name)
                                .font(.system(size: 11))
                                .foregroundStyle(isSelected ? .primary : .secondary)
                                .lineLimit(1)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()
                .overlay(Color.primary.opacity(0.08))

            HStack(spacing: 10) {
                Text("Color wheel & hex")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)

                ColorPicker("", selection: accentPickerBinding, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 26, height: 26)

                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(appearance.accentColor)
                        .frame(width: 14, height: 14)

                    TextField("#44D492", text: $hexDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 76)
                        .onSubmit {
                            applyHexDraft()
                        }
                }
                .padding(.horizontal, 9)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.28))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                        )
                )

                Button("Apply") {
                    applyHexDraft()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.07))
                )

                Spacer()

                Button {
                    appearance.sampleDesktopWallpaperColor()
                    appearance.accentSource = .wallpaper
                    hexDraft = appearance.activeHexString
                    appState.showToast("Sampled accent \(appearance.activeHexString) from desktop wallpaper")
                } label: {
                    Text("Pick from wallpaper")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 11)
                        .frame(height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
            }

            Toggle(isOn: $appearance.tintFoldersWithAccent) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tint folders with the accent")
                        .font(.system(size: 13))
                    Text("Folder icons take the active theme's accent instead of neutral grey.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .tint(appearance.accentColor)

            Toggle(isOn: $appearance.allowPerFolderAccent) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Allow a different accent per folder")
                        .font(.system(size: 13))
                    Text("Set one from a folder's context menu, handy for telling projects apart.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .tint(appearance.accentColor)
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
