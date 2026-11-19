import SwiftUI
import AppKit

struct SidebarView: View {
    @Bindable var appState: AppState
    var appearance: AppearanceManager

    private var homeURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    private var favorites: [(label: String, icon: String, url: URL, badge: String?, isCustomPin: Bool)] {
        let dlBadge = appState.downloadsBadgeCount > 0 ? "\(appState.downloadsBadgeCount)" : nil
        var base: [(label: String, icon: String, url: URL, badge: String?, isCustomPin: Bool)] = [
            ("Desktop", "menubar.dock.rectangle", homeURL.appendingPathComponent("Desktop"), nil, false),
            ("Documents", "doc.text", homeURL.appendingPathComponent("Documents"), nil, false),
            ("Downloads", "arrow.down.to.line", homeURL.appendingPathComponent("Downloads"), dlBadge, false),
            ("Home", "house", homeURL, nil, false),
            ("Applications", "square.grid.2x2", URL(fileURLWithPath: "/Applications"), nil, false),
        ]
        for pinned in appState.pinnedFolderURLs {
            if !base.contains(where: { $0.url.standardizedFileURL.path == pinned.standardizedFileURL.path }) {
                base.append((pinned.lastPathComponent, "pin.fill", pinned, nil, true))
            }
        }
        return base
    }

    private var tools: [(label: String, icon: String, screen: AppScreen, shortcut: String)] {
        [
            ("Smart Organizer", "wand.and.stars", .organizer, "⌘2"),
            ("Groups", "infinity", .groups, "⌘3"),
            ("Storage map", "rectangle.3.group", .storage, "⌘4"),
            ("Settings", "slider.horizontal.3", .settings, "⌘,"),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    // Favorites + Custom Pinned Folders
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("FAVORITES")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(0.8)
                                .foregroundStyle(.secondary.opacity(0.8))
                            Spacer()
                            Button {
                                appState.togglePinFolder(appState.currentURL)
                            } label: {
                                Image(systemName: appState.isPinned(appState.currentURL) ? "pin.slash" : "plus")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18, height: 18)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .stratumHelp("Pin or unpin current folder")
                        }
                        .padding(.horizontal, 10)
                        .padding(.bottom, 3)

                        ForEach(favorites, id: \.url.path) { fav in
                            let isActive = (appState.screen == .browser && appState.activeSmartFolderName == nil && appState.selectedTagFilter == nil && appState.currentURL.standardizedFileURL == fav.url.standardizedFileURL)
                            sidebarRow(
                                label: fav.label,
                                icon: fav.icon,
                                badge: fav.badge,
                                isActive: isActive
                            ) {
                                appState.navigate(to: fav.url)
                            }
                            .contextMenu {
                                Button("Open") {
                                    appState.navigate(to: fav.url)
                                }
                                Button("Open in New Tab") {
                                    appState.addNewTab(at: fav.url)
                                }
                                Button("Open in Smart Organizer") {
                                    appState.openInSmartOrganizer(fav.url)
                                }
                                Divider()
                                Button("Open in Terminal") {
                                    TerminalLauncher.openInTerminal(url: fav.url)
                                }
                                Button("Scan in Storage Map") {
                                    appState.scanFolder(fav.url, inScreen: .storage)
                                }
                                Button("Copy Path") {
                                    TerminalLauncher.copyPathToPasteboard(fav.url.path)
                                    appState.showToast("Copied path")
                                }
                                Button("Reveal in Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([fav.url])
                                }
                                if fav.isCustomPin {
                                    Divider()
                                    Button("Unpin from Favorites") {
                                        appState.togglePinFolder(fav.url)
                                    }
                                }
                            }
                        }
                    }

                    // Workspace Modes
                    sidebarSection("WORKSPACE MODES") {
                        ForEach(tools, id: \.label) { tool in
                            let isActive = (appState.screen == tool.screen)
                            sidebarRow(
                                label: tool.label,
                                icon: tool.icon,
                                badge: tool.shortcut,
                                isShortcutBadge: true,
                                isActive: isActive
                            ) {
                                appState.screen = tool.screen
                            }
                        }
                    }

                    // Smart Folders (Cross-Mac live queries)
                    sidebarSection("SMART FOLDERS") {
                        sidebarRow(
                            label: "Large files",
                            icon: "chart.bar",
                            badge: nil,
                            isActive: appState.screen == .browser && appState.activeSmartFolderName == "Large files"
                        ) {
                            appState.openSmartFolder(named: "Large files")
                        }
                        sidebarRow(
                            label: "Modified recently",
                            icon: "calendar",
                            badge: nil,
                            isActive: appState.screen == .browser && appState.activeSmartFolderName == "Modified recently"
                        ) {
                            appState.openSmartFolder(named: "Modified recently")
                        }
                        sidebarRow(
                            label: "Screenshots",
                            icon: "viewfinder",
                            badge: nil,
                            isActive: appState.screen == .browser && appState.activeSmartFolderName == "Screenshots"
                        ) {
                            appState.openSmartFolder(named: "Screenshots")
                        }
                        ForEach(appState.smartSearches) { smart in
                            let smartIcon: String = {
                                switch smart.name.lowercased() {
                                case "recent pdfs": return "doc.richtext"
                                case "large media": return "video"
                                case "source code": return "chevron.left.forwardslash.chevron.right"
                                case "archives & zips": return "archivebox"
                                default: return "sparkle.magnifyingglass"
                                }
                            }()
                            sidebarRow(
                                label: smart.name,
                                icon: smartIcon,
                                badge: nil,
                                isActive: appState.screen == .browser && appState.activeSmartFolderName == smart.name
                            ) {
                                appState.openSmartFolder(named: smart.name, customQuery: smart.query)
                            }
                            .contextMenu {
                                Button("Open Smart Folder Across Mac") {
                                    appState.openSmartFolder(named: smart.name, customQuery: smart.query)
                                }
                                Button("Filter Only Current Folder by \"\(smart.query)\"") {
                                    appState.activeSmartFolderName = nil
                                    appState.searchEverywhereInBrowser = false
                                    appState.screen = .browser
                                    appState.showQuickFilter = true
                                    appState.filterQuery = smart.query
                                }
                                if appState.activeSmartFolderName != nil || !appState.filterQuery.isEmpty {
                                    Divider()
                                    Button("Exit Smart Folder / Clear Filter") {
                                        appState.exitSmartFolder()
                                    }
                                }
                            }
                        }
                    }

                    // Locations
                    sidebarSection("LOCATIONS") {
                        ForEach(appState.volumes) { vol in
                            let isActive = (appState.screen == .browser && appState.activeSmartFolderName == nil && appState.currentURL.standardizedFileURL == vol.url.standardizedFileURL)
                            HStack(spacing: 2) {
                                sidebarRow(
                                    label: vol.name,
                                    icon: vol.isNetwork ? "server.rack" : (vol.isEjectable ? "externaldrive" : "internaldrive"),
                                    badge: BulkDirectoryReader.fastFormatBytes(vol.freeBytes),
                                    isActive: isActive
                                ) {
                                    appState.navigate(to: vol.url)
                                }
                                .contextMenu {
                                    Button("Open Volume") {
                                        appState.navigate(to: vol.url)
                                    }
                                    Button("Open in New Tab") {
                                        appState.addNewTab(at: vol.url)
                                    }
                                    Button("Scan Volume in Storage Map") {
                                        appState.scanFolder(vol.url, inScreen: .storage)
                                    }
                                    Button("Open in Terminal") {
                                        TerminalLauncher.openInTerminal(url: vol.url)
                                    }
                                    if vol.isEjectable {
                                        Divider()
                                        Button("Eject \(vol.name)") {
                                            appState.ejectVolume(vol)
                                        }
                                    }
                                }

                                if vol.isEjectable {
                                    Button {
                                        appState.ejectVolume(vol)
                                    } label: {
                                        Image(systemName: "eject")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 26, height: 26)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .stratumHelp("Eject \(vol.name)")
                                }
                            }
                        }

                        // iCloud Drive if present
                        let icloudURL = homeURL.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
                        if FileManager.default.fileExists(atPath: icloudURL.path) {
                            let isActive = (appState.screen == .browser && appState.currentURL.standardizedFileURL == icloudURL.standardizedFileURL)
                            Button {
                                appState.navigate(to: icloudURL)
                            } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: "cloud")
                                        .font(.system(size: 13.5, weight: .medium))
                                        .foregroundStyle(appearance.accentColor)
                                        .frame(width: 16)
                                    Text("iCloud Drive")
                                        .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                                    Spacer()
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color(nsColor: NSColor(hex: "#5FD38D") ?? .systemGreen))
                                }
                                .padding(.horizontal, 10)
                                .frame(height: 30)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(isActive ? appearance.selectionFillColor : Color.clear)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // 2-Column Tags Grid
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("TAGS")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(0.8)
                                .foregroundStyle(.secondary.opacity(0.8))
                            Spacer()
                            if appState.selectedTagFilter != nil {
                                Button("Clear") {
                                    appState.selectedTagFilter = nil
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(appearance.accentColor)
                            }
                        }
                        .padding(.horizontal, 10)

                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 6),
                                GridItem(.flexible(), spacing: 6)
                            ],
                            spacing: 6
                        ) {
                            ForEach(FinderTag.presets) { tag in
                                let isActive = (appState.selectedTagFilter == tag.name)
                                let tagColor = Color(nsColor: NSColor(hex: tag.hexColor) ?? .systemBlue)

                                Button {
                                    if appState.selectedTagFilter == tag.name {
                                        appState.selectedTagFilter = nil
                                    } else {
                                        appState.selectedTagFilter = tag.name
                                    }
                                } label: {
                                    HStack(spacing: 7) {
                                        Circle()
                                            .fill(tagColor)
                                            .frame(width: 8.5, height: 8.5)
                                            .shadow(color: tagColor.opacity(0.55), radius: 3)

                                        Text(tag.name)
                                            .font(.system(size: 11.5, weight: isActive ? .semibold : .medium))
                                            .foregroundStyle(isActive ? Color.primary : Color.primary.opacity(0.88))
                                            .lineLimit(1)
                                            .fixedSize(horizontal: true, vertical: false)

                                        Spacer(minLength: 0)

                                        if isActive {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundStyle(appearance.accentColor)
                                        }
                                    }
                                    .padding(.horizontal, 9)
                                    .frame(maxWidth: .infinity, minHeight: 28)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(isActive ? appearance.selectionFillColor : appearance.cardGlassFillColor)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                    .strokeBorder(
                                                        isActive ? appearance.selectionBorderColor : Color.primary.opacity(0.08),
                                                        lineWidth: 1
                                                    )
                                            )
                                    )
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(isActive ? "Clear Tag Filter" : "Filter by \(tag.name)") {
                                        appState.selectedTagFilter = isActive ? nil : tag.name
                                    }
                                    if !appState.selectedItems.isEmpty {
                                        Divider()
                                        Button("Apply \"\(tag.name)\" to \(appState.selectedItems.count) Selected Item(s)") {
                                            for item in appState.selectedItems {
                                                appState.toggleTag(tag, on: item)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 6)
                    }
                }
            }

            Spacer(minLength: 0)

            // Disk Usage Glass Card at bottom of sidebar (matches reference design)
            if let boot = appState.bootVolume {
                Button {
                    appState.screen = .storage
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            HStack(spacing: 6) {
                                Image(systemName: "internaldrive")
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(appearance.accentColor)
                                Text(boot.name)
                                    .font(.system(size: 12, weight: .bold))
                            }
                            Spacer()
                            Text("\(BulkDirectoryReader.fastFormatBytes(boot.freeBytes)) free")
                                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                                .foregroundStyle(appearance.accentColor)
                        }

                        GeometryReader { geo in
                            let w = geo.size.width
                            let frac = min(1.0, max(0.02, boot.usedFraction))
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.primary.opacity(0.10))
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [appearance.accentColor, appearance.accentColor.opacity(0.55)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: w * frac)
                            }
                        }
                        .frame(height: 5)

                        HStack {
                            Text("\(BulkDirectoryReader.fastFormatBytes(boot.usedBytes)) used of \(BulkDirectoryReader.fastFormatBytes(boot.totalBytes))")
                                .font(.system(size: 10.5).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text("open storage ↗")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(appearance.cardGlassFillColor)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
                            )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .frame(width: 236)
        .background(appearance.sidebarGlassColor)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(width: 1)
        }
    }

    private func sidebarSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(.secondary.opacity(0.8))
                .padding(.horizontal, 10)
                .padding(.bottom, 3)
            content()
        }
    }

    private func sidebarRow(
        label: String,
        icon: String,
        badge: String?,
        isShortcutBadge: Bool = false,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isActive ? appearance.accentColor : appearance.accentColor.opacity(0.78))
                    .stratumSymbolPop(value: isActive)
                    .frame(width: 16)
                Text(label)
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? Color.primary : Color.primary.opacity(0.86))
                    .lineLimit(1)
                Spacer()
                if let badge {
                    if isShortcutBadge && isActive {
                        Text(badge)
                            .font(.system(size: 10, weight: .bold).monospacedDigit())
                            .foregroundStyle(appearance.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(appearance.accentColor.opacity(0.18))
                            )
                    } else {
                        Text(badge)
                            .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 31)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isActive ? appearance.selectionFillColor : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(
                                isActive ? appearance.selectionBorderColor.opacity(0.55) : Color.clear,
                                lineWidth: 1
                            )
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
