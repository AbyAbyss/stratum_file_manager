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

            // First-launch walkthrough (night sky, scan, permission, water-break reveal)
            if appState.showWalkthrough {
                WalkthroughView(appState: appState, appearance: appearance) {
                    appState.finishWalkthrough()
                }
                .zIndex(150)
            }

            // Startup Logo & Motion Graphics Overlay
            if appState.showStartupSplash && !appState.showWalkthrough {
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

// MARK: - Startup Splash Animation View

// MARK: - Custom macOS Dock AppIcon Generator

// MARK: - Reusable Motion Graphics & Interactive Modifiers
