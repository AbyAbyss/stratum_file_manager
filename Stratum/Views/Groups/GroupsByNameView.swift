import SwiftUI
import AppKit

struct GroupsByNameView: View {
    @Bindable var appState: AppState
    var appearance: AppearanceManager
    var scanCoordinator = ScanCoordinator.shared
    var transferEngine = TransferQueueEngine.shared

    @State private var showStaleOnly: Bool = false
    @State private var expandedGroupNames: Set<String> = []
    @State private var checkedPaths: Set<String> = []
    @State private var searchQuery: String = ""
    @State private var bubblesAppeared: Bool = false
    /// How many folder rows each expanded group renders. Grows on "Show more".
    @State private var visibleRows: [String: Int] = [:]
    private static let initialRows = 12
    private static let rowsPerStep = 40

    private let bubblePalette: [String] = [
        "#7C5CFF", "#4AD6C8", "#5AA9FF", "#5FD38D", "#FFC46B", "#FF7A90", "#B784F7", "#8B86A3"
    ]

    private var displayedGroups: [GroupRow] {
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

    private var totalGroupsBytes: Int64 {
        displayedGroups.reduce(Int64(0)) { $0 + $1.total }
    }

    private var allAvailableInstances: [GroupInstanceRow] {
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

    private var selectedInstances: [GroupInstanceRow] {
        allAvailableInstances.filter { checkedPaths.contains($0.fullPath) }
    }

    private var selectedTotalBytes: Int64 {
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
                    // Main Content: Left Bubble Chart + Right Groups Accordion List
                    HStack(alignment: .top, spacing: 14) {
                        bubbleChartCard
                            .frame(minWidth: 360, maxWidth: 420)

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

    private var headerBar: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Groups by name")
                    .font(.system(size: 22, weight: .bold))
                Text("Folders with the same name across \(formatTilde(scanCoordinator.scannedRootPath)), totalled. Click any folder row or checkbox to select for cleanup.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            ScanRefreshControl(coordinator: scanCoordinator, appearance: appearance)

            // Quick Scope Scan Buttons
            HStack(spacing: 5) {
                let home = FileManager.default.homeDirectoryForCurrentUser
                scopeButton("Desktop", url: home.appendingPathComponent("Desktop"))
                scopeButton("Home (~)", url: home)

                Button {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.prompt = "Scan Folder"
                    if panel.runModal() == .OK, let url = panel.url {
                        scanCoordinator.startScan(at: url)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "folder.badge.gearshape")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Choose Folder…")
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
                .buttonStyle(.plain)
            }

            // Filter Segmented Control (All / Stale)
            HStack(spacing: 2) {
                Button {
                    showStaleOnly = false
                } label: {
                    Text("All")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(!showStaleOnly ? .white : .secondary)
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(!showStaleOnly ? appearance.accentColor : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    showStaleOnly = true
                } label: {
                    Text("Stale / Dev caches")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(showStaleOnly ? .white : .secondary)
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(showStaleOnly ? appearance.accentColor : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
    }

    private func scopeButton(_ title: String, url: URL) -> some View {
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

    private var quickToolbarRow: some View {
        HStack(spacing: 10) {
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
            .frame(width: 280, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            )

            Spacer()

            // Quick batch selection helpers
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

    private func quickSelectPill(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
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

    // MARK: - Left Card: Interactive Bubble Chart

    private struct BubbleLayoutItem: Identifiable {
        var id: String { group.name }
        let group: GroupRow
        let x: CGFloat
        let y: CGFloat
        let diameter: CGFloat
        let hexColor: String
    }

    private var bubbleLayouts: [BubbleLayoutItem] {
        let items = Array(displayedGroups.prefix(7))
        guard !items.isEmpty else { return [] }
        let maxTotal = max(1, Double(items.map(\.total).max() ?? 1))

        let centers: [(CGFloat, CGFloat)] = [
            (175, 185),
            (295, 115),
            (95, 315),
            (255, 330),
            (85, 105),
            (315, 245),
            (175, 375)
        ]

        return items.enumerated().map { idx, grp in
            let ratio = sqrt(Double(max(1, grp.total)) / maxTotal)
            let diameter = CGFloat(max(68.0, min(160.0, 68.0 + ratio * 92.0)))
            let pos = centers[idx % centers.count]
            let color = bubblePalette[idx % bubblePalette.count]
            return BubbleLayoutItem(
                group: grp,
                x: pos.0,
                y: pos.1,
                diameter: diameter,
                hexColor: color
            )
        }
    }

    private var bubbleChartCard: some View {
        ZStack {
            if bubbleLayouts.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "circle.grid.2x1")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No matching folder groups found")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            } else {
                ZStack {
                    ForEach(bubbleLayouts) { b in
                        let isExpanded = expandedGroupNames.contains(b.group.name)
                        let baseColor = Color(nsColor: NSColor(hex: b.hexColor) ?? .systemPurple)

                        Button {
                            if expandedGroupNames.contains(b.group.name) {
                                // Also select all in this bubble when clicked while already expanded
                                let insts = filteredInstances(for: b.group.name)
                                let allSelected = !insts.isEmpty && insts.allSatisfy { checkedPaths.contains($0.fullPath) }
                                toggleGroupCheck(group: b.group, instances: insts, currentlyAllChecked: allSelected)
                            } else {
                                expandedGroupNames.insert(b.group.name)
                                scanCoordinator.selectedGroupName = b.group.name
                            }
                        } label: {
                            VStack(spacing: 2) {
                                Text(b.group.name)
                                    .font(.system(size: b.diameter > 110 ? 13 : 11, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text(BulkDirectoryReader.fastFormatBytes(b.group.total))
                                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                                    .foregroundStyle(.white.opacity(0.9))
                            }
                            .frame(width: b.diameter, height: b.diameter)
                            .background(
                                Circle()
                                    .fill(baseColor.opacity(isExpanded ? 0.92 : 0.72))
                                    .overlay(
                                        Circle()
                                            .strokeBorder(isExpanded ? Color.white : Color.primary.opacity(0.22), lineWidth: isExpanded ? 2.5 : 1)
                                    )
                            )
                            .contentShape(Circle())
                            .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
                        }
                        .buttonStyle(StratumInteractiveButtonStyle(hoverScale: 1.07, pressScale: 0.94))
                        .scaleEffect(bubblesAppeared ? 1 : 0.6)
                        .opacity(bubblesAppeared ? 1 : 0)
                        .position(x: b.x, y: b.y)
                    }
                }
                .frame(width: 380, height: 440)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 472)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
                )
        )
    }

    // MARK: - Right Card: Accordion List + Trash Action Bar

    private func filteredInstances(for groupName: String) -> [GroupInstanceRow] {
        let base = scanCoordinator.instances(forGroup: groupName)
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty, !groupName.lowercased().contains(q) else { return base }
        return base.filter { $0.fullPath.lowercased().contains(q) }
    }

    private var groupsAccordionCard: some View {
        let maxGroupTotal = max(Int64(1), displayedGroups.first?.total ?? 1)

        return LazyVStack(spacing: 0) {
            HStack {
                Text("Groups")
                Spacer()
                Text("\(displayedGroups.count) groups · \(BulkDirectoryReader.fastFormatBytes(totalGroupsBytes))")
                    .monospacedDigit()
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            ForEach(Array(displayedGroups.enumerated()), id: \.element.id) { idx, group in
                let isExpanded = expandedGroupNames.contains(group.name)
                let colorHex = bubblePalette[idx % bubblePalette.count]
                let barColor = Color(nsColor: NSColor(hex: colorHex) ?? .systemPurple)
                let instances = filteredInstances(for: group.name)
                let checkedInGroup = instances.filter { checkedPaths.contains($0.fullPath) }.count
                let allChecked = !instances.isEmpty && checkedInGroup == instances.count
                let someChecked = checkedInGroup > 0 && !allChecked

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        // Group checkbox — explicit hit-testable contentShape(Rectangle()) so clicking inside always works!
                        Button {
                            toggleGroupCheck(group: group, instances: instances, currentlyAllChecked: allChecked)
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill((allChecked || someChecked) ? appearance.accentColor : Color.primary.opacity(0.04))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .strokeBorder((allChecked || someChecked) ? appearance.accentColor : Color.primary.opacity(0.32), lineWidth: 1.5)
                                    )
                                if allChecked || someChecked {
                                    Image(systemName: allChecked ? "checkmark" : "minus")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                        .contentTransition(.symbolEffect(.replace))
                                        .stratumSymbolPop(value: allChecked)
                                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                                }
                            }
                            .frame(width: 22, height: 22)
                            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: allChecked || someChecked)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .stratumHelp(allChecked ? "Deselect all \(group.name) folders" : "Select all \(group.name) folders")

                        // Row title + expand trigger
                        Button {
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.80)) {
                                if expandedGroupNames.contains(group.name) {
                                    expandedGroupNames.remove(group.name)
                                } else {
                                    expandedGroupNames.insert(group.name)
                                    scanCoordinator.selectedGroupName = group.name
                                }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 8) {
                                        Text(group.name)
                                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                        if group.avgAgeDays >= 60 || group.devOnly {
                                            Text("STALE")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundStyle(Color.stratumLabel(Color(nsColor: NSColor(hex: "#FFC46B") ?? .systemYellow)))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 1)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                                        .fill(Color(nsColor: NSColor(hex: "#FFC46B") ?? .systemYellow).opacity(0.16))
                                                )
                                        }
                                        if checkedInGroup > 0 {
                                            Text("\(checkedInGroup) selected")
                                                .font(.system(size: 10.5, weight: .semibold))
                                                .foregroundStyle(appearance.accentColor)
                                                .padding(.horizontal, 7)
                                                .padding(.vertical, 1)
                                                .background(
                                                    Capsule()
                                                        .fill(appearance.selectionFillColor)
                                                )
                                        }
                                    }
                                    Text("\(group.count) \(group.count == 1 ? "folder" : "folders") · \(group.tagline)")
                                        .font(.system(size: 12).monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text(BulkDirectoryReader.fastFormatBytes(group.total))
                                    .font(.system(size: 15, weight: .semibold).monospacedDigit())

                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    // Proportional size bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.primary.opacity(0.08))
                            Capsule()
                                .fill(barColor)
                                .frame(width: max(6, geo.size.width * (Double(group.total) / Double(maxGroupTotal))))
                        }
                    }
                    .frame(height: 4)
                    .padding(.leading, 34)

                    // Expanded child folders — clicking ANYWHERE on the row toggles selection!
                    if isExpanded {
                        LazyVStack(alignment: .leading, spacing: 3) {
                            ForEach(instances.prefix(visibleRows[group.name] ?? Self.initialRows)) { inst in
                                let isInstChecked = checkedPaths.contains(inst.fullPath)

                                HStack(spacing: 10) {
                                    // Whole-row toggle button (checkbox + path + size)
                                    Button {
                                        if isInstChecked {
                                            checkedPaths.remove(inst.fullPath)
                                        } else {
                                            checkedPaths.insert(inst.fullPath)
                                        }
                                    } label: {
                                        HStack(spacing: 10) {
                                            ZStack {
                                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                                    .fill(isInstChecked ? appearance.accentColor : Color.primary.opacity(0.04))
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                                                            .strokeBorder(isInstChecked ? appearance.accentColor : Color.primary.opacity(0.32), lineWidth: 1.5)
                                                    )
                                                if isInstChecked {
                                                    Image(systemName: "checkmark")
                                                        .font(.system(size: 10, weight: .bold))
                                                        .foregroundStyle(.white)
                                                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                                                }
                                            }
                                            .frame(width: 19, height: 19)
                                            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isInstChecked)

                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(inst.parentProjectName)
                                                    .font(.system(size: 12, weight: .semibold))
                                                    .foregroundStyle(.primary)
                                                    .lineLimit(1)
                                                Text(formatTilde(inst.fullPath))
                                                    .font(.system(size: 11.5, design: .monospaced))
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                                    .truncationMode(.middle)
                                            }

                                            Spacer()

                                            Text(BulkDirectoryReader.fastFormatBytes(inst.dirRow.totalSize))
                                                .font(.system(size: 12.5, weight: .medium).monospacedDigit())
                                                .foregroundStyle(isInstChecked ? appearance.accentColor : .secondary)
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)

                                    // Quick row action buttons
                                    HStack(spacing: 6) {
                                        Button("Reveal") {
                                            let parent = URL(fileURLWithPath: inst.fullPath).deletingLastPathComponent()
                                            appState.navigate(to: parent)
                                            appState.selectedItemIDs = [inst.fullPath]
                                        }
                                        .buttonStyle(.plain)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(appearance.accentColor)
                                        .padding(.horizontal, 7)
                                        .frame(height: 22)
                                        .background(
                                            Capsule()
                                                .fill(appearance.selectionFillColor)
                                        )
                                        .contentShape(Capsule())

                                        Button {
                                            scanCoordinator.trashGroupInstances([inst], appState: appState)
                                            checkedPaths.remove(inst.fullPath)
                                        } label: {
                                            Image(systemName: "trash")
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundStyle(.secondary)
                                                .frame(width: 24, height: 22)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .stratumHelp("Move this folder to Trash")
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(isInstChecked ? appearance.selectionFillColor.opacity(0.65) : Color.primary.opacity(0.02))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .strokeBorder(isInstChecked ? appearance.selectionBorderColor : Color.clear, lineWidth: 1)
                                        )
                                )
                                .contextMenu {
                                    Button(isInstChecked ? "Deselect Folder" : "Select Folder") {
                                        if isInstChecked {
                                            checkedPaths.remove(inst.fullPath)
                                        } else {
                                            checkedPaths.insert(inst.fullPath)
                                        }
                                    }
                                    Divider()
                                    Button("Open in Browser") {
                                        appState.navigate(to: URL(fileURLWithPath: inst.fullPath))
                                    }
                                    Button("Reveal Parent Folder in Browser") {
                                        let parent = URL(fileURLWithPath: inst.fullPath).deletingLastPathComponent()
                                        appState.navigate(to: parent)
                                        appState.selectedItemIDs = [inst.fullPath]
                                    }
                                    Button("Open in New Tab") {
                                        appState.addNewTab(at: URL(fileURLWithPath: inst.fullPath))
                                    }
                                    Button("Open in Terminal") {
                                        TerminalLauncher.openInTerminal(url: URL(fileURLWithPath: inst.fullPath))
                                    }
                                    Button("Copy Path") {
                                        TerminalLauncher.copyPathToPasteboard(inst.fullPath)
                                        appState.showToast("Copied path")
                                    }
                                    Button("Reveal in macOS Finder") {
                                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: inst.fullPath)])
                                    }
                                    Divider()
                                    Button("Move to Trash (\(BulkDirectoryReader.fastFormatBytes(inst.dirRow.totalSize)))") {
                                        checkedPaths.remove(inst.fullPath)
                                        scanCoordinator.trashGroupInstances([inst], appState: appState)
                                    }
                                }
                            }

                            let shown = visibleRows[group.name] ?? Self.initialRows
                            if instances.count > shown {
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                        visibleRows[group.name] = shown + Self.rowsPerStep
                                    }
                                } label: {
                                    Label("Show \(min(Self.rowsPerStep, instances.count - shown)) more · \(instances.count - shown) hidden", systemImage: "chevron.down")
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .foregroundStyle(appearance.accentColor)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 28)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.leading, 34)
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(isExpanded ? Color.primary.opacity(0.025) : Color.clear)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.06))
                        .frame(height: 1)
                }
            }

            // Bottom Reclaim Bar
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(selectedInstances.count) \(selectedInstances.count == 1 ? "folder" : "folders") selected · \(BulkDirectoryReader.fastFormatBytes(selectedTotalBytes))")
                        .font(.system(size: 13.5, weight: .semibold).monospacedDigit())
                    Text("Goes to the Trash, so you can restore anytime with ⌘Z.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !selectedInstances.isEmpty {
                    Button("Clear") {
                        checkedPaths.removeAll()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                }

                Button {
                    let targets = selectedInstances
                    guard !targets.isEmpty else { return }
                    for t in targets {
                        checkedPaths.remove(t.fullPath)
                    }
                    scanCoordinator.trashGroupInstances(targets, appState: appState)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Move to Trash · \(BulkDirectoryReader.fastFormatBytes(selectedTotalBytes))")
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11.5, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 15)
                    .frame(height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(selectedInstances.isEmpty ? Color.secondary.opacity(0.35) : appearance.accentColor)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(selectedInstances.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.22))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 1)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func toggleGroupCheck(group: GroupRow, instances: [GroupInstanceRow], currentlyAllChecked: Bool) {
        expandedGroupNames.insert(group.name)
        scanCoordinator.selectedGroupName = group.name

        let targetList = instances.isEmpty ? scanCoordinator.instances(forGroup: group.name) : instances
        if currentlyAllChecked {
            for r in targetList {
                checkedPaths.remove(r.fullPath)
            }
        } else {
            for r in targetList {
                checkedPaths.insert(r.fullPath)
            }
        }
    }

    private func formatTilde(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home {
            return "~"
        }
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
