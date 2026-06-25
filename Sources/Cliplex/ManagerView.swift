import SwiftUI
import CliplexKit
import KeyboardShortcuts

// MARK: - Snippets window

// MARK: - Snippets

struct SnippetsView: View {
    @ObservedObject var viewModel: ManagerViewModel
    @State private var hoveredFolder: Int64?
    @State private var hoveredSnippet: Int64?
    @State private var folderWidth: CGFloat = 200
    @State private var listWidth: CGFloat = 290

    private let editorMinWidth: CGFloat = 360
    private let folderRange: ClosedRange<CGFloat> = 170...300
    private let listRange: ClosedRange<CGFloat> = 230...460

    var body: some View {
        GeometryReader { geo in
            let panes = paneWidths(container: geo.size.width)
            HStack(spacing: 0) {
                folderSidebar
                    .frame(width: panes.folder)
                    .frame(maxHeight: .infinity)
                PaneResizer(
                    width: $folderWidth,
                    minWidth: folderRange.lowerBound,
                    maxWidth: max(folderRange.lowerBound,
                                  min(folderRange.upperBound, geo.size.width - panes.list - editorMinWidth - 2))
                )
                snippetList
                    .frame(width: panes.list)
                    .frame(maxHeight: .infinity)
                PaneResizer(
                    width: $listWidth,
                    minWidth: listRange.lowerBound,
                    maxWidth: max(listRange.lowerBound,
                                  min(listRange.upperBound, geo.size.width - panes.folder - editorMinWidth - 2))
                )
                editor
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .tint(Theme.accent)
        .overlay {
            dialogOverlay
                .animation(.easeOut(duration: 0.16), value: viewModel.isNamingFolder)
                .animation(.easeOut(duration: 0.16), value: viewModel.isRenamingFolder)
                .animation(.easeOut(duration: 0.16), value: viewModel.confirmingFolderDelete)
                .animation(.easeOut(duration: 0.16), value: viewModel.confirmingSnippetDelete)
        }
    }

    /// Resolves the folder/list pane widths for the current container so the
    /// editor always keeps at least its minimum width — preventing the content
    /// from overflowing the window when panes are widened or the window shrinks.
    private func paneWidths(container: CGFloat) -> (folder: CGFloat, list: CGFloat) {
        let available = max(0, container - 2) // two 1px resizers
        var folder = folderWidth.clamped(to: folderRange)
        var list = listWidth.clamped(to: listRange)
        let maxPanes = max(0, available - editorMinWidth)
        if folder + list > maxPanes {
            list = max(listRange.lowerBound, maxPanes - folder)
            if folder + list > maxPanes {
                folder = max(folderRange.lowerBound, maxPanes - list)
            }
        }
        return (folder, list)
    }

    @ViewBuilder
    private var dialogOverlay: some View {
        if viewModel.isNamingFolder {
            DialogScrim(onDismiss: viewModel.cancelNewFolder) {
                InputDialog(
                    title: "New Folder",
                    placeholder: "Folder name",
                    text: $viewModel.newFolderName,
                    confirmTitle: "Create",
                    onCancel: viewModel.cancelNewFolder,
                    onConfirm: viewModel.createFolder
                )
            }
        } else if viewModel.isRenamingFolder {
            DialogScrim(onDismiss: viewModel.cancelRenameFolder) {
                InputDialog(
                    icon: "pencil",
                    title: "Rename Folder",
                    placeholder: "Folder name",
                    text: $viewModel.renameFolderName,
                    confirmTitle: "Rename",
                    onCancel: viewModel.cancelRenameFolder,
                    onConfirm: viewModel.confirmRenameFolder
                )
            }
        } else if viewModel.confirmingFolderDelete {
            DialogScrim(onDismiss: { viewModel.confirmingFolderDelete = false }) {
                ConfirmDialog(
                    title: "Delete “\(viewModel.folderPendingDeleteName)”?",
                    message: "This permanently deletes the folder and its \(viewModel.folderPendingDeleteCountText). This can’t be undone.",
                    confirmTitle: "Delete Folder",
                    onCancel: { viewModel.confirmingFolderDelete = false },
                    onConfirm: viewModel.confirmDeleteFolder
                )
            }
        } else if viewModel.confirmingSnippetDelete {
            DialogScrim(onDismiss: { viewModel.confirmingSnippetDelete = false }) {
                ConfirmDialog(
                    title: "Delete “\(viewModel.snippetPendingDeleteName)”?",
                    message: "This snippet will be permanently deleted. This can’t be undone.",
                    confirmTitle: "Delete Snippet",
                    onCancel: { viewModel.confirmingSnippetDelete = false },
                    onConfirm: viewModel.confirmDeleteSnippet
                )
            }
        }
    }

    private var folderSidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            folderButton(name: "All snippets", glyph: "tray.full", folder: nil)
            ForEach(viewModel.folders) { folder in
                folderButton(name: folder.name, glyph: "folder", folder: folder)
            }
            Spacer()
            Button {
                viewModel.promptNewFolder()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "folder.badge.plus").font(.system(size: 13))
                    Text("New Folder").font(.system(size: 13, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 10).padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .background(Theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.accent.opacity(0.25), lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 6) {
                sidebarActionButton("Import", "square.and.arrow.down") { viewModel.importSnippets() }
                sidebarActionButton("Export", "square.and.arrow.up") { viewModel.exportSnippets() }
            }
            .padding(.top, 2)
        }
        .padding(10)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func sidebarActionButton(_ title: String, _ glyph: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: glyph).font(.system(size: 11))
                Text(title).font(.system(size: 12))
            }
            .foregroundStyle(Theme.secondaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(Theme.fieldBackground, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(title) all snippets")
    }

    private func folderButton(name: String, glyph: String, folder: SnippetFolder?) -> some View {
        let id = folder?.id
        let isActive = viewModel.selectedFolderID == id
        return HStack(spacing: 8) {
            Image(systemName: glyph).font(.system(size: 11)).foregroundStyle(isActive ? Theme.accent : Theme.mutedText)
            Text(name).font(.system(size: 13)).foregroundStyle(isActive ? Theme.accent : Theme.primaryText)
                .lineLimit(1)
            Spacer()
            if let folder {
                HStack(spacing: 6) {
                    HoverIconButton(systemName: "pencil", help: "Rename", visible: hoveredFolder == folder.id) {
                        viewModel.requestRenameFolder(folder)
                    }
                    HoverIconButton(systemName: "trash", help: "Delete", visible: hoveredFolder == folder.id) {
                        viewModel.requestDeleteFolder(folder)
                    }
                }
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(isActive ? Theme.accent.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .onHover { hovering in hoveredFolder = hovering ? id : (hoveredFolder == id ? nil : hoveredFolder) }
        .onTapGesture { viewModel.selectFolder(id) }
        .modifier(ReorderDrag(
            kind: "folder",
            id: folder?.id,
            onDrop: { source, target in viewModel.reorderFolder(source, before: target) }
        ))
    }

    private var snippetList: some View {
        VStack(spacing: 0) {
            HStack {
                Text(viewModel.selectedFolderName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                GhostButton(title: "＋ New snippet", accent: true) { viewModel.newSnippet() }
                    .keyboardShortcut("n", modifiers: .command)
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            Divider().overlay(Theme.hairline)

            if viewModel.snippets.isEmpty && !viewModel.isDraft {
                Text("No snippets yet").font(.system(size: 13)).foregroundStyle(Theme.mutedText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if viewModel.isDraft { draftRow }
                        ForEach(viewModel.snippets) { snippet in
                            snippetRow(snippet)
                        }
                    }
                    .padding(6)
                }
            }
        }
    }

    /// The in-progress, unsaved snippet shown at the top of the list.
    private var draftRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(viewModel.draftTitle.isEmpty ? "New snippet" : viewModel.draftTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .italic(viewModel.draftTitle.isEmpty)
                    .foregroundStyle(viewModel.draftTitle.isEmpty ? Theme.mutedText : Theme.primaryText)
                    .lineLimit(1)
                Spacer()
                Text("DRAFT")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.filesTag)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.filesTag.opacity(0.4), lineWidth: 1))
            }
            Text(viewModel.draftContent.isEmpty ? "editing…" : String(viewModel.draftContent.prefix(60)))
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.mutedText).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Theme.filesTag.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(Theme.filesTag.opacity(0.45))
        )
    }

    private func snippetRow(_ snippet: Snippet) -> some View {
        let isActive = !viewModel.isDraft && viewModel.selectedSnippetID == snippet.id
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(snippet.title.isEmpty ? "Untitled" : snippet.title)
                    .font(.system(size: 13)).foregroundStyle(Theme.primaryText).lineLimit(1)
                Text(snippet.content.prefix(60))
                    .font(.system(size: 11)).foregroundStyle(Theme.mutedText).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HoverIconButton(systemName: "trash", help: "Delete", visible: hoveredSnippet == snippet.id) {
                viewModel.requestDeleteSnippet(snippet)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(isActive ? Theme.accent.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .onHover { hovering in hoveredSnippet = hovering ? snippet.id : (hoveredSnippet == snippet.id ? nil : hoveredSnippet) }
        .onTapGesture { viewModel.openSnippet(snippet) }
        .modifier(ReorderDrag(
            kind: "snippet",
            id: viewModel.canReorderSnippets ? snippet.id : nil,
            onDrop: { source, target in viewModel.reorderSnippet(source, before: target) }
        ))
    }

    private var editor: some View {
        Group {
            if !viewModel.isEditing {
                VStack(spacing: 10) {
                    Text("Select a snippet, or")
                        .font(.system(size: 13)).foregroundStyle(Theme.mutedText)
                    GhostButton(title: "＋ New snippet", accent: true) { viewModel.newSnippet() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Title", text: $viewModel.draftTitle)
                            .textFieldStyle(.plain)
                            .font(.system(size: 17, weight: .semibold))
                        Text("Saving to  ▸ \(viewModel.selectedFolderName)")
                            .font(.system(size: 11.5)).foregroundStyle(Theme.mutedText)
                    }
                    .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)
                    Divider().overlay(Theme.hairline)

                    TextEditor(text: $viewModel.draftContent)
                        .font(.system(size: 13, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Divider().overlay(Theme.hairline)
                    editorFooter
                }
            }
        }
    }

    private var editorFooter: some View {
        HStack(spacing: 14) {
            Text("\(viewModel.draftLineCount) lines · \(viewModel.draftCharCount) chars")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.mutedText)
            if viewModel.hasUnsavedChanges {
                HStack(spacing: 6) {
                    Circle().fill(Theme.filesTag).frame(width: 7, height: 7)
                    Text(viewModel.isDraft ? "Unsaved draft" : "Unsaved changes")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.filesTag)
                }
            }
            Spacer()
            if viewModel.isDraft {
                GhostButton(title: "Discard", danger: true) { viewModel.discardDraft() }
                    .keyboardShortcut(.cancelAction)
            }
            PrimaryButton(title: "Save") { viewModel.saveSnippet() }
                .keyboardShortcut("s", modifiers: .command)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }
}

// MARK: - Settings window

struct SettingsView: View {
    @ObservedObject var viewModel: ManagerViewModel

    var body: some View {
        Form {
            Section {
                LabeledContent("Maximum history items") {
                    TextField("", value: $viewModel.settings.maxHistory, format: .number)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                }
            } header: {
                Text("Clipboard history")
            } footer: {
                Text("Older unpinned clips beyond the maximum are removed.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Ignore concealed & password clips", isOn: $viewModel.settings.ignoreConcealed)
            } header: {
                Text("Privacy")
            } footer: {
                Text("Clips that apps mark as secret — like password managers — are never stored.")
                    .foregroundStyle(.secondary)
            }

            Section("Behavior") {
                Toggle("Paste automatically on select", isOn: $viewModel.settings.pasteOnSelect)
                Toggle("Launch Cliplex at login", isOn: $viewModel.autostartEnabled)
            }

            Section {
                KeyboardShortcuts.Recorder("Open Cliplex", name: .openCliplex)
                KeyboardShortcuts.Recorder("Open Snippets", name: .openSnippets)
            } header: {
                Text("Shortcuts")
            } footer: {
                Text("“Open Cliplex” shows the clipboard history; “Open Snippets” opens straight to the snippets tab.")
                    .foregroundStyle(.secondary)
            }

            Section("Appearance") {
                Picker("Theme", selection: $viewModel.settings.theme) {
                    Text("System").tag(Appearance.system)
                    Text("Dark").tag(Appearance.dark)
                    Text("Light").tag(Appearance.light)
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .tint(Theme.accent)
        .frame(width: 460, height: 560)
        // Settings apply immediately (native Settings behavior). Number fields
        // commit on Return / focus loss, so this doesn't churn while typing.
        .onChange(of: viewModel.settings) { viewModel.applySettings() }
        .onChange(of: viewModel.autostartEnabled) { viewModel.applyAutostart() }
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
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(accent ? Theme.accent : Theme.secondaryText)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .fixedSize()
    }
}

private struct PrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(Theme.accentInk)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .fixedSize()
    }
}
