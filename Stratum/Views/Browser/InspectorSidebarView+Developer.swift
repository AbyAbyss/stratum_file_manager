import SwiftUI
import AppKit

extension InspectorSidebarView {
    // MARK: - Developer & Quick Actions Section

    func developerToolsSection(for item: FileItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tools")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            if item.isFolderLike {
                HStack(spacing: 6) {
                    smallActionPill("Scan Storage", icon: "chart.pie") {
                        appState.scanFolder(item.url, inScreen: .storage)
                    }
                    smallActionPill("Open in New Tab", icon: "plus.square.on.square") {
                        appState.addNewTab(at: item.url)
                    }
                }
            } else {
                HStack(spacing: 6) {
                    smallActionPill("Copy SHA-256", icon: "number.square") {
                        appState.computeSHA256(for: item.url)
                    }
                    smallActionPill(isExecutableFile ? "Remove +x" : "chmod +x", icon: "bolt.horizontal.circle") {
                        appState.toggleExecutableBit(for: item.url)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            loadInspectorDetails(for: item)
                        }
                    }
                }
            }
        }
    }

    func smallActionPill(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 27)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
