import SwiftUI
import AppKit
import CryptoKit

extension SmartOrganizerView {
    // MARK: - Mode 2: Exact Duplicate File Finder (SHA-256 Verified)

    var duplicateFinderSection: some View {
        let totalReclaimable = duplicateClusters.reduce(Int64(0)) { $0 + $1.reclaimableBytes }

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SHA-256 Verified Duplicate Files")
                        .font(.system(size: 16, weight: .bold))
                    Text("Found \(duplicateClusters.count) identical file sets (\(BulkDirectoryReader.fastFormatBytes(totalReclaimable)) reclaimable) across your workspace.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    autoSelectRedundantDuplicates()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.badge.questionmark")
                            .font(.system(size: 11.5, weight: .semibold))
                        Text("Auto-Select Redundant Copies (Keep Original)")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(appearance.selectionFillColor)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(appearance.selectionBorderColor, lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(StratumInteractiveButtonStyle())
                .disabled(duplicateClusters.isEmpty)

                if !selectedDuplicatePaths.isEmpty {
                    Button {
                        trashSelectedDuplicates()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 11.5))
                            Text("Trash \(selectedDuplicatePaths.count) Selected (\(BulkDirectoryReader.fastFormatBytes(selectedDuplicatesBytes)))")
                                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(appearance.accentColor)
                        )
                    }
                    .buttonStyle(StratumInteractiveButtonStyle())
                }

                Button {
                    scanForExactDuplicates()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                        )
                }
                .buttonStyle(StratumInteractiveButtonStyle())
                .help("Rescan for duplicate files")
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            )

            if isScanningDuplicates {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Verifying exact file hashes with SHA-256…")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
            } else if duplicateClusters.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(appearance.accentColor)
                    Text("No duplicate files found!")
                        .font(.system(size: 15, weight: .semibold))
                    Text("All scanned files in \(targetFolderURL.lastPathComponent), Desktop, and Documents are unique.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 44)
            } else {
                VStack(spacing: 10) {
                    ForEach(duplicateClusters) { cluster in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(cluster.fileName)
                                    .font(.system(size: 13.5, weight: .semibold))
                                Text("· \(cluster.items.count) identical copies · \(BulkDirectoryReader.fastFormatBytes(cluster.sizeBytes)) each")
                                    .font(.system(size: 12).monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("SHA-256: \(cluster.hashHex.prefix(12))…")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }

                            ForEach(Array(cluster.items.enumerated()), id: \.element.id) { idx, file in
                                let isChecked = selectedDuplicatePaths.contains(file.id)
                                Button {
                                    if isChecked {
                                        selectedDuplicatePaths.remove(file.id)
                                    } else {
                                        selectedDuplicatePaths.insert(file.id)
                                    }
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                                            .font(.system(size: 14))
                                            .foregroundStyle(isChecked ? appearance.accentColor : .secondary)

                                        Image(nsImage: IconPipeline.shared.icon(for: file))
                                            .resizable()
                                            .frame(width: 18, height: 18)

                                        Text(file.id)
                                            .font(.system(size: 12, design: .monospaced))
                                            .lineLimit(1)
                                            .truncationMode(.middle)

                                        if idx == 0 {
                                            Text("KEEP ORIGINAL")
                                                .font(.system(size: 9.5, weight: .bold))
                                                .foregroundStyle(appearance.accentColor)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Capsule().fill(appearance.selectionFillColor))
                                        }

                                        Spacer()

                                        Text(file.formattedModDate)
                                            .font(.system(size: 11.5).monospacedDigit())
                                            .foregroundStyle(.secondary)

                                        Button("Reveal") {
                                            appState.navigate(to: file.url.deletingLastPathComponent())
                                            appState.selectedItemIDs = [file.id]
                                        }
                                        .buttonStyle(.plain)
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .foregroundStyle(appearance.accentColor)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(isChecked ? appearance.faintTintColor : Color.primary.opacity(0.03))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                    .strokeBorder(isChecked ? appearance.selectionBorderColor : Color.clear, lineWidth: 1)
                                            )
                                    )
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
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
