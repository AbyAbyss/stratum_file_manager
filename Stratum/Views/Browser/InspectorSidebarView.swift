import SwiftUI
import AppKit

struct InspectorSidebarView: View {
    @Bindable var appState: AppState
    var appearance: AppearanceManager

    @State var previewThumbnail: NSImage?
    @State var textSnippet: String?
    @State var posixPermissionString: String = ""
    @State var appVersionString: String = ""
    @State var appBundleIDString: String = ""
    @State var isExecutableFile: Bool = false
    @State var showTagPopover = false
    @State var showRenamePopover = false
    @State var renameDraft = ""
    @State var fileVersions: [NSFileVersion] = []

    var item: FileItem? {
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
        .background(Color.primary.opacity(0.025))
        .resizablePanel(key: "Stratum.inspectorWidth", defaultWidth: 306, range: WindowMetrics.inspectorMinWidth...520, edge: .leading)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1)
        }
    }

    // MARK: - Metadata Card

    func metadataCard(for item: FileItem) -> some View {
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

}
