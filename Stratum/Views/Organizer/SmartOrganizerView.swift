import SwiftUI
import AppKit
import CryptoKit

struct SmartOrganizerView: View {
    @Bindable var appState: AppState
    var appearance: AppearanceManager
    var scanCoordinator = ScanCoordinator.shared
    var transferEngine = TransferQueueEngine.shared

    enum StudioMode: String, CaseIterable, Identifiable {
        case organizer = "1-Click Folder Organizer"
        case duplicates = "Duplicate File Finder"
        case shelf = "Drop Shelf & Batch Stash"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .organizer: return "wand.and.stars"
            case .duplicates: return "doc.on.doc.fill"
            case .shelf: return "tray.and.arrow.down.fill"
            }
        }
    }

    struct OrganizerBucket: Identifiable {
        let id: String
        let title: String
        let folderName: String
        let icon: String
        let tintHex: String
        let items: [FileItem]
        let isCleanupCandidate: Bool

        var totalBytes: Int64 {
            items.reduce(Int64(0)) { $0 + $1.size }
        }
    }

    struct ExistingOrganizedFolder: Identifiable {
        var id: String { folderURL.path }
        let folderName: String
        let folderURL: URL
        let icon: String
        let tintHex: String
        let items: [FileItem]

        var totalBytes: Int64 {
            items.reduce(Int64(0)) { $0 + $1.size }
        }
    }

    struct VerifiedDuplicateCluster: Identifiable {
        let id: String
        let hashHex: String
        let fileName: String
        let sizeBytes: Int64
        let items: [FileItem]

        var reclaimableBytes: Int64 {
            sizeBytes * Int64(max(0, items.count - 1))
        }
    }

    struct OrganizeMoveRecord {
        let fromURL: URL
        let toURL: URL
    }

    static let organizedPathsDefaultsKey = "stratum.organizedCategoryFolderPaths"

    static func trackedOrganizedFolderPaths() -> Set<String> {
        if let saved = UserDefaults.standard.stringArray(forKey: organizedPathsDefaultsKey) {
            return Set(saved)
        }
        // Seed with "Documents & PDFs" in ~/Downloads if it was already clicked & created by the user
        let defaultDocsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads/Documents & PDFs").path
        var initial = Set<String>()
        if FileManager.default.fileExists(atPath: defaultDocsPath) {
            initial.insert(defaultDocsPath)
        }
        UserDefaults.standard.set(Array(initial), forKey: organizedPathsDefaultsKey)
        return initial
    }

    static func recordOrganizedFolderPath(_ path: String) {
        var current = trackedOrganizedFolderPaths()
        current.insert(path)
        UserDefaults.standard.set(Array(current), forKey: organizedPathsDefaultsKey)
    }

    static func removeOrganizedFolderPath(_ path: String) {
        var current = trackedOrganizedFolderPaths()
        current.remove(path)
        UserDefaults.standard.set(Array(current), forKey: organizedPathsDefaultsKey)
    }

    static let categoryDefinitions: [(id: String, title: String, folderName: String, icon: String, tintHex: String, isCleanup: Bool)] = [
        ("installers", "Installers & Disk Images (.dmg / .pkg)", "Installers", "opticaldiscdrive.fill", "#FF6B6B", true),
        ("archives", "Archives & ZIPs (.zip / .tar.gz)", "Archives", "doc.zipper", "#FFC46B", true),
        ("screenshots", "Screenshots", "Screenshots", "camera.viewfinder", "#4AD6C8", false),
        ("docs", "Documents, PDFs & Sheets", "Documents & PDFs", "doc.richtext.fill", "#5AA9FF", false),
        ("images", "Photos & Design Assets", "Photos & Images", "photo.on.rectangle.angled", "#5FD38D", false),
        ("media", "Videos & Audio", "Videos & Media", "film.stack.fill", "#B784F7", false),
        ("code", "Code, Scripts & Configs", "Code & Scripts", "chevron.left.forwardslash.chevron.right", "#7C5CFF", false)
    ]

    @State var activeMode: StudioMode = .organizer
    @State var targetFolderURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    @State var looseFiles: [FileItem] = []
    @State var organizedFolders: [ExistingOrganizedFolder] = []
    @State var lastOrganizeMoves: [OrganizeMoveRecord] = []

    // Duplicate scanner state
    @State var isScanningDuplicates: Bool = false
    @State var duplicateClusters: [VerifiedDuplicateCluster] = []
    @State var selectedDuplicatePaths: Set<String> = []
    @State var isDropTargetedOnShelf: Bool = false

    @Namespace var studioNamespace

    var organizerBuckets: [OrganizerBucket] {
        let installers = looseFiles.filter { ["dmg", "pkg", "iso"].contains($0.ext) }
        let archives = looseFiles.filter { ["zip", "tar", "gz", "tgz", "7z", "rar", "xz"].contains($0.ext) }
        let screenshots = looseFiles.filter {
            $0.kindCategory == .image && ($0.lowercasedName.contains("screenshot") || $0.lowercasedName.contains("screen shot") || $0.lowercasedName.contains("cleanshot"))
        }
        let screenshotIDs = Set(screenshots.map(\.id))
        let images = looseFiles.filter { $0.kindCategory == .image && !screenshotIDs.contains($0.id) }
        let docsAndPDFs = looseFiles.filter {
            $0.kindCategory == .pdf || $0.kindCategory == .document || $0.kindCategory == .spreadsheet || $0.kindCategory == .presentation
        }
        let media = looseFiles.filter { $0.kindCategory == .video || $0.kindCategory == .audio }
        let code = looseFiles.filter { $0.kindCategory == .code }

        let allBucketed: [OrganizerBucket] = [
            OrganizerBucket(
                id: "installers",
                title: "Installers & Disk Images (.dmg / .pkg)",
                folderName: "Installers",
                icon: "opticaldiscdrive.fill",
                tintHex: "#FF6B6B",
                items: installers,
                isCleanupCandidate: true
            ),
            OrganizerBucket(
                id: "archives",
                title: "Archives & ZIPs (.zip / .tar.gz)",
                folderName: "Archives",
                icon: "doc.zipper",
                tintHex: "#FFC46B",
                items: archives,
                isCleanupCandidate: true
            ),
            OrganizerBucket(
                id: "screenshots",
                title: "Screenshots",
                folderName: "Screenshots",
                icon: "camera.viewfinder",
                tintHex: "#4AD6C8",
                items: screenshots,
                isCleanupCandidate: false
            ),
            OrganizerBucket(
                id: "docs",
                title: "Documents, PDFs & Sheets",
                folderName: "Documents & PDFs",
                icon: "doc.richtext.fill",
                tintHex: "#5AA9FF",
                items: docsAndPDFs,
                isCleanupCandidate: false
            ),
            OrganizerBucket(
                id: "images",
                title: "Photos & Design Assets",
                folderName: "Photos & Images",
                icon: "photo.on.rectangle.angled",
                tintHex: "#5FD38D",
                items: images,
                isCleanupCandidate: false
            ),
            OrganizerBucket(
                id: "media",
                title: "Videos & Audio",
                folderName: "Videos & Media",
                icon: "film.stack.fill",
                tintHex: "#B784F7",
                items: media,
                isCleanupCandidate: false
            ),
            OrganizerBucket(
                id: "code",
                title: "Code, Scripts & Configs",
                folderName: "Code & Scripts",
                icon: "chevron.left.forwardslash.chevron.right",
                tintHex: "#7C5CFF",
                items: code,
                isCleanupCandidate: false
            )
        ]

        return allBucketed.filter { !$0.items.isEmpty }
    }

    var totalOrganizableFiles: Int {
        organizerBuckets.reduce(0) { $0 + $1.items.count }
    }

    var totalOrganizableBytes: Int64 {
        organizerBuckets.reduce(Int64(0)) { $0 + $1.totalBytes }
    }

    var selectedDuplicatesBytes: Int64 {
        var total: Int64 = 0
        for cluster in duplicateClusters {
            for item in cluster.items where selectedDuplicatePaths.contains(item.id) {
                total += item.size
            }
        }
        return total
    }

    var body: some View {
        VStack(spacing: 0) {
            topModeHeaderBar

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch activeMode {
                    case .organizer:
                        folderOrganizerSection
                            .transition(.opacity.combined(with: .offset(y: 8)))
                    case .duplicates:
                        duplicateFinderSection
                            .transition(.opacity.combined(with: .offset(y: 8)))
                    case .shelf:
                        dropShelfStudioSection
                            .transition(.opacity.combined(with: .offset(y: 8)))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.84), value: activeMode)
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(appearance.contentBackgroundOpacity))
        .onAppear {
            if let customTarget = appState.organizerTargetURL {
                targetFolderURL = customTarget
                appState.organizerTargetURL = nil
            }
            reloadTargetFolder()
            if duplicateClusters.isEmpty {
                scanForExactDuplicates()
            }
        }
    }

    // MARK: - Top Header & Mode Switcher

    var topModeHeaderBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title beside the folder pills when both fit, above them when they don't.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 14) {
                    headerTitles
                        .frame(minWidth: 0, idealWidth: 340, maxWidth: .infinity, alignment: .leading)
                    scopePills.fixedSize()
                }
                VStack(alignment: .leading, spacing: 10) {
                    headerTitles
                    ScrollView(.horizontal, showsIndicators: false) { scopePills.fixedSize() }
                }
            }

            // Mode tabs: the "view in Browser" button shrinks to an icon first, then the tabs scroll.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    modeTabs.fixedSize()
                    Spacer(minLength: 8)
                    viewInBrowserButton(showsTitle: true).fixedSize()
                }
                HStack(spacing: 8) {
                    modeTabs.fixedSize()
                    Spacer(minLength: 8)
                    viewInBrowserButton(showsTitle: false)
                }
                HStack(spacing: 8) {
                    ScrollView(.horizontal, showsIndicators: false) { modeTabs.fixedSize() }
                    viewInBrowserButton(showsTitle: false)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color.black.opacity(0.16))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(height: 1)
        }
    }

    private var headerTitles: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Smart Clean & Organizer Studio")
                .font(.system(size: 22, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text("Target folder: \(targetFolderURL.path) · Click any category below to create its folder & move files, find SHA-256 duplicates, or use the Drop Shelf.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Scope Selector Pills
    private var scopePills: some View {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return HStack(spacing: 6) {
            folderScopePill("Downloads", url: home.appendingPathComponent("Downloads"))
            folderScopePill("Desktop", url: home.appendingPathComponent("Desktop"))
            folderScopePill("Documents", url: home.appendingPathComponent("Documents"))

            Button {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                panel.prompt = "Choose Folder"
                if panel.runModal() == .OK, let url = panel.url {
                    targetFolderURL = url
                    reloadTargetFolder()
                    if activeMode == .duplicates {
                        scanForExactDuplicates()
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Choose Folder…")
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(StratumInteractiveButtonStyle())
        }
    }

    /// 3-Mode Segmented Pill Switcher
    private var modeTabs: some View {
        HStack(spacing: 8) {
            ForEach(StudioMode.allCases) { mode in
                let isSelected = (activeMode == mode)
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        activeMode = mode
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(isSelected ? .white : appearance.accentColor)
                        Text(mode.rawValue)
                            .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? .white : .primary)
                            .lineLimit(1)

                        if mode == .shelf && !appState.shelfURLs.isEmpty {
                            Text("\(appState.shelfURLs.count)")
                                .font(.system(size: 10.5, weight: .bold).monospacedDigit())
                                .foregroundStyle(isSelected ? appearance.accentColor : .white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(isSelected ? .white : appearance.accentColor))
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(appearance.accentColor)
                                .shadow(color: appearance.accentColor.opacity(0.4), radius: 8, y: 2)
                                .matchedGeometryEffect(id: "StudioTabPill", in: studioNamespace)
                        } else {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                                )
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(StratumInteractiveButtonStyle())
            }
        }
    }

    private func viewInBrowserButton(showsTitle: Bool) -> some View {
        let title = "View \(targetFolderURL.lastPathComponent) in Browser"
        return Button {
            appState.navigate(to: targetFolderURL)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11.5, weight: .semibold))
                if showsTitle {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(appearance.accentColor)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(appearance.selectionFillColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(appearance.selectionBorderColor, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(StratumInteractiveButtonStyle())
        .stratumHelp(title)
    }

    func folderScopePill(_ title: String, url: URL) -> some View {
        let isActive = (targetFolderURL.standardizedFileURL == url.standardizedFileURL)
        return Button {
            targetFolderURL = url
            reloadTargetFolder()
            if activeMode == .duplicates {
                scanForExactDuplicates()
            }
        } label: {
            Text(title)
                .font(.system(size: 12, weight: isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? .primary : .secondary)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isActive ? appearance.selectionFillColor : Color.primary.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(isActive ? appearance.selectionBorderColor : Color.primary.opacity(0.08), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(StratumInteractiveButtonStyle())
    }

}
