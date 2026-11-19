import Foundation
import AppKit
import SwiftUI
import CryptoKit

enum AppScreen: String, CaseIterable, Codable, Sendable {
    case browser = "browser"
    case organizer = "organizer"
    case groups = "groups"
    case storage = "storage"
    case settings = "settings"

    var title: String {
        switch self {
        case .browser: return "Browser"
        case .organizer: return "Smart Organizer"
        case .groups: return "Groups"
        case .storage: return "Storage"
        case .settings: return "Settings"
        }
    }
}

enum BrowserViewMode: String, CaseIterable, Sendable {
    case grid = "grid"
    case list = "list"
    case columns = "columns"
}

struct NavigationHistoryItem: Equatable, Sendable {
    var screen: AppScreen
    var url: URL
    var smartFolderName: String? = nil
    var smartFolderQuery: String? = nil
    var tagFilter: String? = nil
}

struct BrowserTab: Identifiable, Sendable {
    let id: UUID
    var url: URL
    var history: [NavigationHistoryItem]
    var historyIndex: Int
    var selectedIDs: Set<String>

    var title: String {
        if url.path == "/" { return "Macintosh HD" }
        return url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
    }
}

struct MountedVolumeInfo: Identifiable, Sendable {
    var id: String { url.path }
    let name: String
    let url: URL
    let totalBytes: Int64
    let freeBytes: Int64
    let isEjectable: Bool
    let isNetwork: Bool

    var usedBytes: Int64 {
        max(0, totalBytes - freeBytes)
    }

    var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }
}

struct PathSegment: Identifiable, Sendable {
    var id: String { url.path }
    let name: String
    let url: URL
    let isLast: Bool
}

struct SavedSmartSearch: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var query: String
    var kindFilter: String?
    var tagFilter: String?
}

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

    // MARK: - File Operations (Milestone 2 + Power User Actions)

    func createNewFolder() {
        let baseDir = currentURL
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let fm = FileManager.default
            var name = "untitled folder"
            var candidate = baseDir.appendingPathComponent(name)
            var counter = 2
            while fm.fileExists(atPath: candidate.path) {
                name = "untitled folder \(counter)"
                candidate = baseDir.appendingPathComponent(name)
                counter += 1
            }
            do {
                try fm.createDirectory(at: candidate, withIntermediateDirectories: false)
                Task { @MainActor in
                    guard let self else { return }
                    self.selectedItemIDs = [candidate.path]
                    self.reloadCurrentDirectory(preserveSelection: true)
                    ScanCoordinator.shared.notifyFileSystemMutation(near: candidate)
                    self.showToast("Created \(name)")
                }
            } catch {
                Task { @MainActor in
                    self?.showToast("Could not create folder: \(error.localizedDescription)")
                }
            }
        }
    }

    func createNewFolderWithSelection() {
        let selectedURLs = selectedItems.map(\.url)
        guard !selectedURLs.isEmpty else {
            createNewFolder()
            return
        }
        let baseDir = currentURL
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let fm = FileManager.default
            var name = "New Folder with Items"
            var candidate = baseDir.appendingPathComponent(name)
            var counter = 2
            while fm.fileExists(atPath: candidate.path) {
                name = "New Folder with Items \(counter)"
                candidate = baseDir.appendingPathComponent(name)
                counter += 1
            }
            do {
                try fm.createDirectory(at: candidate, withIntermediateDirectories: false)
                var movedCount = 0
                for src in selectedURLs {
                    let dst = candidate.appendingPathComponent(src.lastPathComponent)
                    try? fm.moveItem(at: src, to: dst)
                    movedCount += 1
                }
                Task { @MainActor in
                    guard let self else { return }
                    self.selectedItemIDs = [candidate.path]
                    self.reloadCurrentDirectory(preserveSelection: true)
                    ScanCoordinator.shared.notifyFileSystemMutation(near: candidate)
                    self.showToast("Grouped \(movedCount) \(movedCount == 1 ? "item" : "items") into \(name)")
                }
            } catch {
                Task { @MainActor in
                    self?.showToast("Could not create folder: \(error.localizedDescription)")
                }
            }
        }
    }

    func createNewFile(baseName: String, ext: String, contents: String = "") {
        let baseDir = currentURL
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let fm = FileManager.default
            let suffix = ext.isEmpty ? "" : ".\(ext)"
            var name = "\(baseName)\(suffix)"
            var candidate = baseDir.appendingPathComponent(name)
            var counter = 2
            while fm.fileExists(atPath: candidate.path) {
                name = "\(baseName) \(counter)\(suffix)"
                candidate = baseDir.appendingPathComponent(name)
                counter += 1
            }
            do {
                try Data(contents.utf8).write(to: candidate, options: .atomic)
                if ext == "sh" {
                    try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: candidate.path)
                }
                Task { @MainActor in
                    guard let self else { return }
                    self.selectedItemIDs = [candidate.path]
                    self.reloadCurrentDirectory(preserveSelection: true)
                    ScanCoordinator.shared.notifyFileSystemMutation(near: candidate)
                    self.showToast("Created \(name)")
                }
            } catch {
                Task { @MainActor in
                    self?.showToast("Could not create file: \(error.localizedDescription)")
                }
            }
        }
    }

    func computeSHA256(for url: URL) {
        showToast("Calculating SHA-256 for \(url.lastPathComponent)…")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
                Task { @MainActor in
                    self?.showToast("Could not read \(url.lastPathComponent) for checksum")
                }
                return
            }
            let digest = SHA256.hash(data: data)
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            Task { @MainActor in
                TerminalLauncher.copyPathToPasteboard(hex)
                self?.showToast("SHA-256 copied: \(hex.prefix(16))…")
            }
        }
    }

    func toggleExecutableBit(for url: URL) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let fm = FileManager.default
            guard let attrs = try? fm.attributesOfItem(atPath: url.path),
                  let perms = attrs[.posixPermissions] as? Int else {
                return
            }
            let isExec = (perms & 0o111) != 0
            let newPerms = isExec ? (perms & ~0o111) : (perms | 0o111)
            try? fm.setAttributes([.posixPermissions: newPerms], ofItemAtPath: url.path)
            Task { @MainActor in
                self?.reloadCurrentDirectory(preserveSelection: true)
                self?.showToast(isExec ? "Removed executable permission (-x)" : "Marked executable (chmod +x)")
            }
        }
    }

    func copySelectionToClipboard() {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        clipboardURLs = urls
        clipboardIsMove = false
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(urls as [NSURL])
        showToast("Copied \(urls.count) \(urls.count == 1 ? "item" : "items")")
    }

    func cutSelectionToClipboard() {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        clipboardURLs = urls
        clipboardIsMove = true
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(urls as [NSURL])
        showToast("Ready to move \(urls.count) \(urls.count == 1 ? "item" : "items")")
    }

    func pasteIntoCurrentFolder(forceMove: Bool = false) {
        var urls = clipboardURLs
        if urls.isEmpty {
            let pb = NSPasteboard.general
            if let read = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] {
                urls = read
            }
        }
        guard !urls.isEmpty else { return }
        let kind: TransferKind = (forceMove || clipboardIsMove) ? .move : .copy
        let dest = currentURL
        if kind == .move {
            clipboardURLs = []
            clipboardIsMove = false
        }
        TransferQueueEngine.shared.enqueueTransfer(
            kind: kind,
            sourceURLs: urls,
            to: dest,
            conflictPolicy: .keepBoth
        ) { [weak self] in
            self?.reloadCurrentDirectory(preserveSelection: true)
            self?.showToast("\(kind == .move ? "Moved" : "Pasted") \(urls.count) \(urls.count == 1 ? "item" : "items")")
        }
    }

    func duplicateSelection() {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        let dest = currentURL
        TransferQueueEngine.shared.enqueueTransfer(
            kind: .copy,
            sourceURLs: urls,
            to: dest,
            conflictPolicy: .keepBoth
        ) { [weak self] in
            self?.reloadCurrentDirectory(preserveSelection: true)
            self?.showToast("Duplicated \(urls.count) \(urls.count == 1 ? "item" : "items")")
        }
    }

    func compressSelection() {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        let dest = currentURL
        TransferQueueEngine.shared.enqueueTransfer(
            kind: .compress,
            sourceURLs: urls,
            to: dest,
            conflictPolicy: .keepBoth
        ) { [weak self] in
            self?.reloadCurrentDirectory(preserveSelection: true)
            self?.showToast("Compressed \(urls.count) \(urls.count == 1 ? "item" : "items")")
        }
    }

    func moveSelectionToTrash() {
        let items = selectedItems
        guard !items.isEmpty else { return }
        moveURLsToTrash(items.map { (url: $0.url, size: $0.size) })
    }

    func deleteSelectionImmediately() {
        let items = selectedItems
        guard !items.isEmpty else { return }
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Delete \(items.count) \(items.count == 1 ? "item" : "items") immediately?"
        alert.informativeText = "These items will be permanently deleted and cannot be restored from the Trash."
        alert.addButton(withTitle: "Delete Immediately")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let urls = items.map(\.url)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let fm = FileManager.default
            var deletedCount = 0
            for url in urls where !ProtectedPaths.isProtected(url.path) {
                if (try? fm.removeItem(at: url)) != nil {
                    deletedCount += 1
                }
            }
            Task { @MainActor in
                self?.selectedItemIDs = []
                self?.reloadCurrentDirectory(preserveSelection: false)
                self?.refreshVolumes()
                ScanCoordinator.shared.notifyFileSystemMutation(near: self?.currentURL)
                self?.showToast("Permanently deleted \(deletedCount) \(deletedCount == 1 ? "item" : "items")")
            }
        }
    }

    func moveURLsToTrash(_ targets: [(url: URL, size: Int64)]) {
        guard !targets.isEmpty else { return }
        let deleteItems = targets.map { DeleteTargetItem(path: $0.url.path, sizeBytes: $0.size) }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcome = DeleteService.moveToTrash(deleteItems)
            Task { @MainActor in
                guard let self else { return }
                TransferQueueEngine.shared.recordTrashOutcome(outcome)
                self.selectedItemIDs.subtract(outcome.removedPaths)
                self.reloadCurrentDirectory(preserveSelection: true)
                self.refreshVolumes()
                ScanCoordinator.shared.notifyFileSystemMutation(near: targets.first?.url)
                if !outcome.removed.isEmpty {
                    let count = outcome.removed.count
                    self.showToast("Moved \(count) \(count == 1 ? "item" : "items") to Trash (⌘Z to Undo)")
                } else if let err = outcome.failed.first?.reason {
                    self.showToast("Cannot move to Trash: \(err)")
                }
            }
        }
    }

    func undoLastTrash() {
        guard let last = TransferQueueEngine.shared.trashHistory.first else {
            showToast("Nothing to undo in Trash history")
            return
        }
        TransferQueueEngine.shared.undoTrashRecord(last) { [weak self] in
            self?.reloadCurrentDirectory(preserveSelection: true)
            self?.refreshVolumes()
            ScanCoordinator.shared.notifyFileSystemMutation(near: self?.currentURL)
            self?.showToast("Restored \(last.itemCount) \(last.itemCount == 1 ? "item" : "items") from Trash")
        }
    }

    func handleDroppedURLs(_ urls: [URL], into destinationFolder: URL, isMove: Bool) {
        let validURLs = urls.filter { $0.standardizedFileURL != destinationFolder.standardizedFileURL }
        guard !validURLs.isEmpty else { return }
        let kind: TransferKind = isMove ? .move : .copy
        TransferQueueEngine.shared.enqueueTransfer(
            kind: kind,
            sourceURLs: validURLs,
            to: destinationFolder,
            conflictPolicy: .keepBoth
        ) { [weak self] in
            self?.reloadCurrentDirectory(preserveSelection: true)
            self?.showToast("\(isMove ? "Moved" : "Copied") \(validURLs.count) \(validURLs.count == 1 ? "item" : "items") to \(destinationFolder.lastPathComponent)")
        }
    }

    // MARK: - Shelf Support

    func addToShelf(_ urls: [URL]) {
        for url in urls where !shelfURLs.contains(url) {
            shelfURLs.append(url)
        }
        if !urls.isEmpty {
            showToast("Parked \(urls.count) \(urls.count == 1 ? "item" : "items") on Shelf")
        }
    }

    func removeFromShelf(_ url: URL) {
        shelfURLs.removeAll(where: { $0 == url })
    }

    func dropAllShelfItems(into destinationFolder: URL) {
        guard !shelfURLs.isEmpty else { return }
        let itemsToCopy = shelfURLs
        shelfURLs.removeAll()
        TransferQueueEngine.shared.enqueueTransfer(
            kind: .copy,
            sourceURLs: itemsToCopy,
            to: destinationFolder,
            conflictPolicy: .keepBoth
        ) { [weak self] in
            self?.reloadCurrentDirectory(preserveSelection: true)
            self?.showToast("Dropped \(itemsToCopy.count) Shelf \(itemsToCopy.count == 1 ? "item" : "items") into \(destinationFolder.lastPathComponent)")
        }
    }

    func startWalkthrough() {
        withAnimation(.easeOut(duration: 0.3)) { showWalkthrough = true }
    }

    func finishWalkthrough() {
        showStartupSplash = false   // the tour was the welcome; don't play the splash right after it
        withAnimation(.easeOut(duration: 0.25)) { showWalkthrough = false }
    }

    func replayStartupSplash() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            showStartupSplash = true
        }
    }

    func showToast(_ text: String) {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
            toastMessage = text
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if self.toastMessage == text {
                withAnimation(.easeInOut(duration: 0.25)) {
                    self.toastMessage = nil
                }
            }
        }
    }
}
