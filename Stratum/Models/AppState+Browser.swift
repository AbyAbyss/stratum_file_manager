import Foundation
import AppKit
import SwiftUI

extension AppState {
    // MARK: - Pinned Favorites Support

    func isPinned(_ url: URL) -> Bool {
        let std = url.standardizedFileURL.path
        return pinnedFolderURLs.contains(where: { $0.standardizedFileURL.path == std })
    }

    func togglePinFolder(_ url: URL) {
        let std = url.standardizedFileURL
        if let idx = pinnedFolderURLs.firstIndex(where: { $0.standardizedFileURL.path == std.path }) {
            pinnedFolderURLs.remove(at: idx)
            showToast("Unpinned \(std.lastPathComponent) from Sidebar")
        } else {
            pinnedFolderURLs.append(std)
            showToast("Pinned \(std.lastPathComponent) to Sidebar")
        }
    }

    // MARK: - Column View Support

    func rebuildColumns(for targetURL: URL) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let targetPath = targetURL.standardizedFileURL.path
        var urlsToLoad: [URL] = []

        if targetPath.hasPrefix(home) {
            var cursor = URL(fileURLWithPath: home, isDirectory: true)
            urlsToLoad.append(cursor)
            let rel = targetPath.dropFirst(home.count)
            for comp in rel.split(separator: "/").map(String.init) {
                cursor.appendPathComponent(comp, isDirectory: true)
                urlsToLoad.append(cursor)
            }
        } else {
            var cursor = URL(fileURLWithPath: "/", isDirectory: true)
            urlsToLoad.append(cursor)
            for comp in targetPath.split(separator: "/").map(String.init) {
                cursor.appendPathComponent(comp, isDirectory: true)
                urlsToLoad.append(cursor)
            }
        }

        // Keep all ancestor columns so scrolling left always reveals previous folders
        let allColumnURLs = urlsToLoad
        let showHidden = showHiddenFiles
        let sort = sortField
        let asc = sortAscending
        let leafSelectedID = selectedItemIDs.first

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var panes: [ColumnPane] = []
            panes.reserveCapacity(allColumnURLs.count)
            for (idx, colURL) in allColumnURLs.enumerated() {
                let items = BulkDirectoryReader.shared.readDirectorySync(
                    at: colURL,
                    showHidden: showHidden,
                    sortField: sort,
                    ascending: asc
                )
                let nextURL: URL? = (idx + 1 < allColumnURLs.count) ? allColumnURLs[idx + 1] : nil
                let selectedID = nextURL?.path ?? leafSelectedID
                panes.append(ColumnPane(directoryURL: colURL, items: items, selectedItemID: selectedID))
            }
            Task { @MainActor in
                self?.columnPanes = panes
            }
        }
    }

    // MARK: - Tag Toggling on Selection

    func toggleTag(_ tag: FinderTag, on item: FileItem) {
        var currentTags = item.tags
        if let idx = currentTags.firstIndex(where: { $0.name.caseInsensitiveCompare(tag.name) == .orderedSame }) {
            currentTags.remove(at: idx)
        } else {
            currentTags.append(tag)
        }
        let path = item.id
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            BulkDirectoryReader.writeFinderTags(currentTags, toPath: path)
            Task { @MainActor in
                self?.reloadCurrentDirectory(preserveSelection: true)
            }
        }
    }

    func clearAllTags(on item: FileItem) {
        let path = item.id
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            BulkDirectoryReader.writeFinderTags([], toPath: path)
            Task { @MainActor in
                self?.reloadCurrentDirectory(preserveSelection: true)
                self?.showToast("Cleared tags on \(item.name)")
            }
        }
    }
}
