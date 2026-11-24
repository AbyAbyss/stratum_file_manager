import SwiftUI
import AppKit

extension CommandPaletteView {
    // MARK: - Results List Column

    var resultsListColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                // Path jump helper if query starts with "/" or "~"
                if query.hasPrefix("/") || query.hasPrefix("~") {
                    sectionHeader("Direct Path Jump")
                    paletteActionRow(
                        icon: "folder.fill",
                        title: "Jump to \(query)",
                        shortcut: "↵"
                    ) {
                        let expanded = (query as NSString).expandingTildeInPath
                        let url = URL(fileURLWithPath: expanded)
                        appState.navigate(to: url)
                        appState.showCommandPalette = false
                    }
                }

                // Tags section when on Tags tab
                if scopeTab == .tags {
                    sectionHeader("Finder Tags")
                    ForEach(FinderTag.presets) { tag in
                        Button {
                            appState.selectedTagFilter = tag.name
                            appState.screen = .browser
                            appState.showCommandPalette = false
                        } label: {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(Color(nsColor: NSColor(hex: tag.hexColor) ?? .systemBlue))
                                    .frame(width: 10, height: 10)
                                Text("#\(tag.name)")
                                    .font(.system(size: 13, weight: .medium))
                                Spacer()
                                Text("Filter by tag")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 36)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Top Hit + Names section
                if (scopeTab == .all || scopeTab == .names), let top = nameResults.first {
                    sectionHeader("Top hit")
                    resultRow(top, isTopHit: true)

                    if nameResults.count > 1 {
                        sectionHeader("Names · \(nameResults.count - 1)")
                        ForEach(nameResults.dropFirst().prefix(6)) { res in
                            resultRow(res, isTopHit: false)
                        }
                    }
                }

                // Inside Files section
                if (scopeTab == .all || scopeTab == .insideFiles), !contentResults.isEmpty {
                    sectionHeader("Inside files · \(contentResults.count)")
                    ForEach(contentResults.prefix(5)) { res in
                        resultRow(res, isTopHit: false)
                    }
                }

                // Go To section
                if scopeTab == .all || scopeTab == .actions {
                    sectionHeader("Go to")
                    paletteGoToRow(title: "Go to Groups by name", screen: .groups)
                    paletteGoToRow(title: "Go to Storage map", screen: .storage)
                    paletteGoToRow(title: "Go to Storage history", screen: .history)
                    paletteGoToRow(title: "Open Smart Organizer", screen: .organizer)
                    paletteGoToRow(title: "Open Settings", screen: .settings)

                    // Actions section (matches stratum-design.html lines 781-797)
                    sectionHeader("Actions")
                    paletteActionRow(
                        icon: "pencil",
                        title: "Batch rename the \(max(1, nameResults.count)) results",
                        shortcut: "⇧⌘R"
                    ) {
                        let ids = Set(nameResults.map(\.id))
                        if !ids.isEmpty {
                            appState.selectedItemIDs = ids
                        }
                        appState.showCommandPalette = false
                        appState.showBatchRename = true
                    }

                    paletteActionRow(
                        icon: "folder.badge.plus",
                        title: "New folder with the \(max(1, nameResults.count)) results",
                        shortcut: "⌃⌘N"
                    ) {
                        appState.createNewFolder()
                        appState.showCommandPalette = false
                    }

                    paletteActionRow(
                        icon: "plus.magnifyingglass",
                        title: "Save this search as a smart folder",
                        shortcut: "⌘S"
                    ) {
                        let label = query.isEmpty ? "Saved Search \(appState.smartSearches.count + 1)" : query
                        appState.smartSearches.append(
                            SavedSmartSearch(
                                id: UUID(),
                                name: label,
                                query: query,
                                kindFilter: activeChips.first(where: { $0.key == "kind" })?.value,
                                tagFilter: activeChips.first(where: { $0.key == "tag" })?.value
                            )
                        )
                        appState.showToast("Saved Smart Folder '\(label)' to Sidebar")
                        appState.showCommandPalette = false
                    }

                    paletteActionRow(
                        icon: "terminal",
                        title: "Open \(appState.currentFolderTitle) in Terminal",
                        shortcut: "⌥⌘T"
                    ) {
                        TerminalLauncher.openInTerminal(url: appState.currentURL)
                        appState.showCommandPalette = false
                    }
                }
            }
            .padding(10)
        }
    }

    func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 3)
    }

    func resultRow(_ result: SpotlightResultItem, isTopHit: Bool) -> some View {
        let isSelected = (selectedResult?.id == result.id)
        return Button {
            selectedResultID = result.id
            appState.openItem(result.item)
            appState.showCommandPalette = false
        } label: {
            HStack(spacing: 11) {
                miniFileBadge(for: result.item)

                VStack(alignment: .leading, spacing: 1) {
                    Text(result.item.name)
                        .font(.system(size: 13, weight: isTopHit ? .semibold : .medium))
                        .lineLimit(1)

                    if let snippet = result.snippet {
                        Text(snippet)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("\(result.parentChain) · \(result.item.formattedModDate)")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if isTopHit {
                    Text("↵ Open")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.primary.opacity(0.14))
                        )
                } else {
                    Text(result.item.isFolderLike ? result.item.subtitleText : result.item.formattedSize)
                        .font(.system(size: 11.5).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minHeight: isTopHit ? 46 : 40)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? appearance.selectionTintColor : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(isSelected ? appearance.selectionBorderColor : Color.clear, lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    func miniFileBadge(for item: FileItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(item.isFolderLike ? appearance.folderFrontColor.opacity(0.25) : Color(nsColor: NSColor(hex: "#EFEDF6") ?? .white))
                .frame(width: 26, height: 32)

            if item.isFolderLike {
                Image(systemName: "folder.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(appearance.folderFrontColor)
                    .frame(width: 26, height: 32)
            } else {
                Text(item.displayExt)
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color(nsColor: NSColor(hex: item.badgeTintHex) ?? .systemRed))
                    )
                    .padding(2)
            }
        }
    }

    func paletteGoToRow(title: String, screen: AppScreen) -> some View {
        Button {
            appState.screen = screen
            appState.showCommandPalette = false
        } label: {
            HStack(spacing: 11) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(appearance.accentColor)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                    )
                Text(title)
                    .font(.system(size: 13))
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    func paletteActionRow(icon: String, title: String, shortcut: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(appearance.accentColor)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                    )
                Text(title)
                    .font(.system(size: 13))
                Spacer()
                Text(shortcut)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.09))
                    )
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
