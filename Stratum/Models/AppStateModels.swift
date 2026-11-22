import Foundation
import SwiftUI

enum AppScreen: String, CaseIterable, Codable, Sendable {
    case browser = "browser"
    case organizer = "organizer"
    case groups = "groups"
    case storage = "storage"
    case history = "history"
    case settings = "settings"

    var title: String {
        switch self {
        case .browser: return "Browser"
        case .organizer: return "Smart Organizer"
        case .groups: return "Groups"
        case .storage: return "Storage"
        case .history: return "Storage History"
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
    /// Pinned tabs sit at the left as compact icons, can't be closed by accident, and come back
    /// on the next launch.
    var isPinned: Bool = false

    /// Pinned tabs first, keeping each group's existing order.
    static func pinnedFirst(_ tabs: [BrowserTab]) -> [BrowserTab] {
        tabs.filter(\.isPinned) + tabs.filter { !$0.isPinned }
    }

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
