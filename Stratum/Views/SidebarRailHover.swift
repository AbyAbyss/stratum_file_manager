import SwiftUI

/// What the collapsed sidebar's hover label is showing, and where.
struct RailHover: Equatable {
    /// Identifies the hover that put the label up, so a late "pointer left" from one icon
    /// can't take down the label another icon has since claimed.
    var token = UUID()
    var label: String
    var badge: String?
    /// Vertical centre of the hovered icon, in the sidebar's coordinate space.
    var midY: CGFloat
}

/// Makes a collapsed-sidebar icon drive the hover label: shows it the moment the pointer
/// arrives, keeps it attached while the list scrolls, and washes the icon's background.
struct RailHoverSource: ViewModifier {
    static let coordinateSpace = "SidebarRail"
    /// Long enough to cross the gap between two icons without the label blinking off.
    private static let hideDelay: TimeInterval = 0.09

    var isEnabled: Bool
    var label: String
    var badge: String?
    @Binding var hover: RailHover?

    @State private var midY: CGFloat = 0
    @State private var isHovered = false
    @State private var token: UUID?

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(isEnabled && isHovered ? 0.08 : 0))
            )
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.coordinateSpace)).midY } action: { newMidY in
                midY = newMidY
                if hover?.token == token { hover?.midY = newMidY }
            }
            .onHover { inside in
                isHovered = inside
                guard isEnabled else { return }
                if inside {
                    let new = RailHover(label: label, badge: badge, midY: midY)
                    token = new.token
                    hover = new
                } else {
                    let leaving = token
                    DispatchQueue.main.asyncAfter(deadline: .now() + Self.hideDelay) {
                        if hover?.token == leaving { hover = nil }
                    }
                }
            }
    }
}

/// The label that slides out beside a collapsed-sidebar icon.
struct RailHoverLabel: View {
    /// Same height as a sidebar row, so the label lines up with the icon it names.
    static let height: CGFloat = 31

    var hover: RailHover
    var appearance: AppearanceManager

    var body: some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(appearance.accentColor)
                .frame(width: 3, height: 14)
            Text(hover.label)
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(1)
            if let badge = hover.badge {
                Text(badge)
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.10)))
            }
        }
        .padding(.leading, 9)
        .padding(.trailing, 12)
        .frame(height: Self.height)
        .frame(maxWidth: 280, alignment: .leading)
        .fixedSize()
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.ultraThickMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(appearance.selectionBorderColor, lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.30), radius: 12, y: 5)
        .accessibilityHidden(true)   // the icon itself already carries this label
    }
}
