import SwiftUI
import AppKit

extension AppearanceSettingsView {
    // MARK: - Right-hand Live Preview Sidebar

    var livePreviewSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LIVE GLASS PREVIEW")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(.secondary)

            ZStack {
                LinearGradient(
                    colors: [
                        Color(nsColor: appearance.windowSurfaceNSColor),
                        Color(nsColor: appearance.sidebarSurfaceNSColor),
                        appearance.accentColor.opacity(0.35)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .strokeBorder(appearance.accentColor.opacity(0.75), lineWidth: 18)
                    .frame(width: 140, height: 140)
                    .offset(x: -85, y: 40)

                VStack(spacing: 0) {
                    HStack(spacing: 5) {
                        Circle().fill(Color(nsColor: NSColor(hex: "#FF5F57") ?? .red)).frame(width: 8, height: 8)
                        Circle().fill(Color(nsColor: NSColor(hex: "#FEBC2E") ?? .yellow)).frame(width: 8, height: 8)
                        Circle().fill(Color(nsColor: NSColor(hex: "#28C840") ?? .green)).frame(width: 8, height: 8)
                        Spacer()
                        Text("Stratum Glass")
                            .font(.system(size: 11, weight: .semibold))
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color.primary.opacity(0.09)).frame(height: 1)
                    }

                    VStack(spacing: 2) {
                        previewRow(name: "Brand Refresh", sub: "15 items", isFolder: true, isSelected: true)
                        previewRow(name: "Client Work", sub: "8 items", isFolder: true, isSelected: false)
                        previewRow(name: "Invoice 1042.pdf", sub: "84 KB", isFolder: false, isSelected: false)
                    }
                    .padding(8)

                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.primary.opacity(0.14))
                                    Capsule()
                                        .fill(appearance.accentColor)
                                        .frame(width: geo.size.width * 0.64)
                                }
                            }
                            .frame(height: 5)
                            Text("64%")
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 8) {
                            Text("Auto-Sync")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(appearance.accentColor)
                                .padding(.horizontal, 9)
                                .frame(height: 22)
                                .background(
                                    Capsule()
                                        .fill(appearance.selectionTintColor)
                                        .overlay(
                                            Capsule().strokeBorder(appearance.selectionBorderColor, lineWidth: 1)
                                        )
                                )
                            Spacer()
                            Text("Reveal")
                                .font(.system(size: 11.5))
                                .padding(.horizontal, 10)
                                .frame(height: 24)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
                                )
                            Text("Clean")
                                .font(.system(size: 11.5, weight: .bold))
                                .foregroundStyle(Color.black.opacity(0.88))
                                .padding(.horizontal, 12)
                                .frame(height: 24)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(appearance.accentColor)
                                )
                        }
                    }
                    .padding(12)
                    .overlay(alignment: .top) {
                        Rectangle().fill(Color.primary.opacity(0.09)).frame(height: 1)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(appearance.cardGlassFillColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(appearance.selectionBorderColor.opacity(0.75), lineWidth: 1.2)
                        )
                )
                .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
                .padding(.horizontal, 16)
                .padding(.vertical, 22)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            )

            Text("Every glass theme adjusts window tint, sidebar tint, card opacity, blur material, and neon border glow in real time.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                appearance.restoreDefaults()
                hexDraft = appearance.activeHexString
                appState.showToast("Restored Stratum Emerald Glass defaults")
            } label: {
                Text("Restore Stratum Emerald Glass Defaults")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
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
        .padding(.horizontal, 18)
        .padding(.vertical, 22)
        .background(appearance.sidebarGlassColor.opacity(0.65))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(width: 1)
        }
    }

    func previewRow(name: String, sub: String, isFolder: Bool, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isFolder ? "folder.fill" : "doc")
                .font(.system(size: 13))
                .foregroundStyle(isFolder ? appearance.folderFrontColor : .secondary)
            Text(name)
                .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
            Spacer()
            Text(sub)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .frame(height: appearance.density.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? appearance.selectionTintColor : Color.clear)
        )
    }

    func saveCustomTheme() {
        appearance.saveCurrentAsCustomTheme(named: customThemeNameDraft)
        let savedName = customThemeNameDraft.isEmpty ? "Custom Glass Theme" : customThemeNameDraft
        customThemeNameDraft = ""
        appState.showToast("Saved custom theme \"\(savedName)\"")
    }

    func applyHexDraft() {
        let cleaned = hexDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard NSColor(hex: cleaned) != nil else {
            appState.showToast("Invalid hex color (use #RRGGBB)")
            return
        }
        appearance.customHex = cleaned.hasPrefix("#") ? cleaned.uppercased() : "#\(cleaned.uppercased())"
        appearance.accentSource = .custom
        hexDraft = appearance.customHex
    }
}
