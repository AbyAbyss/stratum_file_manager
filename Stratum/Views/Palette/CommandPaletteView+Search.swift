import SwiftUI
import AppKit

extension CommandPaletteView {
    // MARK: - Search Execution

    func parseInlineFilterTokensIfNeeded(_ raw: String) {
        if raw.lowercased().hasPrefix("kind:pdf ") {
            activeChips.append(SearchFilterChip(key: "kind", value: "PDF"))
            query = String(raw.dropFirst("kind:pdf ".count))
        } else if raw.lowercased().hasPrefix("kind:folder ") {
            activeChips.append(SearchFilterChip(key: "kind", value: "Folder"))
            query = String(raw.dropFirst("kind:folder ".count))
        }
    }

    func runSearch() {
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

    func triggerPrimaryAction() {
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
