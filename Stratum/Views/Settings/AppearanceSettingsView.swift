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
        case about = "About"

        var id: String { rawValue }
    }

    @State var activeTab: SettingsTab = .all
    @State var hexDraft: String = "#44D492"
    @State var customThemeNameDraft: String = ""
    @State var newProtectedPathDraft: String = ""
    @State var userProtectedPaths: [String] = ProtectedPaths.loadUserPaths()

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

                    if activeTab == .all || activeTab == .about {
                        AboutCard(appearance: appearance)
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

}
