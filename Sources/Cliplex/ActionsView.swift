import SwiftUI
import CliplexKit

/// The Actions manager: a folders sidebar, an action list, and an inline editor
/// (title + type picker + value/transform). Mirrors `SnippetsView`, reusing the
/// shared dialog/resizer/reorder components.
struct ActionsView: View {
    @ObservedObject var viewModel: ActionsViewModel
    @State private var hoveredFolder: Int64?
    @State private var hoveredAction: Int64?
    @State private var folderWidth: CGFloat = 200
    @State private var listWidth: CGFloat = 300

    private let editorMinWidth: CGFloat = 360
    private let folderRange: ClosedRange<CGFloat> = 170...300
    private let listRange: ClosedRange<CGFloat> = 240...460

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
                actionList
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
                .animation(.easeOut(duration: 0.16), value: viewModel.confirmingActionDelete)
        }
    }

    private func paneWidths(container: CGFloat) -> (folder: CGFloat, list: CGFloat) {
        let available = max(0, container - 2)
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

    // MARK: - Dialogs

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
        } else if viewModel.confirmingActionDelete {
            DialogScrim(onDismiss: { viewModel.confirmingActionDelete = false }) {
                ConfirmDialog(
                    title: "Delete “\(viewModel.actionPendingDeleteName)”?",
                    message: "This action will be permanently deleted. This can’t be undone.",
                    confirmTitle: "Delete Action",
                    onCancel: { viewModel.confirmingActionDelete = false },
                    onConfirm: viewModel.confirmDeleteAction
                )
            }
        }
    }

    // MARK: - Folder sidebar

    private var folderSidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            folderButton(name: "All actions", glyph: "bolt.fill", folder: nil)
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
        }
        .padding(10)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func folderButton(name: String, glyph: String, folder: ActionFolder?) -> some View {
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
            kind: "actionfolder",
            id: folder?.id,
            onDrop: { source, target in viewModel.reorderFolder(source, before: target) }
        ))
    }

    // MARK: - Action list

    private var actionList: some View {
        VStack(spacing: 0) {
            HStack {
                Text(viewModel.selectedFolderName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                GhostButton(title: "＋ New action", accent: true) { viewModel.newAction() }
                    .keyboardShortcut("n", modifiers: .command)
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            Divider().overlay(Theme.hairline)

            if viewModel.actions.isEmpty && !viewModel.isDraft {
                Text("No actions yet").font(.system(size: 13)).foregroundStyle(Theme.mutedText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if viewModel.isDraft { draftRow }
                        ForEach(viewModel.actions) { action in
                            actionRow(action)
                        }
                    }
                    .padding(6)
                }
            }
        }
    }

    private var draftRow: some View {
        HStack(spacing: 8) {
            Image(systemName: viewModel.draftType.symbol)
                .font(.system(size: 11)).foregroundStyle(Theme.filesTag).frame(width: 16)
            Text(viewModel.draftTitle.isEmpty ? "New action" : viewModel.draftTitle)
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Theme.filesTag.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(Theme.filesTag.opacity(0.45))
        )
    }

    private func actionRow(_ action: ActionItem) -> some View {
        let isActive = !viewModel.isDraft && viewModel.selectedActionID == action.id
        return HStack(spacing: 8) {
            Image(systemName: action.type.symbol)
                .font(.system(size: 12)).foregroundStyle(Theme.accent).frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(action.title.isEmpty ? "Untitled" : action.title)
                    .font(.system(size: 13)).foregroundStyle(Theme.primaryText).lineLimit(1)
                Text(subtitle(for: action))
                    .font(.system(size: 11)).foregroundStyle(Theme.mutedText).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HoverIconButton(systemName: "trash", help: "Delete", visible: hoveredAction == action.id) {
                viewModel.requestDeleteAction(action)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(isActive ? Theme.accent.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .onHover { hovering in hoveredAction = hovering ? action.id : (hoveredAction == action.id ? nil : hoveredAction) }
        .onTapGesture { viewModel.openAction(action) }
        .modifier(ReorderDrag(
            kind: "action",
            id: viewModel.canReorderActions ? action.id : nil,
            onDrop: { source, target in viewModel.reorderAction(source, before: target) }
        ))
    }

    private func subtitle(for action: ActionItem) -> String {
        switch action.type {
        case .transform: return action.transform?.label ?? "Transform"
        default: return action.value.isEmpty ? action.type.label : action.value
        }
    }

    // MARK: - Editor

    private var editor: some View {
        Group {
            if !viewModel.isEditing {
                VStack(spacing: 10) {
                    Text("Select an action, or")
                        .font(.system(size: 13)).foregroundStyle(Theme.mutedText)
                    GhostButton(title: "＋ New action", accent: true) { viewModel.newAction() }
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

                    editorForm
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                    Divider().overlay(Theme.hairline)
                    editorFooter
                }
            }
        }
    }

    private var editorForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("Type")
                Picker("", selection: $viewModel.draftType) {
                    ForEach(ActionType.allCases, id: \.self) { type in
                        Text(type.label).tag(type)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 260, alignment: .leading)
            }

            if viewModel.draftUsesValue {
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel(valueLabel)
                    TextField(valuePlaceholder, text: $viewModel.draftValue)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(Theme.fieldBackground, in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.hairline, lineWidth: 1))
                    Text(valueHint)
                        .font(.system(size: 11)).foregroundStyle(Theme.mutedText)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("Transform")
                    Picker("", selection: $viewModel.draftTransform) {
                        ForEach(ActionTransform.allCases, id: \.self) { transform in
                            Text(transform.label).tag(transform)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 260, alignment: .leading)
                    Text("Applies to the current clipboard text and writes the result back.")
                        .font(.system(size: 11)).foregroundStyle(Theme.mutedText)
                }
            }
        }
        .padding(16)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9.5, weight: .semibold))
            .tracking(1.0)
            .foregroundStyle(Theme.mutedText)
    }

    private var valueLabel: String {
        switch viewModel.draftType {
        case .openURL: return "URL"
        case .openApp: return "Application"
        case .openPath: return "File or Folder Path"
        case .transform: return "Value"
        }
    }

    private var valuePlaceholder: String {
        switch viewModel.draftType {
        case .openURL: return "https://github.com/search?q={clipboard}"
        case .openApp: return "com.apple.Safari  or  /Applications/Safari.app"
        case .openPath: return "~/Projects/my-repo"
        case .transform: return ""
        }
    }

    private var valueHint: String {
        switch viewModel.draftType {
        case .openURL: return "Use {clipboard} to insert the current clipboard text (URL-encoded)."
        case .openApp: return "A bundle identifier or an app path. {clipboard} is supported."
        case .openPath: return "Opens in Finder / the default app. {clipboard} and ~ are supported."
        case .transform: return ""
        }
    }

    private var editorFooter: some View {
        HStack(spacing: 14) {
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
            PrimaryButton(title: "Save") { viewModel.save() }
                .keyboardShortcut("s", modifiers: .command)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }
}
