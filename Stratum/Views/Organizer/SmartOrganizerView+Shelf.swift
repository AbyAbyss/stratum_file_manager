import SwiftUI
import AppKit
import CryptoKit

extension SmartOrganizerView {
    // MARK: - Mode 3: Drop Shelf & Batch Stash

    var dropShelfStudioSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Drop Shelf (\(appState.shelfURLs.count) items parked)")
                        .font(.system(size: 16, weight: .bold))
                    Text("Park files from any folder (Right-Click → Park on Drop Shelf, or drag files below) and move, copy, or zip them all at once.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !appState.shelfURLs.isEmpty {
                    Button {
                        appState.dropAllShelfItems(into: appState.currentURL)
                    } label: {
                        Label("Copy All to \(appState.currentFolderTitle)", systemImage: "arrow.down.doc.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(appearance.accentColor))
                    }
                    .buttonStyle(StratumInteractiveButtonStyle())

                    Button("Clear Shelf") {
                        appState.shelfURLs.removeAll()
                    }
                    .buttonStyle(StratumInteractiveButtonStyle())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                }
            }

            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isDropTargetedOnShelf ? appearance.faintTintColor : Color.primary.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                isDropTargetedOnShelf ? appearance.accentColor : Color.primary.opacity(0.14),
                                style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                            )
                    )

                if appState.shelfURLs.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(.secondary)
                        Text("Drag and drop files here from Finder or Browser to park them on the Shelf")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 54)
                } else {
                    VStack(spacing: 6) {
                        ForEach(appState.shelfURLs, id: \.path) { url in
                            HStack(spacing: 10) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                    .resizable()
                                    .frame(width: 22, height: 22)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(url.lastPathComponent)
                                        .font(.system(size: 13, weight: .medium))
                                    Text(url.deletingLastPathComponent().path)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Reveal") {
                                    appState.navigate(to: url.deletingLastPathComponent())
                                    appState.selectedItemIDs = [url.path]
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(appearance.accentColor)

                                Button {
                                    appState.removeFromShelf(url)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.04)))
                        }
                    }
                    .padding(14)
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isDropTargetedOnShelf) { providers in
                for provider in providers {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        guard let url else { return }
                        Task { @MainActor in
                            appState.addToShelf([url])
                        }
                    }
                }
                return true
            }
        }
    }
}
