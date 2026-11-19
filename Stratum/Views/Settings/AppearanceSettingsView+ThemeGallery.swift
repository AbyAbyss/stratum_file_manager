import SwiftUI
import AppKit

extension AppearanceSettingsView {
    // MARK: - 1. VS Code-Style Glass Theme Gallery (Built-In + User Custom Themes)

    var presetThemeGallerySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Glass Themes (Curated & Custom)")
                        .font(.system(size: 14, weight: .bold))
                    Text("Each theme has its own window glass tint, sidebar tint, card tint, accent color, blur material, and translucency — and every property can be edited below.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()

                // Base Light / Dark / System Mode Switcher
                HStack(spacing: 3) {
                    ForEach(AppThemeOverride.allCases, id: \.rawValue) { mode in
                        let isSelected = (appearance.themeMode == mode)
                        Button {
                            appearance.themeMode = mode
                        } label: {
                            Text(mode.label)
                                .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
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

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                ForEach(appearance.allThemes) { preset in
                    glassThemePresetCard(preset)
                }
            }

            Divider()
                .overlay(Color.primary.opacity(0.08))

            // Save or Update Custom Theme Bar
            HStack(spacing: 10) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(appearance.accentColor)

                TextField("Name your custom theme (e.g. Midnight Emerald)…", text: $customThemeNameDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.black.opacity(0.28))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                            )
                    )
                    .onSubmit {
                        saveCustomTheme()
                    }

                Button {
                    saveCustomTheme()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 11.5))
                        Text("Save as New Theme")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(Color.black.opacity(0.88))
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(appearance.accentColor)
                    )
                }
                .buttonStyle(StratumInteractiveButtonStyle())

                if let activeCustom = appearance.customThemes.first(where: { $0.id == appearance.activeThemeID }) {
                    Button {
                        appearance.updateActiveCustomTheme()
                        appState.showToast("Updated \"\(activeCustom.name)\" with current colors & translucency")
                    } label: {
                        Text("Update \"\(activeCustom.name)\"")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 11)
                            .frame(height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.primary.opacity(0.08))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .strokeBorder(appearance.selectionBorderColor, lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(StratumInteractiveButtonStyle())
                }
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

    func glassThemePresetCard(_ preset: StratumThemePreset) -> some View {
        let isSelected = (appearance.activeThemeID == preset.id)
        let pAccent = Color(nsColor: NSColor(hex: preset.accentHex) ?? .systemGreen)
        let pWin = Color(nsColor: NSColor(hex: preset.windowTintHex) ?? .black)
        let pSide = Color(nsColor: NSColor(hex: preset.sidebarTintHex) ?? .darkGray)
        let pCard = Color(nsColor: NSColor(hex: preset.cardTintHex) ?? .darkGray)

        return Button {
            appearance.applyThemePreset(preset)
            hexDraft = preset.accentHex
            appState.showToast("Applied \(preset.name)")
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                // Miniature Window Preview
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 3) {
                            Circle().fill(Color.red.opacity(0.8)).frame(width: 5, height: 5)
                            Circle().fill(Color.yellow.opacity(0.8)).frame(width: 5, height: 5)
                            Circle().fill(Color.green.opacity(0.8)).frame(width: 5, height: 5)
                        }
                        .padding(.bottom, 2)

                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(pAccent.opacity(0.28))
                            .overlay(
                                RoundedRectangle(cornerRadius: 2.5)
                                    .strokeBorder(pAccent.opacity(0.75), lineWidth: 0.8)
                            )
                            .frame(height: 8)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.primary.opacity(0.15))
                            .frame(width: 24, height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.primary.opacity(0.10))
                            .frame(width: 20, height: 4)
                        Spacer()
                    }
                    .padding(7)
                    .frame(width: 44)
                    .background(pSide)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(pCard)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .strokeBorder(pAccent.opacity(0.85), lineWidth: 1)
                                )
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(pCard)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .strokeBorder(Color.cyan.opacity(0.55), lineWidth: 0.8)
                                )
                        }
                        .frame(height: 26)

                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(pCard)
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(pAccent)
                                    .frame(width: 38, height: 3.5)
                                    .padding(.leading, 6)
                            }
                            .frame(height: 14)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(pWin)
                }
                .frame(height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(isSelected ? pAccent : Color.primary.opacity(0.12), lineWidth: isSelected ? 2 : 1)
                )

                HStack(alignment: .top, spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(pAccent)
                                .frame(width: 7, height: 7)
                            Text(preset.name)
                                .font(.system(size: 12.5, weight: .bold))
                                .lineLimit(1)
                        }
                        Text("\(Int(preset.translucency))% glass · \(preset.blurStyle.rawValue)")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if !preset.isBuiltIn {
                        Button {
                            appearance.deleteCustomTheme(preset)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .stratumHelp("Delete custom theme")
                    } else if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(pAccent)
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? pAccent.opacity(0.11) : Color.primary.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(isSelected ? pAccent.opacity(0.65) : Color.primary.opacity(0.07), lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(StratumInteractiveButtonStyle(hoverScale: 1.015, pressScale: 0.98))
    }
}
