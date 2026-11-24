import SwiftUI
import AppKit

struct FocusCard: View {
    let item: StorageItem
    let total: Int64
    let appearance: AppearanceManager
    let actions: StorageItemActions

    var body: some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(item.color)
                .frame(width: 6, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).font(.system(size: 16, weight: .semibold, design: .rounded)).lineLimit(1)
                Text(item.path).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }

            Spacer(minLength: 8)

            stat(StorageFormat.bytes(item.size), "Size")
            stat(StorageFormat.percent(item.size, of: total), "Of folder")
            if !item.isFile { stat("\(item.dir.descendantFileCount)", "Files") }
            stat(StorageFormat.age(item.dir.mtime), "Modified")

            Button(item.isFile ? "Reveal" : "Open") { actions.open(item) }
                .buttonStyle(.borderedProminent)
                .tint(appearance.accentColor)
                .controlSize(.large)
        }
        .padding(16)
        .storageCard(appearance)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value).font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
            Text(label).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
        }
    }
}

struct FolderRow: View {
    let item: StorageItem
    let maxSize: Int64
    let total: Int64
    let isSelected: Bool
    let isHovered: Bool
    let appearance: AppearanceManager

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.isFile ? "doc.fill" : (item.isProtected ? "lock.fill" : "folder.fill"))
                .font(.system(size: 15))
                .foregroundStyle(item.color)
                .frame(width: 22)

            Text(item.name)
                .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                .lineLimit(1)
                .frame(minWidth: 120, alignment: .leading)

            GeometryReader { geo in
                Capsule()
                    .fill(item.color.opacity(isHovered || isSelected ? 0.95 : 0.7))
                    .frame(width: max(4, geo.size.width * CGFloat(item.size) / CGFloat(max(1, maxSize))))
                    .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 8)

            Text(StorageFormat.percent(item.size, of: total))
                .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)

            Text(StorageFormat.bytes(item.size))
                .font(.system(size: 12.5, weight: .semibold, design: .rounded).monospacedDigit())
                .frame(width: 74, alignment: .trailing)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .opacity(item.isFile ? 0 : 1)
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? appearance.selectionFillColor : (isHovered ? Color.primary.opacity(0.06) : .clear))
                .padding(.horizontal, 6)
        )
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
    }
}

struct CategoryCard: View {
    let total: FileTypeTotal
    let percent: String
    let isSelected: Bool
    let appearance: AppearanceManager
    @State private var hovering = false

    var body: some View {
        let tint = StoragePalette.color(for: total.type)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: StoragePalette.symbol(for: total.type))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(tint.opacity(0.16)))
                Spacer()
                Text(percent).font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(.secondary)
            }
            Text(StorageFormat.bytes(total.totalSize))
                .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
            Text("\(total.type.displayName) · \(total.fileCount) \(total.fileCount == 1 ? "file" : "files")")
                .font(.system(size: 11.5)).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(isSelected ? 0.2 : (hovering ? 0.14 : 0.09)))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(isSelected ? tint : Color.primary.opacity(0.07), lineWidth: isSelected ? 2 : 1)
                )
        )
        .animation(.easeOut(duration: 0.14), value: hovering)
        .onHover { hovering = $0 }
        .contentShape(Rectangle())
    }
}

struct LargeFileRowView: View {
    let file: LargeFileRow
    let path: String
    let maxSize: Int64
    let appearance: AppearanceManager
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: StorageFormat.fileIcon(forExtension: file.ext))
                .resizable().frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text((path as NSString).deletingLastPathComponent)
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
            }
            Spacer()
            Text(StorageFormat.age(file.mtime)).font(.system(size: 11.5)).foregroundStyle(.secondary)
            Text(StorageFormat.bytes(file.size))
                .font(.system(size: 12.5, weight: .semibold, design: .rounded).monospacedDigit())
                .frame(width: 74, alignment: .trailing)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            } label: {
                Image(systemName: "magnifyingglass.circle.fill").font(.system(size: 16))
            }
            .buttonStyle(StratumInteractiveButtonStyle())
            .foregroundStyle(appearance.accentColor)
            .opacity(hovering ? 1 : 0.35)
            .stratumHelp("Reveal in Finder")
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hovering ? Color.primary.opacity(0.05) : .clear).padding(.horizontal, 6))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

struct EmptyScanCard: View {
    let appearance: AppearanceManager
    let scan: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "chart.pie.fill").font(.system(size: 40)).foregroundStyle(appearance.accentColor)
            Text("No storage data yet").font(.system(size: 18, weight: .semibold, design: .rounded))
            Text("Scan your home folder to see what's using space.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            Button("Scan Home Folder", action: scan)
                .buttonStyle(.borderedProminent).tint(appearance.accentColor).controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
