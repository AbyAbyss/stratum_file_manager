import SwiftUI
import AppKit

enum BatchRenameMode: String, CaseIterable {
    case replace = "Replace Text"
    case addText = "Add Text"
    case formatNumber = "Name & Index"
}

struct BatchRenameSheet: View {
    @Bindable var appState: AppState
    var appearance: AppearanceManager

    @State private var mode: BatchRenameMode = .replace
    @State private var findText: String = ""
    @State private var replaceText: String = ""
    @State private var addText: String = ""
    @State private var addAsPrefix: Bool = false
    @State private var customBaseName: String = "Item"
    @State private var startIndex: Int = 1

    private var targetItems: [FileItem] {
        let sel = appState.selectedItems
        return sel.isEmpty ? Array(appState.displayedItems.prefix(10)) : sel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Batch Rename \(targetItems.count) \(targetItems.count == 1 ? "Item" : "Items")")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Picker("", selection: $mode) {
                    ForEach(BatchRenameMode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 290)
            }

            // Mode controls
            Group {
                switch mode {
                case .replace:
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Find")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.secondary)
                            TextField("Text to find", text: $findText)
                                .textFieldStyle(.roundedBorder)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Replace with")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.secondary)
                            TextField("Replacement text", text: $replaceText)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                case .addText:
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Text to add")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.secondary)
                            TextField("e.g. -final or v2_", text: $addText)
                                .textFieldStyle(.roundedBorder)
                        }
                        Picker("Position", selection: $addAsPrefix) {
                            Text("After name").tag(false)
                            Text("Before name").tag(true)
                        }
                        .frame(width: 170)
                        .padding(.top, 16)
                    }

                case .formatNumber:
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Base Name")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.secondary)
                            TextField("Base name", text: $customBaseName)
                                .textFieldStyle(.roundedBorder)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Start Number")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.secondary)
                            TextField("1", value: $startIndex, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 90)
                        }
                    }
                }
            }

            Text("Live Preview")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(Array(targetItems.enumerated()), id: \.element.id) { idx, item in
                        let newName = computeNewName(for: item, index: idx)
                        HStack(spacing: 8) {
                            Text(item.name)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Image(systemName: "arrow.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.tertiary)

                            Text(newName)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(newName != item.name ? appearance.accentColor : .primary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                        )
                    }
                }
            }
            .frame(height: 190)

            HStack {
                Spacer()
                Button("Cancel") {
                    appState.showBatchRename = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Rename") {
                    applyBatchRename()
                }
                .buttonStyle(.borderedProminent)
                .tint(appearance.accentColor)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 540)
    }

    func computeNewName(for item: FileItem, index: Int) -> String {
        let ns = item.name as NSString
        let ext = ns.pathExtension
        let stem = ns.deletingPathExtension

        let newStem: String
        switch mode {
        case .replace:
            guard !findText.isEmpty else { return item.name }
            newStem = stem.replacingOccurrences(of: findText, with: replaceText)
        case .addText:
            newStem = addAsPrefix ? "\(addText)\(stem)" : "\(stem)\(addText)"
        case .formatNumber:
            let num = String(format: "%02d", startIndex + index)
            newStem = "\(customBaseName) \(num)"
        }

        return ext.isEmpty ? newStem : "\(newStem).\(ext)"
    }

    private func applyBatchRename() {
        let pairs: [(oldURL: URL, newURL: URL)] = targetItems.enumerated().compactMap { idx, item in
            let nextName = computeNewName(for: item, index: idx)
            guard nextName != item.name, !nextName.isEmpty else { return nil }
            let dst = item.url.deletingLastPathComponent().appendingPathComponent(nextName)
            return (item.url, dst)
        }

        appState.showBatchRename = false
        guard !pairs.isEmpty else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            var renamedCount = 0
            for pair in pairs {
                if (try? fm.moveItem(at: pair.oldURL, to: pair.newURL)) != nil {
                    renamedCount += 1
                }
            }
            Task { @MainActor in
                appState.reloadCurrentDirectory(preserveSelection: false)
                appState.showToast("Renamed \(renamedCount) \(renamedCount == 1 ? "item" : "items")")
            }
        }
    }
}
