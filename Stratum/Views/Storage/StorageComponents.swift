import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Model

/// One folder (or file) shown in the treemap and the list. Both views read the same value,
/// so hover, selection and colour stay in sync.
struct StorageItem: Identifiable {
    let dir: DirRow
    let path: String
    let rank: Int
    let isFile: Bool
    let isProtected: Bool

    var id: Int64 { dir.id }
    var name: String { dir.name }
    var size: Int64 { dir.totalSize }
    var color: Color { StoragePalette.color(rank: rank) }
}

struct StorageItemActions {
    var open: (StorageItem) -> Void
    var reveal: (StorageItem) -> Void
    var showInBrowser: (StorageItem) -> Void
    var trash: (StorageItem) -> Void
}

// MARK: - Palette

/// Tile colours are mid-to-deep so white text stays readable in both light and dark themes.
enum StoragePalette {
    private static let hexes = [
        "#5B5BD6", "#12A594", "#2E7CF6", "#E5604D", "#D6409F", "#0E9FBC",
        "#C98A00", "#8E4EC6", "#3E9B4F", "#E54666", "#4F7BD9", "#B26A3B"
    ]
    static func color(rank: Int) -> Color {
        Color(nsColor: NSColor(hex: hexes[rank % hexes.count]) ?? .systemIndigo)
    }

    static func color(for category: FileTypeCategory) -> Color {
        Color(nsColor: NSColor(hex: category.tintHex) ?? .systemGray)
    }

    static func symbol(for category: FileTypeCategory) -> String {
        switch category {
        case .video: return "film.fill"
        case .photos: return "photo.fill"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .apps: return "app.fill"
        case .documents: return "doc.text.fill"
        case .music: return "music.note"
        case .archives: return "archivebox.fill"
        case .other: return "square.stack.3d.up.fill"
        }
    }
}

// MARK: - Shared styling

extension View {
    /// Rounded card surface that follows the active theme (works in light and dark).
    func storageCard(_ appearance: AppearanceManager, radius: CGFloat = 18) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(appearance.cardGlassFillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.06), radius: 10, y: 3)
        )
    }
}

struct StorageItemMenu: View {
    let item: StorageItem
    let actions: StorageItemActions

    var body: some View {
        Button(item.isFile ? "Reveal in Finder" : "Open") { actions.open(item) }
        Button("Reveal in Finder") { actions.reveal(item) }
        Button("Show in Stratum Browser") { actions.showInBrowser(item) }
        Divider()
        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.path, forType: .string)
        }
        Button("Move to Trash", role: .destructive) { actions.trash(item) }
            .disabled(item.isProtected)
    }
}

enum StorageFormat {
    /// File icon for an extension, without the deprecated `icon(forFileType:)`.
    static func fileIcon(forExtension ext: String?) -> NSImage {
        let type = ext.flatMap { $0.isEmpty ? nil : UTType(filenameExtension: $0) } ?? .data
        return NSWorkspace.shared.icon(for: type)
    }

    static func bytes(_ value: Int64) -> String { BulkDirectoryReader.fastFormatBytes(value) }

    static func percent(_ part: Int64, of total: Int64) -> String {
        guard total > 0 else { return "0%" }
        let p = Double(part) / Double(total) * 100
        return p < 1 ? "<1%" : "\(Int(p.rounded()))%"
    }

    static func age(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
    }
}

// MARK: - Treemap

struct StorageTreemapView: View {
    let items: [StorageItem]
    let totalBytes: Int64
    @Binding var selectedID: Int64?
    @Binding var hoveredID: Int64?
    /// Where the next zoom starts from: the centre of the tile that was opened.
    @Binding var zoomAnchor: UnitPoint
    let actions: StorageItemActions

    var body: some View {
        GeometryReader { geo in
            let rects = TreemapLayout.rects(
                for: items.map { Double($0.size) },
                in: CGRect(origin: .zero, size: geo.size)
            )
            ZStack(alignment: .topLeading) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    TreemapTile(
                        item: item,
                        rect: rects[index],
                        index: index,
                        percent: StorageFormat.percent(item.size, of: totalBytes),
                        isSelected: selectedID == item.id,
                        isHovered: hoveredID == item.id,
                        isDimmed: (hoveredID ?? selectedID).map { $0 != item.id } ?? false
                    )
                    .onHover { inside in
                        hoveredID = inside ? item.id : (hoveredID == item.id ? nil : hoveredID)
                    }
                    .onTapGesture {
                        // One gesture reading the click count: a separate single-tap gesture
                        // waits out the whole double-click interval, which made selecting lag.
                        if (NSApp.currentEvent?.clickCount ?? 1) >= 2 {
                            zoomAnchor = UnitPoint(
                                x: geo.size.width > 0 ? rects[index].midX / geo.size.width : 0.5,
                                y: geo.size.height > 0 ? rects[index].midY / geo.size.height : 0.5
                            )
                            actions.open(item)
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selectedID = item.id }
                        }
                    }
                    .contextMenu { StorageItemMenu(item: item, actions: actions) }
                }
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.86), value: items.map(\.id))
        }
    }
}

private struct TreemapTile: View {
    let item: StorageItem
    let rect: CGRect
    let index: Int
    let percent: String
    let isSelected: Bool
    let isHovered: Bool
    let isDimmed: Bool

    @State private var appeared = false

    private static let gap: CGFloat = 3
    /// Slivers smaller than this are not drawn; they are still listed below the map.
    private static let minSide: CGFloat = 8

    var body: some View {
        // Not `rect.insetBy`: it returns CGRectNull (infinite origin) when the inset exceeds the
        // rect, and an infinite layer position makes AppKit throw during layout.
        let frame = CGRect(
            x: rect.minX + Self.gap / 2,
            y: rect.minY + Self.gap / 2,
            width: rect.width - Self.gap,
            height: rect.height - Self.gap
        )
        if frame.width >= Self.minSide && frame.height >= Self.minSide {
            tile(in: frame)
        }
    }

    private func tile(in frame: CGRect) -> some View {
        let roomy = frame.width > 90 && frame.height > 56
        let compact = frame.width > 48 && frame.height > 30

        return RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [item.color.opacity(0.98), item.color.opacity(0.74)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(isSelected ? 0.95 : 0.22), lineWidth: isSelected ? 2.5 : 1)
            )
            .overlay(alignment: .topLeading) {
                if compact {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            if item.isProtected {
                                Image(systemName: "lock.fill").font(.system(size: 9, weight: .semibold))
                            }
                            Text(item.name)
                                .font(.system(size: roomy ? 13 : 11, weight: .semibold))
                                .lineLimit(1)
                        }
                        if roomy {
                            Text(StorageFormat.bytes(item.size))
                                .font(.system(size: 18, weight: .semibold, design: .rounded).monospacedDigit())
                            Text(percent)
                                .font(.system(size: 11, weight: .medium))
                                .opacity(0.85)
                        }
                    }
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                    .padding(10)
                }
            }
            .frame(width: max(0, frame.width), height: max(0, frame.height))
            .scaleEffect(appeared ? 1 : 0.88)
            .brightness(isHovered ? 0.06 : 0)
            .opacity(appeared ? (isDimmed ? 0.5 : 1) : 0)
            .shadow(color: .black.opacity(isHovered || isSelected ? 0.3 : 0), radius: 12, y: 4)
            .zIndex(isHovered || isSelected ? 1 : 0)
            .offset(x: frame.minX, y: frame.minY)
            .animation(.easeOut(duration: 0.14), value: isHovered)
            .animation(.easeOut(duration: 0.2), value: isDimmed)
            .onAppear {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.8).delay(Double(index) * 0.035)) {
                    appeared = true
                }
            }
            .stratumHelp("\(item.name), \(StorageFormat.bytes(item.size)), \(percent) of this folder")
            .accessibilityAddTraits(.isButton)
    }
}
