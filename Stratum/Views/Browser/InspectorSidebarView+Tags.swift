import SwiftUI
import AppKit

extension InspectorSidebarView {
    // MARK: - Tags Section (True Wrapping FlowLayout so tags never clip or truncate!)

    func tagsSection(for item: FileItem) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Tags")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            TagWrappingFlowLayout(spacing: 6) {
                ForEach(item.tags) { tag in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(nsColor: NSColor(hex: tag.hexColor) ?? .systemBlue))
                            .frame(width: 8, height: 8)
                        Text(tag.name)
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 25)
                    .background(
                        Capsule()
                            .fill(Color.primary.opacity(0.07))
                            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.09), lineWidth: 1))
                    )
                    .contentShape(Capsule())
                    .onTapGesture {
                        appState.toggleTag(tag, on: item)
                    }
                }

                Button {
                    showTagPopover = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text("Add tag")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .frame(height: 25)
                    .background(
                        Capsule()
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                            .foregroundStyle(Color.primary.opacity(0.22))
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showTagPopover) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Toggle Tags")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        ForEach(FinderTag.presets) { preset in
                            let isAssigned = item.tags.contains(where: { $0.name.caseInsensitiveCompare(preset.name) == .orderedSame })
                            Button {
                                appState.toggleTag(preset, on: item)
                            } label: {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Color(nsColor: NSColor(hex: preset.hexColor) ?? .systemBlue))
                                        .frame(width: 9, height: 9)
                                    Text(preset.name)
                                        .font(.system(size: 12.5))
                                    Spacer()
                                    if isAssigned {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 11, weight: .bold))
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(width: 160)
                    .padding(10)
                }
            }
        }
    }
}
