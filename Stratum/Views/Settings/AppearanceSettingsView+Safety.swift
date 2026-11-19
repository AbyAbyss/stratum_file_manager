import SwiftUI
import AppKit

extension AppearanceSettingsView {
    // MARK: - 0. Safety, Protected Paths, Scans & Snapshots (Matches Screenshot 5)

    var safetyAndScansSection: some View {
        @Bindable var coordinator = scanCoordinator

        return HStack(alignment: .top, spacing: 14) {
            // Left Column: SAFETY + PROTECTED PATHS
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("SAFETY")
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .tracking(1.0)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("What Stratum refuses to delete")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Divider().overlay(Color.primary.opacity(0.08))

                Toggle(isOn: .constant(true)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Protect system paths")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Always on. Stratum never touches /System, /usr, /private, and similar.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .tint(appearance.accentColor)
                .disabled(true)
                .disabled(true)

                Divider().overlay(Color.primary.opacity(0.06))

                Toggle(isOn: $coordinator.protectActiveProjects) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Protect active projects")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Bulk cleanups skip folders modified in the last 14 days.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .tint(appearance.accentColor)

                Divider().overlay(Color.primary.opacity(0.06))

                Toggle(isOn: $coordinator.confirmLargeDeletes) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Confirm large deletes")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Show the confirmation sheet for any cleanup over 1 GB.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .tint(appearance.accentColor)

                Divider().overlay(Color.primary.opacity(0.06))

                Toggle(isOn: $coordinator.allowDeletingHidden) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Allow deleting hidden")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Show and allow removal of dot-folders like .Trash, .config.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .tint(appearance.accentColor)

                // Protected Paths List
                Text("PROTECTED PATHS")
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .tracking(1.0)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)

                VStack(spacing: 6) {
                    ForEach(["/System", "/Library", "/usr", "/private", "~/Library/Keychains"], id: \.self) { sysPath in
                        HStack {
                            Text(sysPath)
                                .font(.system(size: 12, design: .monospaced))
                            Spacer()
                            Text("built in")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.black.opacity(0.22))
                        )
                    }

                    ForEach(userProtectedPaths, id: \.self) { customPath in
                        HStack {
                            Text(customPath)
                                .font(.system(size: 12, design: .monospaced))
                            Spacer()
                            Button {
                                removeUserProtectedPath(customPath)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20, height: 20)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(appearance.selectionTintColor.opacity(0.55))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .strokeBorder(appearance.selectionBorderColor.opacity(0.5), lineWidth: 1)
                                )
                        )
                    }

                    // Add Custom Protected Path Input Row
                    HStack(spacing: 8) {
                        TextField("~/Clients or /Volumes/Archive…", text: $newProtectedPathDraft)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color.black.opacity(0.28))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                                    )
                            )
                            .onSubmit {
                                addCustomProtectedPath()
                            }

                        Button {
                            addCustomProtectedPath()
                        } label: {
                            Text("Add path")
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 12)
                                .frame(height: 30)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(Color.primary.opacity(0.08))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
                                        )
                                )
                        }
                        .buttonStyle(StratumInteractiveButtonStyle())
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(appearance.cardGlassFillColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            )

            // Right Column: SCANS + SNAPSHOTS · DETECTION · EXPORT
            VStack(alignment: .leading, spacing: 14) {
                // Card 1: SCANS
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("SCANS")
                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                            .tracking(1.0)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("When and how Stratum sweeps")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Divider().overlay(Color.primary.opacity(0.08))

                    Toggle(isOn: $coordinator.autoRefreshEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Scheduled & smart background scans")
                                .font(.system(size: 13, weight: .semibold))
                            Text(coordinator.autoRefreshEnabled ? "Active — coalesced FSEvents + delta monitor" : "Off")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .tint(appearance.accentColor)

                    Divider().overlay(Color.primary.opacity(0.06))

                    Toggle(isOn: $coordinator.onlyOnPower) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Only on power")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Skip a scheduled background scan on battery.")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .tint(appearance.accentColor)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(appearance.cardGlassFillColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                )

                // Card 2: SNAPSHOTS · DETECTION · EXPORT
                VStack(alignment: .leading, spacing: 12) {
                    Text("SNAPSHOTS · DETECTION · EXPORT")
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .tracking(1.0)
                        .foregroundStyle(.secondary)

                    Divider().overlay(Color.primary.opacity(0.08))

                    snapshotMetaRow(
                        label: "Scans kept",
                        value: "\(coordinator.snapshotCount) · \(BulkDirectoryReader.fastFormatBytes(coordinator.snapshotTotalBytes))"
                    )

                    snapshotMetaRow(
                        label: "Engine",
                        value: "getattrlistbulk → SQLite (GRDB)"
                    )

                    snapshotMetaRow(
                        label: "Version",
                        value: AppInfo.version
                    )

                    HStack(spacing: 10) {
                        Button {
                            coordinator.exportScanSummary(appState: appState)
                        } label: {
                            Text("Export scan summary")
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 14)
                                .frame(height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.primary.opacity(0.07))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
                                        )
                                )
                        }
                        .buttonStyle(StratumInteractiveButtonStyle())

                        Button {
                            coordinator.clearAllScanData(appState: appState)
                        } label: {
                            Text("Clear all scan data")
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 14)
                                .frame(height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.primary.opacity(0.07))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
                                        )
                                )
                        }
                        .buttonStyle(StratumInteractiveButtonStyle())
                    }
                    .padding(.top, 4)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(appearance.cardGlassFillColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                )
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    func snapshotMetaRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
        }
    }

    func addCustomProtectedPath() {
        let trimmed = newProtectedPathDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !userProtectedPaths.contains(trimmed) {
            userProtectedPaths.append(trimmed)
            ProtectedPaths.saveUserPaths(userProtectedPaths)
            appState.showToast("Added protected path: \(trimmed)")
        }
        newProtectedPathDraft = ""
    }

    func removeUserProtectedPath(_ path: String) {
        userProtectedPaths.removeAll(where: { $0 == path })
        ProtectedPaths.saveUserPaths(userProtectedPaths)
        appState.showToast("Removed protected path: \(path)")
    }
}
