import Foundation

struct SearchFilterChip: Identifiable, Equatable, Sendable {
    let id = UUID()
    let key: String   // e.g. "kind", "modified", "tag"
    let value: String // e.g. "PDF", "last 7 days", "Client"
}

enum PaletteTabScope: String, CaseIterable, Sendable {
    case all = "All results"
    case names = "Names"
    case insideFiles = "Inside files"
    case actions = "Actions"
    case tags = "Tags"
}

struct SpotlightResultItem: Identifiable, Sendable {
    var id: String { item.id }
    let item: FileItem
    let isContentMatch: Bool
    let snippet: String?
    let parentChain: String
}

final class SpotlightSearchEngine: @unchecked Sendable {
    static let shared = SpotlightSearchEngine()
    private let searchQueue = DispatchQueue(label: "app.stratum.spotlight-search", qos: .userInitiated)

    func search(
        query: String,
        chips: [SearchFilterChip],
        rootURL: URL?,
        inCurrentFolderItems: [FileItem],
        completion: @escaping @MainActor (_ nameMatches: [SpotlightResultItem], _ contentMatches: [SpotlightResultItem]) -> Void
    ) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerQuery = trimmed.lowercased()

        searchQueue.async {
            var candidatePool: [FileItem] = inCurrentFolderItems
            var seen = Set(candidatePool.map(\.id))

            // When searching Everywhere (rootURL == nil), gather items across Desktop, Downloads, Documents, Pictures, Movies, and /Applications up to 3 levels deep
            if rootURL == nil {
                let crossMacPool = AppState.collectCrossMacCandidatePool(including: nil)
                for item in crossMacPool where seen.insert(item.id).inserted {
                    candidatePool.append(item)
                }
            } else if let rootURL {
                let subPool = AppState.collectCrossMacCandidatePool(including: rootURL)
                let rootPrefix = rootURL.standardizedFileURL.path
                for item in subPool where item.id.hasPrefix(rootPrefix) && seen.insert(item.id).inserted {
                    candidatePool.append(item)
                }
            }

            // Apply filter chips
            let filteredPool = candidatePool.filter { item in
                for chip in chips {
                    switch chip.key.lowercased() {
                    case "kind":
                        let val = chip.value.lowercased()
                        if val == "pdf" && item.ext != "pdf" && item.kindCategory != .pdf { return false }
                        if val == "folder" && !item.isFolderLike { return false }
                        if val == "image" && item.kindCategory != .image { return false }
                        if val == "video" && item.kindCategory != .video { return false }
                        if val == "audio" && item.kindCategory != .audio { return false }
                        if val == "code" && item.kindCategory != .code { return false }
                        if val == "archive" && item.kindCategory != .archive { return false }
                        if (val == "app" || val == "application") && !item.isAppOrPackage { return false }
                        if val == "document" && item.kindCategory != .document && item.kindCategory != .pdf { return false }
                    case "modified":
                        let now = Date()
                        if chip.value.lowercased().contains("7") {
                            if now.timeIntervalSince(item.modificationDate) > 7 * 86400 { return false }
                        } else if chip.value.lowercased().contains("today") {
                            if !Calendar.current.isDateInToday(item.modificationDate) { return false }
                        }
                    case "tag":
                        let has = item.tags.contains { $0.name.caseInsensitiveCompare(chip.value) == .orderedSame }
                        if !has { return false }
                    default:
                        break
                    }
                }
                return true
            }

            var nameResults: [SpotlightResultItem] = []
            var contentResults: [SpotlightResultItem] = []

            let cleanQuery: String
            if lowerQuery.hasPrefix(">") || lowerQuery.hasPrefix("#") || lowerQuery.hasPrefix("/") {
                cleanQuery = String(lowerQuery.dropFirst()).trimmingCharacters(in: .whitespaces)
            } else {
                cleanQuery = lowerQuery
            }

            for item in filteredPool {
                let chain = Self.formatParentChain(for: item.url)
                if cleanQuery.isEmpty || item.lowercasedName.contains(cleanQuery) || item.kindDescription.lowercased().contains(cleanQuery) {
                    nameResults.append(
                        SpotlightResultItem(
                            item: item,
                            isContentMatch: false,
                            snippet: nil,
                            parentChain: chain
                        )
                    )
                } else if !item.isFolderLike, !item.isPackage, item.size > 0, item.size < 512_000 {
                    // Lightweight text content check for small text/md/json/swift/txt files
                    let textExts: Set<String> = ["txt", "md", "json", "swift", "py", "js", "ts", "html", "css", "csv", "log", "xml", "yml", "yaml", "sh"]
                    if textExts.contains(item.ext),
                       let text = try? String(contentsOf: item.url, encoding: .utf8),
                       let range = text.range(of: cleanQuery, options: .caseInsensitive) {
                        let start = text.index(range.lowerBound, offsetBy: -24, limitedBy: text.startIndex) ?? text.startIndex
                        let end = text.index(range.upperBound, offsetBy: 36, limitedBy: text.endIndex) ?? text.endIndex
                        let excerpt = text[start..<end].replacingOccurrences(of: "\n", with: " ")
                        contentResults.append(
                            SpotlightResultItem(
                                item: item,
                                isContentMatch: true,
                                snippet: "“…\(excerpt)…”",
                                parentChain: chain
                            )
                        )
                    }
                }
            }

            // Sort name matches so exact/prefix matches come first
            nameResults.sort { a, b in
                if !cleanQuery.isEmpty {
                    let aPrefix = a.item.lowercasedName.hasPrefix(cleanQuery)
                    let bPrefix = b.item.lowercasedName.hasPrefix(cleanQuery)
                    if aPrefix != bPrefix { return aPrefix }
                }
                return a.item.modificationDate > b.item.modificationDate
            }

            let finalNames = Array(nameResults.prefix(35))
            let finalContent = Array(contentResults.prefix(15))

            Task { @MainActor in
                completion(finalNames, finalContent)
            }
        }
    }

    private static func formatParentChain(for url: URL) -> String {
        let parent = url.deletingLastPathComponent()
        let grand = parent.deletingLastPathComponent()
        let pName = parent.lastPathComponent
        let gName = grand.lastPathComponent
        if !gName.isEmpty && gName != "/" && gName != pName {
            return "\(gName) › \(pName)"
        }
        return pName.isEmpty ? "Macintosh HD" : pName
    }
}
