import SwiftUI
import AppKit

extension GroupsByNameView {
    // MARK: - Right Card: Accordion List + Trash Action Bar

    func filteredInstances(for groupName: String) -> [GroupInstanceRow] {
        let base = scanCoordinator.instances(forGroup: groupName)
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty, !groupName.lowercased().contains(q) else { return base }
        return base.filter { $0.fullPath.lowercased().contains(q) }
    }

    var groupsAccordionCard: some View {
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

    func toggleGroupCheck(group: GroupRow, instances: [GroupInstanceRow], currentlyAllChecked: Bool) {
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

    func formatTilde(_ path: String) -> String {
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
