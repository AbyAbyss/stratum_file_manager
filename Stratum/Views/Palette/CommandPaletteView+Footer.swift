import SwiftUI
import AppKit

extension CommandPaletteView {
    // MARK: - Footer Bar

    var footerBar: some View {
        HStack {
            HStack(spacing: 14) {
                Text("↑↓ navigate")
                Text("↵ open")
                Text("Type > for commands, # for tags, / to jump to a path")
            }
            Spacer()
            Text("\(totalResultCount) \(totalResultCount == 1 ? "result" : "results")")
                .monospacedDigit()
        }
        .font(.system(size: 11.5))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.22))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
        }
    }
}
