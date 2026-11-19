import SwiftUI
import AppKit

struct ToolbarView: View {
    @Bindable var appState: AppState
    var appearance: AppearanceManager
    var transferEngine = TransferQueueEngine.shared
    var scanCoordinator = ScanCoordinator.shared

    @State private var showToolbarTagsPopover = false
    @Namespace private var toolbarMotionNamespace

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                // Space for native macOS window traffic lights when fullSizeContentView is active
                Color.clear
                    .frame(width: 68, height: 30)

                // Animated Stratum Isometric Brand Emblem (click to replay startup animation)
                Button {
                    appState.replayStartupSplash()
                } label: {
                    HStack(spacing: 7) {
                        StratumIsometricLogo(
                            size: 22,
                            accentColor: appearance.accentColor,
                            isAnimated: true
                        )
                        Text("STRATUM")
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(appearance.cardGlassFillColor)
                            .overlay(
                                Capsule()
                                    .strokeBorder(appearance.selectionBorderColor.opacity(0.45), lineWidth: 1)
                            )
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(StratumInteractiveButtonStyle(hoverScale: 1.04, pressScale: 0.94))
                .help("Stratum Engine — Click to replay launch animation")
                .contextMenu {
                    Button("Replay Startup Animation") {
                        appState.replayStartupSplash()
                    }
                    Divider()
                    Button("Browser") { appState.screen = .browser }
                    Button("Storage Map") { appState.screen = .storage }
                    Button("Groups by Name") { appState.screen = .groups }
                    Button("Smart Clean & Organizer") { appState.screen = .organizer }
                }

                // Sidebar toggle + Back / Forward / Up (Unified History across Folders, Workspace Modes & Smart Folders)
                HStack(spacing: 2) {
                    toolbarIconButton("sidebar.left", label: "Toggle sidebar") {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            appState.showSidebar.toggle()
                        }
                    }
                    toolbarIconButton("chevron.left", label: "Back", disabled: !appState.canGoBack) {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                            appState.goBack()
                        }
                    }
                    toolbarIconButton("chevron.right", label: "Forward", disabled: !appState.canGoForward) {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                            appState.goForward()
                        }
                    }
                    toolbarIconButton("chevron.up", label: "Up / Exit View (⌘↑)", disabled: !appState.canGoUp) {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                            appState.goUp()
                        }
                    }
                }

                // Path bar in Browser mode, or Screen Breadcrumb in Workspace Modes
                if appState.screen == .browser {
                    pathBar
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                } else {
                    HStack(spacing: 8) {
                        Button {
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                                appState.screen = .browser
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 10, weight: .bold))
                                Text("Browser")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .frame(height: 25)
                            .background(
                                Capsule()
                                    .fill(appearance.cardGlassFillColor)
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                                    )
                            )
                            .contentShape(Capsule())
                        }
                        .buttonStyle(StratumInteractiveButtonStyle())

                        Text("/")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.tertiary)

                        Text(appState.screen.title)
                            .font(.system(size: 13.5, weight: .bold))
                            .padding(.horizontal, 2)
                            .contentTransition(.interpolate)

                        StratumLiveSyncPill(appearance: appearance)
                    }
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }

                Spacer(minLength: 12)

                // View mode switcher (Icon / List / Column) with matchedGeometry sliding indicator
                if appState.screen == .browser {
                    HStack(spacing: 2) {
                        viewModeButton(.grid, icon: "square.grid.2x2", label: "Icon view (⌘1)")
                        viewModeButton(.list, icon: "list.bullet", label: "List view (⌘2)")
                        viewModeButton(.columns, icon: "rectangle.split.3x1", label: "Column view (⌘3)")
                    }
                    .padding(2)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(appearance.cardGlassFillColor)
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                    )
                }

                // Action buttons: New folder, Terminal, Smart Organizer, Share, Tags, Theme Picker, Inspector, Settings
                HStack(spacing: 2) {
                    toolbarIconButton("folder.badge.plus", label: "New folder (⇧⌘N)") {
                        appState.createNewFolder()
                    }
                    toolbarIconButton("terminal", label: "Open current folder in Terminal") {
                        TerminalLauncher.openInTerminal(url: appState.currentURL)
                    }
                    toolbarIconButton("wand.and.stars", label: "Smart Clean & Organizer") {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                            appState.screen = (appState.screen == .organizer) ? .browser : .organizer
                        }
                    }
                    toolbarIconButton("square.and.arrow.up", label: "Share") {
                        shareSelectedItems()
                    }
                    toolbarIconButton("tag", label: "Tags") {
                        showToolbarTagsPopover = true
                    }
                    .popover(isPresented: $showToolbarTagsPopover) {
                        toolbarTagPopoverContent
                    }

                    // Quick Theme Switcher Menu
                    Menu {
                        Text("Glass Themes")
                            .font(.caption)
                        ForEach(appearance.allThemes) { preset in
                            Button {
                                appearance.applyThemePreset(preset)
                                appState.showToast("Applied \(preset.name) (\(preset.accentHex))")
                            } label: {
                                HStack {
                                    Text(preset.name)
                                    if appearance.activeThemeID == preset.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                        Divider()
                        Button {
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                                appState.screen = .settings
                            }
                        } label: {
                            Label("Customize Theme, Blur & Glass…", systemImage: "slider.horizontal.3")
                        }
                    } label: {
                        Image(systemName: "paintpalette")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(appearance.accentColor)
                            .frame(width: 30, height: 30)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 30, height: 30)
                    .help("Switch Glass Theme or Customize Appearance")

                    toolbarIconButton("sidebar.right", label: "Toggle inspector (⌘I)") {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                            appState.showInspector.toggle()
                        }
                    }
                    toolbarIconButton("slider.horizontal.3", label: "Appearance & Theme Studio (⌘,)") {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                            appState.screen = .settings
                        }
                    }
                }

                // Live transfer pill
                if let job = transferEngine.activeJob {
                    Button {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                            appState.screen = .organizer
                        }
                    } label: {
                        HStack(spacing: 7) {
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.primary.opacity(0.15))
                                    .frame(width: 28, height: 5)
                                Capsule()
                                    .fill(appearance.accentColor)
                                    .frame(width: max(4, 28 * job.progressFraction), height: 5)
                                    .animation(.spring(response: 0.25, dampingFraction: 0.8), value: job.progressFraction)
                            }
                            Text("\(job.titleText) · \(job.progressPercent)%")
                                .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                                .contentTransition(.numericText())
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(
                            Capsule()
                                .fill(appearance.selectionTintColor)
                                .overlay(
                                    Capsule()
                                        .strokeBorder(appearance.selectionBorderColor, lineWidth: 1)
                                )
                        )
                        .contentShape(Capsule())
                    }
                    .buttonStyle(StratumInteractiveButtonStyle())
                    .transition(.scale.combined(with: .opacity))
                    .help("View active transfer")
                }

                // Search / Command Palette button (Cmd+K)
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                        appState.showCommandPalette = true
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("Search or run a com…")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text("⌘K")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Color.primary.opacity(0.10))
                            )
                    }
                    .padding(.horizontal, 10)
                    .frame(width: 210, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(appearance.cardGlassFillColor)
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
                            )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(StratumInteractiveButtonStyle(hoverScale: 1.02, pressScale: 0.97))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: 52)
            .background(appearance.sidebarGlassColor.opacity(0.55))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.primary.opacity(0.07))
                    .frame(height: 1)
            }

            // Tab Strip (Browser mode)
            if appState.screen == .browser {
                tabStrip
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private var pathBar: some View {
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
                    .help("Exit Smart Folder")
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

    private var tabStrip: some View {
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
                .help("New Tab (⌘T)")

                Spacer(minLength: 8)

                // Live Smart Auto-Sync indicator right in the tab bar
                StratumLiveSyncPill(appearance: appearance)
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

    private func toolbarIconButton(_ symbol: String, label: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(disabled ? .tertiary : .secondary)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(StratumInteractiveButtonStyle(hoverScale: 1.08, pressScale: 0.90))
        .disabled(disabled)
        .help(label)
    }

    private func viewModeButton(_ mode: BrowserViewMode, icon: String, label: String) -> some View {
        let isActive = (appState.viewMode == mode)
        return Button {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.80)) {
                appState.viewMode = mode
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(isActive ? .white : .secondary)
                .frame(width: 30, height: 24)
                .background {
                    if isActive {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(appearance.accentColor)
                            .shadow(color: appearance.accentColor.opacity(0.45), radius: 5, y: 1)
                            .matchedGeometryEffect(id: "ActiveViewModePill", in: toolbarMotionNamespace)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(StratumInteractiveButtonStyle())
        .help(label)
    }

    private func shareSelectedItems() {
        let urls = appState.selectedItems.isEmpty ? [appState.currentURL] : appState.selectedItems.map(\.url)
        guard let window = NSApp.keyWindow, let contentView = window.contentView else { return }
        let picker = NSSharingServicePicker(items: urls)
        picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
    }

    private var toolbarTagPopoverContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Assign Tag to Selection")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            ForEach(FinderTag.presets) { preset in
                Button {
                    let targets = appState.selectedItems
                    for item in targets {
                        appState.toggleTag(preset, on: item)
                    }
                    showToolbarTagsPopover = false
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(nsColor: NSColor(hex: preset.hexColor) ?? .systemBlue))
                            .frame(width: 9, height: 9)
                        Text(preset.name)
                            .font(.system(size: 12.5))
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(StratumInteractiveButtonStyle())
            }
        }
        .frame(width: 170)
        .padding(10)
    }
}
