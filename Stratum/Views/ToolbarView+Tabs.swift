import SwiftUI
import AppKit

extension ToolbarView {
    /// Chrome-style strip: tabs squeeze to share the width instead of sliding off.
    /// Scrolling is only the last resort when even icon-only tabs don't fit.
    var tabStrip: some View {
        let fit = TabStripFit(width: tabStripWidth, tabs: appState.tabs, activeTitle: appState.currentFolderTitle)
        return Group {
            if fit == .scroll {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) { tabRow(fit: fit) }
                        .onAppear {
                            DispatchQueue.main.async { proxy.scrollTo(appState.activeTabID, anchor: .center) }
                        }
                        .onChange(of: appState.activeTabID) { _, id in
                            withAnimation { proxy.scrollTo(id, anchor: .center) }
                        }
                }
            } else {
                tabRow(fit: fit)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { ($0.size.width / 16).rounded(.down) * 16 } action: { tabStripWidth = $0 }
        .background(appearance.sidebarGlassColor.opacity(0.4))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 1)
        }
    }

    private func tabRow(fit: TabStripFit) -> some View {
        HStack(spacing: 4) {
            ForEach(appState.tabs) { tab in
                let isActive = (tab.id == appState.activeTabID)
                let showsTitle = !tab.isPinned && (isActive || fit.showsInactiveTitles)
                let showsClose = appState.tabs.count > 1 && !tab.isPinned && (isActive || fit.showsInactiveClose)
                HStack(spacing: 4) {
                    // One button for icon + title, so a pinned tab (icon only) is still a full click target.
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            appState.selectTab(tab.id)
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: isActive && appState.activeSmartFolderName != nil ? "sparkle.magnifyingglass" : "folder.fill")
                                .font(.system(size: 11.5))
                                .foregroundStyle(isActive ? appearance.accentColor : .secondary)
                                .overlay(alignment: .topTrailing) {
                                    if tab.isPinned {
                                        Image(systemName: "pin.fill")
                                            .font(.system(size: 6.5, weight: .bold))
                                            .foregroundStyle(appearance.accentColor)
                                            .rotationEffect(.degrees(35))
                                            .offset(x: 5, y: -4)
                                    }
                                }
                            if showsTitle {
                                Text(isActive ? appState.currentFolderTitle : tab.title)
                                    .font(.system(size: 12.5, weight: isActive ? .semibold : .regular))
                                    .foregroundStyle(isActive ? .primary : .secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: 180, alignment: .leading)
                                    // The active title stays whole; the other tabs give up the room.
                                    .fixedSize(horizontal: isActive && fit != .scroll, vertical: false)
                                    .padding(.trailing, 2)
                            }
                        }
                        .frame(height: 24)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .stratumHelp(tab.isPinned ? "\(tab.title) (pinned)" : tab.title)

                    if showsClose {
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
                        .stratumHelp("Close tab")
                    }
                }
                .padding(.leading, showsTitle ? 10 : 9)
                .padding(.trailing, showsClose ? 4 : 9)
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
                    Button(tab.isPinned ? "Unpin Tab" : "Pin Tab") {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            appState.togglePinTab(tab.id)
                        }
                    }
                    Divider()
                    Button("Open in New Window") {
                        openWindow(value: WindowSeed(path: tab.url.path))
                    }
                    if appState.tabs.count > 1 {
                        Button("Move to New Window") {
                            openWindow(value: WindowSeed(path: tab.url.path))
                            appState.closeTab(tab.id)
                        }
                    }
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
}

/// How much of each inactive tab survives at the current strip width.
enum TabStripFit: Equatable {
    case full, noInactiveClose, iconsOnly, scroll

    var showsInactiveTitles: Bool { self == .full || self == .noInactiveClose }
    var showsInactiveClose: Bool { self == .full }

    init(width: CGFloat, tabs: [BrowserTab], activeTitle: String) {
        let pinned = tabs.filter(\.isPinned).count
        let inactive = max(0, tabs.count - pinned - 1)
        guard width > 0, inactive > 0 else { self = .full; return }
        let titleFont = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        let titleWidth = min(180, ceil((activeTitle as NSString).size(withAttributes: [.font: titleFont]).width))
        // Fixed cost: paddings, "+" button, pinned tabs, and the active tab with its whole title.
        let fixed: CGFloat = 20 + 38 + CGFloat(pinned) * 38 + titleWidth + 64
        let perTab = (width - fixed) / CGFloat(inactive) - 4
        switch perTab {
        case 116...: self = .full
        case 84...: self = .noInactiveClose
        case 34...: self = .iconsOnly
        default: self = .scroll
        }
    }
}
