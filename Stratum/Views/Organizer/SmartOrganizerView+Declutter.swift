import SwiftUI
import AppKit
import CryptoKit

extension SmartOrganizerView {
    // MARK: - Mode 1: 1-Click Folder Declutter & Auto-Organizer

    var folderOrganizerSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            // 1. Summary Action Banner
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(appearance.accentColor.opacity(0.18))
                        .frame(width: 48, height: 48)
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(appearance.accentColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("\(targetFolderURL.lastPathComponent) has \(totalOrganizableFiles) loose \(totalOrganizableFiles == 1 ? "file" : "files") (\(BulkDirectoryReader.fastFormatBytes(totalOrganizableBytes)))")
                        .font(.system(size: 16, weight: .bold))
                        .contentTransition(.numericText())
                    Text("Nothing is moved automatically — click any category below (or Organize All) to create its folder inside \(targetFolderURL.path).")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !lastOrganizeMoves.isEmpty {
                    Button {
                        undoLastOrganize()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 11.5, weight: .semibold))
                            Text("Undo Last Move (\(lastOrganizeMoves.count))")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.primary.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(StratumInteractiveButtonStyle())
                }

                Button {
                    organizeBuckets(organizerBuckets)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12.5, weight: .bold))
                        Text("Organize All Categories (\(totalOrganizableFiles))")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(totalOrganizableFiles == 0 ? Color.secondary.opacity(0.35) : appearance.accentColor)
                            .shadow(color: totalOrganizableFiles == 0 ? .clear : appearance.accentColor.opacity(0.45), radius: 8, y: 2)
                    )
                }
                .buttonStyle(StratumInteractiveButtonStyle())
                .disabled(totalOrganizableFiles == 0)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(appearance.selectionBorderColor.opacity(0.7), lineWidth: 1)
                    )
            )

            // 2. Category Folders Created by Stratum inside Target Folder
            if !organizedFolders.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color(nsColor: NSColor(hex: "#5FD38D") ?? .systemGreen))
                        Text("Created Category Folders in \(targetFolderURL.lastPathComponent)")
                            .font(.system(size: 14, weight: .bold))
                        Text("· Folders you clicked to create · Open in Browser or Unpack back to \(targetFolderURL.lastPathComponent)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 14),
                            GridItem(.flexible(), spacing: 14)
                        ],
                        spacing: 14
                    ) {
                        ForEach(organizedFolders) { org in
                            let tint = Color(nsColor: NSColor(hex: org.tintHex) ?? .systemGreen)
                            let badgeTint: Color = .stratumLabel(tint)
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 10) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .fill(tint.opacity(0.22))
                                            .frame(width: 36, height: 36)
                                        Image(systemName: "folder.fill")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(tint)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text("\(org.folderName)/")
                                                .font(.system(size: 14, weight: .bold))
                                            Text("CREATED BY YOU")
                                                .font(.system(size: 9.5, weight: .bold))
                                                .foregroundStyle(badgeTint)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 1.5)
                                                .background(Capsule().fill(tint.opacity(0.16)))
                                        }
                                        Text("\(org.items.count) \(org.items.count == 1 ? "file" : "files") inside · \(BulkDirectoryReader.fastFormatBytes(org.totalBytes)) · \(org.folderURL.path)")
                                            .font(.system(size: 11.5).monospacedDigit())
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }

                                    Spacer()
                                }

                                // Sample files inside the organized folder
                                VStack(spacing: 4) {
                                    ForEach(org.items.prefix(3)) { file in
                                        HStack(spacing: 8) {
                                            Image(nsImage: IconPipeline.shared.icon(for: file))
                                                .resizable()
                                                .frame(width: 15, height: 15)
                                            Text(file.name)
                                                .font(.system(size: 11.5))
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                            Spacer()
                                            Text(file.formattedSize)
                                                .font(.system(size: 11).monospacedDigit())
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3.5)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .fill(Color.primary.opacity(0.035))
                                        )
                                    }
                                    if org.items.count > 3 {
                                        Text("+ \(org.items.count - 3) more files inside \(org.folderName)/…")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                            .padding(.leading, 8)
                                    }
                                }

                                HStack(spacing: 8) {
                                    Button {
                                        appState.navigate(to: org.folderURL)
                                    } label: {
                                        HStack(spacing: 5) {
                                            Image(systemName: "folder.fill")
                                                .font(.system(size: 11, weight: .semibold))
                                            Text("Open \"\(org.folderName)\" in Browser")
                                                .font(.system(size: 11.5, weight: .semibold))
                                        }
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 30)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .fill(appearance.accentColor)
                                        )
                                    }
                                    .buttonStyle(StratumInteractiveButtonStyle())

                                    Button {
                                        appState.navigate(to: targetFolderURL)
                                        appState.selectedItemIDs = [org.folderURL.path]
                                    } label: {
                                        Text("Highlight in \(targetFolderURL.lastPathComponent)")
                                            .font(.system(size: 11.5, weight: .medium))
                                            .padding(.horizontal, 10)
                                            .frame(height: 30)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                    .fill(Color.primary.opacity(0.07))
                                            )
                                    }
                                    .buttonStyle(StratumInteractiveButtonStyle())

                                    Button {
                                        unpackOrganizedFolder(org)
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "arrow.uturn.backward")
                                                .font(.system(size: 10.5, weight: .bold))
                                            Text("Unpack")
                                                .font(.system(size: 11.5, weight: .medium))
                                        }
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 10)
                                        .frame(height: 30)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .fill(Color.primary.opacity(0.06))
                                        )
                                    }
                                    .buttonStyle(StratumInteractiveButtonStyle())
                                    .help("Move all files back out to \(targetFolderURL.lastPathComponent) and remove \(org.folderName)/")
                                }
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(appearance.faintTintColor)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(appearance.selectionBorderColor, lineWidth: 1)
                                    )
                            )
                        }
                    }
                }
            }

            // 3. Loose Unorganized Files Waiting to be Clicked & Organized
            if !organizerBuckets.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Loose Files in \(targetFolderURL.lastPathComponent) — Click a Category to Create Folder & Move")
                        .font(.system(size: 14, weight: .bold))

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 14),
                            GridItem(.flexible(), spacing: 14)
                        ],
                        spacing: 14
                    ) {
                        ForEach(organizerBuckets) { bucket in
                            let bucketColor = Color(nsColor: NSColor(hex: bucket.tintHex) ?? .systemBlue)
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 10) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .fill(bucketColor.opacity(0.20))
                                            .frame(width: 34, height: 34)
                                        Image(systemName: bucket.icon)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(bucketColor)
                                    }

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(bucket.title)
                                            .font(.system(size: 13.5, weight: .semibold))
                                        Text("\(bucket.items.count) \(bucket.items.count == 1 ? "file" : "files") · \(BulkDirectoryReader.fastFormatBytes(bucket.totalBytes))")
                                            .font(.system(size: 11.5).monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()
                                }

                                VStack(spacing: 4) {
                                    ForEach(bucket.items.prefix(4)) { file in
                                        HStack(spacing: 8) {
                                            Image(nsImage: IconPipeline.shared.icon(for: file))
                                                .resizable()
                                                .frame(width: 16, height: 16)
                                            Text(file.name)
                                                .font(.system(size: 12))
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                            Spacer()
                                            Text(file.formattedSize)
                                                .font(.system(size: 11).monospacedDigit())
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .fill(Color.primary.opacity(0.035))
                                        )
                                    }
                                    if bucket.items.count > 4 {
                                        Text("+ \(bucket.items.count - 4) more files…")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.tertiary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.leading, 8)
                                    }
                                }

                                Spacer(minLength: 0)

                                HStack(spacing: 8) {
                                    Button {
                                        organizeBuckets([bucket])
                                    } label: {
                                        HStack(spacing: 5) {
                                            Image(systemName: "folder.badge.plus")
                                                .font(.system(size: 11, weight: .semibold))
                                            Text("Create & Move to \"\(bucket.folderName)/\"")
                                                .font(.system(size: 11.5, weight: .semibold))
                                        }
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 30)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .fill(appearance.accentColor)
                                        )
                                    }
                                    .buttonStyle(StratumInteractiveButtonStyle())

                                    if bucket.isCleanupCandidate {
                                        Button {
                                            let targets = bucket.items.map { (url: $0.url, size: $0.size) }
                                            appState.moveURLsToTrash(targets)
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                                reloadTargetFolder()
                                            }
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: "trash")
                                                    .font(.system(size: 11, weight: .semibold))
                                                Text("Trash All")
                                                    .font(.system(size: 11.5, weight: .semibold))
                                            }
                                            .foregroundStyle(Color(nsColor: NSColor(hex: "#FF6B6B") ?? .systemRed))
                                            .padding(.horizontal, 12)
                                            .frame(height: 30)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                    .fill(Color(nsColor: NSColor(hex: "#FF6B6B") ?? .systemRed).opacity(0.14))
                                            )
                                        }
                                        .buttonStyle(StratumInteractiveButtonStyle())
                                    }
                                }
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.primary.opacity(0.04))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                                    )
                            )
                            .stratumScrollMotion()
                        }
                    }
                }
            }
        }
    }
}
