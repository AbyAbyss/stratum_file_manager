import SwiftUI

/// The walkthrough backdrop: a twinkling night sky over layered hills (the "strata"),
/// with a soft aurora in the user's accent colour. Static when Reduce Motion is on.
struct NightSkyView: View {
    var accent: Color
    /// When set, the sky is displaced by a water ripple spreading from `origin`.
    var ripple: Ripple?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A damped wave travelling outward at `speed` px/s. Computed on the CPU for the few
    /// hundred points the sky is made of, so no shader (and no Metal toolchain) is needed.
    struct Ripple {
        var origin: CGPoint
        var time: Double
        static let amplitude = 16.0, frequency = 16.0, decay = 3.5, speed = 1100.0

        /// The displaced point and the wave height there, normalised to -1...1.
        func apply(to point: CGPoint) -> (point: CGPoint, height: Double) {
            let dx = Double(point.x - origin.x), dy = Double(point.y - origin.y)
            let distance = (dx * dx + dy * dy).squareRoot()
            let local = max(0, time - distance / Self.speed)
            let height = sin(Self.frequency * local) * exp(-Self.decay * local)
            guard distance > 0.001 else { return (point, height) }
            let amount = Self.amplitude * height
            return (CGPoint(x: Double(point.x) + amount * dx / distance, y: Double(point.y) + amount * dy / distance), height)
        }
    }

    private struct Star {
        let x, y, radius, brightness, phase, speed: Double
    }

    private static let stars: [Star] = {
        var rng = SplitMix64(seed: 0x57A7_0000_0001)
        return (0..<180).map { _ in
            Star(
                x: .random(in: 0...1, using: &rng),
                y: .random(in: 0...0.78, using: &rng),
                radius: .random(in: 0.5...1.7, using: &rng),
                brightness: .random(in: 0.35...1, using: &rng),
                phase: .random(in: 0...(2 * .pi), using: &rng),
                speed: .random(in: 0.6...2.2, using: &rng)
            )
        }
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            Canvas { gc, size in
                // Sky
                gc.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .linearGradient(
                        Gradient(colors: [Color(red: 0.016, green: 0.024, blue: 0.055),
                                          Color(red: 0.04, green: 0.065, blue: 0.14),
                                          Color(red: 0.07, green: 0.10, blue: 0.20)]),
                        startPoint: .zero,
                        endPoint: CGPoint(x: 0, y: size.height)
                    )
                )

                // Aurora: two slow-drifting accent blooms
                for (i, strength) in [0.30, 0.18].enumerated() {
                    let drift = sin(t * 0.12 + Double(i) * 2.1)
                    var center = CGPoint(
                        x: size.width * (0.32 + 0.36 * Double(i)) + drift * 60,
                        y: size.height * (0.42 + 0.08 * Double(i)) + cos(t * 0.09 + Double(i)) * 24
                    )
                    if let ripple { center = ripple.apply(to: center).point }
                    gc.fill(
                        Path(CGRect(origin: .zero, size: size)),
                        with: .radialGradient(
                            Gradient(colors: [accent.opacity(strength), .clear]),
                            center: center,
                            startRadius: 0,
                            endRadius: max(size.width, size.height) * 0.5
                        )
                    )
                }

                // Stars
                for star in Self.stars {
                    let twinkle = reduceMotion ? 0.8 : 0.55 + 0.45 * sin(t * star.speed + star.phase)
                    var position = CGPoint(x: star.x * size.width, y: star.y * size.height)
                    var boost = 0.0
                    if let ripple {
                        let moved = ripple.apply(to: position)
                        position = moved.point
                        boost = abs(moved.height)
                    }
                    let r = star.radius * (1 + boost * 0.9)
                    let rect = CGRect(x: position.x - r, y: position.y - r, width: r * 2, height: r * 2)
                    gc.fill(Path(ellipseIn: rect), with: .color(.white.opacity(min(1, star.brightness * twinkle * (1 + boost * 1.4)))))
                }

                // Layered hills: three strata, each a little lighter and further back
                let layers: [(base: Double, amp: Double, shade: Double)] = [(0.80, 0.045, 0.10), (0.88, 0.05, 0.065), (0.95, 0.04, 0.04)]
                for (i, layer) in layers.enumerated() {
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: size.height))
                    stride(from: 0.0, through: 1.0, by: ripple == nil ? 0.02 : 0.008).forEach { x in
                        let wave = sin(x * 6.2 + Double(i) * 1.7) * 0.6 + sin(x * 13.0 + Double(i) * 0.9) * 0.4
                        var vertex = CGPoint(x: x * size.width, y: (layer.base + wave * layer.amp) * size.height)
                        if let ripple { vertex = ripple.apply(to: vertex).point }
                        path.addLine(to: vertex)
                    }
                    path.addLine(to: CGPoint(x: size.width, y: size.height))
                    path.closeSubpath()
                    gc.fill(path, with: .color(Color(red: layer.shade * 0.6, green: layer.shade * 0.8, blue: layer.shade * 1.5)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Deterministic generator so the sky looks the same on every launch.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
