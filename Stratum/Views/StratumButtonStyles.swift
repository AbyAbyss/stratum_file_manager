import SwiftUI
import AppKit

struct StratumInteractiveButtonStyle: ButtonStyle {
    var hoverScale: CGFloat = 1.03
    var pressScale: CGFloat = 0.95

    func makeBody(configuration: Configuration) -> some View {
        StratumInteractiveButtonBody(
            configuration: configuration,
            hoverScale: hoverScale,
            pressScale: pressScale
        )
    }

    private struct StratumInteractiveButtonBody: View {
        let configuration: Configuration
        let hoverScale: CGFloat
        let pressScale: CGFloat
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? pressScale : (isHovered ? hoverScale : 1.0))
                .brightness(configuration.isPressed ? -0.03 : (isHovered ? 0.03 : 0))
                .animation(.spring(response: 0.22, dampingFraction: 0.72), value: configuration.isPressed)
                .animation(.spring(response: 0.24, dampingFraction: 0.74), value: isHovered)
                .onHover { hovering in
                    isHovered = hovering
                }
        }
    }
}

extension View {
    func stratumScrollMotion() -> some View {
        self.scrollTransition(.animated(.spring(response: 0.34, dampingFraction: 0.82))) { content, phase in
            content
                .opacity(phase.isIdentity ? 1.0 : 0.68)
                .scaleEffect(phase.isIdentity ? 1.0 : 0.965)
                .offset(y: phase.isIdentity ? 0 : (phase.value > 0 ? 10 : -6))
        }
    }
}
