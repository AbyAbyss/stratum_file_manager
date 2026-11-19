import SwiftUI
import AppKit

struct AppearanceSettingsView: View {
    @Bindable var appState: AppState
    @Bindable var appearance: AppearanceManager
    var scanCoordinator = ScanCoordinator.shared

    enum SettingsTab: String, CaseIterable, Identifiable {
        case all = "All Settings"
        case appearance = "Glass Themes & Appearance"
        case safetyAndScans = "Safety, Scans & Snapshots"

        var id: String { rawValue }
    }

    @State private var activeTab: SettingsTab = .all
    @State private var hexDraft: String = "#44D492"
    @State private var customThemeNameDraft: String = ""
    @State private var newProtectedPathDraft: String = ""
    @State private var userProtectedPaths: [String] = ProtectedPaths.loadUserPaths()

    var body: some View {
        HStack(spacing: 0) {
            // Left / Main Settings Scroll
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Settings — Glass Themes, Safety & Scans")
                                .font(.system(size: 22, weight: .bold))
                            Text("Customize VS Code–style translucent glass themes, protected paths, scan schedules, snapshots, and export.")
                                .font(.system(size: 12.5))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        // Settings Section Filter Pills
                        HStack(spacing: 4) {
                            ForEach(SettingsTab.allCases) { tab in
                                let isSelected = (activeTab == tab)
                                Button {
                                    withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                                        activeTab = tab
                                    }
                                } label: {
                                    Text(tab.rawValue)
                                        .font(.system(size: 11.5, weight: isSelected ? .bold : .medium))
                                        .foregroundStyle(isSelected ? Color.black.opacity(0.88) : .secondary)
                                        .padding(.horizontal, 11)
                                        .frame(height: 28)
                                        .background(
                                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                .fill(isSelected ? appearance.accentColor : Color.clear)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(3)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(appearance.cardGlassFillColor)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                                )
                        )
                    }

                    if activeTab == .all || activeTab == .safetyAndScans {
                        safetyAndScansSection
                    }

                    if activeTab == .all || activeTab == .appearance {
                        presetThemeGallerySection
                        customSurfaceEditorSection
                        accentColorSection
                        windowMaterialSection
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 22)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Right Live Preview Sidebar
            livePreviewSidebar
                .frame(width: 344)
        }
        .onAppear {
            hexDraft = appearance.activeHexString
            userProtectedPaths = ProtectedPaths.loadUserPaths()
            scanCoordinator.refreshSnapshotStats()
        }
    }

    // MARK: - 0. Safety, Protected Paths, Scans & Snapshots (Matches Screenshot 5)

    private var safetyAndScansSection: some View {
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
                        Text("Always skip /System, /usr, /private, and similar.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .tint(appearance.accentColor)
                .disabled(true)

                Divider().overlay(Color.primary.opacity(0.06))

                Toggle(isOn: $coordinator.protectActiveProjects) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Protect active projects")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Leave recently touched project folders alone.")
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

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("How often")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Runs smoothly on a background utility queue without UI lag.")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("", selection: $coordinator.scanScheduleFrequency) {
                            Text("Live FSEvents").tag("Live FSEvents")
                            Text("On App Open").tag("On App Open")
                            Text("Daily").tag("Daily")
                            Text("Weekly").tag("Weekly")
                        }
                        .labelsHidden()
                        .frame(width: 130)
                    }

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

                    HStack {
                        Text("Large-file threshold")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("", selection: $coordinator.largeFileThresholdMB) {
                            Text("100 MB").tag(100)
                            Text("250 MB").tag(250)
                            Text("500 MB").tag(500)
                            Text("1 GB").tag(1024)
                        }
                        .labelsHidden()
                        .frame(width: 110)
                    }

                    snapshotMetaRow(
                        label: "Engine",
                        value: "getattrlistbulk → SQLite (GRDB)"
                    )

                    snapshotMetaRow(
                        label: "Version",
                        value: "1.0.0"
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

    private func snapshotMetaRow(label: String, value: String) -> some View {
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

    private func addCustomProtectedPath() {
        let trimmed = newProtectedPathDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !userProtectedPaths.contains(trimmed) {
            userProtectedPaths.append(trimmed)
            ProtectedPaths.saveUserPaths(userProtectedPaths)
            appState.showToast("Added protected path: \(trimmed)")
        }
        newProtectedPathDraft = ""
    }

    private func removeUserProtectedPath(_ path: String) {
        userProtectedPaths.removeAll(where: { $0 == path })
        ProtectedPaths.saveUserPaths(userProtectedPaths)
        appState.showToast("Removed protected path: \(path)")
    }

    // MARK: - 1. VS Code-Style Glass Theme Gallery (Built-In + User Custom Themes)

    private var presetThemeGallerySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Glass Themes (Curated & Custom)")
                        .font(.system(size: 14, weight: .bold))
                    Text("Each theme has its own window glass tint, sidebar tint, card tint, accent color, blur material, and translucency — and every property can be edited below.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()

                // Base Light / Dark / System Mode Switcher
                HStack(spacing: 3) {
                    ForEach(AppThemeOverride.allCases, id: \.rawValue) { mode in
                        let isSelected = (appearance.themeMode == mode)
                        Button {
                            appearance.themeMode = mode
                        } label: {
                            Text(mode.label)
                                .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                                .foregroundStyle(isSelected ? Color.black.opacity(0.88) : .secondary)
                                .padding(.horizontal, 10)
                                .frame(height: 26)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(isSelected ? appearance.accentColor : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.28))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                )
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                ForEach(appearance.allThemes) { preset in
                    glassThemePresetCard(preset)
                }
            }

            Divider()
                .overlay(Color.primary.opacity(0.08))

            // Save or Update Custom Theme Bar
            HStack(spacing: 10) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(appearance.accentColor)

                TextField("Name your custom theme (e.g. Midnight Emerald)…", text: $customThemeNameDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.black.opacity(0.28))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                            )
                    )
                    .onSubmit {
                        saveCustomTheme()
                    }

                Button {
                    saveCustomTheme()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 11.5))
                        Text("Save as New Theme")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(Color.black.opacity(0.88))
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(appearance.accentColor)
                    )
                }
                .buttonStyle(StratumInteractiveButtonStyle())

                if let activeCustom = appearance.customThemes.first(where: { $0.id == appearance.activeThemeID }) {
                    Button {
                        appearance.updateActiveCustomTheme()
                        appState.showToast("Updated \"\(activeCustom.name)\" with current colors & translucency")
                    } label: {
                        Text("Update \"\(activeCustom.name)\"")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 11)
                            .frame(height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.primary.opacity(0.08))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .strokeBorder(appearance.selectionBorderColor, lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(StratumInteractiveButtonStyle())
                }
            }
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

    private func glassThemePresetCard(_ preset: StratumThemePreset) -> some View {
        let isSelected = (appearance.activeThemeID == preset.id)
        let pAccent = Color(nsColor: NSColor(hex: preset.accentHex) ?? .systemGreen)
        let pWin = Color(nsColor: NSColor(hex: preset.windowTintHex) ?? .black)
        let pSide = Color(nsColor: NSColor(hex: preset.sidebarTintHex) ?? .darkGray)
        let pCard = Color(nsColor: NSColor(hex: preset.cardTintHex) ?? .darkGray)

        return Button {
            appearance.applyThemePreset(preset)
            hexDraft = preset.accentHex
            appState.showToast("Applied \(preset.name)")
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                // Miniature Window Preview
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 3) {
                            Circle().fill(Color.red.opacity(0.8)).frame(width: 5, height: 5)
                            Circle().fill(Color.yellow.opacity(0.8)).frame(width: 5, height: 5)
                            Circle().fill(Color.green.opacity(0.8)).frame(width: 5, height: 5)
                        }
                        .padding(.bottom, 2)

                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(pAccent.opacity(0.28))
                            .overlay(
                                RoundedRectangle(cornerRadius: 2.5)
                                    .strokeBorder(pAccent.opacity(0.75), lineWidth: 0.8)
                            )
                            .frame(height: 8)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.primary.opacity(0.15))
                            .frame(width: 24, height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.primary.opacity(0.10))
                            .frame(width: 20, height: 4)
                        Spacer()
                    }
                    .padding(7)
                    .frame(width: 44)
                    .background(pSide)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(pCard)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .strokeBorder(pAccent.opacity(0.85), lineWidth: 1)
                                )
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(pCard)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .strokeBorder(Color.cyan.opacity(0.55), lineWidth: 0.8)
                                )
                        }
                        .frame(height: 26)

                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(pCard)
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(pAccent)
                                    .frame(width: 38, height: 3.5)
                                    .padding(.leading, 6)
                            }
                            .frame(height: 14)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(pWin)
                }
                .frame(height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(isSelected ? pAccent : Color.primary.opacity(0.12), lineWidth: isSelected ? 2 : 1)
                )

                HStack(alignment: .top, spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(pAccent)
                                .frame(width: 7, height: 7)
                            Text(preset.name)
                                .font(.system(size: 12.5, weight: .bold))
                                .lineLimit(1)
                        }
                        Text("\(Int(preset.translucency))% glass · \(preset.blurStyle.rawValue)")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if !preset.isBuiltIn {
                        Button {
                            appearance.deleteCustomTheme(preset)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .stratumHelp("Delete custom theme")
                    } else if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(pAccent)
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? pAccent.opacity(0.11) : Color.primary.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(isSelected ? pAccent.opacity(0.65) : Color.primary.opacity(0.07), lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(StratumInteractiveButtonStyle(hoverScale: 1.015, pressScale: 0.98))
    }

    // MARK: - 2. Custom Theme Surface Tint Editor

    private var customSurfaceEditorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Customize Theme Surface Tints")
                        .font(.system(size: 14, weight: .bold))
                    Text("Fine-tune the active theme's underlying glass colors for the main window, sidebar, and cards.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let activePreset = appearance.allThemes.first(where: { $0.id == appearance.activeThemeID }) {
                    Button("Reset to \"\(activePreset.name)\" Preset") {
                        appearance.applyThemePreset(activePreset)
                        hexDraft = activePreset.accentHex
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(appearance.accentColor)
                }
            }

            HStack(spacing: 12) {
                surfaceColorPickerCard(
                    title: "Window Base Glass",
                    subtitle: "Main backdrop tint",
                    hex: $appearance.windowTintHex
                )
                surfaceColorPickerCard(
                    title: "Sidebar & Header Glass",
                    subtitle: "Navigation panel tint",
                    hex: $appearance.sidebarTintHex
                )
                surfaceColorPickerCard(
                    title: "Bento Card Glass",
                    subtitle: "Cards & tables tint",
                    hex: $appearance.cardTintHex
                )
            }
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

    private func surfaceColorPickerCard(title: String, subtitle: String, hex: Binding<String>) -> some View {
        let colorBinding = Binding<Color>(
            get: {
                Color(nsColor: NSColor(hex: hex.wrappedValue) ?? .black)
            },
            set: { newColor in
                if let ns = NSColor(newColor).usingColorSpace(.sRGB) {
                    hex.wrappedValue = ns.toHexString()
                }
            }
        )

        return HStack(spacing: 10) {
            ColorPicker("", selection: colorBinding, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                Text("\(subtitle) · \(hex.wrappedValue)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.24))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }

    // MARK: - 3. Accent Color Section

    private var accentColorSection: some View {
        let isWallpaperAuto = (appearance.accentSource == .wallpaper)
        let accentPickerBinding = Binding<Color>(
            get: { appearance.accentColor },
            set: { newColor in
                if let ns = NSColor(newColor).usingColorSpace(.sRGB) {
                    let newHex = ns.toHexString()
                    appearance.customHex = newHex
                    appearance.accentSource = .custom
                    hexDraft = newHex
                }
            }
        )

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Accent & Neon Glow Color")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Text("\(appearance.activeAccentName) · ")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                + Text(appearance.activeHexString)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(appearance.accentColor)
            }

            Button {
                appearance.sampleDesktopWallpaperColor()
                appearance.accentSource = .wallpaper
                hexDraft = appearance.activeHexString
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        LinearGradient(
                            colors: [
                                Color(nsColor: NSColor(hex: "#0D1520") ?? .blue),
                                Color(nsColor: NSColor(hex: "#192A3E") ?? .purple),
                                appearance.accentColor
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        Circle()
                            .strokeBorder(appearance.accentColor, lineWidth: 5)
                            .frame(width: 34, height: 34)
                            .offset(x: -14, y: 8)
                    }
                    .frame(width: 72, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
                    )

                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)

                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [appearance.accentColor.opacity(0.85), appearance.accentColor],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 68, height: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto, from wallpaper")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Samples your desktop picture and builds a harmonious neon glass accent.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    ZStack {
                        Circle()
                            .fill(isWallpaperAuto ? appearance.accentColor : Color.clear)
                            .overlay(
                                Circle()
                                    .strokeBorder(isWallpaperAuto ? appearance.accentColor : Color.primary.opacity(0.25), lineWidth: 1.5)
                            )
                        if isWallpaperAuto {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.black)
                        }
                    }
                    .frame(width: 22, height: 22)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.24))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(isWallpaperAuto ? appearance.accentColor : Color.primary.opacity(0.10), lineWidth: 1.5)
                        )
                )
            }
            .buttonStyle(.plain)

            HStack {
                Text("Or pick an accent swatch (overrides or customizes the active theme's accent)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Use macOS System Accent") {
                    appearance.accentSource = .system
                    hexDraft = appearance.activeHexString
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(appearance.accentSource == .system ? appearance.accentColor : .secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 6)], spacing: 10) {
                ForEach(Array(AppearanceManager.swatches.enumerated()), id: \.element.id) { idx, swatch in
                    let isSelected = (appearance.activeHexString.caseInsensitiveCompare(swatch.hex) == .orderedSame)
                    let sColor = Color(nsColor: NSColor(hex: swatch.hex) ?? .systemGreen)

                    Button {
                        appearance.selectedSwatchIndex = idx
                        appearance.accentSource = .swatch
                        hexDraft = swatch.hex
                    } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(sColor)
                                    .frame(width: 30, height: 30)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(isSelected ? Color.white : Color.primary.opacity(0.22), lineWidth: isSelected ? 2.5 : 1)
                                    )
                                    .shadow(color: isSelected ? sColor.opacity(0.55) : .clear, radius: 6)
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.black.opacity(0.85))
                                }
                            }
                            Text(swatch.name)
                                .font(.system(size: 11))
                                .foregroundStyle(isSelected ? .primary : .secondary)
                                .lineLimit(1)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()
                .overlay(Color.primary.opacity(0.08))

            HStack(spacing: 10) {
                Text("Color wheel & hex")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)

                ColorPicker("", selection: accentPickerBinding, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 26, height: 26)

                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(appearance.accentColor)
                        .frame(width: 14, height: 14)

                    TextField("#44D492", text: $hexDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 76)
                        .onSubmit {
                            applyHexDraft()
                        }
                }
                .padding(.horizontal, 9)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.28))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                        )
                )

                Button("Apply") {
                    applyHexDraft()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.07))
                )

                Spacer()

                Button {
                    appearance.sampleDesktopWallpaperColor()
                    appearance.accentSource = .wallpaper
                    hexDraft = appearance.activeHexString
                    appState.showToast("Sampled accent \(appearance.activeHexString) from desktop wallpaper")
                } label: {
                    Text("Pick from wallpaper")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 11)
                        .frame(height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
            }

            Toggle(isOn: $appearance.tintFoldersWithAccent) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tint folders with the accent")
                        .font(.system(size: 13))
                    Text("Folder icons take the active theme's accent instead of neutral grey.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .tint(appearance.accentColor)

            Toggle(isOn: $appearance.allowPerFolderAccent) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Allow a different accent per folder")
                        .font(.system(size: 13))
                    Text("Set one from a folder's context menu, handy for telling projects apart.")
                        .font(.system(size: 12))
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
    }

    // MARK: - 4. Window Glass, Blur Material & Glow Section

    private var windowMaterialSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Translucent Glass, Blur Material & Border Glow")
                .font(.system(size: 14, weight: .bold))

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("macOS Vibrancy Blur Material")
                        .font(.system(size: 13, weight: .medium))
                    Text("Controls how the desktop wallpaper refracts through the translucent glass window.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 4) {
                    ForEach(GlassBlurStyle.allCases) { style in
                        let isSelected = (appearance.blurStyle == style)
                        Button {
                            appearance.blurStyle = style
                        } label: {
                            Text(style.rawValue)
                                .font(.system(size: 11.5, weight: isSelected ? .bold : .medium))
                                .foregroundStyle(isSelected ? Color.black.opacity(0.88) : .secondary)
                                .padding(.horizontal, 10)
                                .frame(height: 26)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(isSelected ? appearance.accentColor : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.28))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                )
            }

            HStack(spacing: 12) {
                Text("Glass Translucency (\(Int(appearance.translucency))%)")
                    .font(.system(size: 13))
                Spacer()
                Text("Solid")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Slider(value: $appearance.translucency, in: 0...100)
                    .frame(width: 210)
                    .tint(appearance.accentColor)
                Text("Deep Glass")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Text("Card Neon Border Glow (\(Int(appearance.cardGlowIntensity))%)")
                    .font(.system(size: 13))
                Spacer()
                Text("Subtle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Slider(value: $appearance.cardGlowIntensity, in: 0...100)
                    .frame(width: 210)
                    .tint(appearance.accentColor)
                Text("Vivid")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Toggle(isOn: $appearance.enableBackgroundBlur) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Blur what's behind the window")
                        .font(.system(size: 13))
                    Text("Turns off automatically when Reduce Transparency is enabled in macOS.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .tint(appearance.accentColor)

            Toggle(isOn: $appearance.enableWallpaperWash) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ambient accent radial glow across window")
                        .font(.system(size: 13))
                    Text("A soft radial light bloom of your active accent illuminates the top-left glass.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .tint(appearance.accentColor)

            HStack {
                Text("Row density")
                    .font(.system(size: 13))
                Spacer()
                HStack(spacing: 2) {
                    ForEach(RowDensity.allCases, id: \.self) { density in
                        let isSelected = (appearance.density == density)
                        Button {
                            appearance.density = density
                        } label: {
                            Text(density.rawValue)
                                .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                                .foregroundStyle(isSelected ? Color.black.opacity(0.88) : .secondary)
                                .padding(.horizontal, 12)
                                .frame(height: 26)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(isSelected ? appearance.accentColor : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.black.opacity(0.28))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                )
            }
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

    // MARK: - Right-hand Live Preview Sidebar

    private var livePreviewSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LIVE GLASS PREVIEW")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(.secondary)

            ZStack {
                LinearGradient(
                    colors: [
                        Color(nsColor: appearance.windowSurfaceNSColor),
                        Color(nsColor: appearance.sidebarSurfaceNSColor),
                        appearance.accentColor.opacity(0.35)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .strokeBorder(appearance.accentColor.opacity(0.75), lineWidth: 18)
                    .frame(width: 140, height: 140)
                    .offset(x: -85, y: 40)

                VStack(spacing: 0) {
                    HStack(spacing: 5) {
                        Circle().fill(Color(nsColor: NSColor(hex: "#FF5F57") ?? .red)).frame(width: 8, height: 8)
                        Circle().fill(Color(nsColor: NSColor(hex: "#FEBC2E") ?? .yellow)).frame(width: 8, height: 8)
                        Circle().fill(Color(nsColor: NSColor(hex: "#28C840") ?? .green)).frame(width: 8, height: 8)
                        Spacer()
                        Text("Stratum Glass")
                            .font(.system(size: 11, weight: .semibold))
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color.primary.opacity(0.09)).frame(height: 1)
                    }

                    VStack(spacing: 2) {
                        previewRow(name: "Brand Refresh", sub: "15 items", isFolder: true, isSelected: true)
                        previewRow(name: "Client Work", sub: "8 items", isFolder: true, isSelected: false)
                        previewRow(name: "Invoice 1042.pdf", sub: "84 KB", isFolder: false, isSelected: false)
                    }
                    .padding(8)

                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.primary.opacity(0.14))
                                    Capsule()
                                        .fill(appearance.accentColor)
                                        .frame(width: geo.size.width * 0.64)
                                }
                            }
                            .frame(height: 5)
                            Text("64%")
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 8) {
                            Text("Auto-Sync")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(appearance.accentColor)
                                .padding(.horizontal, 9)
                                .frame(height: 22)
                                .background(
                                    Capsule()
                                        .fill(appearance.selectionTintColor)
                                        .overlay(
                                            Capsule().strokeBorder(appearance.selectionBorderColor, lineWidth: 1)
                                        )
                                )
                            Spacer()
                            Text("Reveal")
                                .font(.system(size: 11.5))
                                .padding(.horizontal, 10)
                                .frame(height: 24)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
                                )
                            Text("Clean")
                                .font(.system(size: 11.5, weight: .bold))
                                .foregroundStyle(Color.black.opacity(0.88))
                                .padding(.horizontal, 12)
                                .frame(height: 24)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(appearance.accentColor)
                                )
                        }
                    }
                    .padding(12)
                    .overlay(alignment: .top) {
                        Rectangle().fill(Color.primary.opacity(0.09)).frame(height: 1)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(appearance.cardGlassFillColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(appearance.selectionBorderColor.opacity(0.75), lineWidth: 1.2)
                        )
                )
                .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
                .padding(.horizontal, 16)
                .padding(.vertical, 22)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            )

            Text("Every glass theme adjusts window tint, sidebar tint, card opacity, blur material, and neon border glow in real time.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                appearance.restoreDefaults()
                hexDraft = appearance.activeHexString
                appState.showToast("Restored Stratum Emerald Glass defaults")
            } label: {
                Text("Restore Stratum Emerald Glass Defaults")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 22)
        .background(appearance.sidebarGlassColor.opacity(0.65))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(width: 1)
        }
    }

    private func previewRow(name: String, sub: String, isFolder: Bool, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isFolder ? "folder.fill" : "doc")
                .font(.system(size: 13))
                .foregroundStyle(isFolder ? appearance.folderFrontColor : .secondary)
            Text(name)
                .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
            Spacer()
            Text(sub)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .frame(height: appearance.density.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? appearance.selectionTintColor : Color.clear)
        )
    }

    private func saveCustomTheme() {
        appearance.saveCurrentAsCustomTheme(named: customThemeNameDraft)
        let savedName = customThemeNameDraft.isEmpty ? "Custom Glass Theme" : customThemeNameDraft
        customThemeNameDraft = ""
        appState.showToast("Saved custom theme \"\(savedName)\"")
    }

    private func applyHexDraft() {
        let cleaned = hexDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard NSColor(hex: cleaned) != nil else {
            appState.showToast("Invalid hex color (use #RRGGBB)")
            return
        }
        appearance.customHex = cleaned.hasPrefix("#") ? cleaned.uppercased() : "#\(cleaned.uppercased())"
        appearance.accentSource = .custom
        hexDraft = appearance.customHex
    }
}
