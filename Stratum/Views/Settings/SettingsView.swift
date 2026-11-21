import SwiftUI
import AppKit

/// The pages of Settings, in the order they appear in the left rail.
enum SettingsPageID: String, CaseIterable, Identifiable {
    case appearance = "Appearance"
    case safety = "Safety"
    case scanning = "Scanning"
    case about = "About"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .appearance: return "paintpalette.fill"
        case .safety: return "checkmark.shield.fill"
        case .scanning: return "arrow.triangle.2.circlepath"
        case .about: return "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .appearance: return Color(red: 0.36, green: 0.36, blue: 0.84)
        case .safety: return Color(red: 0.24, green: 0.61, blue: 0.31)
        case .scanning: return Color(red: 0.18, green: 0.49, blue: 0.96)
        case .about: return Color(red: 0.48, green: 0.53, blue: 0.58)
        }
    }

    var subtitle: String {
        switch self {
        case .appearance: return "Themes, accent colour and how the window looks."
        case .safety: return "What Stratum protects and when it asks first."
        case .scanning: return "Background updates, and the scan data Stratum keeps."
        case .about: return "Version, updates and the people behind Stratum."
        }
    }
}

/// Settings: a rail of pages on the left, one focused page on the right.
struct SettingsView: View {
    @Bindable var appState: AppState
    @Bindable var appearance: AppearanceManager
    var scanCoordinator = ScanCoordinator.shared

    @State private var page: SettingsPageID = .appearance
    /// In a narrow window the rail becomes a row of tabs above the page.
    @State private var isCompact = false
    @Namespace private var railNamespace

    var body: some View {
        let layout = isCompact ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        return layout {
            if isCompact { tabBar } else { rail }

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(page.rawValue)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                        Text(page.subtitle)
                            .font(.system(size: 13.5))
                            .foregroundStyle(.secondary)
                    }
                    pageContent
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, isCompact ? 20 : 36)
                .padding(.top, isCompact ? 24 : 40)
                .padding(.bottom, 44)
                .frame(maxWidth: .infinity)
                .id(page)
                .transition(.opacity.combined(with: .offset(y: 8)))
            }
            .scrollIndicators(.hidden)
            .background(Color(nsColor: .windowBackgroundColor).opacity(appearance.contentBackgroundOpacity))
        }
        .animation(.easeOut(duration: 0.2), value: page)
        .onGeometryChange(for: Bool.self) { $0.size.width < 700 } action: { isCompact = $0 }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case .appearance: SettingsAppearancePage(appState: appState, appearance: appearance)
        case .safety: SettingsSafetyPage(appState: appState, appearance: appearance)
        case .scanning: SettingsScanningPage(appState: appState, appearance: appearance)
        case .about: SettingsAboutPage(appearance: appearance)
        }
    }

    // MARK: Rail

    private var rail: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)

            ForEach(SettingsPageID.allCases) { item in
                railRow(item)
            }

            Spacer()

            Text("Stratum \(AppInfo.version)")
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12)
        }
        .padding(.horizontal, 12)
        .padding(.top, 44)
        .padding(.bottom, 18)
        .frame(maxHeight: .infinity)
        .background(appearance.sidebarGlassColor.opacity(0.55))
        .overlay(alignment: .trailing) { Rectangle().fill(Color.primary.opacity(0.07)).frame(width: 1) }
        .resizablePanel(key: "Stratum.settingsRailWidth", defaultWidth: 224, range: 190...320, edge: .trailing)
    }

    /// The rail's pages as a row of tabs, for narrow windows.
    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(SettingsPageID.allCases) { item in
                    railRow(item).fixedSize()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(appearance.sidebarGlassColor.opacity(0.55))
        .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1) }
    }

    private func railRow(_ item: SettingsPageID) -> some View {
        let isSelected = item == page
        return Button {
            page = item
        } label: {
            HStack(spacing: 11) {
                Image(systemName: item.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(item.tint.gradient))
                Text(item.rawValue)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 40)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(appearance.selectionFillColor)
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(appearance.selectionBorderColor.opacity(0.5), lineWidth: 1))
                        .matchedGeometryEffect(id: "railSelection", in: railNamespace)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
