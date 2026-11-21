import SwiftUI

// MARK: - Scanning state

/// Replaces a screen's results while a foreground scan runs, so nothing from the previous
/// scan is shown as if it were current. Progress is read here (not in the parent) so the
/// frequent progress updates re-render only this view.
struct ScanningStateView: View {
    let coordinator: ScanCoordinator
    let appearance: AppearanceManager
    /// What the screen will show once the scan finishes, e.g. "folder groups".
    let resultName: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    private var isLoadingResults: Bool { !coordinator.isScanning && coordinator.isResultsStale }

    var body: some View {
        let progress = coordinator.progress

        VStack(spacing: 22) {
            ZStack {
                ForEach(0..<3, id: \.self) { ring in
                    Circle()
                        .stroke(appearance.accentColor.opacity(0.35 - Double(ring) * 0.09), lineWidth: 1.5)
                        .frame(width: 70 + CGFloat(ring) * 34, height: 70 + CGFloat(ring) * 34)
                        .scaleEffect(pulse ? 1.12 : 0.92)
                        .opacity(pulse ? 0.25 : 1)
                        .animation(
                            reduceMotion ? nil : .easeInOut(duration: 1.6).repeatForever(autoreverses: true).delay(Double(ring) * 0.22),
                            value: pulse
                        )
                }
                Image(systemName: isLoadingResults ? "sparkles" : "externaldrive.fill.badge.timemachine")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(appearance.accentColor)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(height: 140)

            VStack(spacing: 6) {
                Text(isLoadingResults ? "Preparing your results…" : "Scanning \(displayRoot)…")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .contentTransition(.interpolate)
                Text("The \(resultName) will appear when the scan finishes. Nothing out of date is shown in the meantime.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            if !isLoadingResults {
                VStack(spacing: 10) {
                    ProgressView(value: min(1, max(0, progress.fraction)))
                        .progressViewStyle(.linear)
                        .tint(appearance.accentColor)
                        .frame(width: 320)

                    HStack(spacing: 18) {
                        stat("\(progress.filesScanned.formatted()) files", systemImage: "doc")
                        stat("\(Int((min(1, max(0, progress.fraction)) * 100).rounded()))%", systemImage: "percent")
                        if let eta = progress.etaSeconds {
                            stat(Self.etaText(eta), systemImage: "clock")
                        }
                    }

                    Text(progress.currentPath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(width: 420)
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
        .onAppear { pulse = true }
        .animation(.easeInOut(duration: 0.25), value: isLoadingResults)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isLoadingResults ? "Preparing results" : "Scanning, \(Int(progress.fraction * 100)) percent")
    }

    private var displayRoot: String {
        let path = coordinator.scannedRootPath
        if path == "/" { return "your disk" }
        return path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }

    private func stat(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .foregroundStyle(.secondary)
            .contentTransition(.numericText())
    }

    private static func etaText(_ seconds: Int) -> String {
        seconds < 60 ? "~\(seconds)s left" : "~\(Int((Double(seconds) / 60).rounded(.up))) min left"
    }
}

// MARK: - Rescan control

/// Header control for Storage and Groups. Says what will be rescanned ("Rescan Home"),
/// how old the data on screen is, and what it is doing right now. The menu holds the
/// auto-update switch so people can see why numbers change by themselves.
struct ScanRefreshControl: View {
    let coordinator: ScanCoordinator
    let appearance: AppearanceManager

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clickTurns = 0.0
    @State private var hovering = false

    private var isBusy: Bool { coordinator.isScanning || coordinator.isBackgroundRefreshing }

    private var scopeName: String {
        let path = coordinator.scannedRootPath
        if path == "/" { return "Entire Disk" }
        if path == FileManager.default.homeDirectoryForCurrentUser.path { return "Home" }
        return (path as NSString).lastPathComponent
    }

    private var title: String {
        if coordinator.isScanning { return "Scanning \(scopeName)…" }
        if coordinator.isBackgroundRefreshing { return "Updating \(scopeName)…" }
        return "Rescan \(scopeName)"
    }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: rescan) {
                HStack(spacing: 9) {
                    icon
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.system(size: 12, weight: .semibold))
                            .contentTransition(.interpolate)
                        subtitle
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, 12)
                .padding(.trailing, 9)
                .frame(height: 38)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(coordinator.isScanning)
            .help("Scan \(scopeName) again to refresh every size and list on this screen")

            Divider().frame(height: 18).opacity(0.6)

            Menu {
                Button("Rescan \(scopeName) Now", systemImage: "arrow.clockwise", action: rescan)
                    .disabled(coordinator.isScanning)
                Divider()
                Toggle("Keep up to date automatically", isOn: Bindable(coordinator).autoRefreshEnabled)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 38)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Rescan options")
        }
        .background(
            Capsule()
                .fill(Color.primary.opacity(hovering && !isBusy ? 0.1 : 0.06))
                .overlay(Capsule().strokeBorder(isBusy ? appearance.accentColor.opacity(0.55) : Color.primary.opacity(0.08), lineWidth: 1))
        )
        .clipShape(Capsule())
        .scaleEffect(hovering && !isBusy ? 1.02 : 1)
        .fixedSize()
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: hovering)
        .animation(.easeInOut(duration: 0.25), value: isBusy)
    }

    @ViewBuilder
    private var icon: some View {
        let symbol = Image(systemName: "arrow.clockwise")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(appearance.accentColor)

        if isBusy && !reduceMotion {
            TimelineView(.animation) { context in
                symbol.rotationEffect(.degrees(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 360))
            }
        } else {
            symbol.rotationEffect(.degrees(clickTurns * 360))
        }
    }

    @ViewBuilder
    private var subtitle: some View {
        if coordinator.isScanning {
            Text("This can take a few minutes")
        } else if coordinator.isBackgroundRefreshing {
            Text("Showing current data meanwhile")
        } else if let date = coordinator.lastScanDate {
            TimelineView(.everyMinute) { _ in
                // Say why old data isn't refreshing itself, so it doesn't look broken.
                Text("Updated \(date.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated)))"
                     + (coordinator.isAutoRefreshPausedOnBattery ? " · paused on battery" : ""))
            }
        } else {
            Text("Not scanned yet")
        }
    }

    private func rescan() {
        guard !coordinator.isScanning else { return }
        if !reduceMotion {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.65)) { clickTurns += 1 }
        }
        coordinator.startScan(at: URL(fileURLWithPath: coordinator.scannedRootPath))
    }
}

// MARK: - Deferred content

/// Shows the screen chrome immediately and builds the heavy content one frame later, so a
/// screen switch feels instant instead of stalling while the new view is laid out.
struct DeferredContent<Content: View>: View {
    /// Milliseconds to wait before building the content (default: about one frame).
    var delay: Int = 16
    @ViewBuilder let content: () -> Content
    @State private var ready = false

    var body: some View {
        ZStack {
            if ready {
                content().transition(.opacity)
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(delay))
            withAnimation(.easeOut(duration: 0.18)) { ready = true }
        }
    }
}

// MARK: - Icon feedback

extension View {
    /// One short bounce when `value` changes. Feedback for a user action, never a loop, and
    /// skipped entirely when Reduce Motion is on.
    func stratumSymbolPop<V: Equatable>(value: V) -> some View {
        modifier(SymbolPopModifier(value: value))
    }
}

private struct SymbolPopModifier<V: Equatable>: ViewModifier {
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.symbolEffect(.bounce, options: .speed(1.3), value: value)
        }
    }
}
