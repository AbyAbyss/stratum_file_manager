import SwiftUI
import AppKit

struct StratumStartupSplashView: View {
    var appearance: AppearanceManager
    var onFinished: () -> Void

    @State private var layer1Assembled = false
    @State private var layer2Assembled = false
    @State private var layer3Assembled = false
    @State private var ringRotation: Double = 0
    @State private var textRevealed = false
    @State private var progressFraction: CGFloat = 0.0

    var body: some View {
        ZStack {
            // Deep translucent backdrop
            VisualEffectBackground(
                material: .hudWindow,
                blendingMode: .withinWindow,
                state: .active
            )
            .ignoresSafeArea()

            Color.black.opacity(0.62)
                .ignoresSafeArea()

            // Ambient radial light bloom
            RadialGradient(
                colors: [
                    appearance.accentColor.opacity(layer3Assembled ? 0.30 : 0.05),
                    appearance.accentColor.opacity(0.08),
                    .clear
                ],
                center: .center,
                startRadius: 10,
                endRadius: 340
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                // Orbital Radar Ring + 3D Assembling Strata Emblem
                ZStack {
                    // Outer dashed orbital ring
                    Circle()
                        .strokeBorder(
                            AngularGradient(
                                colors: [
                                    appearance.accentColor.opacity(0.0),
                                    appearance.accentColor.opacity(0.65),
                                    Color.white.opacity(0.85),
                                    appearance.accentColor.opacity(0.1)
                                ],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [6, 8])
                        )
                        .frame(width: 148, height: 148)
                        .rotationEffect(.degrees(ringRotation))
                        .scaleEffect(layer1Assembled ? 1.0 : 0.72)
                        .opacity(layer1Assembled ? 0.85 : 0)

                    // Inner glow ring
                    Circle()
                        .strokeBorder(appearance.accentColor.opacity(0.22), lineWidth: 1)
                        .frame(width: 116, height: 116)
                        .scaleEffect(layer2Assembled ? 1.0 : 0.6)
                        .opacity(layer2Assembled ? 1.0 : 0)

                    // Bottom Plate
                    StratumDiamondPlateShape()
                        .fill(
                            LinearGradient(
                                colors: [appearance.accentColor.opacity(0.45), appearance.accentColor.opacity(0.16)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            StratumDiamondPlateShape()
                                .stroke(appearance.accentColor.opacity(0.6), lineWidth: 1.5)
                        )
                        .frame(width: 78, height: 42)
                        .offset(y: layer1Assembled ? 20 : 65)
                        .scaleEffect(layer1Assembled ? 1.0 : 0.5)
                        .opacity(layer1Assembled ? 1.0 : 0)

                    // Middle Plate
                    StratumDiamondPlateShape()
                        .fill(
                            LinearGradient(
                                colors: [appearance.accentColor.opacity(0.82), appearance.accentColor.opacity(0.42)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            StratumDiamondPlateShape()
                                .stroke(Color.white.opacity(0.55), lineWidth: 1.5)
                        )
                        .frame(width: 78, height: 42)
                        .offset(y: layer2Assembled ? 0 : -45)
                        .scaleEffect(layer2Assembled ? 1.0 : 0.55)
                        .opacity(layer2Assembled ? 1.0 : 0)

                    // Top Specular Plate
                    StratumDiamondPlateShape()
                        .fill(
                            LinearGradient(
                                colors: [Color.white, appearance.accentColor],
                                startPoint: .top,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            StratumDiamondPlateShape()
                                .stroke(Color.white.opacity(0.95), lineWidth: 1.8)
                        )
                        .shadow(color: appearance.accentColor.opacity(0.75), radius: 16, y: 6)
                        .frame(width: 78, height: 42)
                        .offset(y: layer3Assembled ? -20 : -80)
                        .scaleEffect(layer3Assembled ? 1.0 : 0.45)
                        .opacity(layer3Assembled ? 1.0 : 0)
                }

                // Brand Title + Telemetry Pill
                VStack(spacing: 8) {
                    Text("STRATUM")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .tracking(textRevealed ? 7 : 18)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .white.opacity(0.82)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .opacity(textRevealed ? 1 : 0)
                        .offset(y: textRevealed ? 0 : 8)

                    Text("HIGH-SPEED NATIVE FILE & STORAGE ENGINE")
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .tracking(1.6)
                        .foregroundStyle(appearance.accentColor)
                        .opacity(textRevealed ? 0.92 : 0)

                    // Animated progress sweep bar
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.10))
                            .frame(width: 210, height: 4)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [appearance.accentColor, .white],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 210 * progressFraction, height: 4)
                            .shadow(color: appearance.accentColor, radius: 6)
                    }
                    .padding(.top, 8)
                    .opacity(textRevealed ? 1 : 0)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(appearance.accentColor)
                            .frame(width: 6, height: 6)
                        Text("getattrlistbulk · APFS CoW · Smart Auto-Sync Ready")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                    .opacity(textRevealed ? 0.85 : 0)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onFinished()
        }
        .onAppear {
            withAnimation(.linear(duration: 8.0).repeatForever(autoreverses: false)) {
                ringRotation = 360
            }
            withAnimation(.spring(response: 0.44, dampingFraction: 0.72)) {
                layer1Assembled = true
            }
            withAnimation(.spring(response: 0.46, dampingFraction: 0.74).delay(0.10)) {
                layer2Assembled = true
            }
            withAnimation(.spring(response: 0.48, dampingFraction: 0.70).delay(0.20)) {
                layer3Assembled = true
            }
            withAnimation(.spring(response: 0.50, dampingFraction: 0.82).delay(0.22)) {
                textRevealed = true
            }
            withAnimation(.easeInOut(duration: 0.95).delay(0.18)) {
                progressFraction = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.35) {
                onFinished()
            }
        }
    }
}
