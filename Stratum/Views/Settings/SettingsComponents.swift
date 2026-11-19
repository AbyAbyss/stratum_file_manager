import SwiftUI
import AppKit

// MARK: - Contrast

extension AppearanceManager {
    /// Text and icon colour that stays readable when drawn on the accent colour: dark on light
    /// accents (yellow, white), white on dark ones (black, indigo).
    var onAccent: Color {
        let c = activeNSColor.usingColorSpace(.sRGB) ?? .black
        let luminance = 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
        return luminance > 0.6 ? Color.black.opacity(0.88) : .white
    }
}

// MARK: - Group and rows

/// A titled block of rows on a card, like a section in macOS System Settings.
struct SettingsGroup<Content: View>: View {
    var title: String?
    var footer: String?
    var appearance: AppearanceManager
    @ViewBuilder var content: Content

    init(_ title: String? = nil, footer: String? = nil, appearance: AppearanceManager, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.appearance = appearance
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(appearance.cardGlassFillColor)
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                )
            if let footer {
                Text(footer)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }
}

/// Hairline between rows, inset like System Settings.
struct SettingsDivider: View {
    var body: some View {
        Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1).padding(.leading, 16)
    }
}

/// One row: a title and an optional explanation on the left, the control on the right.
/// Text wraps instead of truncating, so nothing is ever cut off.
struct SettingsRow<Trailing: View>: View {
    var title: String
    var detail: String?
    @ViewBuilder var trailing: Trailing

    init(_ title: String, detail: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.detail = detail
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13.5, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 52)
    }
}

struct SettingsToggleRow: View {
    var title: String
    var detail: String?
    @Binding var isOn: Bool
    var appearance: AppearanceManager
    var isLocked = false

    var body: some View {
        SettingsRow(title, detail: detail) {
            HStack(spacing: 8) {
                if isLocked { Image(systemName: "lock.fill").font(.system(size: 11)).foregroundStyle(.secondary) }
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(appearance.accentColor)
                    .disabled(isLocked)
                    .accessibilityLabel(title)
            }
        }
    }
}

// MARK: - Controls

/// A segmented choice with a sliding selection. Never truncates: it sizes to its labels.
struct SettingsSegmented<Value: Hashable>: View {
    var options: [(value: Value, label: String)]
    @Binding var selection: Value
    var appearance: AppearanceManager
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<options.count, id: \.self) { i in
                let option = options[i]
                let isSelected = option.value == selection
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { selection = option.value }
                } label: {
                    Text(option.label)
                        .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? appearance.onAccent : Color.secondary)
                        .padding(.horizontal, 13)
                        .frame(height: 28)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(appearance.accentColor)
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.07)))
        .fixedSize()
    }
}

/// A slider with its current value and what each end means.
struct SettingsSliderRow: View {
    var title: String
    var valueText: String
    var lowLabel: String
    var highLabel: String
    @Binding var value: Double
    var appearance: AppearanceManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.system(size: 13.5, weight: .medium))
                Spacer()
                Text(valueText)
                    .font(.system(size: 12.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                // Fixed-width end labels so every slider's track lines up with the others.
                Text(lowLabel).font(.system(size: 11.5)).foregroundStyle(.secondary).frame(width: 66, alignment: .trailing)
                Slider(value: $value, in: 0...100).tint(appearance.accentColor).accessibilityLabel(title)
                Text(highLabel).font(.system(size: 11.5)).foregroundStyle(.secondary).frame(width: 66, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// Buttons used across Settings. Primary uses the accent with a readable label colour.
struct SettingsButton: View {
    enum Kind { case primary, secondary, destructive }
    var title: String
    var systemImage: String?
    var kind: Kind = .secondary
    var appearance: AppearanceManager
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage).font(.system(size: 12, weight: .semibold)) }
                Text(title).font(.system(size: 12.5, weight: .semibold))
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(stroke, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(StratumInteractiveButtonStyle(hoverScale: 1.02, pressScale: 0.97))
        .onHover { hovering = $0 }
    }

    private var foreground: Color {
        switch kind {
        case .primary: return appearance.onAccent
        case .secondary: return .primary
        case .destructive: return Color(red: 0.9, green: 0.27, blue: 0.27)
        }
    }

    private var fill: Color {
        switch kind {
        case .primary: return appearance.accentColor
        case .secondary: return Color.primary.opacity(hovering ? 0.12 : 0.07)
        case .destructive: return Color(red: 0.9, green: 0.27, blue: 0.27).opacity(hovering ? 0.18 : 0.1)
        }
    }

    private var stroke: Color {
        kind == .primary ? .clear : Color.primary.opacity(0.08)
    }
}

/// A text field styled to match the rows.
struct SettingsTextField: View {
    var placeholder: String
    @Binding var text: String
    var monospaced = false
    var onSubmit: () -> Void = {}

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 13, design: monospaced ? .monospaced : .default))
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
            )
            .onSubmit(onSubmit)
    }
}
