import SwiftUI
import AppKit

/// Storage map: a squarified treemap of the current folder, a linked list, a file-type view,
/// and a cleanup panel. Hover and selection are shared between map and list.
struct StorageMapView: View {
    @Bindable var appState: AppState
    var appearance: AppearanceManager
    var scanCoordinator = ScanCoordinator.shared

    enum Mode: String, CaseIterable, Identifiable {
        case folders = "Folders"
        case fileTypes = "File Types"
        var id: String { rawValue }
        var symbol: String { self == .folders ? "square.grid.2x2.fill" : "chart.bar.fill" }
    }

    private static let maxTiles = 14

    @State private var mode: Mode = .folders
    @State private var category: FileTypeCategory = .video
    @State private var selectedID: Int64?
    @State private var hoveredID: Int64?
    @State private var items: [StorageItem] = []
    @State private var currentTotal: Int64 = 0
    @State private var ringProgress: Double = 0
    @State private var zoomAnchor: UnitPoint = .center
    @State private var drillingIn = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var modeNamespace
    @FocusState private var focused: Bool

    // MARK: Derived data

    /// Rebuilt only when the folder changes, not on every hover/selection re-render:
    /// building items resolves paths and touches the filesystem.
    private func rebuildItems() {
        let built = scanCoordinator.treemapChildren
            .filter { $0.totalSize > 0 }
            .sorted { $0.totalSize > $1.totalSize }
            .enumerated()
            .map { rank, dir in
                let path = scanCoordinator.fullPath(for: dir.id)
                return StorageItem(
                    dir: dir,
                    path: path,
                    rank: rank,
                    isFile: Self.isFile(dir, path: path),
                    isProtected: ProtectedPaths.isProtected(path) && path != ProtectedPaths.resolve("~")
                )
            }
        let childSum = scanCoordinator.treemapChildren.reduce(Int64(0)) { $0 + $1.totalSize }
        items = built
        currentTotal = max(scanCoordinator.treemapBreadcrumb.last?.totalSize ?? 0, childSum)
    }

    private var hasData: Bool { !scanCoordinator.treemapChildren.isEmpty }

    private static func isFile(_ dir: DirRow, path: String) -> Bool {
        guard dir.id < 0 else { return false }
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && !isDir.boolValue
    }

    private var actions: StorageItemActions {
        StorageItemActions(
            open: open,
            reveal: { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: $0.path)]) },
            showInBrowser: { item in
                let url = URL(fileURLWithPath: item.path)
                appState.navigate(to: item.isFile ? url.deletingLastPathComponent() : url)
                withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) { appState.screen = .browser }
            },
            trash: { item in
                appState.moveURLsToTrash([(url: URL(fileURLWithPath: item.path), size: item.size)])
            }
        )
    }

    // MARK: Body

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                Divider().opacity(0.5)
                content
            }
            Divider().opacity(0.5)
            StorageCleanupPanel(appState: appState, appearance: appearance)
                .frame(width: 310)
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.escape) { goUp() }
        .onKeyPress(.upArrow) { goUp() }
        .onKeyPress(.return) {
            guard let id = selectedID, let item = items.first(where: { $0.id == id }) else { return .ignored }
            open(item)
            return .handled
        }
        .onAppear {
            focused = true
            animateRing()
            rebuildItems()
        }
        .onChange(of: scanCoordinator.treemapChildren) { _, _ in rebuildItems() }
        .onChange(of: scanCoordinator.currentTreemapDirId) { _, _ in
            selectedID = nil
            hoveredID = nil
        }
        .onChange(of: appState.bootVolume?.usedBytes) { _, _ in animateRing() }
    }

    @ViewBuilder
    private var content: some View {
        if scanCoordinator.showsScanState {
            ScanningStateView(coordinator: scanCoordinator, appearance: appearance, resultName: "storage map")
        } else if !hasData {
            EmptyScanCard(appearance: appearance) {
                scanCoordinator.startScan(at: FileManager.default.homeDirectoryForCurrentUser)
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch mode {
                    case .folders: foldersSection
                    case .fileTypes: fileTypesSection
                    }
                }
                .padding(22)
                .transition(.opacity)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: Header

    private var header: some View {
        let volume = appState.bootVolume
        let usedFraction = volume?.usedFraction ?? 0

        let gauge = ZStack {
            Circle().stroke(Color.primary.opacity(0.09), lineWidth: 7)
            Circle()
                .trim(from: 0, to: ringProgress)
                .stroke(appearance.accentColor, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((usedFraction * 100).rounded()))%")
                .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                .contentTransition(.numericText())
        }
        .frame(width: 58, height: 58)

        let titles = VStack(alignment: .leading, spacing: 3) {
            Text(volume?.name ?? "Storage")
                .font(.system(size: 20, weight: .bold, design: .rounded))
            Text(volume.map { "\(StorageFormat.bytes($0.usedBytes)) used · \(StorageFormat.bytes($0.freeBytes)) free of \(StorageFormat.bytes($0.totalBytes))" } ?? "Scanning volumes…")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
        .fixedSize()

        let controls = HStack(spacing: 10) {
            ScanRefreshControl(coordinator: scanCoordinator, appearance: appearance)
            scopeMenu
            modePicker
        }
        .fixedSize()

        // One row when there is room, two rows when there isn't, instead of squeezing labels.
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) {
                gauge
                titles
                Spacer(minLength: 12)
                controls
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 18) {
                    gauge
                    titles
                    Spacer(minLength: 0)
                }
                controls
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 34)
        .padding(.bottom, 16)
    }

    private func animateRing() {
        let target = max(0.02, min(1, appState.bootVolume?.usedFraction ?? 0))
        withAnimation(.spring(response: 0.9, dampingFraction: 0.82)) { ringProgress = target }
    }

    private var scopeMenu: some View {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let isHome = scanCoordinator.scannedRootPath == home.path
        return Menu {
            Button("Home Folder") { scanCoordinator.startScan(at: home) }
            Button("Entire Disk") { scanCoordinator.startScan(at: URL(fileURLWithPath: "/")) }
        } label: {
            Label(isHome ? "Home" : "Entire Disk", systemImage: isHome ? "house.fill" : "internaldrive.fill")
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 11)
                .frame(height: 30)
                .background(Capsule().fill(Color.primary.opacity(0.07)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Choose what to scan")
    }

    private var modePicker: some View {
        HStack(spacing: 2) {
            ForEach(Mode.allCases) { option in
                Button {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { mode = option }
                } label: {
                    Label(option.rawValue, systemImage: option.symbol)
                        .stratumSymbolPop(value: mode == option)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(mode == option ? Color.white : Color.secondary)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background {
                            if mode == option {
                                Capsule()
                                    .fill(appearance.accentColor)
                                    .matchedGeometryEffect(id: "mode-pill", in: modeNamespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.primary.opacity(0.07)))
    }

    // MARK: Folders

    private var foldersSection: some View {
        let shown = items
        let tiles = Array(shown.prefix(Self.maxTiles))
        return VStack(alignment: .leading, spacing: 16) {
            breadcrumb

            // Opening a folder zooms in from the tile you opened; going up zooms back out.
            ZStack {
                StorageTreemapView(
                    items: tiles,
                    totalBytes: currentTotal,
                    selectedID: $selectedID,
                    hoveredID: $hoveredID,
                    zoomAnchor: $zoomAnchor,
                    actions: actions
                )
                .id(scanCoordinator.currentTreemapDirId)
                .transition(zoomTransition)
            }
            .frame(height: 340)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .animation(.spring(response: 0.5, dampingFraction: 0.86), value: scanCoordinator.currentTreemapDirId)
            .padding(10)
            .storageCard(appearance)

            if shown.count > tiles.count {
                Text("Showing the \(tiles.count) largest of \(shown.count) items. The list below has everything.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }

            if let id = selectedID, let item = shown.first(where: { $0.id == id }) {
                FocusCard(item: item, total: currentTotal, appearance: appearance, actions: actions)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            VStack(spacing: 0) {
                ForEach(shown) { item in
                    FolderRow(
                        item: item,
                        maxSize: shown.first?.size ?? 1,
                        total: currentTotal,
                        isSelected: selectedID == item.id,
                        isHovered: hoveredID == item.id,
                        appearance: appearance
                    )
                    .onHover { inside in
                        hoveredID = inside ? item.id : (hoveredID == item.id ? nil : hoveredID)
                    }
                    .onTapGesture(count: 2) {
                        zoomAnchor = .center
                        open(item)
                    }
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selectedID = item.id }
                    }
                    .contextMenu { StorageItemMenu(item: item, actions: actions) }
                }
            }
            .padding(.vertical, 6)
            .storageCard(appearance)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: selectedID)
    }

    private var breadcrumb: some View {
        let crumbs = scanCoordinator.treemapBreadcrumb
        return HStack(spacing: 6) {
            Button { _ = goUp() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.primary.opacity(0.07)))
            }
            .buttonStyle(StratumInteractiveButtonStyle())
            .disabled(crumbs.count <= 1)
            .help("Up one level (Esc)")

            ForEach(Array(crumbs.enumerated()), id: \.element.id) { index, crumb in
                if index > 0 {
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
                }
                Button(index == 0 ? rootName : crumb.name) {
                    if index < crumbs.count - 1 {
                        drillingIn = false
                        scanCoordinator.drillIntoTreemapDir(crumb)
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: index == crumbs.count - 1 ? .bold : .medium))
                .foregroundStyle(index == crumbs.count - 1 ? Color.primary : Color.secondary)
            }

            Spacer()
            Text(StorageFormat.bytes(currentTotal))
                .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: crumbs.count)
    }

    private var rootName: String {
        let path = scanCoordinator.scannedRootPath
        if path == "/" { return appState.bootVolume?.name ?? "Macintosh HD" }
        return path == FileManager.default.homeDirectoryForCurrentUser.path ? "Home" : (path as NSString).lastPathComponent
    }

    // MARK: File types

    private var fileTypesSection: some View {
        let totals = scanCoordinator.fileTypeTotals.sorted { $0.totalSize > $1.totalSize }
        let sum = max(1, totals.reduce(Int64(0)) { $0 + $1.totalSize })
        let files = scanCoordinator.largeFiles
            .filter { $0.type == category }
            .sorted { $0.size > $1.size }
            .prefix(15)

        return VStack(alignment: .leading, spacing: 16) {
            GeometryReader { geo in
                HStack(spacing: 3) {
                    ForEach(totals) { total in
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(StoragePalette.color(for: total.type).opacity(category == total.type ? 1 : 0.55))
                            .frame(width: max(4, (geo.size.width - 3 * CGFloat(totals.count)) * CGFloat(total.totalSize) / CGFloat(sum)))
                    }
                }
            }
            .frame(height: 26)
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: category)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                ForEach(totals) { total in
                    CategoryCard(
                        total: total,
                        percent: StorageFormat.percent(total.totalSize, of: sum),
                        isSelected: category == total.type,
                        appearance: appearance
                    )
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { category = total.type }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                Text("LARGEST \(category.displayName.uppercased()) FILES")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                if files.isEmpty {
                    Text("No large \(category.displayName.lowercased()) files found.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                }
                ForEach(files) { file in
                    LargeFileRowView(file: file, path: filePath(file), maxSize: files.first?.size ?? 1, appearance: appearance)
                }
            }
            .padding(.bottom, 6)
            .storageCard(appearance)
        }
    }

    private func filePath(_ file: LargeFileRow) -> String {
        (scanCoordinator.fullPath(for: file.dirId) as NSString).appendingPathComponent(file.name)
    }

    // MARK: Actions

    private var zoomTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return drillingIn
            ? .asymmetric(
                insertion: .scale(scale: 0.35, anchor: zoomAnchor).combined(with: .opacity),
                removal: .scale(scale: 1.7, anchor: zoomAnchor).combined(with: .opacity)
            )
            : .asymmetric(
                insertion: .scale(scale: 1.6, anchor: .center).combined(with: .opacity),
                removal: .scale(scale: 0.5, anchor: .center).combined(with: .opacity)
            )
    }

    private func open(_ item: StorageItem) {
        drillingIn = true
        if item.isFile {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
        } else {
            scanCoordinator.drillIntoTreemapDir(item.dir)
        }
    }

    private func goUp() -> KeyPress.Result {
        guard scanCoordinator.treemapBreadcrumb.count > 1 else { return .ignored }
        drillingIn = false
        scanCoordinator.navigateTreemapUp()
        return .handled
    }
}

// MARK: - Pieces

private struct FocusCard: View {
    let item: StorageItem
    let total: Int64
    let appearance: AppearanceManager
    let actions: StorageItemActions

    var body: some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(item.color)
                .frame(width: 6, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).font(.system(size: 16, weight: .bold, design: .rounded)).lineLimit(1)
                Text(item.path).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }

            Spacer(minLength: 8)

            stat(StorageFormat.bytes(item.size), "Size")
            stat(StorageFormat.percent(item.size, of: total), "Of folder")
            if !item.isFile { stat("\(item.dir.descendantFileCount)", "Files") }
            stat(StorageFormat.age(item.dir.mtime), "Modified")

            Button(item.isFile ? "Reveal" : "Open") { actions.open(item) }
                .buttonStyle(.borderedProminent)
                .tint(appearance.accentColor)
                .controlSize(.large)
        }
        .padding(16)
        .storageCard(appearance)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value).font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
            Text(label).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
        }
    }
}

private struct FolderRow: View {
    let item: StorageItem
    let maxSize: Int64
    let total: Int64
    let isSelected: Bool
    let isHovered: Bool
    let appearance: AppearanceManager

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.isFile ? "doc.fill" : (item.isProtected ? "lock.fill" : "folder.fill"))
                .font(.system(size: 15))
                .foregroundStyle(item.color)
                .frame(width: 22)

            Text(item.name)
                .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                .lineLimit(1)
                .frame(minWidth: 120, alignment: .leading)

            GeometryReader { geo in
                Capsule()
                    .fill(item.color.opacity(isHovered || isSelected ? 0.95 : 0.7))
                    .frame(width: max(4, geo.size.width * CGFloat(item.size) / CGFloat(max(1, maxSize))))
                    .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 8)

            Text(StorageFormat.percent(item.size, of: total))
                .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)

            Text(StorageFormat.bytes(item.size))
                .font(.system(size: 12.5, weight: .semibold, design: .rounded).monospacedDigit())
                .frame(width: 74, alignment: .trailing)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)
                .opacity(item.isFile ? 0 : 1)
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? appearance.selectionFillColor : (isHovered ? Color.primary.opacity(0.06) : .clear))
                .padding(.horizontal, 6)
        )
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
    }
}

private struct CategoryCard: View {
    let total: FileTypeTotal
    let percent: String
    let isSelected: Bool
    let appearance: AppearanceManager
    @State private var hovering = false

    var body: some View {
        let tint = StoragePalette.color(for: total.type)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: StoragePalette.symbol(for: total.type))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(tint.opacity(0.16)))
                Spacer()
                Text(percent).font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(.secondary)
            }
            Text(StorageFormat.bytes(total.totalSize))
                .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
            Text("\(total.type.displayName) · \(total.fileCount) files")
                .font(.system(size: 11.5)).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(isSelected ? 0.2 : 0.09))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(isSelected ? tint : Color.primary.opacity(0.07), lineWidth: isSelected ? 2 : 1)
                )
        )
        .scaleEffect(hovering ? 1.02 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: hovering)
        .onHover { hovering = $0 }
        .contentShape(Rectangle())
    }
}

private struct LargeFileRowView: View {
    let file: LargeFileRow
    let path: String
    let maxSize: Int64
    let appearance: AppearanceManager
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFileType: file.ext ?? ""))
                .resizable().frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text((path as NSString).deletingLastPathComponent)
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
            }
            Spacer()
            Text(StorageFormat.age(file.mtime)).font(.system(size: 11.5)).foregroundStyle(.secondary)
            Text(StorageFormat.bytes(file.size))
                .font(.system(size: 12.5, weight: .semibold, design: .rounded).monospacedDigit())
                .frame(width: 74, alignment: .trailing)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            } label: {
                Image(systemName: "magnifyingglass.circle.fill").font(.system(size: 16))
            }
            .buttonStyle(StratumInteractiveButtonStyle())
            .foregroundStyle(appearance.accentColor)
            .opacity(hovering ? 1 : 0.35)
            .help("Reveal in Finder")
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hovering ? Color.primary.opacity(0.05) : .clear).padding(.horizontal, 6))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

private struct EmptyScanCard: View {
    let appearance: AppearanceManager
    let scan: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "chart.pie.fill").font(.system(size: 40)).foregroundStyle(appearance.accentColor)
            Text("No storage data yet").font(.system(size: 18, weight: .bold, design: .rounded))
            Text("Scan your home folder to see what's using space.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            Button("Scan Home Folder", action: scan)
                .buttonStyle(.borderedProminent).tint(appearance.accentColor).controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
