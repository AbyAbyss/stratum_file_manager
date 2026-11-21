import SwiftUI

extension ToolbarView {
    /// Updates, the welcome tour, and the project's support links, one click from anywhere.
    var helpMenu: some View {
        Menu {
            if density == .minimal {
                Button("Open in Terminal", systemImage: "terminal") {
                    TerminalLauncher.openInTerminal(url: appState.currentURL)
                }
                Button("Smart Clean & Organizer", systemImage: "wand.and.stars") { toggleOrganizer() }
                Button("Share…", systemImage: "square.and.arrow.up") { shareSelectedItems() }
                Button("Tags…", systemImage: "tag") { showToolbarTagsPopover = true }
                Menu("Theme", systemImage: "paintpalette") { themeMenuItems }

                Divider()
            }
            if UpdateController.shared.isAvailable {
                Button("Check for Updates…", systemImage: "arrow.triangle.2.circlepath") {
                    UpdateController.shared.checkForUpdates()
                }
            }
            Link(destination: AppInfo.releases) { Label("What's New", systemImage: "sparkles") }
            Button("New Window", systemImage: "macwindow.badge.plus") {
                openWindow(value: WindowSeed(path: appState.currentURL.path))
            }
            Button("Welcome Tour", systemImage: "play.circle") {
                appState.startWalkthrough()
            }

            Divider()

            Link(destination: AppInfo.support) { Label("Buy Me a Coffee", systemImage: "cup.and.saucer") }
            Link(destination: AppInfo.repository) { Label("Star on GitHub", systemImage: "star") }
            Link(destination: AppInfo.newIssue) { Label("Report an Issue", systemImage: "ladybug") }

            Divider()

            Button("Settings…", systemImage: "gearshape") { openSettings() }
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
        .stratumHelp(density == .minimal ? "More actions, updates and links" : "Updates, support and links")
    }
}
