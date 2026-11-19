import SwiftUI
import AppKit

extension InspectorSidebarView {
    // MARK: - Versions Section

    func versionsSection(for item: FileItem) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Versions")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 9) {
                Circle()
                    .fill(appearance.accentColor)
                    .frame(width: 8, height: 8)
                Text("Current version")
                    .font(.system(size: 12))
                Spacer()
                Text(item.formattedModDate)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(fileVersions.prefix(3).enumerated()), id: \.offset) { _, ver in
                HStack(spacing: 9) {
                    Circle()
                        .strokeBorder(Color.secondary, lineWidth: 1.5)
                        .frame(width: 8, height: 8)
                    Text(ver.localizedNameOfSavingComputer ?? "Earlier version")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button("Restore") {
                        restoreVersion(ver, to: item.url)
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                }
            }
        }
    }
}
