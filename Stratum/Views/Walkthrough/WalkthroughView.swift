import SwiftUI
import AppKit

enum Walkthrough {
    private static let key = "stratum.walkthroughCompleted"
    static var hasCompleted: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

/// First-launch tour over a night sky: welcome, scanning, the Full Disk Access ask, ready.
/// Leaves with a water ripple that breaks the sky open from wherever you clicked. Clicking
/// the sky itself at any step does the same, so it is never a trap.
struct WalkthroughView: View {
    @Bindable var appState: AppState
    var appearance: AppearanceManager
    var scanCoordinator = ScanCoordinator.shared
    var onFinish: () -> Void

    private enum Step: Int, CaseIterable { case welcome, scanning, permission, ready }

    @State private var step: Step = .welcome
    @State private var goingForward = true
    @State private var appeared = false
    @State private var hasAccess = false
    @State private var revealOrigin: CGPoint?
    @State private var revealStart: Date?
    @State private var canvasSize: CGSize = .zero
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let revealDuration: Double = 1.7

    // MARK: Body

    var body: some View {
        GeometryReader { geo in
            Group {
                if let start = revealStart, let origin = revealOrigin {
                    revealing(start: start, origin: origin, size: geo.size)
                } else {
                    overlay(size: geo.size)
                }
            }
            .onAppear { canvasSize = geo.size }
            .onChange(of: geo.size) { _, size in canvasSize = size }
        }
        .coordinateSpace(name: "walkthrough")
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.rightArrow) { next(); return .handled }
        .onKeyPress(.return) { next(); return .handled }
        .onKeyPress(.leftArrow) { back(); return .handled }
        .onKeyPress(.escape) { reveal(at: center); return .handled }
        .onAppear {
            focused = true
            withAnimation(.easeOut(duration: 0.9)) { appeared = true }
        }
        .task(id: step) { await watchAccess() }
    }

    private var center: CGPoint { CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2) }

    // MARK: Layers

    private func overlay(size: CGSize) -> some View {
        ZStack {
            NightSkyView(accent: appearance.accentColor)
            content(size: size)
        }
        .environment(\.colorScheme, .dark)
        .contentShape(Rectangle())
        // Parent gesture: buttons win over it, so only taps on empty sky (or plain text) break the water.
        .gesture(SpatialTapGesture(coordinateSpace: .named("walkthrough")).onEnded { reveal(at: $0.location) })
    }

    private func content(size: CGSize) -> some View {
        VStack(spacing: 0) {
            topBar(size: size)
            Spacer(minLength: 20)
            stepContent
                .id(step)
                .transition(stepTransition)
            Spacer(minLength: 20)
            bottomBar
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 30)
    }

    private func revealing(start: Date, origin: CGPoint, size: CGSize) -> some View {
        TimelineView(.animation) { context in
            revealFrame(t: max(0, context.date.timeIntervalSince(start)), origin: origin, size: size)
        }
    }

    @ViewBuilder
    private func revealFrame(t: Double, origin: CGPoint, size: CGSize) -> some View {
        let radius = CGFloat(t * NightSkyView.Ripple.speed)
        if reduceMotion {
            overlay(size: size)
                .environment(\.colorScheme, .dark)
                .allowsHitTesting(false)
                .opacity(max(0, 1 - t / 0.5))
        } else {
            ZStack {
                skyWithHole(t: t, radius: radius, origin: origin, size: size)
                ForEach(0..<3, id: \.self) { ring in
                    rippleRing(ring, t: t, radius: radius, origin: origin)
                }
                .allowsHitTesting(false)
            }
        }
    }

    private func skyWithHole(t: Double, radius: CGFloat, origin: CGPoint, size: CGSize) -> some View {
        ZStack {
            // The sky itself ripples; the text and buttons dissolve first so
            // nothing flat is left floating over the water.
            NightSkyView(accent: appearance.accentColor, ripple: .init(origin: origin, time: t))
            content(size: size)
                .environment(\.colorScheme, .dark)
                .opacity(max(0, 1 - t / 0.3))
        }
        .allowsHitTesting(false)
        .mask {
            // The sky with a growing hole where the water has broken through.
            ZStack {
                Rectangle().fill(.white)
                Circle()
                    .fill(.black)
                    .frame(width: radius * 2, height: radius * 2)
                    .position(origin)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
        }
    }

    private func rippleRing(_ ring: Int, t: Double, radius: CGFloat, origin: CGPoint) -> some View {
        let r = max(0, radius - CGFloat(ring) * 70)
        let fade: Double = max(0, 0.55 * (1 - t / 1.5))
        let opacity: Double = fade * (1 - Double(ring) * 0.3)
        let lineWidth: CGFloat = 2.5 - CGFloat(ring) * 0.6
        return Circle()
            .strokeBorder(.white.opacity(opacity), lineWidth: lineWidth)
            .frame(width: r * 2, height: r * 2)
            .position(origin)
    }

    // MARK: Chrome

    private func topBar(size: CGSize) -> some View {
        HStack {
            Spacer()
            Button("Skip") { reveal(at: CGPoint(x: size.width - 70, y: 44)) }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 10)
                .frame(height: 28)
                .contentShape(Rectangle())
                .stratumHelp("Skip the tour")
        }
        .opacity(appeared ? 1 : 0)
    }

    private var bottomBar: some View {
        HStack {
            Button { back() } label: {
                Label("Back", systemImage: "chevron.left")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
                    .frame(height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(step == .welcome ? 0 : 1)
            .disabled(step == .welcome)

            Spacer()

            HStack(spacing: 7) {
                ForEach(Step.allCases, id: \.rawValue) { s in
                    Capsule()
                        .fill(s == step ? Color.white : Color.white.opacity(0.28))
                        .frame(width: s == step ? 22 : 7, height: 7)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: step)
            .accessibilityHidden(true)

            Spacer()

            primaryButton
        }
        .opacity(appeared ? 1 : 0)
    }

    @ViewBuilder
    private var primaryButton: some View {
        if step == .ready {
            // A tap gesture rather than a Button so the water breaks from exactly where you press.
            pill("Reveal Stratum", systemImage: "sparkles")
                .gesture(SpatialTapGesture(coordinateSpace: .named("walkthrough")).onEnded { reveal(at: $0.location) })
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { reveal(at: center) }
        } else {
            Button { next() } label: { pill(step == .welcome ? "Begin" : "Next", systemImage: "arrow.right") }
                .buttonStyle(.plain)
        }
    }

    private func pill(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
            Image(systemName: systemImage).font(.system(size: 12, weight: .bold))
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(Color.black.opacity(0.88))
        .padding(.horizontal, 20)
        .frame(height: 38)
        .background(Capsule().fill(.white))
        .shadow(color: appearance.accentColor.opacity(0.55), radius: 14, y: 3)
        .contentShape(Capsule())
    }

    // MARK: Steps

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome: welcomeStep
        case .scanning: scanningStep
        case .permission: permissionStep
        case .ready: readyStep
        }
    }

    private var stepTransition: AnyTransition {
        let dx: CGFloat = goingForward ? 50 : -50
        return .asymmetric(
            insertion: .offset(x: dx).combined(with: .opacity),
            removal: .offset(x: -dx).combined(with: .opacity)
        )
    }

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            StratumIsometricLogo(size: 96, accentColor: appearance.accentColor)
                .scaleEffect(appeared ? 1 : 0.7)
            Text("STRATUM")
                .font(.system(size: 60, weight: .bold, design: .rounded))
                .tracking(12)
                .foregroundStyle(.white)
            Text("Your Mac, in layers.")
                .font(.system(size: 19, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
            Text("Click anywhere on the sky to skip the tour")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.top, 14)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 14)
    }

    private var scanningStep: some View {
        VStack(spacing: 26) {
            header(
                symbol: "chart.pie.fill",
                title: "Mapping your Mac",
                text: "Stratum is scanning in the background so the storage map and cleanup tools are ready when you are. Nothing leaves this Mac."
            )
            WalkthroughScanProgress(coordinator: scanCoordinator, accent: appearance.accentColor)
        }
    }

    private var permissionStep: some View {
        VStack(spacing: 24) {
            header(
                symbol: "lock.shield.fill",
                title: "One permission",
                text: "To see protected folders like Library and caches, Stratum needs Full Disk Access. Without it they look empty and your storage totals come out too low."
            )

            if hasAccess {
                Label("Full Disk Access is on", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 0.45, green: 0.9, blue: 0.6))
                    .transition(.scale.combined(with: .opacity))
            } else {
                VStack(spacing: 10) {
                    Button {
                        FullDiskAccess.hasShownFirstRunPrompt = true
                        FullDiskAccess.openSystemSettings()
                    } label: {
                        Label("Open System Settings", systemImage: "gearshape.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .frame(height: 38)
                            .background(Capsule().fill(appearance.accentColor.opacity(0.85)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Text("Turn on Stratum under Privacy & Security → Full Disk Access. You can skip this and change it any time.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: hasAccess)
    }

    private var readyStep: some View {
        VStack(spacing: 26) {
            header(symbol: "checkmark.seal.fill", title: "You're all set", text: "A few things worth knowing:")
            VStack(alignment: .leading, spacing: 14) {
                tip("⌘K", "Search files, run actions, jump anywhere")
                tip("Double-click", "Open a folder in the storage map")
                tip("Groups", "Find node_modules, caches and other space hogs")
            }
            .frame(maxWidth: 500)
        }
    }

    private func header(symbol: String, title: String, text: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(appearance.accentColor)
                .frame(width: 76, height: 76)
                .background(Circle().fill(appearance.accentColor.opacity(0.16)))
                .overlay(Circle().strokeBorder(appearance.accentColor.opacity(0.4), lineWidth: 1))
                .shadow(color: appearance.accentColor.opacity(0.5), radius: 22)
            Text(title)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 470)
        }
    }

    private func tip(_ key: String, _ text: String) -> some View {
        HStack(spacing: 14) {
            Text(key)
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 96, height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.12)))
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    // MARK: Actions

    private func next() {
        guard revealStart == nil else { return }
        if let following = Step(rawValue: step.rawValue + 1) {
            goingForward = true
            withAnimation(.spring(response: 0.5, dampingFraction: 0.84)) { step = following }
        } else {
            reveal(at: center)
        }
    }

    private func back() {
        guard revealStart == nil, let previous = Step(rawValue: step.rawValue - 1) else { return }
        goingForward = false
        withAnimation(.spring(response: 0.5, dampingFraction: 0.84)) { step = previous }
    }

    private func reveal(at point: CGPoint) {
        guard revealStart == nil else { return }
        revealOrigin = point
        revealStart = Date()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.5 : Self.revealDuration))
            Walkthrough.hasCompleted = true
            FullDiskAccess.hasShownFirstRunPrompt = true
            onFinish()
        }
    }

    /// While the permission step is showing, notice the moment access is granted.
    private func watchAccess() async {
        guard step == .permission else { return }
        while !Task.isCancelled {
            FullDiskAccess.checkAccess { granted in
                hasAccess = granted
                appState.hasFullDiskAccess = granted
            }
            try? await Task.sleep(for: .seconds(1.5))
        }
    }
}

/// Live scan status. Reads progress here, not in the parent, so frequent updates only
/// redraw this small view.
private struct WalkthroughScanProgress: View {
    let coordinator: ScanCoordinator
    let accent: Color

    var body: some View {
        VStack(spacing: 10) {
            if coordinator.showsScanState {
                ProgressView(value: min(1, max(0, coordinator.progress.fraction)))
                    .progressViewStyle(.linear)
                    .tint(accent)
                    .frame(width: 340)
                Text("\(coordinator.progress.filesScanned.formatted()) files · \(Int((min(1, max(0, coordinator.progress.fraction)) * 100).rounded()))%")
                    .font(.system(size: 12.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
                    .contentTransition(.numericText())
                Text(coordinator.progress.currentPath)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 420)
            } else {
                Label("Scan ready · \(coordinator.scannedFileCount.formatted()) files mapped", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 0.45, green: 0.9, blue: 0.6))
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: coordinator.showsScanState)
        .frame(minHeight: 70)
    }
}
