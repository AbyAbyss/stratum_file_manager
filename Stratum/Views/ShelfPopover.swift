import SwiftUI
import AppKit

/// The toolbar's view of the shelf: what is parked, and copy or move it all into the current folder.
struct ShelfPopover: View {
    var appState: AppState
    var appearance: AppearanceManager
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Shelf")
                    .font(.system(size: 13, weight: .semibold))
                Text("\(appState.shelfURLs.count) parked")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") {
                    appState.shelfURLs.removeAll()
                    isPresented = false
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(appState.shelfURLs, id: \.path) { url in
                        row(url)
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 260)

            Divider()

            HStack(spacing: 8) {
                dropButton("Copy Here", icon: "doc.on.doc", filled: false, move: false)
                dropButton("Move Here", icon: "arrow.right.doc.on.clipboard", filled: true, move: true)
            }
            .padding(10)

            Text("Into \u{201C}\(appState.currentFolderTitle)\u{201D}")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 10)
        }
        .frame(width: 320)
    }

    private func row(_ url: URL) -> some View {
        HStack(spacing: 9) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(url.deletingLastPathComponent().path)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 4)
            Button {
                appState.removeFromShelf(url)
                if appState.shelfURLs.isEmpty { isPresented = false }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .stratumHelp("Take off the shelf")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func dropButton(_ title: String, icon: String, filled: Bool, move: Bool) -> some View {
        Button {
            isPresented = false
            appState.dropAllShelfItems(into: appState.currentURL, move: move)
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(filled ? .white : appearance.accentColor)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background {
                    let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
                    if filled { shape.fill(appearance.accentColor) } else { shape.strokeBorder(appearance.accentColor.opacity(0.6), lineWidth: 1) }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(StratumInteractiveButtonStyle())
    }
}
