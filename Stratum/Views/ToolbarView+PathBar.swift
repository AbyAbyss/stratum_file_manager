import SwiftUI
import AppKit

extension ToolbarView {
    @ViewBuilder
    var pathBar: some View {
        if let smartName = appState.activeSmartFolderName {
            // Smart Folder Breadcrumb Pill (so title & top bar always match!)
            HStack(spacing: 8) {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                        appState.exitSmartFolder()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.system(size: 11, weight: .semibold))
                        Text(appState.currentURL.lastPathComponent.isEmpty ? "Macintosh HD" : appState.currentURL.lastPathComponent)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
                }
                .buttonStyle(StratumInteractiveButtonStyle())

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)

                HStack(spacing: 6) {
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(appearance.accentColor)
                    Text("Smart Folder: \(smartName)")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.primary)

                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                            appState.exitSmartFolder()
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .stratumHelp("Exit Smart Folder")
                }
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(appearance.selectionFillColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(appearance.selectionBorderColor.opacity(0.65), lineWidth: 1)
                        )
                )
            }
            .padding(.horizontal, 6)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(appearance.cardGlassFillColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            )
        } else if let tagName = appState.selectedTagFilter {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                        appState.selectedTagFilter = nil
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.system(size: 11, weight: .semibold))
                        Text(appState.currentURL.lastPathComponent.isEmpty ? "Macintosh HD" : appState.currentURL.lastPathComponent)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                }
                .buttonStyle(StratumInteractiveButtonStyle())

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)

                HStack(spacing: 6) {
                    Image(systemName: "tag.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(appearance.accentColor)
                    Text("Tag: \(tagName)")
                        .font(.system(size: 12.5, weight: .semibold))
                    Button {
                        appState.selectedTagFilter = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(appearance.selectionFillColor)
                )
            }
            .padding(.horizontal, 6)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(appearance.cardGlassFillColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            )
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(appState.pathSegments) { seg in
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                                appState.navigate(to: seg.url)
                            }
                        } label: {
                            HStack(spacing: 5) {
                                if seg.isLast {
                                    Image(systemName: "folder.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(appearance.accentColor)
                                        .transition(.scale.combined(with: .opacity))
                                }
                                Text(seg.name)
                                    .font(.system(size: 12.5, weight: seg.isLast ? .semibold : .regular))
                                    .foregroundStyle(seg.isLast ? .primary : .secondary)
                            }
                            .padding(.horizontal, 7)
                            .frame(height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(seg.isLast ? appearance.faintTintColor : Color.clear)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(StratumInteractiveButtonStyle(hoverScale: 1.04, pressScale: 0.95))
                        .contextMenu {
                            Button("Open in New Tab") {
                                appState.addNewTab(at: seg.url)
                            }
                            Button("Open in Smart Organizer") {
                                appState.openInSmartOrganizer(seg.url)
                            }
                            Button(appState.isPinned(seg.url) ? "Unpin from Sidebar" : "Pin to Sidebar Favorites") {
                                appState.togglePinFolder(seg.url)
                            }
                            Divider()
                            Button("Copy Path") {
                                TerminalLauncher.copyPathToPasteboard(seg.url.path)
                                appState.showToast("Copied \(seg.url.path)")
                            }
                            Button("Open in Terminal") {
                                TerminalLauncher.openInTerminal(url: seg.url)
                            }
                            Button("Scan in Storage Map") {
                                appState.scanFolder(seg.url, inScreen: .storage)
                            }
                            Button("Go to Folder… (⇧⌘G)") {
                                appState.showGoToFolder = true
                            }
                            Divider()
                            Button("Reveal in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([seg.url])
                            }
                        }

                        if !seg.isLast {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.82), value: appState.currentURL)
                .padding(.horizontal, 6)
                .frame(height: 30)
            }
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(appearance.cardGlassFillColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            )
        }
    }
}
