import SwiftUI
import AppKit

extension InspectorSidebarView {
    // MARK: - Preview Card (with live Code/Text Snippet Preview!)

    func previewCard(for item: FileItem) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.26))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )

            if item.isAppOrPackage {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [appearance.accentColor.opacity(0.28), .clear],
                                center: .center,
                                startRadius: 4,
                                endRadius: 68
                            )
                        )
                        .frame(width: 136, height: 136)

                    Image(nsImage: IconPipeline.shared.icon(for: item))
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 96, height: 96)
                        .shadow(color: .black.opacity(0.42), radius: 14, y: 6)
                }
            } else if item.isFolderLike {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(appearance.folderBackColor)
                        .frame(width: 56, height: 26)
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(appearance.folderFrontColor)
                        .frame(width: 132, height: 89)
                        .offset(y: 15)
                        .shadow(color: .black.opacity(0.38), radius: 14, y: 6)
                }
                .frame(width: 132, height: 104)
            } else if item.isImageOrVideo {
                ZStack {
                    if let thumb = previewThumbnail {
                        Image(nsImage: thumb)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 220, height: 142)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color(nsColor: NSColor(hex: item.badgeTintHex) ?? .systemBlue).opacity(0.45))
                            .frame(width: 220, height: 142)
                    }
                    if item.isVideo {
                        Circle()
                            .fill(Color.black.opacity(0.7))
                            .frame(width: 42, height: 42)
                            .overlay {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.white)
                                    .offset(x: 1)
                            }
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.95), lineWidth: 2.5)
                )
                .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
            } else if let snippet = textSnippet, !snippet.isEmpty {
                // Live Code / Text File Preview inside the Inspector!
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(item.displayExt)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color(nsColor: NSColor(hex: item.badgeTintHex) ?? .darkGray))
                            )
                        Spacer()
                        Text("Live Preview")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Text(snippet)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.primary.opacity(0.88))
                        .lineLimit(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
            } else {
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: NSColor(hex: "#EFEDF6") ?? .white))
                        .frame(width: 100, height: 132)
                        .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
                        .overlay(alignment: .topLeading) {
                            VStack(alignment: .leading, spacing: 7) {
                                Capsule().fill(Color(nsColor: NSColor(hex: "#9F9AB5") ?? .gray)).frame(width: 50, height: 7)
                                Capsule().fill(Color(nsColor: NSColor(hex: "#C9C5D8") ?? .lightGray)).frame(width: 72, height: 4)
                                Capsule().fill(Color(nsColor: NSColor(hex: "#C9C5D8") ?? .lightGray)).frame(width: 72, height: 4)
                                Capsule().fill(Color(nsColor: NSColor(hex: "#C9C5D8") ?? .lightGray)).frame(width: 60, height: 4)
                                Capsule().fill(Color(nsColor: NSColor(hex: "#C9C5D8") ?? .lightGray)).frame(width: 40, height: 4)
                            }
                            .padding(.horizontal, 14)
                            .padding(.top, 18)
                        }

                    Text(item.displayExt)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color(nsColor: NSColor(hex: item.badgeTintHex) ?? .darkGray))
                        )
                        .offset(x: -10, y: -14)
                }
            }
        }
        .frame(height: 168)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            appState.openItem(item)
        }
    }
}
