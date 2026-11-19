import SwiftUI
import AppKit

/// A miniature Stratum window drawn with the current theme, so every change in Appearance is
/// visible straight away without leaving the page.
struct SettingsLivePreview: View {
    var appearance: AppearanceManager

    var body: some View {
        ZStack {
            // A stand-in for the desktop wallpaper behind the glass.
            LinearGradient(
                colors: [Color(nsColor: appearance.windowSurfaceNSColor), appearance.accentColor.opacity(0.45)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Circle().fill(appearance.accentColor.opacity(0.35)).frame(width: 170).blur(radius: 50).offset(x: -170, y: 40)
            Circle().fill(appearance.accentColor.opacity(0.25)).frame(width: 140).blur(radius: 46).offset(x: 190, y: -50)

            miniWindow
                .frame(width: 440, height: 168)
                .shadow(color: .black.opacity(0.35), radius: 22, y: 10)
        }
        .frame(height: 224)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Live preview of the current theme")
    }

    private var miniWindow: some View {
        HStack(spacing: 0) {
            // Sidebar
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    ForEach([Color.red, .yellow, .green], id: \.self) { c in Circle().fill(c.opacity(0.85)).frame(width: 7, height: 7) }
                }
                .padding(.bottom, 4)
                sidebarItem("Desktop", selected: true)
                sidebarItem("Documents", selected: false)
                sidebarItem("Downloads", selected: false)
                Spacer()
            }
            .padding(10)
            .frame(width: 118)
            .background(appearance.sidebarGlassColor)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                previewRow("Brand Refresh", "15 items", folder: true, selected: true)
                previewRow("Client Work", "8 items", folder: true, selected: false)
                previewRow("Invoice 1042.pdf", "84 KB", folder: false, selected: false)
                Spacer(minLength: 4)
                HStack(spacing: 8) {
                    Capsule().fill(Color.primary.opacity(0.14)).frame(height: 5)
                        .overlay(alignment: .leading) { GeometryReader { g in Capsule().fill(appearance.accentColor).frame(width: g.size.width * 0.64) } }
                    Text("64%").font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)
                }
                .frame(height: 12)
                HStack {
                    Spacer()
                    Text("Clean")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(appearance.onAccent)
                        .padding(.horizontal, 12).frame(height: 22)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(appearance.accentColor))
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(appearance.cardGlassFillColor)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(appearance.selectionBorderColor.opacity(0.7), lineWidth: 1))
    }

    private func sidebarItem(_ name: String, selected: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "folder.fill").font(.system(size: 9)).foregroundStyle(appearance.accentColor)
            Text(name).font(.system(size: 10.5, weight: selected ? .semibold : .regular)).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6).frame(height: 20)
        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(selected ? appearance.selectionTintColor : .clear))
    }

    private func previewRow(_ name: String, _ sub: String, folder: Bool, selected: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: folder ? "folder.fill" : "doc").font(.system(size: 11)).foregroundStyle(folder ? appearance.folderFrontColor : .secondary)
            Text(name).font(.system(size: 11, weight: selected ? .semibold : .regular)).lineLimit(1)
            Spacer()
            Text(sub).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 7)
        .frame(height: appearance.density.rowHeight - 6)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(selected ? appearance.selectionTintColor : .clear))
    }
}
