import SwiftUI

/// Right-hand "Quick wins" panel: tick cleanup candidates, see the running total, move to Trash.
struct StorageCleanupPanel: View {
    @Bindable var appState: AppState
    var appearance: AppearanceManager
    var scanCoordinator = ScanCoordinator.shared

    // Nothing is pre-ticked: destructive actions should be opt-in.
    @State private var checked: Set<String> = []

    private struct Task: Identifiable {
        let id: String
        let title: String
        let detail: String
        let bytes: Int64
        let isGroup: Bool
        let paths: [String]
    }

    private static let duplicatesID = "duplicates"

    private var tasks: [Task] {
        var list = scanCoordinator.groups.prefix(8).map { group in
            Task(
                id: group.name,
                title: group.name,
                detail: "\(group.count) \(group.count == 1 ? "folder" : "folders") · \(group.tagline)",
                bytes: group.total,
                isGroup: true,
                paths: []
            )
        }
        let clusters = scanCoordinator.duplicateClusters
        if !clusters.isEmpty {
            list.append(Task(
                id: Self.duplicatesID,
                title: "Duplicate files",
                detail: "\(clusters.count) identical sets · keeps one copy of each",
                bytes: clusters.reduce(0) { $0 + $1.reclaimableBytes },
                isGroup: false,
                paths: clusters.flatMap { $0.paths.dropFirst() }
            ))
        }
        return list
    }

    private var selectedBytes: Int64 {
        tasks.filter { checked.contains($0.id) }.reduce(0) { $0 + $1.bytes }
    }

    var body: some View {
        // Never offer cleanup candidates from a scan that is being replaced.
        let all = scanCoordinator.showsScanState ? [] : tasks
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("QUICK WINS")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(checked.isEmpty ? "Select All" : "Clear") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        checked = checked.isEmpty ? Set(all.map(\.id)) : []
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(appearance.accentColor)
                .disabled(all.isEmpty)
            }

            Text("Everything goes to the Trash first. Press ⌘Z to restore.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)

            if scanCoordinator.showsScanState {
                Spacer()
                VStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for the scan to finish…")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else if all.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "sparkles").font(.system(size: 26)).foregroundStyle(appearance.accentColor)
                    Text("Nothing to clean up").font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(all) { task in
                            TaskRow(
                                title: task.title,
                                detail: task.detail,
                                bytes: task.bytes,
                                isChecked: checked.contains(task.id),
                                appearance: appearance
                            ) {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                    if checked.contains(task.id) { checked.remove(task.id) } else { checked.insert(task.id) }
                                }
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            reclaimBar
        }
        .padding(18)
        .padding(.top, 20)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(appearance.sidebarGlassColor.opacity(0.6))
    }

    private var reclaimBar: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Selected to free").font(.system(size: 12.5, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Text(StorageFormat.bytes(selectedBytes))
                    .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
            }
            Button(action: reclaim) {
                Label(selectedBytes > 0 ? "Free \(StorageFormat.bytes(selectedBytes))" : "Move to Trash", systemImage: "trash")
                    .font(.system(size: 13.5, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
            }
            .buttonStyle(.borderedProminent)
            .tint(appearance.accentColor)
            .disabled(selectedBytes == 0 || scanCoordinator.showsScanState)

            Button("Inspect folders in Groups →") {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) { appState.screen = .groups }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .padding(.top, 10)
        .overlay(alignment: .top) { Divider().opacity(0.6) }
    }

    private func reclaim() {
        let chosen = tasks.filter { checked.contains($0.id) }

        let instances = chosen.filter(\.isGroup).flatMap { scanCoordinator.instances(forGroup: $0.id) }
        if !instances.isEmpty {
            scanCoordinator.trashGroupInstances(instances, appState: appState)
        }
        if let dupes = chosen.first(where: { $0.id == Self.duplicatesID }), !dupes.paths.isEmpty {
            appState.moveURLsToTrash(dupes.paths.map { (url: URL(fileURLWithPath: $0), size: 0) })
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { checked = [] }
    }
}

private struct TaskRow: View {
    let title: String
    let detail: String
    let bytes: Int64
    let isChecked: Bool
    let appearance: AppearanceManager
    let toggle: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isChecked ? appearance.accentColor : Color.secondary.opacity(0.5))
                    .symbolEffect(.bounce, value: isChecked)

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(title).font(.system(size: 13, weight: .bold)).lineLimit(1)
                        Spacer(minLength: 6)
                        Text(StorageFormat.bytes(bytes))
                            .font(.system(size: 12.5, weight: .bold, design: .rounded).monospacedDigit())
                    }
                    Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isChecked ? appearance.selectionFillColor : Color.primary.opacity(hovering ? 0.07 : 0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(isChecked ? appearance.selectionBorderColor : Color.primary.opacity(0.06), lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}
