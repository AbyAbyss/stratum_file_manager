import SwiftUI
import AppKit

extension GroupsByNameView {
    // MARK: - Left Card: Interactive Bubble Chart

    struct BubbleLayoutItem: Identifiable {
        var id: String { group.name }
        let group: GroupRow
        let x: CGFloat
        let y: CGFloat
        let diameter: CGFloat
        let hexColor: String
    }

    var bubbleLayouts: [BubbleLayoutItem] {
        let items = Array(displayedGroups.prefix(7))
        guard !items.isEmpty else { return [] }
        let maxTotal = max(1, Double(items.map(\.total).max() ?? 1))

        let centers: [(CGFloat, CGFloat)] = [
            (175, 185),
            (295, 115),
            (95, 315),
            (255, 330),
            (85, 105),
            (315, 245),
            (175, 375)
        ]

        return items.enumerated().map { idx, grp in
            let ratio = sqrt(Double(max(1, grp.total)) / maxTotal)
            let diameter = CGFloat(max(68.0, min(160.0, 68.0 + ratio * 92.0)))
            let pos = centers[idx % centers.count]
            let color = bubblePalette[idx % bubblePalette.count]
            return BubbleLayoutItem(
                group: grp,
                x: pos.0,
                y: pos.1,
                diameter: diameter,
                hexColor: color
            )
        }
    }

    var bubbleChartCard: some View {
        ZStack {
            if bubbleLayouts.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "circle.grid.2x1")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No matching folder groups found")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            } else {
                ZStack {
                    ForEach(bubbleLayouts) { b in
                        let isExpanded = expandedGroupNames.contains(b.group.name)
                        let baseColor = Color(nsColor: NSColor(hex: b.hexColor) ?? .systemPurple)

                        Button {
                            if expandedGroupNames.contains(b.group.name) {
                                // Also select all in this bubble when clicked while already expanded
                                let insts = filteredInstances(for: b.group.name)
                                let allSelected = !insts.isEmpty && insts.allSatisfy { checkedPaths.contains($0.fullPath) }
                                toggleGroupCheck(group: b.group, instances: insts, currentlyAllChecked: allSelected)
                            } else {
                                expandedGroupNames.insert(b.group.name)
                                scanCoordinator.selectedGroupName = b.group.name
                            }
                        } label: {
                            VStack(spacing: 2) {
                                Text(b.group.name)
                                    .font(.system(size: b.diameter > 110 ? 13 : 11, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text(BulkDirectoryReader.fastFormatBytes(b.group.total))
                                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                                    .foregroundStyle(.white.opacity(0.9))
                            }
                            .frame(width: b.diameter, height: b.diameter)
                            .background(
                                Circle()
                                    .fill(baseColor.opacity(isExpanded ? 0.92 : 0.72))
                                    .overlay(
                                        Circle()
                                            .strokeBorder(isExpanded ? Color.white : Color.primary.opacity(0.22), lineWidth: isExpanded ? 2.5 : 1)
                                    )
                            )
                            .contentShape(Circle())
                            .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
                        }
                        .buttonStyle(StratumInteractiveButtonStyle(hoverScale: 1.07, pressScale: 0.94))
                        .scaleEffect(bubblesAppeared ? 1 : 0.6)
                        .opacity(bubblesAppeared ? 1 : 0)
                        .position(x: b.x, y: b.y)
                    }
                }
                .frame(width: 380, height: 440)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 472)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
                )
        )
    }
}
