import SwiftUI
import AppKit

extension CommandPaletteView {
    // MARK: - Right-hand Preview Sidebar (matches stratum-design.html lines 800-822)

    var previewSidebar: some View {
        let target = selectedResult?.item ?? appState.primarySelectedItem

        return VStack(alignment: .leading, spacing: 12) {
            // Document/Folder Preview Card
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.30))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
                    )

                if let item = target {
                    if item.isFolderLike {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(appearance.folderFrontColor)
                    } else {
                        ZStack(alignment: .bottomLeading) {
                            VStack(alignment: .leading, spacing: 7) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color(nsColor: NSColor(hex: "#9F9AB5") ?? .gray))
                                    .frame(width: 52, height: 7)
                                ForEach(0..<4, id: \.self) { idx in
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color(nsColor: NSColor(hex: "#C9C5D8") ?? .lightGray))
                                        .frame(width: idx == 3 ? 40 : 70, height: 4)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 18)
                            .frame(width: 100, height: 132)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(nsColor: NSColor(hex: "#EFEDF6") ?? .white))
                                    .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
                            )

                            Text(item.displayExt)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(Color(nsColor: NSColor(hex: item.badgeTintHex) ?? .systemRed))
                                )
                                .offset(x: -10, y: -14)
                        }
                    }
                }
            }
            .frame(height: 170)

            if let item = target {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(2)
                    Text("\(item.kindDescription) · \(item.isFolderLike ? item.subtitleText : item.formattedSize)")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                if !item.tags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(item.tags) { tag in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color(nsColor: NSColor(hex: tag.hexColor) ?? .systemBlue))
                                    .frame(width: 8, height: 8)
                                Text(tag.name)
                                    .font(.system(size: 11.5))
                            }
                            .padding(.horizontal, 9)
                            .frame(height: 24)
                            .background(
                                Capsule()
                                    .fill(Color.primary.opacity(0.07))
                                    .overlay(
                                        Capsule().strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
                                    )
                            )
                        }
                    }
                }
            }

            Spacer(minLength: 4)

            // Keyboard shortcut hints
            VStack(spacing: 6) {
                shortcutHintRow("Reveal in folder", key: "⌘↵") {
                    if let item = target {
                        appState.navigate(to: item.url.deletingLastPathComponent())
                        appState.selectedItemIDs = [item.id]
                        appState.showCommandPalette = false
                    }
                }
                shortcutHintRow("Quick Look", key: "Space") {
                    if let item = target {
                        QuickLookCoordinator.shared.togglePreview(for: [item.url])
                    }
                }
                shortcutHintRow("Copy path", key: "⌥⌘C") {
                    if let item = target {
                        TerminalLauncher.copyPathToPasteboard(item.id)
                        appState.showToast("Copied path")
                    }
                }
                shortcutHintRow("More actions", key: "Tab") {
                    scopeTab = .actions
                }
            }
        }
        .padding(16)
        .background(Color.black.opacity(0.18))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(width: 1)
        }
    }

    func shortcutHintRow(_ label: String, key: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(key)
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.primary.opacity(0.09))
                    )
            }
        }
        .buttonStyle(.plain)
    }
}
