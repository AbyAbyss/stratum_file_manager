import Foundation
import AppKit
import SwiftUI
import CryptoKit

extension AppState {
    // MARK: - File Operations (Milestone 2 + Power User Actions)

    func createNewFolder() {
        let baseDir = currentURL
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let fm = FileManager.default
            var name = "untitled folder"
            var candidate = baseDir.appendingPathComponent(name)
            var counter = 2
            while fm.fileExists(atPath: candidate.path) {
                name = "untitled folder \(counter)"
                candidate = baseDir.appendingPathComponent(name)
                counter += 1
            }
            do {
                try fm.createDirectory(at: candidate, withIntermediateDirectories: false)
                Task { @MainActor in
                    guard let self else { return }
                    self.selectedItemIDs = [candidate.path]
                    self.reloadCurrentDirectory(preserveSelection: true)
                    ScanCoordinator.shared.notifyFileSystemMutation(near: candidate)
                    self.showToast("Created \(name)")
                }
            } catch {
                Task { @MainActor in
                    self?.showToast("Could not create folder: \(error.localizedDescription)")
                }
            }
        }
    }

    func createNewFolderWithSelection() {
        let selectedURLs = selectedItems.map(\.url)
        guard !selectedURLs.isEmpty else {
            createNewFolder()
            return
        }
        let baseDir = currentURL
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let fm = FileManager.default
            var name = "New Folder with Items"
            var candidate = baseDir.appendingPathComponent(name)
            var counter = 2
            while fm.fileExists(atPath: candidate.path) {
                name = "New Folder with Items \(counter)"
                candidate = baseDir.appendingPathComponent(name)
                counter += 1
            }
            do {
                try fm.createDirectory(at: candidate, withIntermediateDirectories: false)
                var movedCount = 0
                for src in selectedURLs {
                    let dst = candidate.appendingPathComponent(src.lastPathComponent)
                    try? fm.moveItem(at: src, to: dst)
                    movedCount += 1
                }
                Task { @MainActor in
                    guard let self else { return }
                    self.selectedItemIDs = [candidate.path]
                    self.reloadCurrentDirectory(preserveSelection: true)
                    ScanCoordinator.shared.notifyFileSystemMutation(near: candidate)
                    self.showToast("Grouped \(movedCount) \(movedCount == 1 ? "item" : "items") into \(name)")
                }
            } catch {
                Task { @MainActor in
                    self?.showToast("Could not create folder: \(error.localizedDescription)")
                }
            }
        }
    }

    func createNewFile(baseName: String, ext: String, contents: String = "") {
        let baseDir = currentURL
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let fm = FileManager.default
            let suffix = ext.isEmpty ? "" : ".\(ext)"
            var name = "\(baseName)\(suffix)"
            var candidate = baseDir.appendingPathComponent(name)
            var counter = 2
            while fm.fileExists(atPath: candidate.path) {
                name = "\(baseName) \(counter)\(suffix)"
                candidate = baseDir.appendingPathComponent(name)
                counter += 1
            }
            do {
                try Data(contents.utf8).write(to: candidate, options: .atomic)
                if ext == "sh" {
                    try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: candidate.path)
                }
                Task { @MainActor in
                    guard let self else { return }
                    self.selectedItemIDs = [candidate.path]
                    self.reloadCurrentDirectory(preserveSelection: true)
                    ScanCoordinator.shared.notifyFileSystemMutation(near: candidate)
                    self.showToast("Created \(name)")
                }
            } catch {
                Task { @MainActor in
                    self?.showToast("Could not create file: \(error.localizedDescription)")
                }
            }
        }
    }

    func computeSHA256(for url: URL) {
        showToast("Calculating SHA-256 for \(url.lastPathComponent)…")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
                Task { @MainActor in
                    self?.showToast("Could not read \(url.lastPathComponent) for checksum")
                }
                return
            }
            let digest = SHA256.hash(data: data)
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            Task { @MainActor in
                TerminalLauncher.copyPathToPasteboard(hex)
                self?.showToast("SHA-256 copied: \(hex.prefix(16))…")
            }
        }
    }

    func toggleExecutableBit(for url: URL) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let fm = FileManager.default
            guard let attrs = try? fm.attributesOfItem(atPath: url.path),
                  let perms = attrs[.posixPermissions] as? Int else {
                return
            }
            let isExec = (perms & 0o111) != 0
            let newPerms = isExec ? (perms & ~0o111) : (perms | 0o111)
            try? fm.setAttributes([.posixPermissions: newPerms], ofItemAtPath: url.path)
            Task { @MainActor in
                self?.reloadCurrentDirectory(preserveSelection: true)
                self?.showToast(isExec ? "Removed executable permission (-x)" : "Marked executable (chmod +x)")
            }
        }
    }

    func copySelectionToClipboard() {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        clipboardURLs = urls
        clipboardIsMove = false
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(urls as [NSURL])
        clipboardChangeCount = pb.changeCount
        showToast("Copied \(urls.count) \(urls.count == 1 ? "item" : "items")")
    }

    func cutSelectionToClipboard() {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        clipboardURLs = urls
        clipboardIsMove = true
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(urls as [NSURL])
        clipboardChangeCount = pb.changeCount
        showToast("Ready to move \(urls.count) \(urls.count == 1 ? "item" : "items")")
    }

    func pasteIntoCurrentFolder(forceMove: Bool = false) {
        let pb = NSPasteboard.general
        // Something was copied elsewhere (in Finder, say) after Stratum's own copy: paste that.
        if pb.changeCount != clipboardChangeCount {
            clipboardURLs = []
            clipboardIsMove = false
        }
        var urls = clipboardURLs
        if urls.isEmpty {
            if let read = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] {
                urls = read
            }
        }
        guard !urls.isEmpty else { return }
        let kind: TransferKind = (forceMove || clipboardIsMove) ? .move : .copy
        let dest = currentURL
        if kind == .move {
            clipboardURLs = []
            clipboardIsMove = false
        }
        TransferQueueEngine.shared.enqueueTransfer(
            kind: kind,
            sourceURLs: urls,
            to: dest,
            conflictPolicy: .keepBoth
        ) { [weak self] in
            self?.reloadCurrentDirectory(preserveSelection: true)
            self?.showToast("\(kind == .move ? "Moved" : "Pasted") \(urls.count) \(urls.count == 1 ? "item" : "items")")
        }
    }

    func duplicateSelection() {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        let dest = currentURL
        TransferQueueEngine.shared.enqueueTransfer(
            kind: .copy,
            sourceURLs: urls,
            to: dest,
            conflictPolicy: .keepBoth
        ) { [weak self] in
            self?.reloadCurrentDirectory(preserveSelection: true)
            self?.showToast("Duplicated \(urls.count) \(urls.count == 1 ? "item" : "items")")
        }
    }

    func compressSelection() {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        let dest = currentURL
        TransferQueueEngine.shared.enqueueTransfer(
            kind: .compress,
            sourceURLs: urls,
            to: dest,
            conflictPolicy: .keepBoth
        ) { [weak self] in
            self?.reloadCurrentDirectory(preserveSelection: true)
            self?.showToast("Compressed \(urls.count) \(urls.count == 1 ? "item" : "items")")
        }
    }

    func moveSelectionToTrash() {
        let items = selectedItems
        guard !items.isEmpty else { return }
        moveURLsToTrash(items.map { (url: $0.url, size: $0.size) })
    }

    func deleteSelectionImmediately() {
        let items = selectedItems
        guard !items.isEmpty else { return }
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Delete \(items.count) \(items.count == 1 ? "item" : "items") immediately?"
        alert.informativeText = "These items will be permanently deleted and cannot be restored from the Trash."
        alert.addButton(withTitle: "Delete Immediately")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let urls = items.map(\.url)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let fm = FileManager.default
            var deletedCount = 0
            for url in urls where !ProtectedPaths.isProtected(url.path) {
                if (try? fm.removeItem(at: url)) != nil {
                    deletedCount += 1
                }
            }
            Task { @MainActor in
                self?.selectedItemIDs = []
                self?.reloadCurrentDirectory(preserveSelection: false)
                self?.refreshVolumes()
                ScanCoordinator.shared.notifyFileSystemMutation(near: self?.currentURL)
                self?.showToast("Permanently deleted \(deletedCount) \(deletedCount == 1 ? "item" : "items")")
            }
        }
    }

    func moveURLsToTrash(_ targets: [(url: URL, size: Int64)]) {
        guard !targets.isEmpty else { return }
        let deleteItems = targets.map { DeleteTargetItem(path: $0.url.path, sizeBytes: $0.size) }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcome = DeleteService.moveToTrash(deleteItems)
            Task { @MainActor in
                guard let self else { return }
                TransferQueueEngine.shared.recordTrashOutcome(outcome)
                self.selectedItemIDs.subtract(outcome.removedPaths)
                self.reloadCurrentDirectory(preserveSelection: true)
                self.refreshVolumes()
                ScanCoordinator.shared.notifyFileSystemMutation(near: targets.first?.url)
                if !outcome.removed.isEmpty {
                    let count = outcome.removed.count
                    self.showToast("Moved \(count) \(count == 1 ? "item" : "items") to Trash (⌘Z to Undo)")
                } else if let err = outcome.failed.first?.reason {
                    self.showToast("Cannot move to Trash: \(err)")
                }
            }
        }
    }

    func undoLastTrash() {
        guard let last = TransferQueueEngine.shared.trashHistory.first else {
            showToast("Nothing to undo in Trash history")
            return
        }
        TransferQueueEngine.shared.undoTrashRecord(last) { [weak self] in
            self?.reloadCurrentDirectory(preserveSelection: true)
            self?.refreshVolumes()
            ScanCoordinator.shared.notifyFileSystemMutation(near: self?.currentURL)
            self?.showToast("Restored \(last.itemCount) \(last.itemCount == 1 ? "item" : "items") from Trash")
        }
    }

    func handleDroppedURLs(_ urls: [URL], into destinationFolder: URL, isMove: Bool) {
        let validURLs = urls.filter { $0.standardizedFileURL != destinationFolder.standardizedFileURL }
        guard !validURLs.isEmpty else { return }
        let kind: TransferKind = isMove ? .move : .copy
        TransferQueueEngine.shared.enqueueTransfer(
            kind: kind,
            sourceURLs: validURLs,
            to: destinationFolder,
            conflictPolicy: .keepBoth
        ) { [weak self] in
            self?.reloadCurrentDirectory(preserveSelection: true)
            self?.showToast("\(isMove ? "Moved" : "Copied") \(validURLs.count) \(validURLs.count == 1 ? "item" : "items") to \(destinationFolder.lastPathComponent)")
        }
    }
}
