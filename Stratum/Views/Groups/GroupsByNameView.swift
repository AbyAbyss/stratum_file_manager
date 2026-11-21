import SwiftUI
import AppKit

struct GroupsByNameView: View {
    @Bindable var appState: AppState
    var appearance: AppearanceManager
    var scanCoordinator = ScanCoordinator.shared
    var transferEngine = TransferQueueEngine.shared

    @State var showStaleOnly: Bool = false
    @State var expandedGroupNames: Set<String> = []
    @State var checkedPaths: Set<String> = []
    @State var searchQuery: String = ""
    @State var bubblesAppeared: Bool = false
    /// The bubble chart stacks above the groups list instead of sitting beside it.
    @State private var isNarrow = false
    /// How many folder rows each expanded group renders. Grows on "Show more".
    @State var visibleRows: [String: Int] = [:]
    static let initialRows = 12
    static let rowsPerStep = 40

    let bubblePalette: [String] = [
        "#7C5CFF", "#4AD6C8", "#5AA9FF", "#5FD38D", "#FFC46B", "#FF7A90", "#B784F7", "#8B86A3"
    ]

    var displayedGroups: [GroupRow] {
        var base = scanCoordinator.groups
        if showStaleOnly {
            base = base.filter { $0.avgAgeDays >= 60 || $0.devOnly }
        }
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            base = base.filter { grp in
                if grp.name.lowercased().contains(q) || grp.tagline.lowercased().contains(q) {
                    return true
                }
                let insts = scanCoordinator.instances(forGroup: grp.name)
                return insts.contains { $0.fullPath.lowercased().contains(q) }
            }
        }
        return base
    }

    var totalGroupsBytes: Int64 {
        displayedGroups.reduce(Int64(0)) { $0 + $1.total }
    }

    var allAvailableInstances: [GroupInstanceRow] {
        var seen = Set<String>()
        var result: [GroupInstanceRow] = []
        for grp in scanCoordinator.groups {
            for inst in scanCoordinator.instances(forGroup: grp.name) {
                if seen.insert(inst.fullPath).inserted {
                    result.append(inst)
                }
            }
        }
        for inst in scanCoordinator.groupInstances {
            if seen.insert(inst.fullPath).inserted {
                result.append(inst)
            }
        }
        return result
    }

    var selectedInstances: [GroupInstanceRow] {
        allAvailableInstances.filter { checkedPaths.contains($0.fullPath) }
    }

    var selectedTotalBytes: Int64 {
        selectedInstances.reduce(Int64(0)) { $0 + $1.dirRow.totalSize }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                headerBar
                quickToolbarRow

                // Undo Trash Banner
                if let lastTrash = transferEngine.trashHistory.first {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(nsColor: NSColor(hex: "#5FD38D") ?? .systemGreen))
                        Text("Moved \(lastTrash.itemCount) \(lastTrash.itemCount == 1 ? "folder" : "folders") to Trash · \(BulkDirectoryReader.fastFormatBytes(lastTrash.freedBytes)) freed")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Button {
                            appState.undoLastTrash()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                scanCoordinator.startScan(at: URL(fileURLWithPath: scanCoordinator.scannedRootPath))
                            }
                        } label: {
                            Text("Undo (⌘Z)")
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 12)
                                .frame(height: 26)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.primary.opacity(0.08))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
                                        )
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.ultraThickMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(appearance.selectionBorderColor, lineWidth: 1)
                            )
                    )
                }

                if scanCoordinator.showsScanState {
                    ScanningStateView(coordinator: scanCoordinator, appearance: appearance, resultName: "folder groups")
                        .frame(height: 460)
                } else {
                    // Main Content: bubble chart beside the groups list, or above it in a narrow window.
                    let layout = isNarrow
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
                        : AnyLayout(HStackLayout(alignment: .top, spacing: 14))
                    layout {
                        bubbleChartCard
                            .frame(minWidth: isNarrow ? nil : 360, maxWidth: isNarrow ? .infinity : 420)

                        // Built a few frames after the rest of the screen so the switch stays snappy.
                        DeferredContent(delay: 70) { groupsAccordionCard }
                            .frame(maxWidth: .infinity, minHeight: 472, alignment: .top)
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(appearance.contentBackgroundOpacity))
        .onGeometryChange(for: Bool.self) { $0.size.width < 800 } action: { isNarrow = $0 }
        .onAppear {
            if let first = scanCoordinator.groups.first {
                expandedGroupNames.insert(first.name)
                scanCoordinator.selectedGroupName = first.name
            }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                bubblesAppeared = true
            }
        }
    }

    // MARK: - Header Bar

    var headerBar: some View {
        // One row when it fits; otherwise the title sits above the controls, and the scope
        // buttons fold into a menu if the row is still too wide.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 12) {
                headerTitles
                    .frame(minWidth: 0, idealWidth: 320, maxWidth: .infinity, alignment: .leading)
                headerControls(scopeAsMenu: false).fixedSize()
            }
            VStack(alignment: .leading, spacing: 12) {
                headerTitles
                headerControls(scopeAsMenu: false).fixedSize()
            }
            VStack(alignment: .leading, spacing: 12) {
                headerTitles
                headerControls(scopeAsMenu: true).fixedSize()
            }
        }
    }

    private var headerTitles: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Groups by name")
                .font(.system(size: 22, weight: .bold))
                .lineLimit(1)
            Text("Folders with the same name across \(formatTilde(scanCoordinator.scannedRootPath)), totalled. Click any folder row or checkbox to select for cleanup.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func headerControls(scopeAsMenu: Bool) -> some View {
        HStack(spacing: 12) {
            ScanRefreshControl(coordinator: scanCoordinator, appearance: appearance)
            if scopeAsMenu { scopeMenu } else { scopeButtons }
            staleFilterPicker
        }
    }

    private func chooseFolderToScan() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan Folder"
        if panel.runModal() == .OK, let url = panel.url {
            scanCoordinator.startScan(at: url)
        }
    }

    /// Quick Scope Scan Buttons
    private var scopeButtons: some View {
        HStack(spacing: 5) {
            let home = FileManager.default.homeDirectoryForCurrentUser
            scopeButton("Desktop", url: home.appendingPathComponent("Desktop"))
            scopeButton("Home (~)", url: home)

            Button {
                chooseFolderToScan()
            } label: {
                scopeLabel("Choose Folder…")
            }
            .buttonStyle(.plain)
        }
    }

    /// The scope buttons as one menu, for narrow windows.
    private var scopeMenu: some View {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return Menu {
            Button("Desktop") { scanCoordinator.startScan(at: home.appendingPathComponent("Desktop"), name: "Desktop") }
            Button("Home (~)") { scanCoordinator.startScan(at: home, name: "Home (~)") }
            Divider()
            Button("Choose Folder…") { chooseFolderToScan() }
        } label: {
            scopeLabel("Scope")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .help("Choose which folder to scan")
    }

    private func scopeLabel(_ title: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
    }

    /// Filter Segmented Control (All / Stale)
    private var staleFilterPicker: some View {
        HStack(spacing: 2) {
            staleFilterButton("All", staleOnly: false)
            staleFilterButton("Stale / Dev caches", staleOnly: true)
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
                )
        )
    }

    private func staleFilterButton(_ title: String, staleOnly: Bool) -> some View {
        let isSelected = showStaleOnly == staleOnly
        return Button {
            showStaleOnly = staleOnly
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSelected ? .white : .secondary)
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? appearance.accentColor : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    func scopeButton(_ title: String, url: URL) -> some View {
        let isCurrent = (scanCoordinator.scannedRootPath == url.standardizedFileURL.path)
        return Button {
            scanCoordinator.startScan(at: url, name: title)
        } label: {
            Text(title)
                .font(.system(size: 12, weight: isCurrent ? .semibold : .medium))
                .foregroundStyle(isCurrent ? .primary : .secondary)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isCurrent ? appearance.selectionFillColor : Color.primary.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(isCurrent ? appearance.selectionBorderColor : Color.primary.opacity(0.08), lineWidth: 1)
                        )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    var quickToolbarRow: some View {
        // Filter and selection helpers side by side, or the helpers on their own scrolling row.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                groupFilterField.frame(width: 280)
                Spacer(minLength: 0)
                quickSelectPills.fixedSize()
            }
            VStack(alignment: .leading, spacing: 10) {
                groupFilterField
                ScrollView(.horizontal, showsIndicators: false) { quickSelectPills.fixedSize() }
            }
        }
    }

    private var groupFilterField: some View {
        // Filter search box
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField("Filter groups or project paths…", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }

    /// Quick batch selection helpers
    private var quickSelectPills: some View {
        HStack(spacing: 10) {
            quickSelectPill("Select All Visible", icon: "checkmark.circle") {
                for grp in displayedGroups {
                    let insts = filteredInstances(for: grp.name)
                    for r in insts {
                        checkedPaths.insert(r.fullPath)
                    }
                }
            }

            quickSelectPill("Select > 100 MB", icon: "flame") {
                for r in allAvailableInstances where r.dirRow.totalSize >= 100 * 1024 * 1024 {
                    checkedPaths.insert(r.fullPath)
                }
            }

            quickSelectPill("Expand All", icon: "arrow.up.left.and.arrow.down.right") {
                if expandedGroupNames.count == displayedGroups.count {
                    expandedGroupNames.removeAll()
                } else {
                    expandedGroupNames = Set(displayedGroups.map(\.name))
                }
            }

            if !checkedPaths.isEmpty {
                quickSelectPill("Clear Selection (\(checkedPaths.count))", icon: "xmark.circle") {
                    checkedPaths.removeAll()
                }
            }
        }
    }

    func quickSelectPill(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(0.05))
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.09), lineWidth: 1))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

}
