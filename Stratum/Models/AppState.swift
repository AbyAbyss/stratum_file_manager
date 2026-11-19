import Foundation
import AppKit
import SwiftUI

@Observable
@MainActor
final class AppState {
    private var isApplyingNavigationHistory: Bool = false

    var screen: AppScreen = .browser {
        didSet {
            guard !isApplyingNavigationHistory, screen != oldValue else { return }
            recordCurrentNavigationState(
                NavigationHistoryItem(
                    screen: screen,
                    url: currentURL,
                    smartFolderName: activeSmartFolderName,
                    smartFolderQuery: activeSmartFolderQuery,
                    tagFilter: selectedTagFilter
                )
            )
        }
    }

    var organizerTargetURL: URL? = nil

    var viewMode: BrowserViewMode = .grid {
        didSet {
            if viewMode == .columns {
                rebuildColumns(for: currentURL)
            }
        }
    }

    var showSidebar: Bool = true
    var showInspector: Bool = true
    var showCommandPalette: Bool = false
    var showGoToFolder: Bool = false
    var showQuickFilter: Bool = false
    var showBatchRename: Bool = false
    var showFDASheet: Bool = false
    var showStartupSplash: Bool = true
    /// True on the very first launch (and when replayed from Help); replaces the splash and
    /// the Full Disk Access sheet while it is up.
    var showWalkthrough: Bool = !Walkthrough.hasCompleted
    var hasFullDiskAccess: Bool = true

    var showHiddenFiles: Bool = false {
        didSet { reloadCurrentDirectory() }
    }

    var sortField: SortField = .name {
        didSet { resortCurrentItems() }
    }

    var sortAscending: Bool = true {
        didSet { resortCurrentItems() }
    }

    var groupByKind: Bool = true
    var iconScale: Double = 3.0 // 1..5 slider in status bar

    var filterQuery: String = "" {
        didSet {
            if searchEverywhereInBrowser {
                let q = filterQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                if !q.isEmpty {
                    runBrowserEverywhereSearch(query: q)
                } else {
                    updateDisplayedItems()
                }
            } else {
                updateDisplayedItems()
            }
        }
    }

    var selectedTagFilter: String? = nil {
        didSet {
            guard !isApplyingNavigationHistory else { return }
            if let tag = selectedTagFilter {
                activeSmartFolderName = nil
                activeSmartFolderQuery = nil
                isApplyingNavigationHistory = true
                screen = .browser
                isApplyingNavigationHistory = false
                recordCurrentNavigationState(
                    NavigationHistoryItem(
                        screen: .browser,
                        url: currentURL,
                        smartFolderName: nil,
                        smartFolderQuery: nil,
                        tagFilter: tag
                    )
                )
                loadCrossMacTagItemsIfNeeded()
            } else {
                recordCurrentNavigationState(
                    NavigationHistoryItem(
                        screen: .browser,
                        url: currentURL,
                        smartFolderName: nil,
                        smartFolderQuery: nil,
                        tagFilter: nil
                    )
                )
                reloadCurrentDirectory(preserveSelection: false)
            }
        }
    }

    var activeSmartFolderName: String? = nil
    var activeSmartFolderQuery: String? = nil
    var searchEverywhereInBrowser: Bool = false {
        didSet {
            if searchEverywhereInBrowser && !filterQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                runBrowserEverywhereSearch(query: filterQuery)
            } else if !searchEverywhereInBrowser && activeSmartFolderName == nil {
                reloadCurrentDirectory(preserveSelection: false)
            }
        }
    }

    // Tabs & Navigation
    var tabs: [BrowserTab] = []
    var activeTabID: UUID = UUID()

    // Current folder items
    private(set) var allItems: [FileItem] = []
    private(set) var displayedItems: [FileItem] = []
    private(set) var displayedFolders: [FileItem] = []
    private(set) var displayedFiles: [FileItem] = []
    private(set) var isLoadingDirectory: Bool = false
    private(set) var currentFolderTotalBytes: Int64 = 0

    // Selection
    var selectedItemIDs: Set<String> = [] {
        didSet {
            syncSelectionToActiveTab()
            let urls = selectedItems.map(\.url)
            QuickLookCoordinator.shared.updateIfVisible(with: urls)
        }
    }

    // Clipboard & Shelf
    var clipboardURLs: [URL] = []
    var clipboardIsMove: Bool = false
    var shelfURLs: [URL] = []

    // Custom Pinned Sidebar Folders
    var pinnedFolderURLs: [URL] = [] {
        didSet {
            let paths = pinnedFolderURLs.map(\.path)
            UserDefaults.standard.set(paths, forKey: "Stratum.pinnedFolderPaths")
        }
    }

    // Smart Folders
    var smartSearches: [SavedSmartSearch] = [
        SavedSmartSearch(id: UUID(), name: "Recent PDFs", query: ".pdf", kindFilter: "PDF", tagFilter: nil),
        SavedSmartSearch(id: UUID(), name: "Large Media", query: ".mov", kindFilter: "Video", tagFilter: nil),
        SavedSmartSearch(id: UUID(), name: "Source Code", query: ".swift", kindFilter: "Code", tagFilter: nil),
        SavedSmartSearch(id: UUID(), name: "Archives & ZIPs", query: ".zip", kindFilter: "Archive", tagFilter: nil)
    ]

    // Column view columns
    struct ColumnPane: Identifiable, Sendable {
        var id: String { directoryURL.path }
        let directoryURL: URL
        var items: [FileItem]
        var selectedItemID: String?

        var displayTitle: String {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            if directoryURL.path == home {
                return "Home"
            }
            if directoryURL.path == "/" {
                return "Macintosh HD"
            }
            return directoryURL.lastPathComponent.isEmpty ? directoryURL.path : directoryURL.lastPathComponent
        }
    }
    var columnPanes: [ColumnPane] = []

    // Volumes & Locations
    private(set) var volumes: [MountedVolumeInfo] = []
    private(set) var bootVolume: MountedVolumeInfo?
    private(set) var downloadsBadgeCount: Int = 0

    // Toast message
    var toastMessage: String? = nil

    private var loadTask: Task<Void, Never>?
    private var directoryWatcher: DirectoryWatcher?

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let initialURL = Self.resolveDefaultStartDirectory(home: home)
        let firstEntry = NavigationHistoryItem(screen: .browser, url: initialURL)
        let firstTab = BrowserTab(
            id: UUID(),
            url: initialURL,
            history: [firstEntry],
            historyIndex: 0,
            selectedIDs: []
        )
        self.tabs = [firstTab]
        self.activeTabID = firstTab.id

        if let savedPaths = UserDefaults.standard.stringArray(forKey: "Stratum.pinnedFolderPaths") {
            self.pinnedFolderURLs = savedPaths.map { URL(fileURLWithPath: $0, isDirectory: true) }
        }

        setupWatcher()
        refreshVolumes()
        checkFDAOnLaunch()
        loadDirectory(at: initialURL, recordHistory: false)
    }

    private static func resolveDefaultStartDirectory(home: URL) -> URL {
        let candidates = [
            home.appendingPathComponent("Desktop"),
            home.appendingPathComponent("Documents"),
            home
        ]
        for url in candidates {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                return url
            }
        }
        return home
    }

    private func setupWatcher() {
        directoryWatcher = DirectoryWatcher(debounceInterval: 0.150) { [weak self] in
            Task { @MainActor in
                self?.reloadCurrentDirectory(preserveSelection: true)
            }
        }
    }

    private func checkFDAOnLaunch() {
        FullDiskAccess.checkAccess { [weak self] granted in
            guard let self else { return }
            self.hasFullDiskAccess = granted
            if !granted && !FullDiskAccess.hasShownFirstRunPrompt && !self.showWalkthrough {
                self.showFDASheet = true
            }
        }
    }

    // MARK: - Navigation & Tabs

    private func recordCurrentNavigationState(_ entry: NavigationHistoryItem) {
        guard let idx = activeTabIndex else { return }
        if tabs[idx].historyIndex < tabs[idx].history.count - 1 {
            tabs[idx].history.removeSubrange((tabs[idx].historyIndex + 1)...)
        }
        if tabs[idx].history.last != entry {
            tabs[idx].history.append(entry)
            tabs[idx].historyIndex = tabs[idx].history.count - 1
        }
    }

    func navigate(to url: URL, recordHistory: Bool = true) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return
        }
        let stdURL = url.standardizedFileURL
        isApplyingNavigationHistory = true
        selectedTagFilter = nil
        activeSmartFolderName = nil
        activeSmartFolderQuery = nil
        searchEverywhereInBrowser = false
        screen = .browser
        isApplyingNavigationHistory = false
        loadDirectory(at: stdURL, recordHistory: recordHistory)
    }

    func selectItemInColumn(_ item: FileItem, paneDirectoryURL: URL) {
        if item.isFolderLike {
            navigate(to: item.url)
        } else {
            let standardizedPane = paneDirectoryURL.standardizedFileURL
            if standardizedPane != currentURL.standardizedFileURL {
                selectedItemIDs = [item.id]
                loadDirectory(at: standardizedPane, recordHistory: true, preserveSelection: true)
            } else {
                selectedItemIDs = [item.id]
            }
        }
    }

    func openItem(_ item: FileItem) {
        if item.isFolderLike {
            navigate(to: item.url)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    func openInSmartOrganizer(_ url: URL) {
        var isDir: ObjCBool = false
        let targetDir = (FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue)
            ? url
            : url.deletingLastPathComponent()
        let stdTarget = targetDir.standardizedFileURL
        organizerTargetURL = stdTarget
        loadDirectory(at: stdTarget, recordHistory: true)
        screen = .organizer
    }

    func scanFolder(_ url: URL, inScreen targetScreen: AppScreen = .storage) {
        var isDir: ObjCBool = false
        let targetDir = (FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue)
            ? url
            : url.deletingLastPathComponent()
        screen = targetScreen
        ScanCoordinator.shared.startScan(at: targetDir.standardizedFileURL)
        showToast("Scanning \(targetDir.lastPathComponent)…")
    }

    func selectAllItems() {
        selectedItemIDs = Set(displayedItems.map(\.id))
    }

    func goBack() {
        guard let idx = activeTabIndex, tabs[idx].historyIndex > 0 else { return }
        tabs[idx].historyIndex -= 1
        let entry = tabs[idx].history[tabs[idx].historyIndex]
        applyNavigationHistoryEntry(entry)
    }

    func goForward() {
        guard let idx = activeTabIndex, tabs[idx].historyIndex < tabs[idx].history.count - 1 else { return }
        tabs[idx].historyIndex += 1
        let entry = tabs[idx].history[tabs[idx].historyIndex]
        applyNavigationHistoryEntry(entry)
    }

    private func applyNavigationHistoryEntry(_ entry: NavigationHistoryItem) {
        isApplyingNavigationHistory = true
        defer { isApplyingNavigationHistory = false }

        screen = entry.screen
        searchEverywhereInBrowser = false

        if let idx = activeTabIndex {
            tabs[idx].url = entry.url
        }

        if let smartName = entry.smartFolderName {
            selectedTagFilter = nil
            openSmartFolder(named: smartName, customQuery: entry.smartFolderQuery, recordHistory: false)
        } else if let tag = entry.tagFilter {
            activeSmartFolderName = nil
            activeSmartFolderQuery = nil
            selectedTagFilter = tag
            loadDirectory(at: entry.url, recordHistory: false)
            loadCrossMacTagItemsIfNeeded()
        } else {
            activeSmartFolderName = nil
            activeSmartFolderQuery = nil
            selectedTagFilter = nil
            loadDirectory(at: entry.url, recordHistory: false)
        }
    }

    func goUp() {
        if screen != .browser {
            screen = .browser
            return
        }
        if activeSmartFolderName != nil || selectedTagFilter != nil {
            exitSmartFolder()
            return
        }
        let parent = currentURL.deletingLastPathComponent()
        if parent.path != currentURL.path {
            navigate(to: parent)
        }
    }

    func addNewTab(at url: URL? = nil) {
        let target = (url ?? currentURL).standardizedFileURL
        let firstEntry = NavigationHistoryItem(screen: .browser, url: target)
        let tab = BrowserTab(
            id: UUID(),
            url: target,
            history: [firstEntry],
            historyIndex: 0,
            selectedIDs: []
        )
        tabs.append(tab)
        selectTab(tab.id)
    }

    func closeTab(_ id: UUID) {
        guard tabs.count > 1, let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        let wasActive = (activeTabID == id)
        tabs.remove(at: idx)
        if wasActive {
            let nextIdx = min(idx, tabs.count - 1)
            selectTab(tabs[nextIdx].id)
        }
    }

    func selectTab(_ id: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        activeTabID = id
        let tab = tabs[idx]
        selectedItemIDs = tab.selectedIDs
        if tab.history.indices.contains(tab.historyIndex) {
            applyNavigationHistoryEntry(tab.history[tab.historyIndex])
        } else {
            isApplyingNavigationHistory = true
            screen = .browser
            activeSmartFolderName = nil
            activeSmartFolderQuery = nil
            selectedTagFilter = nil
            isApplyingNavigationHistory = false
            loadDirectory(at: tab.url, recordHistory: false, preserveSelection: true)
        }
    }

    private func syncSelectionToActiveTab() {
        guard let idx = activeTabIndex else { return }
        tabs[idx].selectedIDs = selectedItemIDs
    }

    // MARK: - Directory Streaming

    func reloadCurrentDirectory(preserveSelection: Bool = true) {
        if let smartName = activeSmartFolderName {
            openSmartFolder(named: smartName, customQuery: activeSmartFolderQuery, recordHistory: false)
            return
        }
        loadDirectory(at: currentURL, recordHistory: false, preserveSelection: preserveSelection)
    }

    private func loadDirectory(at url: URL, recordHistory: Bool, preserveSelection: Bool = false) {
        loadTask?.cancel()

        if let idx = activeTabIndex {
            tabs[idx].url = url
        }
        if recordHistory {
            recordCurrentNavigationState(
                NavigationHistoryItem(
                    screen: screen,
                    url: url,
                    smartFolderName: activeSmartFolderName,
                    smartFolderQuery: activeSmartFolderQuery,
                    tagFilter: selectedTagFilter
                )
            )
        }

        if !preserveSelection {
            selectedItemIDs = []
            filterQuery = ""
        }

        directoryWatcher?.watch(url: url)
        isLoadingDirectory = true

        let showHidden = showHiddenFiles
        let sort = sortField
        let asc = sortAscending

        loadTask = Task { [weak self] in
            let stream = BulkDirectoryReader.shared.streamDirectory(
                at: url,
                showHidden: showHidden,
                sortField: sort,
                ascending: asc
            )

            for await batch in stream {
                if Task.isCancelled { return }
                guard let self else { return }
                self.allItems = batch.items
                self.currentFolderTotalBytes = batch.totalBytes
                self.updateDisplayedItems()
                if batch.isComplete {
                    self.isLoadingDirectory = false
                    if self.viewMode == .columns {
                        self.rebuildColumns(for: url)
                    }
                }
            }
        }
    }

    private func resortCurrentItems() {
        let items = allItems
        let field = sortField
        let asc = sortAscending
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let sorted = BulkDirectoryReader.sortItems(items, by: field, ascending: asc)
            Task { @MainActor in
                guard let self else { return }
                self.allItems = sorted
                self.updateDisplayedItems()
                if self.viewMode == .columns {
                    self.rebuildColumns(for: self.currentURL)
                }
            }
        }
    }

    private func updateDisplayedItems() {
        var filtered = allItems
        if let tag = selectedTagFilter {
            filtered = filtered.filter { item in
                item.tags.contains(where: { $0.name.caseInsensitiveCompare(tag) == .orderedSame })
            }
        }
        let q = filterQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            filtered = filtered.filter { $0.lowercasedName.contains(q) }
        }
        displayedItems = filtered
        displayedFolders = filtered.filter(\.isFolderLike)
        displayedFiles = filtered.filter { !$0.isFolderLike }

        // Keep default selection or valid selection
        if !selectedItemIDs.isEmpty {
            let validIDs = Set(filtered.map(\.id))
            let intersection = selectedItemIDs.intersection(validIDs)
            if intersection != selectedItemIDs {
                selectedItemIDs = intersection
            }
        }
    }

    // MARK: - Cross-Mac Smart Folders & Everywhere Search

    func exitSmartFolder() {
        navigate(to: currentURL, recordHistory: true)
    }

    func openSmartFolder(named name: String, customQuery: String? = nil, recordHistory: Bool = true) {
        loadTask?.cancel()
        let prevFlag = isApplyingNavigationHistory
        isApplyingNavigationHistory = true
        selectedTagFilter = nil
        filterQuery = ""
        searchEverywhereInBrowser = false
        activeSmartFolderName = name
        activeSmartFolderQuery = customQuery
        screen = .browser
        isApplyingNavigationHistory = prevFlag

        if recordHistory {
            recordCurrentNavigationState(
                NavigationHistoryItem(
                    screen: .browser,
                    url: currentURL,
                    smartFolderName: name,
                    smartFolderQuery: customQuery,
                    tagFilter: nil
                )
            )
        }

        isLoadingDirectory = true
        selectedItemIDs = []

        let currentDir = currentURL
        loadTask = Task { [weak self] in
            let items = await Task.detached(priority: .userInitiated) { () -> [FileItem] in
                let pool = Self.collectCrossMacCandidatePool(including: currentDir)
                let lowerName = name.lowercased()
                var matched: [FileItem] = []

                if lowerName == "large files" {
                    let nonFolders = pool.filter { !$0.isFolderLike && $0.size > 0 }
                    let over5MB = nonFolders.filter { $0.size >= 5 * 1024 * 1024 }
                    matched = over5MB.count >= 5 ? over5MB : Array(nonFolders.sorted { $0.size > $1.size }.prefix(80))
                    matched.sort { $0.size > $1.size }
                } else if lowerName == "modified recently" {
                    let cutoff = Date().addingTimeInterval(-14 * 86400)
                    let recent = pool.filter { !$0.isFolderLike && $0.modificationDate >= cutoff }
                    matched = recent.isEmpty ? Array(pool.filter { !$0.isFolderLike }.sorted { $0.modificationDate > $1.modificationDate }.prefix(80)) : recent.sorted { $0.modificationDate > $1.modificationDate }
                } else if lowerName == "screenshots" {
                    matched = pool.filter { item in
                        guard item.kindCategory == .image else { return false }
                        let n = item.lowercasedName
                        return n.contains("screenshot") || n.contains("screen shot") || n.contains("cleanshot") || n.contains("capture") || item.ext == "png"
                    }.sorted { $0.modificationDate > $1.modificationDate }
                } else if lowerName == "recent pdfs" {
                    matched = pool.filter { $0.ext == "pdf" || $0.kindCategory == .pdf }
                        .sorted { $0.modificationDate > $1.modificationDate }
                } else if lowerName == "large media" {
                    matched = pool.filter {
                        $0.kindCategory == .video || $0.kindCategory == .audio || ($0.kindCategory == .image && $0.size >= 250_000)
                    }.sorted { $0.size > $1.size }
                } else if lowerName == "source code" {
                    matched = pool.filter {
                        $0.kindCategory == .code || ["swift", "py", "js", "ts", "tsx", "jsx", "rs", "go", "c", "cpp", "h", "html", "css", "json", "md", "sh", "yml", "yaml", "toml"].contains($0.ext)
                    }.sorted { $0.modificationDate > $1.modificationDate }
                } else if lowerName == "archives & zips" {
                    matched = pool.filter {
                        $0.kindCategory == .archive || ["zip", "dmg", "pkg", "tar", "gz", "tgz", "7z", "rar", "iso"].contains($0.ext)
                    }.sorted { $0.size > $1.size }
                } else if let q = customQuery?.lowercased(), !q.isEmpty {
                    let cleanExt = q.hasPrefix(".") ? String(q.dropFirst()) : q
                    matched = pool.filter {
                        $0.lowercasedName.contains(q) || $0.ext == cleanExt
                    }.sorted { $0.modificationDate > $1.modificationDate }
                } else {
                    matched = pool.filter { $0.lowercasedName.contains(lowerName) }
                }
                return Array(matched.prefix(250))
            }.value

            guard let self, !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                self.allItems = items
                self.currentFolderTotalBytes = items.reduce(Int64(0)) { $0 + $1.size }
                self.isLoadingDirectory = false
                self.updateDisplayedItems()
            }
        }
    }

    private func loadCrossMacTagItemsIfNeeded() {
        guard let tag = selectedTagFilter else { return }
        let currentMatches = allItems.filter { item in
            item.tags.contains(where: { $0.name.caseInsensitiveCompare(tag) == .orderedSame })
        }
        updateDisplayedItems()
        guard currentMatches.isEmpty else { return }

        let currentDir = currentURL
        Task { [weak self] in
            let taggedAcrossMac = await Task.detached(priority: .userInitiated) { () -> [FileItem] in
                let pool = Self.collectCrossMacCandidatePool(including: currentDir)
                return pool.filter { item in
                    item.tags.contains(where: { $0.name.caseInsensitiveCompare(tag) == .orderedSame })
                }
            }.value
            guard let self, self.selectedTagFilter == tag, !taggedAcrossMac.isEmpty else { return }
            self.allItems = taggedAcrossMac
            self.updateDisplayedItems()
        }
    }

    func runBrowserEverywhereSearch(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return }
        isLoadingDirectory = true
        let currentDir = currentURL

        loadTask?.cancel()
        loadTask = Task { [weak self] in
            let matches = await Task.detached(priority: .userInitiated) { () -> [FileItem] in
                let pool = Self.collectCrossMacCandidatePool(including: currentDir)
                return pool.filter {
                    $0.lowercasedName.contains(trimmed) || $0.kindDescription.lowercased().contains(trimmed)
                }.sorted { a, b in
                    let aPre = a.lowercasedName.hasPrefix(trimmed)
                    let bPre = b.lowercasedName.hasPrefix(trimmed)
                    if aPre != bPre { return aPre }
                    return a.modificationDate > b.modificationDate
                }
            }.value

            guard let self, !Task.isCancelled else { return }
            self.allItems = Array(matches.prefix(250))
            self.currentFolderTotalBytes = self.allItems.reduce(Int64(0)) { $0 + $1.size }
            self.isLoadingDirectory = false
            self.updateDisplayedItems()
        }
    }

    nonisolated static func collectCrossMacCandidatePool(including extraRoot: URL?) -> [FileItem] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var roots: [URL] = [
            home.appendingPathComponent("Desktop"),
            home.appendingPathComponent("Downloads"),
            home.appendingPathComponent("Documents"),
            home.appendingPathComponent("Pictures"),
            home.appendingPathComponent("Movies"),
            URL(fileURLWithPath: "/Applications")
        ]
        if let extraRoot, !roots.contains(where: { $0.standardizedFileURL == extraRoot.standardizedFileURL }) {
            roots.insert(extraRoot, at: 0)
        }

        let skipDirs: Set<String> = ["node_modules", ".git", "target", "DerivedData", ".build", ".next", ".venv", "venv", "__pycache__", "Library"]
        var seen = Set<String>()
        var pool: [FileItem] = []

        for root in roots {
            let level1 = BulkDirectoryReader.shared.readDirectorySync(at: root, showHidden: false)
            for item in level1 where seen.insert(item.id).inserted {
                pool.append(item)
            }
            // Level 2 subfolders
            for sub1 in level1.prefix(35) where sub1.isFolderLike && !skipDirs.contains(sub1.name) {
                let level2 = BulkDirectoryReader.shared.readDirectorySync(at: sub1.url, showHidden: false)
                for item2 in level2 where seen.insert(item2.id).inserted {
                    pool.append(item2)
                }
                // Level 3 subfolders
                for sub2 in level2.prefix(20) where sub2.isFolderLike && !skipDirs.contains(sub2.name) {
                    let level3 = BulkDirectoryReader.shared.readDirectorySync(at: sub2.url, showHidden: false)
                    for item3 in level3 where seen.insert(item3.id).inserted {
                        pool.append(item3)
                    }
                }
            }
        }
        return pool
    }

    // MARK: - Volumes & Favorite Locations

    func refreshVolumes() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let keys: [URLResourceKey] = [
                .volumeNameKey,
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeAvailableCapacityKey,
                .volumeIsEjectableKey,
                .volumeIsRemovableKey,
                .volumeIsLocalKey,
                .volumeIsBrowsableKey
            ]
            let urls = FileManager.default.mountedVolumeURLs(
                includingResourceValuesForKeys: keys,
                options: [.skipHiddenVolumes]
            ) ?? []

            var list: [MountedVolumeInfo] = []
            for u in urls {
                guard let vals = try? u.resourceValues(forKeys: Set(keys)) else { continue }
                let name = vals.volumeName ?? u.lastPathComponent
                let total = Int64(vals.volumeTotalCapacity ?? 0)
                let availImportant = vals.volumeAvailableCapacityForImportantUsage ?? 0
                let availStd = Int64(vals.volumeAvailableCapacity ?? 0)
                let free = max(availImportant, availStd)
                let ejectable = (vals.volumeIsEjectable ?? false) || (vals.volumeIsRemovable ?? false)
                let isNet = !(vals.volumeIsLocal ?? true)
                list.append(MountedVolumeInfo(
                    name: name,
                    url: u,
                    totalBytes: total,
                    freeBytes: free,
                    isEjectable: ejectable,
                    isNetwork: isNet
                ))
            }

            // Count items in Downloads for the sidebar badge
            let dlURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
            let dlItems = BulkDirectoryReader.shared.readDirectorySync(at: dlURL, showHidden: false)
            let dlCount = dlItems.count

            Task { @MainActor in
                guard let self else { return }
                self.volumes = list
                self.bootVolume = list.first(where: { $0.url.path == "/" }) ?? list.first
                self.downloadsBadgeCount = dlCount
            }
        }
    }

    func ejectVolume(_ volume: MountedVolumeInfo) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try NSWorkspace.shared.unmountAndEjectDevice(at: volume.url)
                Task { @MainActor in
                    self?.showToast("Ejected \(volume.name)")
                    self?.refreshVolumes()
                }
            } catch {
                Task { @MainActor in
                    self?.showToast("Could not eject \(volume.name): \(error.localizedDescription)")
                }
            }
        }
    }

}
