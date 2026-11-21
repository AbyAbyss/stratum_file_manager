import SwiftUI
import AppKit

/// Lets a side panel be resized by dragging its inner edge. Double-click the edge to reset.
/// With a `collapse` option, dragging well past the minimum width snaps the panel to a narrow
/// rail, and dragging the rail back out expands it again.
/// The width is remembered between launches under `key`. The panel can be laid out narrower than
/// that (down to the range's lower bound) by `SidePanelLayout` when the window is small.
private struct ResizablePanel: ViewModifier {
    var key: String
    var defaultWidth: Double
    var range: ClosedRange<Double>
    /// The panel's edge that touches the content (trailing for a left sidebar, leading for a right one).
    var edge: HorizontalEdge
    var collapse: Collapse?

    /// A narrow fixed-width state the panel can snap to.
    struct Collapse {
        var width: Double
        var isCollapsed: Binding<Bool>
    }

    /// How far past the minimum width the drag must go before the panel snaps to the rail.
    private static let collapseOvershoot: Double = 50

    private var isCollapsed: Bool { collapse?.isCollapsed.wrappedValue ?? false }

    @State private var width: Double
    @State private var widthAtDragStart: Double?
    @State private var isHovering = false

    init(key: String, defaultWidth: Double, range: ClosedRange<Double>, edge: HorizontalEdge, collapse: Collapse?) {
        self.key = key
        self.defaultWidth = defaultWidth
        self.range = range
        self.edge = edge
        self.collapse = collapse
        let saved = UserDefaults.standard.object(forKey: key) as? Double
        _width = State(initialValue: min(max(saved ?? defaultWidth, range.lowerBound), range.upperBound))
    }

    func body(content: Content) -> some View {
        content
            .frame(
                minWidth: collapse.flatMap { isCollapsed ? $0.width : nil } ?? range.lowerBound,
                idealWidth: collapse.flatMap { isCollapsed ? $0.width : nil } ?? width,
                maxWidth: collapse.flatMap { isCollapsed ? $0.width : nil } ?? width
            )
            .overlay(alignment: edge == .trailing ? .trailing : .leading) { handle }
    }

    private var handle: some View {
        Rectangle()
            .fill(Color.accentColor.opacity(widthAtDragStart != nil ? 0.55 : (isHovering ? 0.3 : 0)))
            .frame(width: 2)
            .padding(.horizontal, 3)                 // 8pt grab area around a 2pt line
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .background(ResizeCursor())
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { drag in
                        let start = widthAtDragStart ?? (collapse.flatMap { isCollapsed ? $0.width : nil } ?? width)
                        widthAtDragStart = start
                        let delta = edge == .trailing ? drag.translation.width : -drag.translation.width
                        let wanted = start + delta
                        if let collapse {
                            let shouldCollapse = wanted < range.lowerBound - Self.collapseOvershoot
                            if shouldCollapse != isCollapsed {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                    collapse.isCollapsed.wrappedValue = shouldCollapse
                                }
                            }
                        }
                        width = min(max(wanted, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in
                        widthAtDragStart = nil
                        UserDefaults.standard.set(width, forKey: key)
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    width = defaultWidth
                    collapse?.isCollapsed.wrappedValue = false
                }
                UserDefaults.standard.set(defaultWidth, forKey: key)
            }
            .accessibilityLabel("Resize panel")
            .accessibilityHint("Drag to change the width. Double-click to reset.")
    }
}

extension View {
    func resizablePanel(
        key: String, defaultWidth: Double, range: ClosedRange<Double>, edge: HorizontalEdge,
        collapsedWidth: Double? = nil, isCollapsed: Binding<Bool> = .constant(false)
    ) -> some View {
        let collapse = collapsedWidth.map { ResizablePanel.Collapse(width: $0, isCollapsed: isCollapsed) }
        return modifier(ResizablePanel(key: key, defaultWidth: defaultWidth, range: range, edge: edge, collapse: collapse))
    }
}

/// Shows the left-right resize cursor over its frame (cursor rects, so it needs macOS 14 only).
private struct ResizeCursor: NSViewRepresentable {
    final class CursorView: NSView {
        override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }
    }
    func makeNSView(context: Context) -> NSView { CursorView() }
    func updateNSView(_ nsView: NSView, context: Context) { nsView.window?.invalidateCursorRects(for: nsView) }
}
