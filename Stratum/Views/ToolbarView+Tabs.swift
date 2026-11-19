import SwiftUI
import AppKit

extension ToolbarView {
    var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(appState.tabs) { tab in
                    let isActive = (tab.id == appState.activeTabID)
                    HStack(spacing: 4) {
                        Image(systemName: isActive && appState.activeSmartFolderName != nil ? "sparkle.magnifyingglass" : "folder.fill")
                            .font(.system(size: 11.5))
                            .foregroundStyle(isActive ? appearance.accentColor : .secondary)

                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                appState.selectTab(tab.id)
                            }
                        } label: {
                            Text(isActive ? appState.currentFolderTitle : tab.title)
                                .font(.system(size: 12.5, weight: isActive ? .semibold : .regular))
                                .foregroundStyle(isActive ? .primary : .secondary)
                                .padding(.horizontal, 6)
                                .frame(height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if appState.tabs.count > 1 {
                            Button {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                    appState.closeTab(tab.id)
                                }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20, height: 20)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(StratumInteractiveButtonStyle())
                        }
                    }
                    .padding(.leading, 10)
                    .padding(.trailing, 4)
                    .frame(height: 28)
                    .background {
                        if isActive {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(appearance.selectionFillColor)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(appearance.selectionBorderColor.opacity(0.65), lineWidth: 1)
                                )
                                .matchedGeometryEffect(id: "ActiveTabBackground", in: toolbarMotionNamespace)
                        }
                    }
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                    .contextMenu {
                        Button("Duplicate Tab") {
                            appState.addNewTab(at: tab.url)
                        }
                        Button(appState.isPinned(tab.url) ? "Unpin from Sidebar" : "Pin Folder to Sidebar") {
                            appState.togglePinFolder(tab.url)
                        }
                        Divider()
                        Button("Open in Terminal") {
                            TerminalLauncher.openInTerminal(url: tab.url)
                        }
                        Button("Copy Path") {
                            TerminalLauncher.copyPathToPasteboard(tab.url.path)
                            appState.showToast("Copied path")
                        }
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([tab.url])
                        }
                        if appState.tabs.count > 1 {
                            Divider()
                            Button("Close Tab") {
                                appState.closeTab(tab.id)
                            }
                        }
                    }
                }

                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        appState.addNewTab()
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(StratumInteractiveButtonStyle())
                .stratumHelp("New Tab (⌘T)")

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
        .background(appearance.sidebarGlassColor.opacity(0.4))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 1)
        }
    }
}
