import SwiftUI
import AppKit

extension InspectorSidebarView {
    // MARK: - Action Buttons Grid (2x4 Quick Actions)

    func actionButtonsGrid(for item: FileItem) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Button {
                    appState.openItem(item)
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Open")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(appearance.accentColor)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                inspectorTileButton(title: "Preview", icon: "eye") {
                    QuickLookCoordinator.shared.togglePreview(for: [item.url])
                }

                Button {
                    renameDraft = item.name
                    showRenamePopover = true
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: "pencil")
                            .font(.system(size: 13, weight: .medium))
                        Text("Rename")
                            .font(.system(size: 11))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showRenamePopover) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Rename Item")
                            .font(.system(size: 12, weight: .semibold))
                        TextField("New name", text: $renameDraft)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                            .onSubmit {
                                performSingleRename(item: item, newName: renameDraft)
                                showRenamePopover = false
                            }
                        HStack {
                            Spacer()
                            Button("Cancel") { showRenamePopover = false }
                            Button("Rename") {
                                performSingleRename(item: item, newName: renameDraft)
                                showRenamePopover = false
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(12)
                }

                inspectorTileButton(title: "Zip", icon: "archivebox") {
                    compressItem(item)
                }
            }

            HStack(spacing: 6) {
                inspectorTileButton(title: "Terminal", icon: "terminal") {
                    TerminalLauncher.openInTerminal(url: item.url)
                }

                inspectorTileButton(title: "Copy Path", icon: "link") {
                    TerminalLauncher.copyPathToPasteboard(item.id)
                    appState.showToast("Copied path")
                }

                ShareServiceButton(urls: [item.url])

                inspectorTileButton(title: "Trash", icon: "trash") {
                    appState.moveURLsToTrash([(url: item.url, size: item.size)])
                }
            }
        }
    }

    func inspectorTileButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                Text(title)
                    .font(.system(size: 11))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
