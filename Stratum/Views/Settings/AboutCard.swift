import SwiftUI

/// Settings → About: version, update check, the project's links, and where to say thanks.
struct AboutCard: View {
    var appearance: AppearanceManager

    var body: some View {
        VStack(spacing: 14) {
            StratumIsometricLogo(size: 64, accentColor: appearance.accentColor)

            VStack(spacing: 4) {
                Text("Stratum").font(.system(size: 20, weight: .bold, design: .rounded))
                Text("Version \(AppInfo.version)").font(.system(size: 12.5)).foregroundStyle(.secondary)
                Text("A native macOS file manager and storage analyzer.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 18) {
                Link(destination: AppInfo.repository) {
                    Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                if UpdateController.shared.isAvailable {
                    Button {
                        UpdateController.shared.checkForUpdates()
                    } label: {
                        Label("Check for Updates…", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.link)
                }
            }
            .font(.system(size: 12, weight: .semibold))

            Link(destination: AppInfo.support) {
                Label("Buy me a coffee", systemImage: "cup.and.saucer.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.88))
                    .padding(.horizontal, 16)
                    .frame(height: 34)
                    .background(Capsule().fill(Color(red: 1, green: 0.867, blue: 0)))   // Buy Me a Coffee yellow
                    .contentShape(Capsule())
            }
            .accessibilityHint("Opens the support page in your browser")

            HStack(spacing: 4) {
                Text("Made by")
                Link(AppInfo.authorName, destination: AppInfo.author)
            }
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(appearance.cardGlassFillColor)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        )
    }
}
