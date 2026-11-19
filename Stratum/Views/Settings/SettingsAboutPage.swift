import SwiftUI

/// About: version, updates, and where to find the project and say thanks.
struct SettingsAboutPage: View {
    var appearance: AppearanceManager

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(spacing: 10) {
                StratumIsometricLogo(size: 84, accentColor: appearance.accentColor)
                Text("Stratum")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("Version \(AppInfo.version)")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Text("A native macOS file manager and storage analyzer.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)

            SettingsGroup("Updates", appearance: appearance) {
                if UpdateController.shared.isAvailable {
                    SettingsRow("Check for updates", detail: "Stratum can also check by itself once you allow it.") {
                        SettingsButton(title: "Check now", systemImage: "arrow.triangle.2.circlepath", kind: .primary, appearance: appearance) {
                            UpdateController.shared.checkForUpdates()
                        }
                    }
                } else {
                    SettingsRow("Updates", detail: "This build has no update key, so it can't update itself. Download the latest release from GitHub.") {
                        Link("Releases", destination: AppInfo.repository.appendingPathComponent("releases/latest"))
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
            }

            SettingsGroup("Project", footer: "MIT licensed. Copyright © 2026 \(AppInfo.authorName).", appearance: appearance) {
                SettingsRow("Source code", detail: "Read it, report a bug, or star the repo.") {
                    Link(destination: AppInfo.repository) {
                        Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                SettingsDivider()
                SettingsRow("Made by \(AppInfo.authorName)") {
                    Link(destination: AppInfo.author) {
                        Label("Website", systemImage: "globe").font(.system(size: 13, weight: .semibold))
                    }
                }
                SettingsDivider()
                SettingsRow("Support Stratum", detail: "Stratum is free. If it saves you time, a coffee keeps the updates coming.") {
                    Link(destination: AppInfo.support) {
                        Label("Buy me a coffee", systemImage: "cup.and.saucer.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.88))
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(Capsule().fill(Color(red: 1, green: 0.867, blue: 0)))
                            .contentShape(Capsule())
                    }
                    .accessibilityHint("Opens the support page in your browser")
                }
            }
        }
    }
}
