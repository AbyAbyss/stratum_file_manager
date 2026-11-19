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

    private static let organizedPathsDefaultsKey = "stratum.organizedCategoryFolderPaths"

    private static func trackedOrganizedFolderPaths() -> Set<String> {
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

    private static func recordOrganizedFolderPath(_ path: String) {
        var current = trackedOrganizedFolderPaths()
        current.insert(path)
        UserDefaults.standard.set(Array(current), forKey: organizedPathsDefaultsKey)
    }

    private static func removeOrganizedFolderPath(_ path: String) {
        var current = trackedOrganizedFolderPaths()
        current.remove(path)
        UserDefaults.standard.set(Array(current), forKey: organizedPathsDefaultsKey)
    }

    private static let categoryDefinitions: [(id: String, title: String, folderName: String, icon: String, tintHex: String, isCleanup: Bool)] = [
        ("installers", "Installers & Disk Images (.dmg / .pkg)", "Installers", "opticaldiscdrive.fill", "#FF6B6B", true),
        ("archives", "Archives & ZIPs (.zip / .tar.gz)", "Archives", "doc.zipper", "#FFC46B", true),
        ("screenshots", "Screenshots", "Screenshots", "camera.viewfinder", "#4AD6C8", false),
        ("docs", "Documents, PDFs & Sheets", "Documents & PDFs", "doc.richtext.fill", "#5AA9FF", false),
        ("images", "Photos & Design Assets", "Photos & Images", "photo.on.rectangle.angled", "#5FD38D", false),
        ("media", "Videos & Audio", "Videos & Media", "film.stack.fill", "#B784F7", false),
        ("code", "Code, Scripts & Configs", "Code & Scripts", "chevron.left.forwardslash.chevron.right", "#7C5CFF", false)
    ]

    @State private var activeMode: StudioMode = .organizer
    @State private var targetFolderURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    @State private var looseFiles: [FileItem] = []
    @State private var organizedFolders: [ExistingOrganizedFolder] = []
    @State private var lastOrganizeMoves: [OrganizeMoveRecord] = []

    // Duplicate scanner state
    @State private var isScanningDuplicates: Bool = false
    @State private var duplicateClusters: [VerifiedDuplicateCluster] = []
    @State private var selectedDuplicatePaths: Set<String> = []
    @State private var isDropTargetedOnShelf: Bool = false

    @Namespace private var studioNamespace

    private var organizerBuckets: [OrganizerBucket] {
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

    private var totalOrganizableFiles: Int {
        organizerBuckets.reduce(0) { $0 + $1.items.count }
    }

    private var totalOrganizableBytes: Int64 {
        organizerBuckets.reduce(Int64(0)) { $0 + $1.totalBytes }
    }

    private var selectedDuplicatesBytes: Int64 {
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

    private var topModeHeaderBar: some View {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Smart Clean & Organizer Studio")
                        .font(.system(size: 22, weight: .bold))
                    Text("Target folder: \(targetFolderURL.path) · Click any category below to create its folder & move files, find SHA-256 duplicates, or use the Drop Shelf.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Scope Selector Pills
                HStack(spacing: 6) {
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

            // 3-Mode Segmented Pill Switcher
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

                Spacer()

                Button {
                    appState.navigate(to: targetFolderURL)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 11.5, weight: .semibold))
                        Text("View \(targetFolderURL.lastPathComponent) in Browser")
                            .font(.system(size: 12, weight: .semibold))
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

    private func folderScopePill(_ title: String, url: URL) -> some View {
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

    // MARK: - Mode 1: 1-Click Folder Declutter & Auto-Organizer

    private var folderOrganizerSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            // 1. Summary Action Banner
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(appearance.accentColor.opacity(0.18))
                        .frame(width: 48, height: 48)
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(appearance.accentColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("\(targetFolderURL.lastPathComponent) has \(totalOrganizableFiles) loose \(totalOrganizableFiles == 1 ? "file" : "files") (\(BulkDirectoryReader.fastFormatBytes(totalOrganizableBytes)))")
                        .font(.system(size: 16, weight: .bold))
                        .contentTransition(.numericText())
                    Text("Nothing is moved automatically — click any category below (or Organize All) to create its folder inside \(targetFolderURL.path).")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !lastOrganizeMoves.isEmpty {
                    Button {
                        undoLastOrganize()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 11.5, weight: .semibold))
                            Text("Undo Last Move (\(lastOrganizeMoves.count))")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.primary.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(StratumInteractiveButtonStyle())
                }

                Button {
                    organizeBuckets(organizerBuckets)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12.5, weight: .bold))
                        Text("Organize All Categories (\(totalOrganizableFiles))")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(totalOrganizableFiles == 0 ? Color.secondary.opacity(0.35) : appearance.accentColor)
                            .shadow(color: totalOrganizableFiles == 0 ? .clear : appearance.accentColor.opacity(0.45), radius: 8, y: 2)
                    )
                }
                .buttonStyle(StratumInteractiveButtonStyle())
                .disabled(totalOrganizableFiles == 0)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(appearance.selectionBorderColor.opacity(0.7), lineWidth: 1)
                    )
            )

            // 2. Category Folders Created by Stratum inside Target Folder
            if !organizedFolders.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color(nsColor: NSColor(hex: "#5FD38D") ?? .systemGreen))
                        Text("Created Category Folders in \(targetFolderURL.lastPathComponent)")
                            .font(.system(size: 14, weight: .bold))
                        Text("· Folders you clicked to create · Open in Browser or Unpack back to \(targetFolderURL.lastPathComponent)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 14),
                            GridItem(.flexible(), spacing: 14)
                        ],
                        spacing: 14
                    ) {
                        ForEach(organizedFolders) { org in
                            let tint = Color(nsColor: NSColor(hex: org.tintHex) ?? .systemGreen)
                            let badgeTint: Color = .stratumLabel(tint)
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 10) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .fill(tint.opacity(0.22))
                                            .frame(width: 36, height: 36)
                                        Image(systemName: "folder.fill")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(tint)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text("\(org.folderName)/")
                                                .font(.system(size: 14, weight: .bold))
                                            Text("CREATED BY YOU")
                                                .font(.system(size: 9.5, weight: .bold))
                                                .foregroundStyle(badgeTint)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 1.5)
                                                .background(Capsule().fill(tint.opacity(0.16)))
                                        }
                                        Text("\(org.items.count) \(org.items.count == 1 ? "file" : "files") inside · \(BulkDirectoryReader.fastFormatBytes(org.totalBytes)) · \(org.folderURL.path)")
                                            .font(.system(size: 11.5).monospacedDigit())
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }

                                    Spacer()
                                }

                                // Sample files inside the organized folder
                                VStack(spacing: 4) {
                                    ForEach(org.items.prefix(3)) { file in
                                        HStack(spacing: 8) {
                                            Image(nsImage: IconPipeline.shared.icon(for: file))
                                                .resizable()
                                                .frame(width: 15, height: 15)
                                            Text(file.name)
                                                .font(.system(size: 11.5))
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                            Spacer()
                                            Text(file.formattedSize)
                                                .font(.system(size: 11).monospacedDigit())
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3.5)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .fill(Color.primary.opacity(0.035))
                                        )
                                    }
                                    if org.items.count > 3 {
                                        Text("+ \(org.items.count - 3) more files inside \(org.folderName)/…")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                            .padding(.leading, 8)
                                    }
                                }

                                HStack(spacing: 8) {
                                    Button {
                                        appState.navigate(to: org.folderURL)
                                    } label: {
                                        HStack(spacing: 5) {
                                            Image(systemName: "folder.fill")
                                                .font(.system(size: 11, weight: .semibold))
                                            Text("Open \"\(org.folderName)\" in Browser")
                                                .font(.system(size: 11.5, weight: .semibold))
                                        }
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 30)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .fill(appearance.accentColor)
                                        )
                                    }
                                    .buttonStyle(StratumInteractiveButtonStyle())

                                    Button {
                                        appState.navigate(to: targetFolderURL)
                                        appState.selectedItemIDs = [org.folderURL.path]
                                    } label: {
                                        Text("Highlight in \(targetFolderURL.lastPathComponent)")
                                            .font(.system(size: 11.5, weight: .medium))
                                            .padding(.horizontal, 10)
                                            .frame(height: 30)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                    .fill(Color.primary.opacity(0.07))
                                            )
                                    }
                                    .buttonStyle(StratumInteractiveButtonStyle())

                                    Button {
                                        unpackOrganizedFolder(org)
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "arrow.uturn.backward")
                                                .font(.system(size: 10.5, weight: .bold))
                                            Text("Unpack")
                                                .font(.system(size: 11.5, weight: .medium))
                                        }
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 10)
                                        .frame(height: 30)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .fill(Color.primary.opacity(0.06))
                                        )
                                    }
                                    .buttonStyle(StratumInteractiveButtonStyle())
                                    .help("Move all files back out to \(targetFolderURL.lastPathComponent) and remove \(org.folderName)/")
                                }
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(appearance.faintTintColor)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(appearance.selectionBorderColor, lineWidth: 1)
                                    )
                            )
                        }
                    }
                }
            }

            // 3. Loose Unorganized Files Waiting to be Clicked & Organized
            if !organizerBuckets.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Loose Files in \(targetFolderURL.lastPathComponent) — Click a Category to Create Folder & Move")
                        .font(.system(size: 14, weight: .bold))

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 14),
                            GridItem(.flexible(), spacing: 14)
                        ],
                        spacing: 14
                    ) {
                        ForEach(organizerBuckets) { bucket in
                            let bucketColor = Color(nsColor: NSColor(hex: bucket.tintHex) ?? .systemBlue)
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 10) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .fill(bucketColor.opacity(0.20))
                                            .frame(width: 34, height: 34)
                                        Image(systemName: bucket.icon)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(bucketColor)
                                    }

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(bucket.title)
                                            .font(.system(size: 13.5, weight: .semibold))
                                        Text("\(bucket.items.count) \(bucket.items.count == 1 ? "file" : "files") · \(BulkDirectoryReader.fastFormatBytes(bucket.totalBytes))")
                                            .font(.system(size: 11.5).monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()
                                }

                                VStack(spacing: 4) {
                                    ForEach(bucket.items.prefix(4)) { file in
                                        HStack(spacing: 8) {
                                            Image(nsImage: IconPipeline.shared.icon(for: file))
                                                .resizable()
                                                .frame(width: 16, height: 16)
                                            Text(file.name)
                                                .font(.system(size: 12))
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                            Spacer()
                                            Text(file.formattedSize)
                                                .font(.system(size: 11).monospacedDigit())
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .fill(Color.primary.opacity(0.035))
                                        )
                                    }
                                    if bucket.items.count > 4 {
                                        Text("+ \(bucket.items.count - 4) more files…")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.tertiary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.leading, 8)
                                    }
                                }

                                Spacer(minLength: 0)

                                HStack(spacing: 8) {
                                    Button {
                                        organizeBuckets([bucket])
                                    } label: {
                                        HStack(spacing: 5) {
                                            Image(systemName: "folder.badge.plus")
                                                .font(.system(size: 11, weight: .semibold))
                                            Text("Create & Move to \"\(bucket.folderName)/\"")
                                                .font(.system(size: 11.5, weight: .semibold))
                                        }
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 30)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .fill(appearance.accentColor)
                                        )
                                    }
                                    .buttonStyle(StratumInteractiveButtonStyle())

                                    if bucket.isCleanupCandidate {
                                        Button {
                                            let targets = bucket.items.map { (url: $0.url, size: $0.size) }
                                            appState.moveURLsToTrash(targets)
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                                reloadTargetFolder()
                                            }
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: "trash")
                                                    .font(.system(size: 11, weight: .semibold))
                                                Text("Trash All")
                                                    .font(.system(size: 11.5, weight: .semibold))
                                            }
                                            .foregroundStyle(Color(nsColor: NSColor(hex: "#FF6B6B") ?? .systemRed))
                                            .padding(.horizontal, 12)
                                            .frame(height: 30)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                    .fill(Color(nsColor: NSColor(hex: "#FF6B6B") ?? .systemRed).opacity(0.14))
                                            )
                                        }
                                        .buttonStyle(StratumInteractiveButtonStyle())
                                    }
                                }
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.primary.opacity(0.04))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                                    )
                            )
                            .stratumScrollMotion()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Mode 2: Exact Duplicate File Finder (SHA-256 Verified)

    private var duplicateFinderSection: some View {
        let totalReclaimable = duplicateClusters.reduce(Int64(0)) { $0 + $1.reclaimableBytes }

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SHA-256 Verified Duplicate Files")
                        .font(.system(size: 16, weight: .bold))
                    Text("Found \(duplicateClusters.count) identical file sets (\(BulkDirectoryReader.fastFormatBytes(totalReclaimable)) reclaimable) across your workspace.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    autoSelectRedundantDuplicates()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.badge.questionmark")
                            .font(.system(size: 11.5, weight: .semibold))
                        Text("Auto-Select Redundant Copies (Keep Original)")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 32)
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
                .disabled(duplicateClusters.isEmpty)

                if !selectedDuplicatePaths.isEmpty {
                    Button {
                        trashSelectedDuplicates()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 11.5))
                            Text("Trash \(selectedDuplicatePaths.count) Selected (\(BulkDirectoryReader.fastFormatBytes(selectedDuplicatesBytes)))")
                                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(appearance.accentColor)
                        )
                    }
                    .buttonStyle(StratumInteractiveButtonStyle())
                }

                Button {
                    scanForExactDuplicates()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                        )
                }
                .buttonStyle(StratumInteractiveButtonStyle())
                .help("Rescan for duplicate files")
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            )

            if isScanningDuplicates {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Verifying exact file hashes with SHA-256…")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
            } else if duplicateClusters.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(appearance.accentColor)
                    Text("No duplicate files found!")
                        .font(.system(size: 15, weight: .semibold))
                    Text("All scanned files in \(targetFolderURL.lastPathComponent), Desktop, and Documents are unique.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 44)
            } else {
                VStack(spacing: 10) {
                    ForEach(duplicateClusters) { cluster in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(cluster.fileName)
                                    .font(.system(size: 13.5, weight: .semibold))
                                Text("· \(cluster.items.count) identical copies · \(BulkDirectoryReader.fastFormatBytes(cluster.sizeBytes)) each")
                                    .font(.system(size: 12).monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("SHA-256: \(cluster.hashHex.prefix(12))…")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }

                            ForEach(Array(cluster.items.enumerated()), id: \.element.id) { idx, file in
                                let isChecked = selectedDuplicatePaths.contains(file.id)
                                Button {
                                    if isChecked {
                                        selectedDuplicatePaths.remove(file.id)
                                    } else {
                                        selectedDuplicatePaths.insert(file.id)
                                    }
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                                            .font(.system(size: 14))
                                            .foregroundStyle(isChecked ? appearance.accentColor : .secondary)

                                        Image(nsImage: IconPipeline.shared.icon(for: file))
                                            .resizable()
                                            .frame(width: 18, height: 18)

                                        Text(file.id)
                                            .font(.system(size: 12, design: .monospaced))
                                            .lineLimit(1)
                                            .truncationMode(.middle)

                                        if idx == 0 {
                                            Text("KEEP ORIGINAL")
                                                .font(.system(size: 9.5, weight: .bold))
                                                .foregroundStyle(appearance.accentColor)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Capsule().fill(appearance.selectionFillColor))
                                        }

                                        Spacer()

                                        Text(file.formattedModDate)
                                            .font(.system(size: 11.5).monospacedDigit())
                                            .foregroundStyle(.secondary)

                                        Button("Reveal") {
                                            appState.navigate(to: file.url.deletingLastPathComponent())
                                            appState.selectedItemIDs = [file.id]
                                        }
                                        .buttonStyle(.plain)
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .foregroundStyle(appearance.accentColor)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(isChecked ? appearance.faintTintColor : Color.primary.opacity(0.03))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                    .strokeBorder(isChecked ? appearance.selectionBorderColor : Color.clear, lineWidth: 1)
                                            )
                                    )
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                                )
                        )
                        .stratumScrollMotion()
                    }
                }
            }
        }
    }

    // MARK: - Mode 3: Drop Shelf & Batch Stash

    private var dropShelfStudioSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Drop Shelf (\(appState.shelfURLs.count) items parked)")
                        .font(.system(size: 16, weight: .bold))
                    Text("Park files from any folder (Right-Click → Park on Drop Shelf, or drag files below) and move, copy, or zip them all at once.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !appState.shelfURLs.isEmpty {
                    Button {
                        appState.dropAllShelfItems(into: appState.currentURL)
                    } label: {
                        Label("Copy All to \(appState.currentFolderTitle)", systemImage: "arrow.down.doc.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(appearance.accentColor))
                    }
                    .buttonStyle(StratumInteractiveButtonStyle())

                    Button("Clear Shelf") {
                        appState.shelfURLs.removeAll()
                    }
                    .buttonStyle(StratumInteractiveButtonStyle())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                }
            }

            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isDropTargetedOnShelf ? appearance.faintTintColor : Color.primary.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                isDropTargetedOnShelf ? appearance.accentColor : Color.primary.opacity(0.14),
                                style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                            )
                    )

                if appState.shelfURLs.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(.secondary)
                        Text("Drag and drop files here from Finder or Browser to park them on the Shelf")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 54)
                } else {
                    VStack(spacing: 6) {
                        ForEach(appState.shelfURLs, id: \.path) { url in
                            HStack(spacing: 10) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                    .resizable()
                                    .frame(width: 22, height: 22)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(url.lastPathComponent)
                                        .font(.system(size: 13, weight: .medium))
                                    Text(url.deletingLastPathComponent().path)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Reveal") {
                                    appState.navigate(to: url.deletingLastPathComponent())
                                    appState.selectedItemIDs = [url.path]
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(appearance.accentColor)

                                Button {
                                    appState.removeFromShelf(url)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.04)))
                        }
                    }
                    .padding(14)
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isDropTargetedOnShelf) { providers in
                for provider in providers {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        guard let url else { return }
                        Task { @MainActor in
                            appState.addToShelf([url])
                        }
                    }
                }
                return true
            }
        }
    }

    // MARK: - Logic Helpers

    private func reloadTargetFolder() {
        let url = targetFolderURL
        let trackedPaths = Self.trackedOrganizedFolderPaths()
        DispatchQueue.global(qos: .userInitiated).async {
            let items = BulkDirectoryReader.shared.readDirectorySync(at: url, showHidden: false)
            let filesOnly = items.filter { !$0.isFolderLike && !$0.isPackage }

            // Only show category folders that the user explicitly clicked to create in Stratum
            var existing: [ExistingOrganizedFolder] = []
            for def in Self.categoryDefinitions {
                let subURL = url.appendingPathComponent(def.folderName, isDirectory: true)
                guard trackedPaths.contains(subURL.path) else { continue }
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: subURL.path, isDirectory: &isDir), isDir.boolValue {
                    let subItems = BulkDirectoryReader.shared.readDirectorySync(at: subURL, showHidden: false)
                        .filter { !$0.isFolderLike }
                    if !subItems.isEmpty {
                        existing.append(
                            ExistingOrganizedFolder(
                                folderName: def.folderName,
                                folderURL: subURL,
                                icon: def.icon,
                                tintHex: def.tintHex,
                                items: subItems
                            )
                        )
                    }
                }
            }

            Task { @MainActor in
                withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                    self.looseFiles = filesOnly
                    self.organizedFolders = existing
                }
            }
        }
    }

    private func organizeBuckets(_ buckets: [OrganizerBucket]) {
        let baseDir = targetFolderURL
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            var moveRecords: [OrganizeMoveRecord] = []
            var createdFolderPaths: [String] = []

            for bucket in buckets where !bucket.items.isEmpty {
                let categoryDir = baseDir.appendingPathComponent(bucket.folderName, isDirectory: true)
                try? fm.createDirectory(at: categoryDir, withIntermediateDirectories: true)
                createdFolderPaths.append(categoryDir.path)

                for file in bucket.items {
                    var destURL = categoryDir.appendingPathComponent(file.name)
                    var counter = 2
                    while fm.fileExists(atPath: destURL.path) {
                        let base = (file.name as NSString).deletingPathExtension
                        let ext = (file.name as NSString).pathExtension
                        let newName = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
                        destURL = categoryDir.appendingPathComponent(newName)
                        counter += 1
                    }
                    if (try? fm.moveItem(at: file.url, to: destURL)) != nil {
                        moveRecords.append(OrganizeMoveRecord(fromURL: file.url, toURL: destURL))
                    }
                }
            }

            Task { @MainActor in
                for path in createdFolderPaths {
                    Self.recordOrganizedFolderPath(path)
                }
                self.lastOrganizeMoves = moveRecords
                self.reloadTargetFolder()
                self.appState.reloadCurrentDirectory(preserveSelection: false)
                ScanCoordinator.shared.notifyFileSystemMutation(near: baseDir)
                self.appState.showToast("Moved \(moveRecords.count) \(moveRecords.count == 1 ? "file" : "files") into \(buckets.map(\.folderName).joined(separator: ", "))/")
            }
        }
    }

    private func unpackOrganizedFolder(_ org: ExistingOrganizedFolder) {
        let baseDir = targetFolderURL
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            var unpackedCount = 0
            for file in org.items {
                var destURL = baseDir.appendingPathComponent(file.name)
                var counter = 2
                while fm.fileExists(atPath: destURL.path) {
                    let base = (file.name as NSString).deletingPathExtension
                    let ext = (file.name as NSString).pathExtension
                    let newName = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
                    destURL = baseDir.appendingPathComponent(newName)
                    counter += 1
                }
                if (try? fm.moveItem(at: file.url, to: destURL)) != nil {
                    unpackedCount += 1
                }
            }
            // If folder is now empty, remove the empty category folder
            let remaining = (try? fm.contentsOfDirectory(atPath: org.folderURL.path)) ?? []
            if remaining.isEmpty {
                try? fm.removeItem(at: org.folderURL)
            }

            Task { @MainActor in
                Self.removeOrganizedFolderPath(org.folderURL.path)
                self.reloadTargetFolder()
                self.appState.reloadCurrentDirectory(preserveSelection: false)
                ScanCoordinator.shared.notifyFileSystemMutation(near: baseDir)
                self.appState.showToast("Unpacked \(unpackedCount) \(unpackedCount == 1 ? "file" : "files") from \(org.folderName)/ back into \(baseDir.lastPathComponent)")
            }
        }
    }

    private func undoLastOrganize() {
        let moves = lastOrganizeMoves
        guard !moves.isEmpty else { return }
        lastOrganizeMoves = []
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            var restored = 0
            var touchedFolders = Set<URL>()
            for record in moves.reversed() {
                touchedFolders.insert(record.toURL.deletingLastPathComponent())
                if (try? fm.moveItem(at: record.toURL, to: record.fromURL)) != nil {
                    restored += 1
                }
            }
            var removedPaths: [String] = []
            for dirURL in touchedFolders {
                let remaining = (try? fm.contentsOfDirectory(atPath: dirURL.path)) ?? []
                if remaining.isEmpty {
                    try? fm.removeItem(at: dirURL)
                    removedPaths.append(dirURL.path)
                }
            }
            Task { @MainActor in
                for path in removedPaths {
                    Self.removeOrganizedFolderPath(path)
                }
                self.reloadTargetFolder()
                self.appState.reloadCurrentDirectory(preserveSelection: false)
                self.appState.showToast("Restored \(restored) \(restored == 1 ? "file" : "files") to \(self.targetFolderURL.lastPathComponent)")
            }
        }
    }

    private func scanForExactDuplicates() {
        isScanningDuplicates = true
        let rootURL = targetFolderURL
        DispatchQueue.global(qos: .userInitiated).async {
            let pool = AppState.collectCrossMacCandidatePool(including: rootURL)
                .filter { !$0.isFolderLike && !$0.isPackage && !$0.isDataless && $0.size >= 4096 && $0.size <= 250 * 1024 * 1024 }

            var bySize: [Int64: [FileItem]] = [:]
            for item in pool {
                bySize[item.size, default: []].append(item)
            }

            var byHash: [String: [FileItem]] = [:]
            for (_, sameSizeItems) in bySize where sameSizeItems.count > 1 {
                for file in sameSizeItems {
                    guard let data = try? Data(contentsOf: file.url, options: .mappedIfSafe) else { continue }
                    let digest = SHA256.hash(data: data)
                    let hex = digest.map { String(format: "%02x", $0) }.joined()
                    byHash[hex, default: []].append(file)
                }
            }

            var clusters: [VerifiedDuplicateCluster] = []
            for (hex, items) in byHash where items.count > 1 {
                let sorted = items.sorted { $0.modificationDate > $1.modificationDate }
                if let first = sorted.first {
                    clusters.append(
                        VerifiedDuplicateCluster(
                            id: hex,
                            hashHex: hex,
                            fileName: first.name,
                            sizeBytes: first.size,
                            items: sorted
                        )
                    )
                }
            }
            clusters.sort { $0.reclaimableBytes > $1.reclaimableBytes }

            Task { @MainActor in
                withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                    self.duplicateClusters = clusters
                    self.isScanningDuplicates = false
                }
            }
        }
    }

    private func autoSelectRedundantDuplicates() {
        var redundant = Set<String>()
        for cluster in duplicateClusters {
            for copy in cluster.items.dropFirst() {
                redundant.insert(copy.id)
            }
        }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.80)) {
            selectedDuplicatePaths = redundant
        }
    }

    private func trashSelectedDuplicates() {
        var targets: [(url: URL, size: Int64)] = []
        for cluster in duplicateClusters {
            for file in cluster.items where selectedDuplicatePaths.contains(file.id) {
                targets.append((url: file.url, size: file.size))
            }
        }
        guard !targets.isEmpty else { return }
        appState.moveURLsToTrash(targets)
        selectedDuplicatePaths.removeAll()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            scanForExactDuplicates()
        }
    }
}
