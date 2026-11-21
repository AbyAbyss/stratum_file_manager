import SwiftUI
import AppKit

/// Lets a side panel be resized by dragging its inner edge. Double-click the edge to reset.
/// The width is remembered between launches under `key`. The panel can be laid out narrower than
/// that (down to the range's lower bound) by `SidePanelLayout` when the window is small.
private struct ResizablePanel: ViewModifier {
    var key: String
    var defaultWidth: Double
    var range: ClosedRange<Double>
    /// The panel's edge that touches the content (trailing for a left sidebar, leading for a right one).
    var edge: HorizontalEdge

    @State private var width: Double
    @State private var widthAtDragStart: Double?
    @State private var isHovering = false

    init(key: String, defaultWidth: Double, range: ClosedRange<Double>, edge: HorizontalEdge) {
        self.key = key
        self.defaultWidth = defaultWidth
        self.range = range
        self.edge = edge
        let saved = UserDefaults.standard.object(forKey: key) as? Double
        _width = State(initialValue: min(max(saved ?? defaultWidth, range.lowerBound), range.upperBound))
    }

    func body(content: Content) -> some View {
        content
            .frame(minWidth: range.lowerBound, idealWidth: width, maxWidth: width)
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
                        let start = widthAtDragStart ?? width
                        widthAtDragStart = start
                        let delta = edge == .trailing ? drag.translation.width : -drag.translation.width
                        width = min(max(start + delta, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in
                        widthAtDragStart = nil
                        UserDefaults.standard.set(width, forKey: key)
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { width = defaultWidth }
                UserDefaults.standard.set(defaultWidth, forKey: key)
            }
            .accessibilityLabel("Resize panel")
            .accessibilityHint("Drag to change the width. Double-click to reset.")
    }
}

extension View {
    func resizablePanel(key: String, defaultWidth: Double, range: ClosedRange<Double>, edge: HorizontalEdge) -> some View {
        modifier(ResizablePanel(key: key, defaultWidth: defaultWidth, range: range, edge: edge))
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
