import SwiftUI
import AppKit

extension InspectorSidebarView {
    // MARK: - Helpers

    func loadInspectorDetails(for item: FileItem) {
        previewThumbnail = nil
        textSnippet = nil
        fileVersions = []
        posixPermissionString = ""
        appVersionString = ""
        appBundleIDString = ""
        isExecutableFile = false

        let targetURL = item.url
        let targetID = item.id

        if item.isImageOrVideo {
            let size = CGSize(width: 400, height: 264)
            if let cached = IconPipeline.shared.cachedThumbnail(for: item.id, size: size) {
                previewThumbnail = cached
            } else {
                IconPipeline.shared.requestThumbnail(for: item, size: size) { img in
                    if self.item?.id == targetID {
                        self.previewThumbnail = img
                    }
                }
            }
        }

        DispatchQueue.global(qos: .utility).async {
            // Read App Bundle metadata if package
            var verText = ""
            var bundleIDText = ""
            if item.isAppOrPackage, let bundle = Bundle(url: targetURL), let info = bundle.infoDictionary {
                verText = (info["CFBundleShortVersionString"] as? String) ?? (info["CFBundleVersion"] as? String) ?? ""
                bundleIDText = bundle.bundleIdentifier ?? ""
            }

            // Read POSIX permissions
            var permText = ""
            var isExec = false
            if let attrs = try? FileManager.default.attributesOfItem(atPath: targetURL.path),
               let p = attrs[.posixPermissions] as? Int {
                isExec = (p & 0o111) != 0
                permText = Self.formatPosixMode(p)
            }

            // Read text snippet if applicable
            var snippet: String? = nil
            if item.isTextPreviewable && !item.isDataless && item.size > 0 && item.size < 2_000_000 {
                if let fh = try? FileHandle(forReadingFrom: targetURL) {
                    let data = (try? fh.read(upToCount: 1200)) ?? Data()
                    try? fh.close()
                    if let str = String(data: data, encoding: .utf8) {
                        snippet = str.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }

            let versions = (!item.isFolderLike && !item.isDataless)
                ? (NSFileVersion.otherVersionsOfItem(at: targetURL) ?? [])
                : []

            Task { @MainActor in
                guard self.item?.id == targetID else { return }
                self.posixPermissionString = permText
                self.appVersionString = verText
                self.appBundleIDString = bundleIDText
                self.isExecutableFile = isExec
                self.textSnippet = snippet
                self.fileVersions = versions
            }
        }
    }

    nonisolated static func formatPosixMode(_ mode: Int) -> String {
        let chars: [(Int, Character)] = [
            (0o400, "r"), (0o200, "w"), (0o100, "x"),
            (0o040, "r"), (0o020, "w"), (0o010, "x"),
            (0o004, "r"), (0o002, "w"), (0o001, "x")
        ]
        let symbolic = String(chars.map { (mode & $0.0) != 0 ? $0.1 : "-" })
        let octal = String(format: "%03o", mode & 0o777)
        return "\(symbolic) (\(octal))"
    }

    func performSingleRename(item: FileItem, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != item.name else { return }
        let destURL = item.url.deletingLastPathComponent().appendingPathComponent(trimmed)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try FileManager.default.moveItem(at: item.url, to: destURL)
                Task { @MainActor in
                    appState.selectedItemIDs = [destURL.path]
                    appState.reloadCurrentDirectory(preserveSelection: true)
                }
            } catch {
                Task { @MainActor in
                    appState.showToast("Rename failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func compressItem(_ item: FileItem) {
        let sourceURL = item.url
        let parentDir = sourceURL.deletingLastPathComponent()
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let zipURL = parentDir.appendingPathComponent("\(baseName).zip")
        DispatchQueue.global(qos: .userInitiated).async {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            proc.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", sourceURL.path, zipURL.path]
            try? proc.run()
            proc.waitUntilExit()
            Task { @MainActor in
                appState.selectedItemIDs = [zipURL.path]
                appState.reloadCurrentDirectory(preserveSelection: true)
                appState.showToast("Compressed \(zipURL.lastPathComponent)")
            }
        }
    }

    func restoreVersion(_ version: NSFileVersion, to url: URL) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                _ = try version.replaceItem(at: url, options: [])
                Task { @MainActor in
                    appState.reloadCurrentDirectory(preserveSelection: true)
                    appState.showToast("Restored earlier version")
                }
            } catch {
                Task { @MainActor in
                    appState.showToast("Restore failed: \(error.localizedDescription)")
                }
            }
        }
    }
}
