import SwiftUI
import CliplexKit

/// The compact, at-cursor clipboard panel. A single column with a search field,
/// a Clips/Snippets segmented toggle, a grouped (virtualized) list, and a hint
/// footer — rendered with a translucent material and the blue accent.
struct PanelView: View {
    @ObservedObject var viewModel: PanelViewModel
    @FocusState private var searchFocused: Bool

    private static let width: CGFloat = 380
    private static let height: CGFloat = 460

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider().overlay(Theme.hairline)
            list
            if viewModel.needsAccessibility {
                Divider().overlay(Theme.hairline)
                accessibilityBanner
            }
            Divider().overlay(Theme.hairline)
            footer
        }
        .frame(width: Self.width, height: Self.height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .tint(Theme.accent)
        .onAppear { searchFocused = true }
        .onChange(of: viewModel.showToken) { searchFocused = true }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent)
            TextField(
                viewModel.mode == .clipboard ? "Search clipboard…" : "Search snippets…",
                text: $viewModel.query
            )
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .focused($searchFocused)
            .onChange(of: viewModel.query) { viewModel.selection = 0 }

            segmentedToggle
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
    }

    private var segmentedToggle: some View {
        HStack(spacing: 1) {
            ForEach(PanelMode.allCases, id: \.self) { mode in
                let isOn = viewModel.mode == mode
                Text(mode.label)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(isOn ? Theme.accentInk : Theme.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(isOn ? Theme.accent : .clear, in: RoundedRectangle(cornerRadius: 5))
                    .contentShape(Rectangle())
                    .onTapGesture { viewModel.switchMode(to: mode) }
            }
        }
        .padding(2)
        .background(Theme.fieldBackground, in: RoundedRectangle(cornerRadius: 7))
    }

    // MARK: - List

    private var list: some View {
        Group {
            if viewModel.layout.entries.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(viewModel.layout.entries) { entry in
                                entryView(entry)
                                    .transition(.opacity)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onChange(of: viewModel.scrollToken) {
                        guard let id = viewModel.selectedScrollID else { return }
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        Text(viewModel.query.isEmpty
             ? (viewModel.mode == .clipboard ? "Clipboard is empty" : "No snippets yet")
             : "No matches")
            .font(.system(size: 13))
            .foregroundStyle(Theme.mutedText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func entryView(_ entry: PanelEntry) -> some View {
        switch entry {
        case let .header(_, title, folderKey, collapsed):
            HeaderView(
                title: title,
                folderKey: folderKey,
                collapsed: collapsed,
                selected: folderKey.map { viewModel.isHeaderSelected($0) } ?? false
            ) { key in
                viewModel.toggleFolder(key)
            }
        case let .row(row, flatIndex, quickIndex):
            RowView(
                row: row,
                quickIndex: quickIndex,
                selected: viewModel.isRowSelected(flatIndex),
                indented: viewModel.mode == .snippets && viewModel.query.isEmpty
            )
            .onContinuousHover(coordinateSpace: .global) { phase in
                if case let .active(location) = phase {
                    viewModel.hoverMoved(to: location, index: flatIndex)
                }
            }
            .onTapGesture { viewModel.selectRow(flatIndex); viewModel.activateSelection() }
        }
    }

    // MARK: - Accessibility banner

    private var accessibilityBanner: some View {
        HStack(spacing: 8) {
            Text("Enable auto-paste → grant Accessibility")
                .font(.system(size: 11))
                .foregroundStyle(Theme.filesTag)
            Spacer()
            Text("Grant…")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Theme.accentInk)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Theme.filesTag, in: RoundedRectangle(cornerRadius: 5))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture { viewModel.requestAccessibility() }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            SettingsButton { viewModel.openSettings() }
            Text(viewModel.statusText)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.mutedText)
            Spacer()
            if let toast = viewModel.toast {
                Text(toast)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            } else {
                hints
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
    }

    private var hints: some View {
        HStack(spacing: 6) {
            if viewModel.mode == .clipboard {
                HintKey("⏎"); Text("paste").hintLabel()
                HintKey("⌘P"); Text("pin").hintLabel()
                HintKey("⌘S"); Text("snippet").hintLabel()
            } else {
                HintKey("⏎"); Text("paste").hintLabel()
                HintKey("⇥"); Text("clips").hintLabel()
            }
        }
    }
}

private extension Text {
    func hintLabel() -> some View {
        self.font(.system(size: 10.5)).foregroundStyle(Theme.mutedText)
    }
}

private struct HintKey: View {
    let label: String
    init(_ label: String) { self.label = label }
    var body: some View {
        Text(label)
            .font(.system(size: 9.5, design: .monospaced))
            .foregroundStyle(Theme.secondaryText)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Theme.fieldBackground, in: RoundedRectangle(cornerRadius: 3))
    }
}

/// A subtle gear button in the footer that opens Settings.
private struct SettingsButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(hovering ? Theme.secondaryText : Theme.mutedText)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Settings")
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
