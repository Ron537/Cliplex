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
            header
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
        .background {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(LinearGradient(colors: [Theme.bgTop, Theme.bgBottom], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(alignment: .topTrailing) {
                    RadialGradient(colors: [Theme.accent.opacity(0.10), .clear], center: .topTrailing, startRadius: 0, endRadius: 360)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .tint(Theme.accent)
        .onAppear { searchFocused = true }
        .onChange(of: viewModel.showToken) { searchFocused = true }
    }

    // MARK: - Header (search + mode pills)

    private var header: some View {
        VStack(spacing: 11) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.ui(16, .medium))
                    .foregroundStyle(Theme.mutedText)
                TextField(viewModel.searchPlaceholder, text: $viewModel.query)
                    .textFieldStyle(.plain)
                    .font(.ui(16))
                    .focused($searchFocused)
                    .onChange(of: viewModel.query) { viewModel.selection = 0 }
            }
            segmentedToggle
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 11)
    }

    private var segmentedToggle: some View {
        HStack(spacing: 6) {
            ForEach(PanelMode.allCases, id: \.self) { mode in
                let isOn = viewModel.mode == mode
                HStack(spacing: 5) {
                    if let dot = modeDot(mode) { Circle().fill(isOn ? Theme.accentInk : dot).frame(width: 6, height: 6) }
                    Text(mode.label).font(.ui(11.5, .semibold)).lineLimit(1).fixedSize()
                }
                .foregroundStyle(isOn ? Theme.accentInk : Theme.secondaryText)
                .padding(.horizontal, 11).padding(.vertical, 4)
                .background(isOn ? Theme.accent : Theme.fieldBackground, in: Capsule())
                .contentShape(Capsule())
                .onTapGesture { viewModel.switchMode(to: mode) }
            }
            Spacer()
        }
    }

    private func modeDot(_ mode: PanelMode) -> Color? {
        switch mode {
        case .clipboard: return nil
        case .snippets: return Theme.snippetAccent
        case .actions: return Theme.actionAccent
        }
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
        Text(viewModel.query.isEmpty ? emptyMessage : "No matches")
            .font(.ui(13))
            .foregroundStyle(Theme.mutedText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyMessage: String {
        switch viewModel.mode {
        case .clipboard: return "Clipboard is empty"
        case .snippets: return "No snippets yet"
        case .actions: return "No actions yet"
        }
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
                indented: viewModel.showsFolderTree && viewModel.query.isEmpty,
                compact: viewModel.compact
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
                .font(.ui(11))
                .foregroundStyle(Theme.filesTag)
            Spacer()
            Text("Grant…")
                .font(.ui(10.5, .medium))
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
                .font(.mono(10))
                .foregroundStyle(Theme.mutedText)
            Spacer()
            if let toast = viewModel.toast {
                Text(toast)
                    .font(.ui(10.5, .semibold))
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
            switch viewModel.mode {
            case .clipboard:
                HintKey("⏎"); Text("paste").hintLabel()
                HintKey("⌘P"); Text("pin").hintLabel()
                HintKey("⌘S"); Text("snippet").hintLabel()
            case .snippets:
                HintKey("⏎"); Text("paste").hintLabel()
                HintKey("⇥"); Text("next").hintLabel()
            case .actions:
                HintKey("⏎"); Text("run").hintLabel()
                HintKey("⇥"); Text("next").hintLabel()
            }
        }
    }
}

private extension Text {
    func hintLabel() -> some View {
        self.font(.ui(10.5)).foregroundStyle(Theme.mutedText)
    }
}

private struct HintKey: View {
    let label: String
    init(_ label: String) { self.label = label }
    var body: some View {
        Text(label)
            .font(.mono(9.5))
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
                .font(.ui(11.5, .medium))
                .foregroundStyle(hovering ? Theme.secondaryText : Theme.mutedText)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Settings")
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
