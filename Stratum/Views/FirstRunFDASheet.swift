import SwiftUI

struct FirstRunFDASheet: View {
    @Bindable var appState: AppState
    var appearance: AppearanceManager

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(appearance.accentSoftColor)
                        .frame(width: 48, height: 48)
                    Image(systemName: "externaldrive.badge.checkmark")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(appearance.accentColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Full Disk Access")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Let Stratum browse protected folders and scan your whole disk.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                fdaBullet(
                    icon: "folder.fill",
                    title: "Browse every folder without permission roadblocks",
                    detail: "Access ~/Library, Mail attachments, Safari downloads, and application containers."
                )
                fdaBullet(
                    icon: "circle.grid.2x1.fill",
                    title: "Accurate whole-disk Storage Map & Groups by Name",
                    detail: "Find hidden caches, DerivedData, and stale node_modules across your entire drive."
                )
                fdaBullet(
                    icon: "lock.shield.fill",
                    title: "Local and private",
                    detail: "All file indexing and SQLite scan snapshots stay exclusively on your Mac."
                )
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            )

            HStack {
                Button("Continue Without Full Access") {
                    FullDiskAccess.hasShownFirstRunPrompt = true
                    appState.showFDASheet = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Button("Open System Settings…") {
                    FullDiskAccess.hasShownFirstRunPrompt = true
                    FullDiskAccess.openSystemSettings()
                    appState.showFDASheet = false
                }
                .buttonStyle(.borderedProminent)
                .tint(appearance.accentColor)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private func fdaBullet(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(appearance.accentColor)
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct GoToFolderSheet: View {
    @Bindable var appState: AppState
    var appearance: AppearanceManager
    @State private var pathInput: String = ""
    @State private var suggestions: [URL] = []
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Go to Folder")
                .font(.system(size: 14, weight: .semibold))

            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .foregroundStyle(appearance.accentColor)
                TextField("~/Projects", text: $pathInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, design: .monospaced))
                    .onSubmit {
                        confirmGo()
                    }
                    .onChange(of: pathInput) { _, newValue in
                        errorMessage = nil
                        updateAutocomplete(for: newValue)
                    }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(appearance.selectionBorderColor, lineWidth: 1)
                    )
            )

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }

            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(suggestions.prefix(6), id: \.path) { url in
                        Button {
                            pathInput = url.path
                            confirmGo()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(appearance.folderFrontColor)
                                Text(url.path)
                                    .font(.system(size: 12, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.head)
                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    appState.showGoToFolder = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Go") {
                    confirmGo()
                }
                .buttonStyle(.borderedProminent)
                .tint(appearance.accentColor)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 440)
        .onAppear {
            pathInput = appState.displayTildePath
            updateAutocomplete(for: pathInput)
        }
    }

    private func confirmGo() {
        let expanded = (pathInput.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue {
            appState.showGoToFolder = false
            appState.navigate(to: URL(fileURLWithPath: expanded, isDirectory: true))
        } else {
            errorMessage = "Folder not found: \(expanded)"
        }
    }

    private func updateAutocomplete(for raw: String) {
        let expanded = (raw as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        let parentDir = expanded.hasSuffix("/") ? url : url.deletingLastPathComponent()
        let prefix = expanded.hasSuffix("/") ? "" : url.lastPathComponent.lowercased()

        DispatchQueue.global(qos: .userInitiated).async {
            let entries = (try? FileManager.default.contentsOfDirectory(
                at: parentDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            let matches = entries.filter { candidate in
                guard (try? candidate.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
                    return false
                }
                return prefix.isEmpty || candidate.lastPathComponent.lowercased().hasPrefix(prefix)
            }
            Task { @MainActor in
                suggestions = matches
            }
        }
    }
}
