import SwiftUI
import CliplexKit

/// The manager window: snippets (folders + editor) and settings, in two tabs.
struct ManagerView: View {
    @ObservedObject var viewModel: ManagerViewModel
    @State private var tab: Tab = .snippets

    enum Tab { case snippets, settings }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.hairline)
            switch tab {
            case .snippets: SnippetsPane(viewModel: viewModel)
            case .settings: SettingsPane(viewModel: viewModel)
            }
        }
        .frame(minWidth: 820, minHeight: 540)
        .tint(Theme.accent)
    }

    private var header: some View {
        HStack(spacing: 22) {
            HStack(spacing: 7) {
                Text("▚").foregroundStyle(Theme.accent)
                Text("cliplex").foregroundStyle(Theme.secondaryText)
            }
            .font(.system(size: 12, design: .monospaced))

            HStack(spacing: 4) {
                tabButton("Snippets", .snippets)
                tabButton("Settings", .settings)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func tabButton(_ title: String, _ value: Tab) -> some View {
        let isActive = tab == value
        return Text(title.uppercased())
            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
            .tracking(0.6)
            .foregroundStyle(isActive ? Theme.accent : Theme.mutedText)
            .padding(.horizontal, 13)
            .padding(.vertical, 6)
            .background(isActive ? Theme.accent.opacity(0.14) : .clear,
                        in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
            .onTapGesture { tab = value }
    }
}

// MARK: - Snippets

private struct SnippetsPane: View {
    @ObservedObject var viewModel: ManagerViewModel

    var body: some View {
        HStack(spacing: 0) {
            folderSidebar
                .frame(width: 200)
            Divider().overlay(Theme.hairline)
            snippetList
                .frame(width: 300)
            Divider().overlay(Theme.hairline)
            editor
                .frame(maxWidth: .infinity)
        }
        .frame(maxHeight: .infinity)
    }

    private var folderSidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            folderButton(name: "All snippets", glyph: "tray.full", id: nil)
            ForEach(viewModel.folders) { folder in
                folderButton(name: folder.name, glyph: "folder", id: folder.id)
            }
            Spacer()
            HStack(spacing: 6) {
                TextField("new folder…", text: $viewModel.newFolderName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(Theme.fieldBackground, in: RoundedRectangle(cornerRadius: 6))
                    .onSubmit { viewModel.createFolder() }
                Button {
                    viewModel.createFolder()
                } label: {
                    Image(systemName: "plus").font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .frame(width: 28, height: 28)
                .background(Theme.fieldBackground, in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(10)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func folderButton(name: String, glyph: String, id: Int64?) -> some View {
        let isActive = viewModel.selectedFolderID == id
        return HStack(spacing: 8) {
            Image(systemName: glyph).font(.system(size: 11)).foregroundStyle(isActive ? Theme.accent : Theme.mutedText)
            Text(name).font(.system(size: 13)).foregroundStyle(isActive ? Theme.accent : Theme.primaryText)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(isActive ? Theme.accent.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .onTapGesture { viewModel.selectFolder(id) }
    }

    private var snippetList: some View {
        VStack(spacing: 0) {
            HStack {
                Text(viewModel.selectedFolderName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                if viewModel.selectedFolderID != nil {
                    GhostButton(title: "⌫ folder", danger: true) { viewModel.deleteSelectedFolder() }
                }
                GhostButton(title: "+ snippet", accent: true) { viewModel.newSnippet() }
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            Divider().overlay(Theme.hairline)

            if viewModel.snippets.isEmpty {
                Text("no snippets").font(.system(size: 13)).foregroundStyle(Theme.mutedText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(viewModel.snippets) { snippet in
                            snippetRow(snippet)
                        }
                    }
                    .padding(6)
                }
            }
        }
    }

    private func snippetRow(_ snippet: Snippet) -> some View {
        let isActive = viewModel.selectedSnippetID == snippet.id
        return VStack(alignment: .leading, spacing: 3) {
            Text(snippet.title.isEmpty ? "Untitled" : snippet.title)
                .font(.system(size: 13)).foregroundStyle(Theme.primaryText).lineLimit(1)
            Text(snippet.content.prefix(60))
                .font(.system(size: 11)).foregroundStyle(Theme.mutedText).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(isActive ? Theme.accent.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .onTapGesture { viewModel.openSnippet(snippet) }
    }

    private var editor: some View {
        Group {
            if viewModel.selectedSnippetID == nil {
                Text("Select or create a snippet")
                    .font(.system(size: 13)).foregroundStyle(Theme.mutedText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 10) {
                    TextField("Title", text: $viewModel.draftTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .padding(9)
                        .background(Theme.fieldBackground, in: RoundedRectangle(cornerRadius: 8))
                    TextEditor(text: $viewModel.draftContent)
                        .font(.system(size: 13, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Theme.fieldBackground, in: RoundedRectangle(cornerRadius: 8))
                    HStack {
                        GhostButton(title: "Delete", danger: true) { viewModel.deleteSnippet() }
                        Spacer()
                        PrimaryButton(title: "Save") { viewModel.saveSnippet() }
                    }
                }
                .padding(14)
            }
        }
    }
}

// MARK: - Settings

private struct SettingsPane: View {
    @ObservedObject var viewModel: ManagerViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                numberField("Maximum history items",
                            value: $viewModel.settings.maxHistory,
                            hint: "Older unpinned clips beyond this count are removed.")
                numberField("Clipboard poll interval (ms)",
                            value: Binding(
                                get: { Int64(viewModel.settings.pollIntervalMs) },
                                set: { viewModel.settings.pollIntervalMs = Int($0) }),
                            hint: "Lower is more responsive; higher uses less CPU.")

                Toggle("Ignore concealed / password clips", isOn: $viewModel.settings.ignoreConcealed)
                Toggle("Paste automatically on select", isOn: $viewModel.settings.pasteOnSelect)
                Toggle("Launch Cliplex at login", isOn: $viewModel.autostartEnabled)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Theme").font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                    Picker("", selection: $viewModel.settings.theme) {
                        Text("System").tag(Appearance.system)
                        Text("Dark").tag(Appearance.dark)
                        Text("Light").tag(Appearance.light)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 260)
                }

                HStack(spacing: 12) {
                    PrimaryButton(title: "Save settings") { viewModel.saveSettings() }
                    if viewModel.settingsSaved {
                        Text("✓ saved").font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.accent)
                    }
                }
                .padding(.top, 6)
            }
            .padding(28)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .toggleStyle(.switch)
        .onChange(of: viewModel.settings) { viewModel.markSettingsDirty() }
        .onChange(of: viewModel.autostartEnabled) { viewModel.markSettingsDirty() }
        .onChange(of: viewModel.settings.theme) { applyThemePreview() }
    }

    private func numberField(_ label: String, value: Binding<Int64>, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
            TextField("", value: value, format: .number)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .frame(width: 120)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(Theme.fieldBackground, in: RoundedRectangle(cornerRadius: 8))
            Text(hint).font(.system(size: 11)).foregroundStyle(Theme.mutedText)
        }
    }

    private func applyThemePreview() {
        switch viewModel.settings.theme {
        case .system: NSApp.appearance = nil
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        }
    }
}

// MARK: - Buttons

private struct GhostButton: View {
    let title: String
    var accent = false
    var danger = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(accent ? Theme.accent : Theme.secondaryText)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct PrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accentInk)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }
}
