import SwiftUI

extension ToolbarView {
    /// Updates, the welcome tour, and the project's support links, one click from anywhere.
    var helpMenu: some View {
        Menu {
            if UpdateController.shared.isAvailable {
                Button("Check for Updates…", systemImage: "arrow.triangle.2.circlepath") {
                    UpdateController.shared.checkForUpdates()
                }
            }
            Link(destination: AppInfo.releases) { Label("What's New", systemImage: "sparkles") }
            Button("Welcome Tour", systemImage: "play.circle") {
                appState.startWalkthrough()
            }

            Divider()

            Link(destination: AppInfo.support) { Label("Buy Me a Coffee", systemImage: "cup.and.saucer") }
            Link(destination: AppInfo.repository) { Label("Star on GitHub", systemImage: "star") }
            Link(destination: AppInfo.newIssue) { Label("Report an Issue", systemImage: "ladybug") }

            Divider()

            Button("Settings…", systemImage: "gearshape") {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) { appState.screen = .settings }
            }
            Link(destination: AppInfo.author) { Label("Made by \(AppInfo.authorName)", systemImage: "person.crop.circle") }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 30, height: 30)
        .stratumHelp("Updates, support and links")
    }
}
