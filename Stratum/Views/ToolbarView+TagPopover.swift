import SwiftUI
import AppKit

extension ToolbarView {
    var toolbarTagPopoverContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Assign Tag to Selection")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            ForEach(FinderTag.presets) { preset in
                Button {
                    let targets = appState.selectedItems
                    for item in targets {
                        appState.toggleTag(preset, on: item)
                    }
                    showToolbarTagsPopover = false
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(nsColor: NSColor(hex: preset.hexColor) ?? .systemBlue))
                            .frame(width: 9, height: 9)
                        Text(preset.name)
                            .font(.system(size: 12.5))
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(StratumInteractiveButtonStyle())
            }
        }
        .frame(width: 170)
        .padding(10)
    }
}
