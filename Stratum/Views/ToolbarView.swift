import SwiftUI
import AppKit

struct ToolbarView: View {
    @Environment(\.openWindow) var openWindow
    @Bindable var appState: AppState
    var appearance: AppearanceManager
    var transferEngine = TransferQueueEngine.shared
    var scanCoordinator = ScanCoordinator.shared

    @State var showToolbarTagsPopover = false
    @State var density: ToolbarDensity = .full
    @Namespace var toolbarMotionNamespace

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
                        if density == .full {
                            Text("STRATUM")
                                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                                .tracking(0.8)
                                .foregroundStyle(.primary)
                                .fixedSize()
                        }
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
                .stratumHelp("Stratum Engine — Click to replay launch animation")
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
                    toolbarIconButton("sidebar.left", label: "Collapse sidebar to icons, or expand it") {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            appState.toggleSidebarCollapsed()
                        }
                    }
                    .contextMenu {
                        Button(appState.showSidebar ? "Hide Sidebar" : "Show Sidebar") {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                appState.showSidebar.toggle()
                            }
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
                        .layoutPriority(1)
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
                            .lineLimit(1)
                            .padding(.horizontal, 2)
                            .contentTransition(.interpolate)
                    }
                    .layoutPriority(1)
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

                // Action buttons. In a narrow window the less-used ones move into the "…" menu.
                HStack(spacing: 2) {
                    toolbarIconButton("folder.badge.plus", label: "New folder (⇧⌘N)") {
                        appState.createNewFolder()
                    }
                    if density > .minimal {
                        toolbarIconButton("terminal", label: "Open current folder in Terminal") {
                            TerminalLauncher.openInTerminal(url: appState.currentURL)
                        }
                        toolbarIconButton("wand.and.stars", label: "Smart Clean & Organizer") {
                            toggleOrganizer()
                        }
                        toolbarIconButton("square.and.arrow.up", label: "Share") {
                            shareSelectedItems()
                        }
                        toolbarIconButton("tag", label: "Tags") {
                            showToolbarTagsPopover = true
                        }

                        // Quick Theme Switcher Menu
                        Menu {
                            themeMenuItems
                        } label: {
                            Image(systemName: "paintpalette")
                                .font(.system(size: 13.5, weight: .medium))
                                .foregroundStyle(appearance.accentColor)
                                .frame(width: 30, height: 30)
                        }
                        .menuStyle(.borderlessButton)
                        .frame(width: 30, height: 30)
                        .stratumHelp("Switch Glass Theme or Customize Appearance")
                    }

                    toolbarIconButton("sidebar.right", label: "Toggle inspector (⌥⌘I)") {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                            appState.toggleInspector()
                        }
                    }
                    if density > .minimal {
                        toolbarIconButton("slider.horizontal.3", label: "Settings (⌘,)") {
                            openSettings()
                        }
                    }
                    helpMenu
                }
                .popover(isPresented: $showToolbarTagsPopover, arrowEdge: .bottom) {
                    toolbarTagPopoverContent
                }

                // Live transfer pill
                if let job = transferEngine.activeJob {
                    HStack(spacing: 4) {
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
                                Text(density >= .regular
                                     ? "\(job.titleText) · \(job.isPaused ? "Paused" : "\(job.progressPercent)%")"
                                     : (job.isPaused ? "Paused" : "\(job.progressPercent)%"))
                                    .lineLimit(1)
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
                        .stratumHelp("View active transfer")
                        transferControl(job.isPaused ? "play.fill" : "pause.fill", label: job.isPaused ? "Resume transfer" : "Pause transfer") {
                            transferEngine.togglePause(jobID: job.id)
                        }
                        transferControl("xmark", label: "Cancel transfer") {
                            transferEngine.cancel(jobID: job.id)
                        }
                    }
                    .transition(.scale.combined(with: .opacity))
                }

                // Search / Command Palette (⌘K): a field when there is room, an icon when there isn't.
                if density >= .regular {
                    Button {
                        openCommandPalette()
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text("Search & commands")
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
                                .fixedSize()
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
                } else {
                    toolbarIconButton("magnifyingglass", label: "Search or run a command (⌘K)") {
                        openCommandPalette()
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            // Measured on a frame that takes the offered width, so an over-full row can't
            // report its own (too wide) size and stay over-full.
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 52)
            .onGeometryChange(for: ToolbarDensity.self) { ToolbarDensity(toolbarWidth: $0.size.width) } action: { newDensity in
                withAnimation(.easeOut(duration: 0.18)) { density = newDensity }
            }
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

    /// Items of the theme switcher; a toolbar menu when there is room, a submenu of "…" when not.
    @ViewBuilder
    var themeMenuItems: some View {
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
            openSettings()
        } label: {
            Label("Customize Theme, Blur & Glass…", systemImage: "slider.horizontal.3")
        }
    }

    func toggleOrganizer() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
            appState.screen = (appState.screen == .organizer) ? .browser : .organizer
        }
    }

    func openSettings() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
            appState.screen = .settings
        }
    }

    private func openCommandPalette() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            appState.showCommandPalette = true
        }
    }

    func transferControl(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.primary.opacity(0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(StratumInteractiveButtonStyle())
        .stratumHelp(label)
    }

    func toolbarIconButton(_ symbol: String, label: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
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
        .stratumHelp(label)
    }

    func viewModeButton(_ mode: BrowserViewMode, icon: String, label: String) -> some View {
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
        .stratumHelp(label)
    }

    func shareSelectedItems() {
        let urls = appState.selectedItems.isEmpty ? [appState.currentURL] : appState.selectedItems.map(\.url)
        guard let window = NSApp.keyWindow, let contentView = window.contentView else { return }
        let picker = NSSharingServicePicker(items: urls)
        picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
    }
}

/// How much the toolbar shows, from the full set of controls down to the essentials.
/// Each step frees enough width for the next-narrower window range.
enum ToolbarDensity: Int, Comparable {
    /// Secondary actions live in the "…" menu.
    case minimal
    /// Search is an icon.
    case compact
    /// The brand shows its emblem only.
    case regular
    case full

    init(toolbarWidth: CGFloat) {
        switch toolbarWidth {
        case ..<960: self = .minimal
        case ..<1100: self = .compact
        case ..<1190: self = .regular
        default: self = .full
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}
