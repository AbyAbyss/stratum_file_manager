import SwiftUI
import AppKit

struct InspectorSidebarView: View {
    @Bindable var appState: AppState
    var appearance: AppearanceManager

    @State private var previewThumbnail: NSImage?
    @State private var textSnippet: String?
    @State private var posixPermissionString: String = ""
    @State private var appVersionString: String = ""
    @State private var appBundleIDString: String = ""
    @State private var isExecutableFile: Bool = false
    @State private var showTagPopover = false
    @State private var showRenamePopover = false
    @State private var renameDraft = ""
    @State private var fileVersions: [NSFileVersion] = []

    private var item: FileItem? {
        appState.primarySelectedItem
    }

    var body: some View {
        ScrollView {
            if let item {
                VStack(alignment: .leading, spacing: 14) {
                    previewCard(for: item)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name)
                            .font(.system(size: 16, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(item.kindDescription)\(appVersionString.isEmpty ? "" : " · v\(appVersionString)")\((item.isPackage && item.size == 0) ? "" : " · \(item.isFolderLike ? item.subtitleText : item.formattedSize)")")
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    actionButtonsGrid(for: item)

                    metadataCard(for: item)

                    tagsSection(for: item)

                    developerToolsSection(for: item)

                    versionsSection(for: item)
                }
                .padding(14)
                .onChange(of: item.id, initial: true) { _, _ in
                    loadInspectorDetails(for: item)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("No item selected")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 300)
                .padding(14)
            }
        }
        .frame(width: 306)
        .background(Color.primary.opacity(0.025))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1)
        }
    }

    // MARK: - Preview Card (with live Code/Text Snippet Preview!)

    private func previewCard(for item: FileItem) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.26))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )

            if item.isAppOrPackage {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [appearance.accentColor.opacity(0.28), .clear],
                                center: .center,
                                startRadius: 4,
                                endRadius: 68
                            )
                        )
                        .frame(width: 136, height: 136)

                    Image(nsImage: IconPipeline.shared.icon(for: item))
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 96, height: 96)
                        .shadow(color: .black.opacity(0.42), radius: 14, y: 6)
                }
            } else if item.isFolderLike {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(appearance.folderBackColor)
                        .frame(width: 56, height: 26)
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(appearance.folderFrontColor)
                        .frame(width: 132, height: 89)
                        .offset(y: 15)
                        .shadow(color: .black.opacity(0.38), radius: 14, y: 6)
                }
                .frame(width: 132, height: 104)
            } else if item.isImageOrVideo {
                ZStack {
                    if let thumb = previewThumbnail {
                        Image(nsImage: thumb)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 220, height: 142)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color(nsColor: NSColor(hex: item.badgeTintHex) ?? .systemBlue).opacity(0.45))
                            .frame(width: 220, height: 142)
                    }
                    if item.isVideo {
                        Circle()
                            .fill(Color.black.opacity(0.7))
                            .frame(width: 42, height: 42)
                            .overlay {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.white)
                                    .offset(x: 1)
                            }
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.95), lineWidth: 2.5)
                )
                .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
            } else if let snippet = textSnippet, !snippet.isEmpty {
                // Live Code / Text File Preview inside the Inspector!
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(item.displayExt)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color(nsColor: NSColor(hex: item.badgeTintHex) ?? .darkGray))
                            )
                        Spacer()
                        Text("Live Preview")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Text(snippet)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.primary.opacity(0.88))
                        .lineLimit(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
            } else {
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: NSColor(hex: "#EFEDF6") ?? .white))
                        .frame(width: 100, height: 132)
                        .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
                        .overlay(alignment: .topLeading) {
                            VStack(alignment: .leading, spacing: 7) {
                                Capsule().fill(Color(nsColor: NSColor(hex: "#9F9AB5") ?? .gray)).frame(width: 50, height: 7)
                                Capsule().fill(Color(nsColor: NSColor(hex: "#C9C5D8") ?? .lightGray)).frame(width: 72, height: 4)
                                Capsule().fill(Color(nsColor: NSColor(hex: "#C9C5D8") ?? .lightGray)).frame(width: 72, height: 4)
                                Capsule().fill(Color(nsColor: NSColor(hex: "#C9C5D8") ?? .lightGray)).frame(width: 60, height: 4)
                                Capsule().fill(Color(nsColor: NSColor(hex: "#C9C5D8") ?? .lightGray)).frame(width: 40, height: 4)
                            }
                            .padding(.horizontal, 14)
                            .padding(.top, 18)
                        }

                    Text(item.displayExt)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color(nsColor: NSColor(hex: item.badgeTintHex) ?? .darkGray))
                        )
                        .offset(x: -10, y: -14)
                }
            }
        }
        .frame(height: 168)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            appState.openItem(item)
        }
    }

    // MARK: - Action Buttons Grid (2x4 Quick Actions)

    private func actionButtonsGrid(for item: FileItem) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Button {
                    appState.openItem(item)
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Open")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(appearance.accentColor)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                inspectorTileButton(title: "Preview", icon: "eye") {
                    QuickLookCoordinator.shared.togglePreview(for: [item.url])
                }

                Button {
                    renameDraft = item.name
                    showRenamePopover = true
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: "pencil")
                            .font(.system(size: 13, weight: .medium))
                        Text("Rename")
                            .font(.system(size: 11))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showRenamePopover) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Rename Item")
                            .font(.system(size: 12, weight: .semibold))
                        TextField("New name", text: $renameDraft)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                            .onSubmit {
                                performSingleRename(item: item, newName: renameDraft)
                                showRenamePopover = false
                            }
                        HStack {
                            Spacer()
                            Button("Cancel") { showRenamePopover = false }
                            Button("Rename") {
                                performSingleRename(item: item, newName: renameDraft)
                                showRenamePopover = false
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(12)
                }

                inspectorTileButton(title: "Zip", icon: "archivebox") {
                    compressItem(item)
                }
            }

            HStack(spacing: 6) {
                inspectorTileButton(title: "Terminal", icon: "terminal") {
                    TerminalLauncher.openInTerminal(url: item.url)
                }

                inspectorTileButton(title: "Copy Path", icon: "link") {
                    TerminalLauncher.copyPathToPasteboard(item.id)
                    appState.showToast("Copied path")
                }

                ShareServiceButton(urls: [item.url])

                inspectorTileButton(title: "Trash", icon: "trash") {
                    appState.moveURLsToTrash([(url: item.url, size: item.size)])
                }
            }
        }
    }

    private func inspectorTileButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                Text(title)
                    .font(.system(size: 11))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Metadata Card

    private func metadataCard(for item: FileItem) -> some View {
        let rows: [(String, String)] = {
            var base: [(String, String)] = [
                ("Kind", item.kindDescription),
                ("Size", (item.isPackage && item.size == 0) ? "App Bundle" : (item.isFolderLike ? item.subtitleText : item.formattedSize)),
                ("Created", item.formattedCreationDate),
                ("Modified", item.formattedModDate),
                ("Where", appState.displayTildePath),
            ]
            if !appVersionString.isEmpty {
                base.insert(("Version", appVersionString), at: 1)
            }
            if !appBundleIDString.isEmpty {
                base.append(("Bundle ID", appBundleIDString))
            }
            if item.isFolderLike, let c = item.childItemCount {
                base.append(("Contains", "\(c) \(c == 1 ? "item" : "items")"))
            } else if !item.ext.isEmpty {
                base.append(("Extension", ".\(item.ext)"))
            }
            if !posixPermissionString.isEmpty {
                base.append(("Permissions", posixPermissionString))
            }
            return base
        }()

        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { idx, pair in
                HStack(alignment: .top, spacing: 12) {
                    Text(pair.0)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(pair.1)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                }
                .font(.system(size: 12))
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .overlay(alignment: .top) {
                    if idx > 0 {
                        Rectangle()
                            .fill(Color.primary.opacity(0.06))
                            .frame(height: 1)
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.primary.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
                )
        )
    }

    // MARK: - Tags Section (True Wrapping FlowLayout so tags never clip or truncate!)

    private func tagsSection(for item: FileItem) -> some View {
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

    // MARK: - Developer & Quick Actions Section

    private func developerToolsSection(for item: FileItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tools")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            if item.isFolderLike {
                HStack(spacing: 6) {
                    smallActionPill("Scan Storage", icon: "chart.pie") {
                        appState.scanFolder(item.url, inScreen: .storage)
                    }
                    smallActionPill("Open in New Tab", icon: "plus.square.on.square") {
                        appState.addNewTab(at: item.url)
                    }
                }
            } else {
                HStack(spacing: 6) {
                    smallActionPill("Copy SHA-256", icon: "number.square") {
                        appState.computeSHA256(for: item.url)
                    }
                    smallActionPill(isExecutableFile ? "Remove +x" : "chmod +x", icon: "bolt.horizontal.circle") {
                        appState.toggleExecutableBit(for: item.url)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            loadInspectorDetails(for: item)
                        }
                    }
                }
            }
        }
    }

    private func smallActionPill(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 27)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Versions Section

    private func versionsSection(for item: FileItem) -> some View {
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

    // MARK: - Helpers

    private func loadInspectorDetails(for item: FileItem) {
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

    private nonisolated static func formatPosixMode(_ mode: Int) -> String {
        let chars: [(Int, Character)] = [
            (0o400, "r"), (0o200, "w"), (0o100, "x"),
            (0o040, "r"), (0o020, "w"), (0o010, "x"),
            (0o004, "r"), (0o002, "w"), (0o001, "x")
        ]
        let symbolic = String(chars.map { (mode & $0.0) != 0 ? $0.1 : "-" })
        let octal = String(format: "%03o", mode & 0o777)
        return "\(symbolic) (\(octal))"
    }

    private func performSingleRename(item: FileItem, newName: String) {
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

    private func compressItem(_ item: FileItem) {
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

    private func restoreVersion(_ version: NSFileVersion, to url: URL) {
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
