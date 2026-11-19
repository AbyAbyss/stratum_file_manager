import SwiftUI

/// Safety: what Stratum protects, when it asks first, and which folders are off limits.
struct SettingsSafetyPage: View {
    @Bindable var appState: AppState
    @Bindable var appearance: AppearanceManager
    var scanCoordinator = ScanCoordinator.shared

    @State private var userPaths = ProtectedPaths.loadUserPaths()
    @State private var draft = ""

    private let builtInPaths = ["/System", "/Library", "/usr", "/private", "~/Library/Keychains"]

    var body: some View {
        @Bindable var coordinator = scanCoordinator

        return VStack(alignment: .leading, spacing: 28) {
            SettingsGroup("Protection", footer: "Everything Stratum removes goes to the Trash first, so ⌘Z can bring it back.", appearance: appearance) {
                SettingsToggleRow(title: "Protect system paths", detail: "Always on. Stratum never touches /System, /usr, /private and similar.", isOn: .constant(true), appearance: appearance, isLocked: true)
                SettingsDivider()
                SettingsToggleRow(title: "Protect active projects", detail: "Bulk cleanups skip folders modified in the last 14 days.", isOn: $coordinator.protectActiveProjects, appearance: appearance)
                SettingsDivider()
                SettingsToggleRow(title: "Confirm large cleanups", detail: "Ask before moving more than 1 GB to the Trash at once.", isOn: $coordinator.confirmLargeDeletes, appearance: appearance)
                SettingsDivider()
                SettingsToggleRow(title: "Include hidden folders", detail: "Show and allow cleanup of dot-folders such as .cache and .config.", isOn: $coordinator.allowDeletingHidden, appearance: appearance)
            }

            SettingsGroup("Protected folders", footer: "Nothing inside these folders is ever moved to the Trash. Add your own for work you never want touched.", appearance: appearance) {
                ForEach(Array(builtInPaths.enumerated()), id: \.offset) { index, path in
                    if index > 0 { SettingsDivider() }
                    pathRow(path, removable: false)
                }
                ForEach(userPaths, id: \.self) { path in
                    SettingsDivider()
                    pathRow(path, removable: true)
                }
                SettingsDivider()
                HStack(spacing: 10) {
                    SettingsTextField(placeholder: "~/Clients or /Volumes/Archive", text: $draft, monospaced: true, onSubmit: addPath)
                    SettingsButton(title: "Add folder", systemImage: "plus", kind: .primary, appearance: appearance, action: addPath)
                }
                .padding(16)
            }
        }
    }

    private func pathRow(_ path: String, removable: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: removable ? "folder.fill" : "lock.fill")
                .font(.system(size: 12))
                .foregroundStyle(removable ? appearance.accentColor : .secondary)
                .frame(width: 18)
            Text(path)
                .font(.system(size: 13, design: .monospaced))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if removable {
                Button {
                    userPaths.removeAll { $0 == path }
                    ProtectedPaths.saveUserPaths(userPaths)
                    appState.showToast("Removed protected folder \(path)")
                } label: {
                    Image(systemName: "minus.circle.fill").font(.system(size: 15)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .stratumHelp("Remove \(path)")
            } else {
                Text("Built in").font(.system(size: 12)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
    }

    private func addPath() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !userPaths.contains(trimmed) {
            userPaths.append(trimmed)
            ProtectedPaths.saveUserPaths(userPaths)
            appState.showToast("Protecting \(trimmed)")
        }
        draft = ""
    }
}
