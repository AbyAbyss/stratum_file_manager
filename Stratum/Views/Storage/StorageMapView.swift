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
    /// The category the user picked; until then the biggest one with large files is shown.
    @State private var pickedCategory: FileTypeCategory?
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
                selectedID = nil
                scanCoordinator.trashStorageItem(item.dir, path: item.path, appState: appState)
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
            StorageInsightsPanel(appState: appState, appearance: appearance)
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

            Label("Double-click a folder to open it · Esc goes back", systemImage: "cursorarrow.click.2")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)

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
                    .onTapGesture {
                        // One gesture reading the click count: a separate single-tap gesture
                        // waits out the whole double-click interval, which made selecting lag.
                        if (NSApp.currentEvent?.clickCount ?? 1) >= 2 {
                            zoomAnchor = .center
                            open(item)
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selectedID = item.id }
                        }
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
            .stratumHelp("Up one level (Esc)")

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
        let withFiles = Set(scanCoordinator.largeFiles.map(\.type))
        let category = pickedCategory
            ?? totals.first(where: { withFiles.contains($0.type) })?.type
            ?? totals.first?.type
            ?? .other
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
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { pickedCategory = total.type }
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
