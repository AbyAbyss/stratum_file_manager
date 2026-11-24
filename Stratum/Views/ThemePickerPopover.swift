import SwiftUI
import AppKit

/// The toolbar's theme switcher. Moving through the list (pointer or arrow keys) previews each
/// theme on the whole window; Return or a click keeps it, Esc or clicking away puts the
/// previous look back.
struct ThemePickerPopover: View {
    var appearance: AppearanceManager
    @Binding var isPresented: Bool
    /// Called with the theme the user kept.
    var onCommit: (StratumThemePreset) -> Void
    var onCustomize: () -> Void

    @State private var highlightedID: String?
    @State private var originalLook: AppearanceManager.LookSnapshot?
    @State private var didCommit = false
    /// Arrow keys scroll the list under a resting pointer; its hover must not steal the highlight.
    @State private var lastKeyboardMove = Date.distantPast
    @FocusState private var isFocused: Bool

    private var themes: [StratumThemePreset] { appearance.allThemes }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(themes) { preset in
                            row(preset)
                                .id(preset.id)
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 420)
                .onChange(of: highlightedID) { _, id in
                    guard let id, let preset = themes.first(where: { $0.id == id }) else { return }
                    appearance.applyThemePreset(preset)
                    if Date().timeIntervalSince(lastKeyboardMove) < 0.3 {
                        withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id) }
                    }
                }
                .onAppear {
                    originalLook = appearance.captureLook()
                    highlightedID = appearance.activeThemeID
                    proxy.scrollTo(appearance.activeThemeID, anchor: .center)
                    isFocused = true
                }
            }

            Divider()

            Button {
                isPresented = false   // closes without keeping the preview
                onCustomize()
            } label: {
                Label("Customize Theme, Blur & Glass…", systemImage: "slider.horizontal.3")
                    .font(.system(size: 12.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider()

            Text("↑↓ preview · ↩ keep · esc cancel")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .padding(.vertical, 6)
        }
        .frame(width: 300)
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { moveHighlight(by: -1) }
        .onKeyPress(.downArrow) { moveHighlight(by: 1) }
        .onKeyPress(.return) {
            guard let id = highlightedID, let preset = themes.first(where: { $0.id == id }) else { return .ignored }
            commit(preset)
            return .handled
        }
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
        .onDisappear {
            // Esc, clicking away, or "Customize": the preview was only a preview.
            if !didCommit, let originalLook { appearance.restoreLook(originalLook) }
        }
    }

    private func row(_ preset: StratumThemePreset) -> some View {
        let isHighlighted = preset.id == highlightedID
        let wasActive = preset.id == originalLook?.activeThemeID
        return Button {
            commit(preset)
        } label: {
            HStack(spacing: 9) {
                Circle()
                    .fill(Color(nsColor: NSColor(hex: preset.accentHex) ?? .controlAccentColor))
                    .frame(width: 10, height: 10)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5))
                Text(preset.name)
                    .font(.system(size: 13, weight: isHighlighted ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 6)
                if !preset.isBuiltIn {
                    Text("Custom")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                if wasActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isHighlighted ? appearance.selectionFillColor : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(isHighlighted ? appearance.selectionBorderColor.opacity(0.6) : Color.clear, lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            guard inside, Date().timeIntervalSince(lastKeyboardMove) > 0.4 else { return }
            highlightedID = preset.id
        }
        .accessibilityAddTraits(wasActive ? .isSelected : [])
    }

    private func moveHighlight(by step: Int) -> KeyPress.Result {
        guard !themes.isEmpty else { return .ignored }
        let current = themes.firstIndex { $0.id == highlightedID } ?? 0
        lastKeyboardMove = Date()
        highlightedID = themes[min(max(current + step, 0), themes.count - 1)].id
        return .handled
    }

    private func commit(_ preset: StratumThemePreset) {
        didCommit = true
        appearance.applyThemePreset(preset)
        isPresented = false
        onCommit(preset)
    }
}
