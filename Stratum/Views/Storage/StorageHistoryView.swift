import SwiftUI
import Charts

/// Storage history: how much space is used over time, and which folders and file types
/// account for the change. Built from the small daily samples in `StorageHistory`.
struct StorageHistoryView: View {
    @Bindable var appState: AppState
    var appearance: AppearanceManager
    var scanCoordinator = ScanCoordinator.shared
    var history = StorageHistory.shared

    enum Period: String, CaseIterable, Identifiable {
        case week = "7 days", month = "30 days", quarter = "90 days", year = "1 year", all = "All"
        var id: String { rawValue }
        var days: Int? {
            switch self {
            case .week: return 7
            case .month: return 30
            case .quarter: return 90
            case .year: return 365
            case .all: return nil
            }
        }
    }

    @State private var period: Period = .month
    @State private var hoveredDate: Date?
    @State private var expanded: Set<String> = []
    @State private var confirmClear = false

    /// Space taken is the thing to watch, so growth is the warm colour and freed space the cool one.
    private static let growColor = Color(nsColor: NSColor(hex: "#E5604D") ?? .systemOrange)
    private static let shrinkColor = Color(nsColor: NSColor(hex: "#12A594") ?? .systemTeal)

    // MARK: Derived data

    private var rootPath: String { scanCoordinator.scannedRootPath }
    private var allSamples: [StorageSample] { history.samples(forRoot: rootPath) }

    private var samples: [StorageSample] {
        guard let days = period.days, let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else {
            return allSamples
        }
        return allSamples.filter { $0.date >= cutoff }
    }

    private var latest: StorageSample? { samples.last ?? allSamples.last }
    /// The sample the current one is compared against; nil until there are two.
    private var baseline: StorageSample? {
        guard let first = samples.first, first.id != latest?.id else { return nil }
        return first
    }

    private var rootTitle: String {
        if rootPath == "/" { return "Macintosh HD" }
        if rootPath == FileManager.default.homeDirectoryForCurrentUser.path { return "Home folder" }
        return (rootPath as NSString).abbreviatingWithTildeInPath
    }

    // MARK: Body

    var body: some View {
        Group {
            if let latest {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header(latest)
                        tiles(latest)
                        chartCard
                        AdaptiveStack(spacing: 16) {
                            foldersCard(latest)
                            typesCard(latest)
                        }
                        footer
                    }
                    .padding(22)
                    .frame(maxWidth: 1180, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            } else {
                emptyState
            }
        }
        .confirmationDialog("Clear storage history?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear history", role: .destructive) { history.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The saved daily totals are deleted. Your files and scans are not touched.")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
            Text("No history yet")
                .font(.system(size: 17, weight: .semibold))
            Text("Stratum saves a small daily summary each time a scan of \(rootTitle) finishes. The first one appears here after the current scan.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Header

    private func header(_ latest: StorageSample) -> some View {
        AdaptiveStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Storage History")
                    .font(.system(size: 24, weight: .semibold))
                Text("\(rootTitle) · \(allSamples.count) \(allSamples.count == 1 ? "day" : "days") recorded · updated \(latest.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(minWidth: 0, idealWidth: 320, maxWidth: .infinity, alignment: .leading)
            }
            Picker("Period", selection: $period) {
                ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
    }

    // MARK: Stat tiles

    private func tiles(_ latest: StorageSample) -> some View {
        let change = baseline.map { latest.diskUsed - $0.diskUsed }
        let days = baseline.map { max(1, Calendar.current.dateComponents([.day], from: $0.date, to: latest.date).day ?? 1) }
        let content = Group {
            tile("Used on disk", value: StorageFormat.bytes(latest.diskUsed),
                 detail: "of \(StorageFormat.bytes(latest.diskUsed + latest.diskFree))")
            tile("Change", value: change.map(Self.signed) ?? "—",
                 detail: baseline.map { "since \($0.date.formatted(.dateTime.day().month(.abbreviated)))" } ?? "needs a second day",
                 trend: change)
            tile("Average per day", value: (change.flatMap { c in days.map { Self.signed(c / Int64($0)) } }) ?? "—",
                 detail: days.map { "over \($0) \($0 == 1 ? "day" : "days")" } ?? "needs a second day")
            tile("Free", value: StorageFormat.bytes(latest.diskFree),
                 detail: baseline.map { Self.signed(latest.diskFree - $0.diskFree) + " in this period" } ?? "available now")
        }
        // Four in a row when they fit, otherwise two by two: never three and an orphan.
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { content.frame(minWidth: 170) }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) { content }
        }
    }

    private func tile(_ title: String, value: String, detail: String, trend: Int64? = nil) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text(value)
                    .font(.system(size: 21, weight: .semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let trend, trend != 0 {
                    Image(systemName: trend > 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(trend > 0 ? Self.growColor : Self.shrinkColor)
                }
            }
            Text(detail)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .storageCard(appearance, radius: 14)
    }

    // MARK: Chart

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Disk space used")
                .font(.system(size: 14, weight: .semibold))
            if samples.count < 2 {
                HStack(spacing: 10) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(.secondary)
                    Text(allSamples.count < 2
                         ? "History starts here. A point is added each day a scan runs, and the trend appears from the second day."
                         : "Only one day falls in this period. Pick a longer period to see the trend.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
            } else {
                usageChart
                    .frame(height: 220)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .storageCard(appearance)
    }

    private var usageChart: some View {
        let values = samples.map(\.diskUsed)
        let low = Double(values.min() ?? 0), high = Double(values.max() ?? 0)
        let pad = max((high - low) * 0.25, high * 0.002, 1)
        let hovered = hoveredDate.flatMap { date in
            samples.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
        }
        // Whole days between labels, so a short history never repeats the same date.
        let spanDays = Calendar.current.dateComponents([.day], from: samples.first?.date ?? Date(), to: samples.last?.date ?? Date()).day ?? 0
        let dayStride = max(1, Int((Double(spanDays) / 6).rounded(.up)))
        return Chart {
            ForEach(samples) { sample in
                LineMark(x: .value("Day", sample.date), y: .value("Used", Double(sample.diskUsed)))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(appearance.accentColor)
                if samples.count <= 45 {
                    PointMark(x: .value("Day", sample.date), y: .value("Used", Double(sample.diskUsed)))
                        .symbolSize(samples.count <= 14 ? 44 : 22)
                        .foregroundStyle(appearance.accentColor)
                }
            }
            if let hovered {
                RuleMark(x: .value("Day", hovered.date))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(Color.primary.opacity(0.25))
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(hovered.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                            Text(StorageFormat.bytes(hovered.diskUsed))
                                .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.regularMaterial))
                    }
                PointMark(x: .value("Day", hovered.date), y: .value("Used", Double(hovered.diskUsed)))
                    .symbolSize(70)
                    .foregroundStyle(appearance.accentColor)
            }
        }
        // A line may start above zero: the day-to-day change is a tiny part of the whole disk.
        .chartYScale(domain: (low - pad)...(high + pad))
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                AxisValueLabel {
                    if let bytes = value.as(Double.self) { Text(StorageFormat.bytes(Int64(bytes))) }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: dayStride)) { _ in
                AxisGridLine().foregroundStyle(Color.primary.opacity(0.05))
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
        // Keeps the first and last date labels inside the card.
        .chartXScale(range: .plotDimension(padding: 18))
        .chartXSelection(value: $hoveredDate)
    }

    // MARK: Folders

    private func foldersCard(_ latest: StorageSample) -> some View {
        let changes = Array(latest.folderChanges(since: baseline).prefix(14))
        let scale = changes.map { abs($0.delta) }.max() ?? 0
        return card(
            "Folders",
            subtitle: baseline == nil ? "Largest folders now" : "Biggest changes in this period"
        ) {
            ForEach(changes) { change in
                let children = latest.folderChanges(since: baseline, parent: change.id)
                folderRow(change, scale: scale, hasChildren: !children.isEmpty, indent: 0)
                if expanded.contains(change.id) {
                    ForEach(children.prefix(8)) { child in
                        folderRow(child, scale: scale, hasChildren: false, indent: 22)
                    }
                }
            }
        }
        .frame(minWidth: 0, idealWidth: 520, maxWidth: .infinity)
    }

    private func folderRow(_ change: StorageChange, scale: Int64, hasChildren: Bool, indent: CGFloat) -> some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.16)) {
                    if expanded.contains(change.id) { expanded.remove(change.id) } else { expanded.insert(change.id) }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded.contains(change.id) ? 90 : 0))
                        .opacity(hasChildren ? 1 : 0)
                        .frame(width: 10)
                    Image(systemName: "folder.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(appearance.accentColor.opacity(indent > 0 ? 0.6 : 1))
                    Text(change.name)
                        .font(.system(size: 12.5, weight: indent > 0 ? .regular : .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .allowsHitTesting(hasChildren)

            deltaView(change.delta, scale: scale)
            Text(StorageFormat.bytes(change.size))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 68, alignment: .trailing)
            Button {
                appState.navigate(to: URL(fileURLWithPath: rootPath).appendingPathComponent(change.id))
                withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) { appState.screen = .browser }
            } label: {
                Image(systemName: "arrow.right.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .stratumHelp("Open \(change.name) in the browser")
        }
        .padding(.leading, indent)
        .frame(height: 28)
    }

    // MARK: File types

    private func typesCard(_ latest: StorageSample) -> some View {
        let changes = latest.typeChanges(since: baseline)
        let total = max(1, changes.reduce(Int64(0)) { $0 + $1.size })
        let scale = changes.map { abs($0.delta) }.max() ?? 0
        return card("File types", subtitle: baseline == nil ? "What the space holds now" : "What kind of data changed") {
            // Composition strip: one segment per type, separated by a 2pt surface gap.
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(changes.sorted { $0.size > $1.size }, id: \.type) { change in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(StoragePalette.color(for: change.type))
                            .frame(width: max(2, (geo.size.width - CGFloat(changes.count - 1) * 2) * CGFloat(change.size) / CGFloat(total)))
                            .stratumHelp("\(change.type.displayName): \(StorageFormat.bytes(change.size))")
                    }
                }
            }
            .frame(height: 10)
            .padding(.bottom, 6)

            ForEach(changes, id: \.type) { change in
                HStack(spacing: 8) {
                    Image(systemName: StoragePalette.symbol(for: change.type))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(StoragePalette.color(for: change.type)))
                    Text(change.type.displayName)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    deltaView(change.delta, scale: scale)
                    Text(StorageFormat.bytes(change.size))
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 68, alignment: .trailing)
                }
                .frame(height: 28)
            }
        }
        .frame(minWidth: 0, idealWidth: 380, maxWidth: .infinity)
    }

    // MARK: Shared pieces

    private func card<Content: View>(_ title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .storageCard(appearance)
    }

    /// A bar sized by the change plus the signed amount; the sign and arrow carry the direction,
    /// so it never rests on colour alone.
    @ViewBuilder
    private func deltaView(_ delta: Int64, scale: Int64) -> some View {
        if baseline != nil {
            let color = delta > 0 ? Self.growColor : Self.shrinkColor
            HStack(spacing: 6) {
                Capsule()
                    .fill(delta == 0 ? Color.clear : color)
                    .frame(width: scale > 0 ? max(delta == 0 ? 0 : 3, 44 * CGFloat(abs(delta)) / CGFloat(scale)) : 0, height: 5)
                    .frame(width: 44, alignment: .trailing)
                HStack(spacing: 2) {
                    if delta != 0 {
                        Image(systemName: delta > 0 ? "arrow.up" : "arrow.down")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(color)
                    }
                    Text(delta == 0 ? "no change" : Self.signed(delta))
                        .font(.system(size: 12, weight: delta == 0 ? .regular : .medium).monospacedDigit())
                        .foregroundStyle(delta == 0 ? .tertiary : .primary)
                        .lineLimit(1)
                }
                .frame(width: 88, alignment: .trailing)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
            Text("One small summary is saved per day a scan runs. Only folder and file-type totals are kept, so a year takes about a megabyte.")
                .frame(minWidth: 0, idealWidth: 300, maxWidth: .infinity, alignment: .leading)
            Button("Clear history…") { confirmClear = true }
                .buttonStyle(.plain)
                .foregroundStyle(appearance.accentColor)
        }
        .font(.system(size: 11.5))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    private static func signed(_ bytes: Int64) -> String {
        (bytes > 0 ? "+" : bytes < 0 ? "−" : "") + StorageFormat.bytes(abs(bytes))
    }
}
