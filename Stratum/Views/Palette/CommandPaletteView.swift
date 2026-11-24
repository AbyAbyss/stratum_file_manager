import SwiftUI
import AppKit

struct CommandPaletteView: View {
    @Bindable var appState: AppState
    var appearance: AppearanceManager

    @State var query: String = ""
    @State var activeChips: [SearchFilterChip] = []
    @State var scopeTab: PaletteTabScope = .all
    @State var searchEverywhere: Bool = true
    @State var nameResults: [SpotlightResultItem] = []
    @State var contentResults: [SpotlightResultItem] = []
    @State var selectedResultID: String? = nil
    @FocusState var isSearchFocused: Bool

    var selectedResult: SpotlightResultItem? {
        if let id = selectedResultID {
            if let m = nameResults.first(where: { $0.id == id }) { return m }
            if let c = contentResults.first(where: { $0.id == id }) { return c }
        }
        return nameResults.first ?? contentResults.first
    }

    var totalResultCount: Int {
        nameResults.count + contentResults.count
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Backdrop click-to-dismiss
            Color.black.opacity(0.50)
                .ignoresSafeArea()
                .onTapGesture {
                    appState.showCommandPalette = false
                }

            // Palette Dialog
            VStack(spacing: 0) {
                topInputBar
                scopeFilterBar

                HStack(spacing: 0) {
                    resultsListColumn
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    previewSidebar
                        .frame(width: 270)
                }
                .frame(height: 430)

                footerBar
            }
            .frame(maxWidth: 860)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThickMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(appearance.selectionBorderColor, lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.65), radius: 45, y: 24)
            .padding(.top, 64)
            .padding(.horizontal, 16)
        }
        .onAppear {
            isSearchFocused = true
            runSearch()
        }
        .onChange(of: query) { _, newValue in
            parseInlineFilterTokensIfNeeded(newValue)
            if newValue.hasPrefix(">") {
                scopeTab = .actions
            } else if newValue.hasPrefix("#") {
                scopeTab = .tags
            }
            runSearch()
        }
        .onChange(of: activeChips) { _, _ in
            runSearch()
        }
        .onChange(of: searchEverywhere) { _, _ in
            runSearch()
        }
        .onExitCommand {
            appState.showCommandPalette = false
        }
    }

    // MARK: - Top Search & Chip Bar

    var topInputBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(appearance.accentColor)

            ForEach(activeChips) { chip in
                HStack(spacing: 5) {
                    Text(chip.key)
                        .foregroundStyle(.secondary)
                    Text(chip.value)
                        .fontWeight(.semibold)
                    Button {
                        activeChips.removeAll(where: { $0.id == chip.id })
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                }
                .font(.system(size: 12))
                .padding(.leading, 9)
                .padding(.trailing, 4)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(appearance.selectionTintColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(appearance.selectionBorderColor, lineWidth: 1)
                        )
                )
            }

            // Quick filter chip presets if empty
            if activeChips.isEmpty && query.isEmpty {
                Button {
                    activeChips.append(SearchFilterChip(key: "kind", value: "PDF"))
                } label: {
                    Text("+ kind: PDF")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(
                            Capsule().fill(Color.primary.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)

                Button {
                    activeChips.append(SearchFilterChip(key: "modified", value: "last 7 days"))
                } label: {
                    Text("+ modified: 7d")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(
                            Capsule().fill(Color.primary.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
            }

            TextField("Search files, content, tags (#), paths (/), or commands (>)", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .focused($isSearchFocused)
                .onSubmit {
                    triggerPrimaryAction()
                }

            Button {
                appState.showCommandPalette = false
            } label: {
                Text("esc")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.1))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 56)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.09))
                .frame(height: 1)
        }
    }

    // MARK: - Scope Tabs Bar

    var scopeFilterBar: some View {
        HStack(spacing: 4) {
            ForEach(PaletteTabScope.allCases, id: \.self) { tab in
                let isSelected = (scopeTab == tab)
                Button {
                    scopeTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? .white : .secondary)
                        .padding(.horizontal, 11)
                        .frame(height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isSelected ? appearance.accentColor : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Button {
                searchEverywhere.toggle()
            } label: {
                HStack(spacing: 5) {
                    Text(searchEverywhere ? "Everywhere" : appState.currentFolderTitle)
                        .font(.system(size: 12))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(height: 1)
        }
    }

}
