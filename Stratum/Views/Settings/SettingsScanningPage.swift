import SwiftUI

/// Scanning: background updates and the scan data Stratum keeps.
struct SettingsScanningPage: View {
    @Bindable var appState: AppState
    @Bindable var appearance: AppearanceManager
    var scanCoordinator = ScanCoordinator.shared

    @State private var confirmClear = false

    var body: some View {
        @Bindable var coordinator = scanCoordinator

        return VStack(alignment: .leading, spacing: 28) {
            SettingsGroup("Background updates", footer: "Stratum watches for file changes and refreshes the Storage map and Groups quietly. You can always rescan by hand from either screen.", appearance: appearance) {
                SettingsToggleRow(
                    title: "Keep scans up to date",
                    detail: coordinator.autoRefreshEnabled ? "Stratum refreshes in the background when files change." : "Off. Rescan by hand from the Storage map or Groups.",
                    isOn: $coordinator.autoRefreshEnabled,
                    appearance: appearance
                )
                SettingsDivider()
                SettingsToggleRow(title: "Only while on power", detail: "Skip background scans when running on battery.", isOn: $coordinator.onlyOnPower, appearance: appearance)
                    .disabled(!coordinator.autoRefreshEnabled)
                    .opacity(coordinator.autoRefreshEnabled ? 1 : 0.5)
            }

            SettingsGroup("Scan data", appearance: appearance) {
                SettingsRow("Saved scans", detail: "Snapshots that let the Storage map and Groups open instantly.") {
                    Text("\(coordinator.snapshotCount) · \(BulkDirectoryReader.fastFormatBytes(coordinator.snapshotTotalBytes))")
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                SettingsDivider()
                SettingsRow("Scan engine", detail: "Reads folders in bulk and stores the result in a local database.") {
                    Text("getattrlistbulk + SQLite")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                SettingsDivider()
                SettingsRow("Export a summary", detail: "Save the totals from the current scan as a file.") {
                    SettingsButton(title: "Export…", systemImage: "square.and.arrow.up", appearance: appearance) {
                        coordinator.exportScanSummary(appState: appState)
                    }
                }
                SettingsDivider()
                SettingsRow("Clear all scan data", detail: "Deletes every saved scan. Stratum rescans the next time you open a screen that needs one.") {
                    SettingsButton(title: "Clear…", systemImage: "trash", kind: .destructive, appearance: appearance) {
                        confirmClear = true
                    }
                }
            }
        }
        .onAppear { scanCoordinator.refreshSnapshotStats() }
        .confirmationDialog("Clear all scan data?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear scan data", role: .destructive) {
                scanCoordinator.clearAllScanData(appState: appState)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saved scans are deleted and Stratum will rescan. Your files are not touched.")
        }
    }
}
