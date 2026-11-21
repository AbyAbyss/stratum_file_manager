import SwiftUI

struct StatusBarView: View {
    @Bindable var appState: AppState
    var appearance: AppearanceManager

    var body: some View {
        HStack(spacing: 16) {
            Text(appState.displayTildePath)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)

            // The path truncates first; the summary and the free space stay whole.
            Text(appState.statusSelectionSummary)
                .font(.system(size: 11.5).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
                .layoutPriority(1)

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                if let boot = appState.bootVolume {
                    Text("\(BulkDirectoryReader.fastFormatBytes(boot.freeBytes)) available")
                        .font(.system(size: 11.5).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }

                if appState.viewMode == .grid {
                    Slider(value: $appState.iconScale, in: 1...5, step: 0.5)
                        .frame(width: 84)
                        .tint(appearance.accentColor)
                        .stratumHelp("Icon size")
                }
            }
            .layoutPriority(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .frame(minHeight: 30)
        .background(Color.black.opacity(0.16))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(height: 1)
        }
    }
}
