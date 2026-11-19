import SwiftUI
import AppKit

struct CommandPaletteView: View {
    @Bindable var appState: AppState
    var appearance: AppearanceManager

    @State private var query: String = ""
    @State private var activeChips: [SearchFilterChip] = []
    @State private var scopeTab: PaletteTabScope = .all
    @State private var searchEverywhere: Bool = true
    @State private var nameResults: [SpotlightResultItem] = []
    @State private var contentResults: [SpotlightResultItem] = []
    @State private var selectedResultID: String? = nil
    @FocusState private var isSearchFocused: Bool

    private var selectedResult: SpotlightResultItem? {
        if let id = selectedResultID {
            if let m = nameResults.first(where: { $0.id == id }) { return m }
            if let c = contentResults.first(where: { $0.id == id }) { return c }
        }
        return nameResults.first ?? contentResults.first
    }

    private var totalResultCount: Int {
        nameResults.count + contentResults.count
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Backdrop click-to-dismiss
            Color.black.opacity(0.50)
                .ignoresSafeArea()
                .onTapGesture {
                    appState.showCommandPalette = false
                }

            // Palette Dialog
            VStack(spacing: 0) {
                topInputBar
                scopeFilterBar

                HStack(spacing: 0) {
                    resultsListColumn
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    previewSidebar
                        .frame(width: 270)
                }
                .frame(height: 430)

                footerBar
            }
            .frame(maxWidth: 860)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThickMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(appearance.selectionBorderColor, lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.65), radius: 45, y: 24)
            .shadow(color: appearance.accentColor.opacity(0.18), radius: 35)
            .padding(.top, 64)
            .padding(.horizontal, 16)
        }
        .onAppear {
            isSearchFocused = true
            runSearch()
        }
        .onChange(of: query) { _, newValue in
            parseInlineFilterTokensIfNeeded(newValue)
            if newValue.hasPrefix(">") {
                scopeTab = .actions
            } else if newValue.hasPrefix("#") {
                scopeTab = .tags
            }
            runSearch()
        }
        .onChange(of: activeChips) { _, _ in
            runSearch()
        }
        .onChange(of: searchEverywhere) { _, _ in
            runSearch()
        }
        .onExitCommand {
            appState.showCommandPalette = false
        }
    }

    // MARK: - Top Search & Chip Bar

    private var topInputBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(appearance.accentColor)

            ForEach(activeChips) { chip in
                HStack(spacing: 5) {
                    Text(chip.key)
                        .foregroundStyle(.secondary)
                    Text(chip.value)
                        .fontWeight(.semibold)
                    Button {
                        activeChips.removeAll(where: { $0.id == chip.id })
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                }
                .font(.system(size: 12))
                .padding(.leading, 9)
                .padding(.trailing, 4)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(appearance.selectionTintColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(appearance.selectionBorderColor, lineWidth: 1)
                        )
                )
            }

            // Quick filter chip presets if empty
            if activeChips.isEmpty && query.isEmpty {
                Button {
                    activeChips.append(SearchFilterChip(key: "kind", value: "PDF"))
                } label: {
                    Text("+ kind: PDF")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(
                            Capsule().fill(Color.primary.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)

                Button {
                    activeChips.append(SearchFilterChip(key: "modified", value: "last 7 days"))
                } label: {
                    Text("+ modified: 7d")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(
                            Capsule().fill(Color.primary.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
            }

            TextField("Search files, content, tags (#), paths (/), or commands (>)", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .focused($isSearchFocused)
                .onSubmit {
                    triggerPrimaryAction()
                }

            Button {
                appState.showCommandPalette = false
            } label: {
                Text("esc")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.1))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 56)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.09))
                .frame(height: 1)
        }
    }

    // MARK: - Scope Tabs Bar

    private var scopeFilterBar: some View {
        HStack(spacing: 4) {
            ForEach(PaletteTabScope.allCases, id: \.self) { tab in
                let isSelected = (scopeTab == tab)
                Button {
                    scopeTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? .white : .secondary)
                        .padding(.horizontal, 11)
                        .frame(height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isSelected ? appearance.accentColor : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Button {
                searchEverywhere.toggle()
            } label: {
                HStack(spacing: 5) {
                    Text(searchEverywhere ? "Everywhere" : appState.currentFolderTitle)
                        .font(.system(size: 12))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(height: 1)
        }
    }

    // MARK: - Results List Column

    private var resultsListColumn: some View {
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

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 3)
    }

    private func resultRow(_ result: SpotlightResultItem, isTopHit: Bool) -> some View {
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

    private func miniFileBadge(for item: FileItem) -> some View {
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
                    .font(.system(size: 7, weight: .bold))
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

    private func paletteGoToRow(title: String, screen: AppScreen) -> some View {
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

    private func paletteActionRow(icon: String, title: String, shortcut: String, action: @escaping () -> Void) -> some View {
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

    // MARK: - Right-hand Preview Sidebar (matches stratum-design.html lines 800-822)

    private var previewSidebar: some View {
        let target = selectedResult?.item ?? appState.primarySelectedItem

        return VStack(alignment: .leading, spacing: 12) {
            // Document/Folder Preview Card
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.30))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
                    )

                if let item = target {
                    if item.isFolderLike {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(appearance.folderFrontColor)
                    } else {
                        ZStack(alignment: .bottomLeading) {
                            VStack(alignment: .leading, spacing: 7) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color(nsColor: NSColor(hex: "#9F9AB5") ?? .gray))
                                    .frame(width: 52, height: 7)
                                ForEach(0..<4, id: \.self) { idx in
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color(nsColor: NSColor(hex: "#C9C5D8") ?? .lightGray))
                                        .frame(width: idx == 3 ? 40 : 70, height: 4)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 18)
                            .frame(width: 100, height: 132)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(nsColor: NSColor(hex: "#EFEDF6") ?? .white))
                                    .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
                            )

                            Text(item.displayExt)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(Color(nsColor: NSColor(hex: item.badgeTintHex) ?? .systemRed))
                                )
                                .offset(x: -10, y: -14)
                        }
                    }
                }
            }
            .frame(height: 170)

            if let item = target {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(2)
                    Text("\(item.kindDescription) · \(item.isFolderLike ? item.subtitleText : item.formattedSize)")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                if !item.tags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(item.tags) { tag in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color(nsColor: NSColor(hex: tag.hexColor) ?? .systemBlue))
                                    .frame(width: 8, height: 8)
                                Text(tag.name)
                                    .font(.system(size: 11.5))
                            }
                            .padding(.horizontal, 9)
                            .frame(height: 24)
                            .background(
                                Capsule()
                                    .fill(Color.primary.opacity(0.07))
                                    .overlay(
                                        Capsule().strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
                                    )
                            )
                        }
                    }
                }
            }

            Spacer(minLength: 4)

            // Keyboard shortcut hints
            VStack(spacing: 6) {
                shortcutHintRow("Reveal in folder", key: "⌘↵") {
                    if let item = target {
                        appState.navigate(to: item.url.deletingLastPathComponent())
                        appState.selectedItemIDs = [item.id]
                        appState.showCommandPalette = false
                    }
                }
                shortcutHintRow("Quick Look", key: "Space") {
                    if let item = target {
                        QuickLookCoordinator.shared.togglePreview(for: [item.url])
                    }
                }
                shortcutHintRow("Copy path", key: "⌥⌘C") {
                    if let item = target {
                        TerminalLauncher.copyPathToPasteboard(item.id)
                        appState.showToast("Copied path")
                    }
                }
                shortcutHintRow("More actions", key: "Tab") {
                    scopeTab = .actions
                }
            }
        }
        .padding(16)
        .background(Color.black.opacity(0.18))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(width: 1)
        }
    }

    private func shortcutHintRow(_ label: String, key: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(key)
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.primary.opacity(0.09))
                    )
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Footer Bar

    private var footerBar: some View {
        HStack {
            HStack(spacing: 14) {
                Text("↑↓ navigate")
                Text("↵ open")
                Text("Type > for commands, # for tags, / to jump to a path")
            }
            Spacer()
            Text("\(totalResultCount) \(totalResultCount == 1 ? "result" : "results")")
                .monospacedDigit()
        }
        .font(.system(size: 11.5))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.22))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
        }
    }

    // MARK: - Search Execution

    private func parseInlineFilterTokensIfNeeded(_ raw: String) {
        if raw.lowercased().hasPrefix("kind:pdf ") {
            activeChips.append(SearchFilterChip(key: "kind", value: "PDF"))
            query = String(raw.dropFirst("kind:pdf ".count))
        } else if raw.lowercased().hasPrefix("kind:folder ") {
            activeChips.append(SearchFilterChip(key: "kind", value: "Folder"))
            query = String(raw.dropFirst("kind:folder ".count))
        }
    }

    private func runSearch() {
        let root: URL? = searchEverywhere ? nil : appState.currentURL
        let currentItems = appState.allItems
        SpotlightSearchEngine.shared.search(
            query: query,
            chips: activeChips,
            rootURL: root,
            inCurrentFolderItems: currentItems
        ) { names, contents in
            self.nameResults = names
            self.contentResults = contents
            if self.selectedResultID == nil || (!names.contains(where: { $0.id == self.selectedResultID }) && !contents.contains(where: { $0.id == self.selectedResultID })) {
                self.selectedResultID = names.first?.id ?? contents.first?.id
            }
        }
    }

    private func triggerPrimaryAction() {
        if query.hasPrefix("/") || query.hasPrefix("~") {
            let expanded = (query as NSString).expandingTildeInPath
            appState.navigate(to: URL(fileURLWithPath: expanded))
            appState.showCommandPalette = false
            return
        }
        if let top = selectedResult {
            appState.openItem(top.item)
            appState.showCommandPalette = false
        }
    }
}
