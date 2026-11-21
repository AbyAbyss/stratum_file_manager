import Foundation
import AppKit
import SwiftUI

extension AppState {
    // MARK: - Shelf Support

    func addToShelf(_ urls: [URL]) {
        for url in urls where !shelfURLs.contains(url) {
            shelfURLs.append(url)
        }
        if !urls.isEmpty {
            showToast("Parked \(urls.count) \(urls.count == 1 ? "item" : "items") on Shelf")
        }
    }

    func removeFromShelf(_ url: URL) {
        shelfURLs.removeAll(where: { $0 == url })
    }

    /// Copies (or moves) everything on the shelf into a folder and empties the shelf.
    func dropAllShelfItems(into destinationFolder: URL, move: Bool = false) {
        // Moving a file into the folder it is already in would only rename it.
        let itemsToCopy = move
            ? shelfURLs.filter { $0.deletingLastPathComponent().standardizedFileURL != destinationFolder.standardizedFileURL }
            : shelfURLs
        shelfURLs.removeAll()
        guard !itemsToCopy.isEmpty else { return }
        TransferQueueEngine.shared.enqueueTransfer(
            kind: move ? .move : .copy,
            sourceURLs: itemsToCopy,
            to: destinationFolder,
            conflictPolicy: .keepBoth
        ) { [weak self] in
            self?.reloadCurrentDirectory(preserveSelection: true)
            self?.showToast("\(move ? "Moved" : "Copied") \(itemsToCopy.count) Shelf \(itemsToCopy.count == 1 ? "item" : "items") into \(destinationFolder.lastPathComponent)")
        }
    }

    func startWalkthrough() {
        withAnimation(.easeOut(duration: 0.3)) { showWalkthrough = true }
    }

    func finishWalkthrough() {
        showStartupSplash = false   // the tour was the welcome; don't play the splash right after it
        withAnimation(.easeOut(duration: 0.25)) { showWalkthrough = false }
    }

    func replayStartupSplash() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            showStartupSplash = true
        }
    }

    func showToast(_ text: String) {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
            toastMessage = text
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if self.toastMessage == text {
                withAnimation(.easeInOut(duration: 0.25)) {
                    self.toastMessage = nil
                }
            }
        }
    }
}
