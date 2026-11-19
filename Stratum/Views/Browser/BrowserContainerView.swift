import SwiftUI
import AppKit

struct BrowserContainerView: View {
    @Bindable var appState: AppState
    var appearance: AppearanceManager

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// While a different folder loads, the old listing is dimmed so it never reads as current.
    @State private var isNavigating = false
    @State private var navigationToken = 0

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                browserHeader

                quickFilterBar

                ZStack(alignment: .bottom) {
                    ZStack {
                        switch appState.viewMode {
                        case .grid:
                            FastIconGridView(appState: appState, appearance: appearance)
                        case .list:
                            FastListView(appState: appState, appearance: appearance)
                        case .columns:
                            FastColumnView(appState: appState, appearance: appearance)
                        }

                        if appState.displayedItems.isEmpty && !appState.isLoadingDirectory {
                            emptyFolderStateView
                                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        }
                    }
                    .id(appState.viewMode)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.985)))
                    .opacity(isNavigating ? 0.5 : 1)
                    .offset(y: isNavigating && !reduceMotion ? 6 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .animation(.easeOut(duration: 0.2), value: appState.viewMode)
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isNavigating)
                    .animation(.easeOut(duration: 0.2), value: appState.displayedItems.isEmpty)

                    if appState.selectedItemIDs.count > 1 {
                        multiSelectFloatingBar
                            .padding(.bottom, 14)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.easeOut(duration: 0.16), value: appState.selectedItemIDs.count > 1)
            }
            .background(Color(nsColor: .windowBackgroundColor).opacity(appearance.contentBackgroundOpacity))

            if appState.showInspector {
                InspectorSidebarView(appState: appState, appearance: appearance)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: appState.showInspector)
        .onChange(of: appState.currentURL) { _, _ in beginNavigation() }
        .onChange(of: appState.isLoadingDirectory) { _, loading in
            if !loading { endNavigation() }
        }
    }

    // MARK: - Folder navigation feedback

    private func beginNavigation() {
        navigationToken += 1
        let token = navigationToken
        isNavigating = true
        // Safety net: never leave the listing dimmed if a load finishes before we see it.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            if navigationToken == token { isNavigating = false }
        }
    }

    private func endNavigation() {
        guard isNavigating else { return }
        isNavigating = false
    }

    private var emptyFolderStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: appState.filterQuery.isEmpty ? "folder.badge.plus" : "magnifyingglass")
                .font(.system(size: 38, weight: .thin))
                .foregroundStyle(.tertiary)
            Text(appState.filterQuery.isEmpty ? "This folder is empty" : "No items match \"\(appState.filterQuery)\"")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)

            if appState.filterQuery.isEmpty {
                HStack(spacing: 8) {
                    Button {
                        appState.createNewFolder()
                    } label: {
                        Label("New Folder", systemImage: "folder.badge.plus")
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .background(
                                Capsule()
                                    .fill(Color.primary.opacity(0.07))
                                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        appState.createNewFile(baseName: "Untitled", ext: "md", contents: "# Untitled\n\n")
                    } label: {
                        Label("New Note (.md)", systemImage: "doc.badge.plus")
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .background(
                                Capsule()
                                    .fill(Color.primary.opacity(0.07))
                                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
                            )
                    }
                    .buttonStyle(.plain)
                }
            } else {
                HStack(spacing: 10) {
                    if !appState.searchEverywhereInBrowser {
                        Button {
                            appState.searchEverywhereInBrowser = true
                        } label: {
                            Label("Search \"\(appState.filterQuery)\" Across Mac", systemImage: "globe")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .frame(height: 28)
                                .background(Capsule().fill(appearance.accentColor))
                        }
                        .buttonStyle(.plain)
                    }
                    Button("Clear Filter") {
                        appState.exitSmartFolder()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(appearance.accentColor)
                }
            }
        }
    }

    private var browserHeader: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(appState.currentFolderTitle)
                        .font(.system(size: 22, weight: .semibold))
                        .tracking(-0.2)

                    let isPinned = appState.isPinned(appState.currentURL)
                    Button {
                        appState.togglePinFolder(appState.currentURL)
                    } label: {
                        Image(systemName: isPinned ? "pin.fill" : "pin")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(isPinned ? appearance.accentColor : .secondary)
                            .frame(width: 24, height: 24)
                            .background(
                                Circle()
                                    .fill(isPinned ? appearance.selectionFillColor : Color.primary.opacity(0.05))
                            )
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .stratumHelp(isPinned ? "Unpin folder from Sidebar" : "Pin folder to Sidebar Favorites")
                }

                HStack(spacing: 5) {
                    Text("\(appState.displayedItems.count) \(appState.displayedItems.count == 1 ? "item" : "items")")
                    if appState.currentFolderTotalBytes > 0 {
                        Text("·")
                        Text(BulkDirectoryReader.fastFormatBytes(appState.currentFolderTotalBytes))
                    }
                    if appState.isCurrentFolderInICloud {
                        Text("·")
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(nsColor: NSColor(hex: "#5FD38D") ?? .systemGreen))
                        Text("Synced to iCloud")
                    }
                    if let smartName = appState.activeSmartFolderName {
                        Text("·")
                        Button {
                            appState.exitSmartFolder()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 10, weight: .bold))
                                Text("Smart Folder across Mac (\(smartName)) · Exit")
                                Image(systemName: "xmark.circle.fill")
                            }
                            .foregroundStyle(appearance.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                    if let activeTag = appState.selectedTagFilter {
                        Text("·")
                        Button {
                            appState.selectedTagFilter = nil
                        } label: {
                            HStack(spacing: 4) {
                                Text("Filtered by tag: \(activeTag)")
                                Image(systemName: "xmark.circle.fill")
                            }
                            .foregroundStyle(appearance.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 6) {
                // Quick Create Menu (+ New)
                Menu {
                    Button {
                        appState.createNewFolder()
                    } label: {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }
                    if !appState.selectedItems.isEmpty {
                        Button {
                            appState.createNewFolderWithSelection()
                        } label: {
                            Label("New Folder with Selection (\(appState.selectedItems.count))", systemImage: "folder.fill.badge.plus")
                        }
                    }
                    Divider()
                    Button {
                        appState.createNewFile(baseName: "README", ext: "md", contents: "# \(appState.currentFolderTitle)\n\n")
                    } label: {
                        Label("New Markdown (.md)", systemImage: "doc.text")
                    }
                    Button {
                        appState.createNewFile(baseName: "Untitled", ext: "txt", contents: "")
                    } label: {
                        Label("New Text File (.txt)", systemImage: "doc.plaintext")
                    }
                    Button {
                        appState.createNewFile(baseName: "script", ext: "py", contents: "#!/usr/bin/env python3\n\ndef main():\n    pass\n\nif __name__ == \"__main__\":\n    main()\n")
                    } label: {
                        Label("New Python Script (.py)", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    Button {
                        appState.createNewFile(baseName: "run", ext: "sh", contents: "#!/usr/bin/env zsh\nset -euo pipefail\n\n")
                    } label: {
                        Label("New Shell Script (.sh)", systemImage: "terminal")
                    }
                    Button {
                        appState.createNewFile(baseName: "config", ext: "json", contents: "{\n  \n}\n")
                    } label: {
                        Label("New JSON (.json)", systemImage: "curlybraces")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 10.5, weight: .bold))
                        Text("New")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(
                        Capsule()
                            .fill(appearance.selectionFillColor)
                            .overlay(
                                Capsule()
                                    .strokeBorder(appearance.selectionBorderColor, lineWidth: 1)
                            )
                    )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                sortPill(field: .name)
                sortPill(field: .kind)
                sortPill(field: .modified)
                sortPill(field: .size)

                Button {
                    appState.groupByKind.toggle()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "square.grid.3x1.below.line.grid.1x2")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Grouped")
                            .font(.system(size: 12))
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(
                        Capsule()
                            .fill(appState.groupByKind ? appearance.selectionFillColor : Color.primary.opacity(0.05))
                            .overlay(
                                Capsule()
                                    .strokeBorder(
                                        appState.groupByKind ? appearance.selectionBorderColor : Color.primary.opacity(0.10),
                                        lineWidth: 1
                                    )
                            )
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Group items by kind in Grid View")
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private func sortPill(field: SortField) -> some View {
        let isActive = (appState.sortField == field)
        return Button {
            if appState.sortField == field {
                appState.sortAscending.toggle()
            } else {
                appState.sortField = field
                appState.sortAscending = true
            }
        } label: {
            HStack(spacing: 4) {
                Text(field.rawValue)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                Image(systemName: isActive && !appState.sortAscending ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8.5, weight: .bold))
            }
            .foregroundStyle(isActive ? .primary : .secondary)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
                Capsule()
                    .fill(isActive ? appearance.selectionFillColor : Color.primary.opacity(0.05))
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                isActive ? appearance.selectionBorderColor : Color.primary.opacity(0.10),
                                lineWidth: 1
                            )
                    )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var quickFilterBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                .foregroundStyle(appearance.accentColor)
            TextField("Filter current folder (/ to focus)…", text: $appState.filterQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
            if !appState.filterQuery.isEmpty {
                Text("\(appState.displayedItems.count) matches")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                Button {
                    appState.filterQuery = ""
                    appState.showQuickFilter = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.055))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
        .padding(.horizontal, 22)
        .padding(.bottom, 8)
    }

    // MARK: - Multi-Select Floating Action Bar

    private var multiSelectFloatingBar: some View {
        let sel = appState.selectedItems
        let totalBytes = sel.reduce(Int64(0)) { $0 + $1.size }

        return HStack(spacing: 8) {
            HStack(spacing: 6) {
                Text("\(sel.count) selected")
                    .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(appearance.accentColor))

                if totalBytes > 0 {
                    Text(BulkDirectoryReader.fastFormatBytes(totalBytes))
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Divider()
                .frame(height: 18)

            floatingBarButton("Group in Folder", icon: "folder.badge.plus") {
                appState.createNewFolderWithSelection()
            }

            floatingBarButton("Batch Rename", icon: "pencil.and.outline") {
                appState.showBatchRename = true
            }

            floatingBarButton("Park on Shelf", icon: "tray.and.arrow.down") {
                appState.addToShelf(sel.map(\.url))
            }

            floatingBarButton("Zip", icon: "archivebox") {
                appState.compressSelection()
            }

            floatingBarButton("Copy Path", icon: "link") {
                let paths = sel.map(\.id).joined(separator: "\n")
                TerminalLauncher.copyPathToPasteboard(paths)
                appState.showToast("Copied \(sel.count) paths")
            }

            Button {
                appState.moveSelectionToTrash()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "trash")
                        .font(.system(size: 11.5, weight: .semibold))
                    Text("Trash")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Color(nsColor: NSColor(hex: "#FF8A8A") ?? .systemRed))
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.red.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.red.opacity(0.25), lineWidth: 1)
                        )
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                appState.selectedItemIDs = []
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .stratumHelp("Clear selection (Esc)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThickMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(appearance.selectionBorderColor, lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
    }

    private func floatingBarButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11.5, weight: .medium))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared Rich Context Menu Controller (Used by Grid, List, and Column Views)
