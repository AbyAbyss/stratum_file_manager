import SwiftUI
import AppKit

/// Right-hand panel of the Storage screen. Read-only on purpose: it points at what is worth a
/// look and sends cleanup to Groups, where selection, confirmation and undo already live.
struct StorageInsightsPanel: View {
    @Bindable var appState: AppState
    var appearance: AppearanceManager
    var scanCoordinator = ScanCoordinator.shared

    private var cleanableBytes: Int64 { scanCoordinator.groups.reduce(0) { $0 + $1.total } }

    private var largest: [LargeFileRow] {
        Array(scanCoordinator.largeFiles.sorted { $0.size > $1.size }.prefix(5))
    }

    /// Large files not modified for a year or more.
    private var untouched: [LargeFileRow] {
        let cutoff = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? .distantPast
        return scanCoordinator.largeFiles
            .filter { ($0.mtime ?? .distantFuture) < cutoff }
            .sorted { $0.size > $1.size }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("INSIGHTS")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1)
                .foregroundStyle(.secondary)

            if scanCoordinator.showsScanState {
                // Never describe a scan that is being replaced.
                VStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for the scan to finish…")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        cleanableCard
                        if !largest.isEmpty {
                            fileCard("Largest files", symbol: "arrow.up.right.circle", files: largest) {
                                StorageFormat.age($0.mtime)
                            }
                        }
                        if !untouched.isEmpty {
                            fileCard(
                                "Not modified in a year",
                                symbol: "clock.arrow.circlepath",
                                files: Array(untouched.prefix(4)),
                                footnote: "\(untouched.count) large files · \(StorageFormat.bytes(untouched.reduce(0) { $0 + $1.size }))"
                            ) { StorageFormat.age($0.mtime) }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(18)
        .padding(.top, 20)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(appearance.sidebarGlassColor.opacity(0.6))
    }

    // MARK: Cards

    private var cleanableCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Build & cache folders", systemImage: "shippingbox")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            if scanCoordinator.groups.isEmpty {
                Text("Nothing to clean up").font(.system(size: 13, weight: .semibold))
            } else {
                Text(StorageFormat.bytes(cleanableBytes))
                    .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                Text("in \(scanCoordinator.groups.count) groups of folders, like caches, node_modules and DerivedData.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) { appState.screen = .groups }
                } label: {
                    Label("Review in Groups", systemImage: "arrow.right")
                        .font(.system(size: 12.5, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                }
                .buttonStyle(.borderedProminent)
                .tint(appearance.accentColor)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .storageCard(appearance, radius: 14)
    }

    private func fileCard(
        _ title: String,
        symbol: String,
        files: [LargeFileRow],
        footnote: String? = nil,
        detail: @escaping (LargeFileRow) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 4)

            ForEach(files) { file in
                InsightFileRow(
                    file: file,
                    detail: detail(file),
                    path: (scanCoordinator.fullPath(for: file.dirId) as NSString).appendingPathComponent(file.name),
                    appearance: appearance
                )
            }

            if let footnote {
                Text(footnote)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.top, 2)
            }
            Spacer().frame(height: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .storageCard(appearance, radius: 14)
    }
}

private struct InsightFileRow: View {
    let file: LargeFileRow
    let detail: String
    let path: String
    let appearance: AppearanceManager
    @State private var hovering = false

    var body: some View {
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        } label: {
            HStack(spacing: 9) {
                Image(nsImage: NSWorkspace.shared.icon(forFileType: file.ext ?? ""))
                    .resizable()
                    .frame(width: 20, height: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(file.name).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    Text(detail).font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Text(StorageFormat.bytes(file.size))
                    .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(hovering ? Color.primary.opacity(0.07) : .clear)
            )
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .stratumHelp("Reveal \(file.name) in Finder")
    }
}
