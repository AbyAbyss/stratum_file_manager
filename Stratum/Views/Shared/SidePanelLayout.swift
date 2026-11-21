import SwiftUI

/// Sizes the window layout is built around.
enum WindowMetrics {
    static let minWidth: Double = 720
    static let minHeight: Double = 500
    static let sidebarMinWidth: Double = 190
    /// Width of the sidebar when it is collapsed to icons.
    static let sidebarRailWidth: Double = 56
    static let inspectorMinWidth: Double = 260
    /// The file listing never gets narrower than this while a side panel is showing.
    static let browserListMinWidth: Double = 400
    /// Below this window width the sidebar and the inspector can't both be on screen.
    static let bothPanelsMinWidth = sidebarMinWidth + browserListMinWidth + inspectorMinWidth
}

/// Places a side panel next to the main content.
///
/// The panel keeps its preferred width until the main content would drop below `mainMinWidth`;
/// then the panel gives up width, down to its own minimum. With one subview (panel hidden) the
/// subview fills the whole area.
struct SidePanelLayout: Layout {
    /// The window edge the panel sits on. The panel must be the first subview when leading,
    /// the last when trailing.
    var panelEdge: HorizontalEdge
    var mainMinWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else {
            subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
            return
        }
        let panel = panelEdge == .leading ? subviews[0] : subviews[1]
        let main = panelEdge == .leading ? subviews[1] : subviews[0]

        let preferred = panel.sizeThatFits(ProposedViewSize(width: nil, height: bounds.height)).width
        let minimum = panel.sizeThatFits(ProposedViewSize(width: 0, height: bounds.height)).width
        let panelWidth = max(minimum, min(preferred, bounds.width - mainMinWidth))
        let mainWidth = max(0, bounds.width - panelWidth)

        let panelX = panelEdge == .leading ? bounds.minX : bounds.maxX - panelWidth
        let mainX = panelEdge == .leading ? bounds.minX + panelWidth : bounds.minX
        panel.place(at: CGPoint(x: panelX, y: bounds.minY), proposal: ProposedViewSize(width: panelWidth, height: bounds.height))
        main.place(at: CGPoint(x: mainX, y: bounds.minY), proposal: ProposedViewSize(width: mainWidth, height: bounds.height))
    }
}
