import SwiftUI
import AppKit

struct MainWindowView: View {
    @Bindable var appState: AppState
    @Bindable var appearance: AppearanceManager

    var body: some View {
        ZStack {
            // Real macOS Window Vibrancy Material (configurable per theme: HUD Deep Glass, Desktop Vibrancy, Frosted Crystal, Obsidian Acrylic)
            if appearance.enableBlur && !appearance.reduceTransparency {
                VisualEffectBackground(
                    material: appearance.blurStyle.nsMaterial,
                    blendingMode: .behindWindow,
                    state: .followsWindowActiveState
                )
                .ignoresSafeArea()
            }

            // Theme Window Glass Surface Tint (respects translucency slider)
            appearance.windowGlassColor
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // Optional subtle ambient accent wash in window header/sidebar
            if appearance.enableWallpaperWash && !appearance.reduceTransparency {
                RadialGradient(
                    colors: [
                        appearance.accentColor.opacity(0.11 * appearance.glowFraction),
                        appearance.accentColor.opacity(0.03 * appearance.glowFraction),
                        .clear
                    ],
                    center: .topLeading,
                    startRadius: 10,
                    endRadius: 560
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            VStack(spacing: 0) {
                ToolbarView(appState: appState, appearance: appearance)

                HStack(spacing: 0) {
                    if appState.showSidebar {
                        SidebarView(appState: appState, appearance: appearance)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }

                    // Opacity-only: scaling/offsetting two full screens at once is what made
                    // switching between heavy screens (Groups, Storage) stutter.
                    ZStack {
                        contentArea
                            .id(appState.screen)
                            .transition(.opacity)
                    }
                    .animation(.easeOut(duration: 0.16), value: appState.screen)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .animation(.spring(response: 0.32, dampingFraction: 0.84), value: appState.showSidebar)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if appState.screen == .browser {
                    StatusBarView(appState: appState, appearance: appearance)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            // Command Palette Modal Overlay (Cmd+K)
            if appState.showCommandPalette {
                CommandPaletteView(appState: appState, appearance: appearance)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(10)
            }

            // Toast notification with spring entrance
            if let toast = appState.toastMessage {
                VStack {
                    Spacer()
                    HStack(spacing: 9) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color(nsColor: NSColor(hex: "#5FD38D") ?? .systemGreen))
                            .symbolEffect(.bounce, value: toast)
                        Text(toast)
                            .font(.system(size: 12.5, weight: .medium))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        Capsule()
                            .fill(.ultraThickMaterial)
                            .overlay(
                                Capsule()
                                    .strokeBorder(appearance.selectionBorderColor, lineWidth: 1)
                            )
                    )
                    .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                    .padding(.bottom, 42)
                }
                .transition(.move(edge: .bottom).combined(with: .scale(scale: 0.9)).combined(with: .opacity))
                .zIndex(20)
            }

            // Startup Logo & Motion Graphics Overlay
            if appState.showStartupSplash {
                StratumStartupSplashView(appearance: appearance) {
                    withAnimation(.spring(response: 0.52, dampingFraction: 0.86)) {
                        appState.showStartupSplash = false
                    }
                }
                .transition(
                    .asymmetric(
                        insertion: .opacity,
                        removal: .opacity.combined(with: .scale(scale: 1.06))
                    )
                )
                .zIndex(100)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .sheet(isPresented: $appState.showFDASheet) {
            FirstRunFDASheet(appState: appState, appearance: appearance)
        }
        .sheet(isPresented: $appState.showGoToFolder) {
            GoToFolderSheet(appState: appState, appearance: appearance)
        }
        .sheet(isPresented: $appState.showBatchRename) {
            BatchRenameSheet(appState: appState, appearance: appearance)
        }
        .onAppear {
            appearance.applyWindowAppearance()
            StratumAppIconGenerator.applyCustomDockIcon(accentColor: NSColor(hex: appearance.activeHexString) ?? .systemGreen)
        }
        .onChange(of: appearance.activeHexString) { _, newHex in
            StratumAppIconGenerator.applyCustomDockIcon(accentColor: NSColor(hex: newHex) ?? .systemGreen)
        }
    }

    @ViewBuilder
    private var contentArea: some View {
        switch appState.screen {
        case .browser:
            BrowserContainerView(appState: appState, appearance: appearance)
        case .organizer:
            DeferredContent { SmartOrganizerView(appState: appState, appearance: appearance) }
        case .groups:
            DeferredContent { GroupsByNameView(appState: appState, appearance: appearance) }
        case .storage:
            DeferredContent { StorageMapView(appState: appState, appearance: appearance) }
        case .settings:
            DeferredContent { AppearanceSettingsView(appState: appState, appearance: appearance) }
        }
    }
}

// MARK: - Stratum Isometric 3D Layered Logo View

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

// MARK: - Startup Splash Animation View

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

// MARK: - Custom macOS Dock AppIcon Generator

enum StratumAppIconGenerator {
    @MainActor
    static func applyCustomDockIcon(accentColor: NSColor) {
        let size = NSSize(width: 512, height: 512)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            // macOS Squircle Background
            let insetRect = rect.insetBy(dx: 28, dy: 28)
            let squircle = NSBezierPath(roundedRect: insetRect, xRadius: 104, yRadius: 104)

            ctx.saveGState()
            squircle.addClip()

            let bgColors = [
                NSColor(calibratedRed: 0.05, green: 0.08, blue: 0.07, alpha: 1.0).cgColor,
                NSColor(calibratedRed: 0.09, green: 0.14, blue: 0.12, alpha: 1.0).cgColor
            ] as CFArray
            if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: bgColors, locations: [0.0, 1.0]) {
                ctx.drawLinearGradient(
                    grad,
                    start: CGPoint(x: insetRect.minX, y: insetRect.maxY),
                    end: CGPoint(x: insetRect.maxX, y: insetRect.minY),
                    options: []
                )
            }

            // Radial accent glow in center
            let glowColors = [
                accentColor.withAlphaComponent(0.42).cgColor,
                accentColor.withAlphaComponent(0.0).cgColor
            ] as CFArray
            if let radial = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: glowColors, locations: [0.0, 1.0]) {
                ctx.drawRadialGradient(
                    radial,
                    startCenter: CGPoint(x: 256, y: 256),
                    startRadius: 10,
                    endCenter: CGPoint(x: 256, y: 256),
                    endRadius: 210,
                    options: []
                )
            }

            // Draw 3 Isometric Stratum Plates
            let plateOffsets: [(yCenter: CGFloat, alpha: CGFloat, highlight: Bool)] = [
                (176, 0.42, false),
                (252, 0.75, false),
                (328, 1.00, true)
            ]

            for plate in plateOffsets {
                let w: CGFloat = 290
                let h: CGFloat = 152
                let cx: CGFloat = 256
                let cy: CGFloat = plate.yCenter

                let diamond = NSBezierPath()
                diamond.move(to: CGPoint(x: cx, y: cy + h * 0.5))
                diamond.line(to: CGPoint(x: cx + w * 0.5, y: cy))
                diamond.line(to: CGPoint(x: cx, y: cy - h * 0.5))
                diamond.line(to: CGPoint(x: cx - w * 0.5, y: cy))
                diamond.close()

                ctx.saveGState()
                ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 20, color: NSColor.black.withAlphaComponent(0.45).cgColor)

                if plate.highlight {
                    accentColor.setFill()
                } else {
                    accentColor.withAlphaComponent(plate.alpha).setFill()
                }
                diamond.fill()
                ctx.restoreGState()

                NSColor.white.withAlphaComponent(plate.highlight ? 0.85 : 0.35).setStroke()
                diamond.lineWidth = plate.highlight ? 5.0 : 3.0
                diamond.stroke()
            }

            ctx.restoreGState()

            // Outer squircle rim highlight
            NSColor.white.withAlphaComponent(0.18).setStroke()
            squircle.lineWidth = 4.0
            squircle.stroke()

            return true
        }

        NSApplication.shared.applicationIconImage = image
    }
}

// MARK: - Reusable Motion Graphics & Interactive Modifiers

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

struct StratumHoverCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 12
    var accentColor: Color
    var scaleAmount: CGFloat = 1.008

    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? scaleAmount : 1.0)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        isHovered ? accentColor.opacity(0.38) : Color.clear,
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)
            )
            .shadow(
                color: .black.opacity(isHovered ? 0.18 : 0.0),
                radius: isHovered ? 12 : 0,
                y: isHovered ? 4 : 0
            )
            .animation(.spring(response: 0.26, dampingFraction: 0.78), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

extension View {
    func stratumHoverCard(cornerRadius: CGFloat = 12, accent: Color, scale: CGFloat = 1.008) -> some View {
        modifier(StratumHoverCardModifier(cornerRadius: cornerRadius, accentColor: accent, scaleAmount: scale))
    }

    func stratumScrollMotion() -> some View {
        self.scrollTransition(.animated(.spring(response: 0.34, dampingFraction: 0.82))) { content, phase in
            content
                .opacity(phase.isIdentity ? 1.0 : 0.68)
                .scaleEffect(phase.isIdentity ? 1.0 : 0.965)
                .offset(y: phase.isIdentity ? 0 : (phase.value > 0 ? 10 : -6))
        }
    }
}

// MARK: - Live Smart Auto-Sync Indicator Pill

struct StratumLiveSyncPill: View {
    var scanCoordinator = ScanCoordinator.shared
    var appearance: AppearanceManager

    @State private var pulse = false
    @State private var spinAngle: Double = 0

    var body: some View {
        Menu {
            Toggle("Smart Background Auto-Refresh", isOn: Bindable(scanCoordinator).autoRefreshEnabled)

            Divider()

            Button {
                let rootURL = URL(fileURLWithPath: scanCoordinator.scannedRootPath)
                scanCoordinator.startScan(at: rootURL, silent: true)
            } label: {
                Label("Refresh Storage Silently Now", systemImage: "arrow.triangle.2.circlepath")
            }

            Button {
                let rootURL = URL(fileURLWithPath: scanCoordinator.scannedRootPath)
                scanCoordinator.startScan(at: rootURL, silent: false)
            } label: {
                Label("Run Full Foreground Scan", systemImage: "bolt.horizontal.circle")
            }

            if let last = scanCoordinator.lastScanDate {
                Divider()
                Text("Last synced: \(last.formatted(date: .omitted, time: .standard))")
            }
        } label: {
            HStack(spacing: 6) {
                if scanCoordinator.isBackgroundRefreshing || scanCoordinator.isScanning {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(appearance.accentColor)
                        .rotationEffect(.degrees(spinAngle))
                        .onAppear {
                            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                                spinAngle = 360
                            }
                        }
                    Text(scanCoordinator.isBackgroundRefreshing ? "Auto-Syncing…" : "Scanning…")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(appearance.accentColor)
                } else {
                    ZStack {
                        if scanCoordinator.autoRefreshEnabled {
                            Circle()
                                .fill(appearance.accentColor.opacity(0.35))
                                .frame(width: 11, height: 11)
                                .scaleEffect(pulse ? 1.35 : 0.8)
                                .opacity(pulse ? 0.0 : 0.7)
                        }
                        Circle()
                            .fill(scanCoordinator.autoRefreshEnabled ? appearance.accentColor : Color.secondary.opacity(0.5))
                            .frame(width: 6.5, height: 6.5)
                    }
                    Text(scanCoordinator.autoRefreshEnabled ? "Auto-Sync Live" : "Auto-Sync Paused")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(scanCoordinator.autoRefreshEnabled ? appearance.accentColor : .secondary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(scanCoordinator.autoRefreshEnabled ? appearance.accentColor.opacity(0.8) : .secondary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 25)
            .background(
                Capsule()
                    .fill(appearance.accentColor.opacity(0.12))
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                appearance.accentColor.opacity(0.42),
                                lineWidth: 1
                            )
                    )
            )
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}
