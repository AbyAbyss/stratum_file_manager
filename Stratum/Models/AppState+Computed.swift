import Foundation
import AppKit
import SwiftUI

extension AppState {
    /// The inspector is wanted and there is room for it. In a narrow window the full sidebar
    /// wins and the inspector steps aside without forgetting the user's choice.
    var isInspectorVisible: Bool {
        showInspector && (windowFitsBothPanels || !showSidebar || sidebarCollapsed)
    }

    /// Shows or hides the inspector. In a narrow window, showing it collapses the sidebar to
    /// icons to make room.
    func toggleInspector() {
        if isInspectorVisible {
            showInspector = false
        } else {
            showInspector = true
            if !windowFitsBothPanels { sidebarCollapsed = true }
        }
    }

    /// The toolbar's sidebar button: switches between the full sidebar and the icon rail,
    /// and brings a hidden sidebar back.
    func toggleSidebarCollapsed() {
        if showSidebar {
            sidebarCollapsed.toggle()
        } else {
            showSidebar = true
        }
    }

    // MARK: - Computed Properties

    var activeTabIndex: Int? {
        tabs.firstIndex(where: { $0.id == activeTabID })
    }

    var currentURL: URL {
        guard let idx = activeTabIndex else {
            return FileManager.default.homeDirectoryForCurrentUser
        }
        return tabs[idx].url
    }

    var canGoBack: Bool {
        guard let idx = activeTabIndex else { return false }
        return tabs[idx].historyIndex > 0
    }

    var canGoForward: Bool {
        guard let idx = activeTabIndex else { return false }
        return tabs[idx].historyIndex < tabs[idx].history.count - 1
    }

    var canGoUp: Bool {
        if screen != .browser { return true }
        if activeSmartFolderName != nil || selectedTagFilter != nil { return true }
        return currentURL.path != "/"
    }

    var currentFolderTitle: String {
        if let smart = activeSmartFolderName {
            return smart
        }
        if let tag = selectedTagFilter {
            return "Tag: \(tag)"
        }
        if currentURL.path == "/" {
            return bootVolume?.name ?? "Macintosh HD"
        }
        return currentURL.lastPathComponent
    }

    var displayTildePath: String {
        let path = currentURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home {
            return "~"
        } else if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    var pathSegments: [PathSegment] {
        let path = currentURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let rootName = bootVolume?.name ?? "Macintosh HD"
        var segments: [PathSegment] = []

        if path.hasPrefix(home) {
            segments.append(PathSegment(name: rootName, url: URL(fileURLWithPath: "/"), isLast: false))
            segments.append(PathSegment(name: "Home", url: URL(fileURLWithPath: home), isLast: path == home))
            let remainder = path.dropFirst(home.count)
            let parts = remainder.split(separator: "/").map(String.init)
            var running = URL(fileURLWithPath: home)
            for (i, part) in parts.enumerated() {
                running.appendPathComponent(part, isDirectory: true)
                segments.append(PathSegment(name: part, url: running, isLast: i == parts.count - 1))
            }
        } else {
            segments.append(PathSegment(name: rootName, url: URL(fileURLWithPath: "/"), isLast: path == "/"))
            let parts = path.split(separator: "/").map(String.init)
            var running = URL(fileURLWithPath: "/")
            for (i, part) in parts.enumerated() {
                running.appendPathComponent(part, isDirectory: true)
                segments.append(PathSegment(name: part, url: running, isLast: i == parts.count - 1))
            }
        }
        return segments
    }

    var selectedItems: [FileItem] {
        if selectedItemIDs.isEmpty { return [] }
        return displayedItems.filter { selectedItemIDs.contains($0.id) }
    }

    var primarySelectedItem: FileItem? {
        if let first = selectedItems.first {
            return first
        }
        return displayedItems.first
    }

    var statusSelectionSummary: String {
        let total = displayedItems.count
        let sel = selectedItems
        if sel.isEmpty {
            return "\(total) \(total == 1 ? "item" : "items")"
        } else if sel.count == 1, let item = sel.first {
            let sizeStr = item.isFolderLike ? item.subtitleText : item.formattedSize
            return "1 of \(total) selected · \(sizeStr)"
        } else {
            let sumBytes = sel.reduce(Int64(0)) { $0 + $1.size }
            let sizeStr = sumBytes > 0 ? " · \(BulkDirectoryReader.fastFormatBytes(sumBytes))" : ""
            return "\(sel.count) of \(total) selected\(sizeStr)"
        }
    }

    var isCurrentFolderInICloud: Bool {
        currentURL.path.contains("/Library/Mobile Documents/")
    }
}
