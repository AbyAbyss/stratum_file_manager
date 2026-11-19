import SwiftUI
import AppKit

struct StratumIsometricLogo: View {
    var size: CGFloat = 28
    var accentColor: Color
    var isAnimated: Bool = true

    @State private var floatPhase: Bool = false
    @State private var isHovered: Bool = false

    var body: some View {
        ZStack {
            // Subtle ambient glow behind the 3 strata plates
            Circle()
                .fill(
                    RadialGradient(
                        colors: [accentColor.opacity(isHovered ? 0.55 : 0.32), .clear],
                        center: .center,
                        startRadius: 1,
                        endRadius: size * 0.72
                    )
                )
                .frame(width: size * 1.35, height: size * 1.35)

            // Bottom Stratum Plate (Deepest Layer)
            StratumDiamondPlateShape()
                .fill(
                    LinearGradient(
                        colors: [
                            accentColor.opacity(0.38),
                            accentColor.opacity(0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    StratumDiamondPlateShape()
                        .stroke(accentColor.opacity(0.45), lineWidth: max(0.8, size * 0.032))
                )
                .frame(width: size * 0.88, height: size * 0.48)
                .offset(y: size * 0.21 + (floatPhase ? size * 0.025 : 0))

            // Middle Stratum Plate (Core Index Layer)
            StratumDiamondPlateShape()
                .fill(
                    LinearGradient(
                        colors: [
                            accentColor.opacity(0.72),
                            accentColor.opacity(0.40)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    StratumDiamondPlateShape()
                        .stroke(Color.white.opacity(0.45), lineWidth: max(0.8, size * 0.032))
                )
                .frame(width: size * 0.88, height: size * 0.48)
                .offset(y: floatPhase ? -size * 0.015 : size * 0.015)

            // Top Stratum Plate (Bright Specular Surface Layer)
            StratumDiamondPlateShape()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.95),
                            accentColor
                        ],
                        startPoint: .top,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    StratumDiamondPlateShape()
                        .stroke(Color.white.opacity(0.85), lineWidth: max(1.0, size * 0.038))
                )
                .shadow(color: accentColor.opacity(0.55), radius: size * 0.14, y: size * 0.06)
                .frame(width: size * 0.88, height: size * 0.48)
                .offset(y: -size * 0.21 - (floatPhase ? size * 0.035 : 0))
        }
        .frame(width: size, height: size)
        .scaleEffect(isHovered ? 1.08 : 1.0)
        .rotation3DEffect(
            .degrees(isHovered ? 12 : 0),
            axis: (x: -0.4, y: 0.8, z: 0.0)
        )
        .onHover { hovering in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.68)) {
                isHovered = hovering
            }
        }
        .onAppear {
            guard isAnimated else { return }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                floatPhase = true
            }
        }
    }
}

struct StratumDiamondPlateShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let top = CGPoint(x: w * 0.5, y: 0)
        let right = CGPoint(x: w, y: h * 0.5)
        let bottom = CGPoint(x: w * 0.5, y: h)
        let left = CGPoint(x: 0, y: h * 0.5)

        path.move(to: top)
        path.addLine(to: right)
        path.addLine(to: bottom)
        path.addLine(to: left)
        path.closeSubpath()
        return path
    }
}
