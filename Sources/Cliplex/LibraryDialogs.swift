import SwiftUI
import CliplexKit

/// The snippet folder/snippet dialogs (new/rename/delete) rendered over the
/// Library window. Extracted from the original SnippetsView so the unified
/// Library can present them.
struct SnippetDialogs: View {
    @ObservedObject var viewModel: ManagerViewModel

    var body: some View {
        Group {
            if viewModel.isNamingFolder {
                DialogScrim(onDismiss: viewModel.cancelNewFolder) {
                    InputDialog(title: "New Snippet Folder", placeholder: "Folder name",
                                text: $viewModel.newFolderName, confirmTitle: "Create",
                                onCancel: viewModel.cancelNewFolder, onConfirm: viewModel.createFolder)
                }
            } else if viewModel.isRenamingFolder {
                DialogScrim(onDismiss: viewModel.cancelRenameFolder) {
                    InputDialog(icon: "pencil", title: "Rename Folder", placeholder: "Folder name",
                                text: $viewModel.renameFolderName, confirmTitle: "Rename",
                                onCancel: viewModel.cancelRenameFolder, onConfirm: viewModel.confirmRenameFolder)
                }
            } else if viewModel.confirmingFolderDelete {
                DialogScrim(onDismiss: { viewModel.confirmingFolderDelete = false }) {
                    ConfirmDialog(title: "Delete “\(viewModel.folderPendingDeleteName)”?",
                                  message: "This permanently deletes the folder and its \(viewModel.folderPendingDeleteCountText). This can’t be undone.",
                                  confirmTitle: "Delete Folder",
                                  onCancel: { viewModel.confirmingFolderDelete = false },
                                  onConfirm: viewModel.confirmDeleteFolder)
                }
            } else if viewModel.confirmingSnippetDelete {
                DialogScrim(onDismiss: { viewModel.confirmingSnippetDelete = false }) {
                    ConfirmDialog(title: "Delete “\(viewModel.snippetPendingDeleteName)”?",
                                  message: "This snippet will be permanently deleted. This can’t be undone.",
                                  confirmTitle: "Delete Snippet",
                                  onCancel: { viewModel.confirmingSnippetDelete = false },
                                  onConfirm: viewModel.confirmDeleteSnippet)
                }
            }
        }
        .animation(.easeOut(duration: 0.16), value: viewModel.isNamingFolder)
        .animation(.easeOut(duration: 0.16), value: viewModel.isRenamingFolder)
        .animation(.easeOut(duration: 0.16), value: viewModel.confirmingFolderDelete)
        .animation(.easeOut(duration: 0.16), value: viewModel.confirmingSnippetDelete)
    }
}

/// The action folder/action dialogs (new/rename/delete) for the Library window.
struct ActionDialogs: View {
    @ObservedObject var viewModel: ActionsViewModel

    var body: some View {
        Group {
            if viewModel.isNamingFolder {
                DialogScrim(onDismiss: viewModel.cancelNewFolder) {
                    InputDialog(title: "New Action Folder", placeholder: "Folder name",
                                text: $viewModel.newFolderName, confirmTitle: "Create",
                                onCancel: viewModel.cancelNewFolder, onConfirm: viewModel.createFolder)
                }
            } else if viewModel.isRenamingFolder {
                DialogScrim(onDismiss: viewModel.cancelRenameFolder) {
                    InputDialog(icon: "pencil", title: "Rename Folder", placeholder: "Folder name",
                                text: $viewModel.renameFolderName, confirmTitle: "Rename",
                                onCancel: viewModel.cancelRenameFolder, onConfirm: viewModel.confirmRenameFolder)
                }
            } else if viewModel.confirmingFolderDelete {
                DialogScrim(onDismiss: { viewModel.confirmingFolderDelete = false }) {
                    ConfirmDialog(title: "Delete “\(viewModel.folderPendingDeleteName)”?",
                                  message: "This permanently deletes the folder and its \(viewModel.folderPendingDeleteCountText). This can’t be undone.",
                                  confirmTitle: "Delete Folder",
                                  onCancel: { viewModel.confirmingFolderDelete = false },
                                  onConfirm: viewModel.confirmDeleteFolder)
                }
            } else if viewModel.confirmingActionDelete {
                DialogScrim(onDismiss: { viewModel.confirmingActionDelete = false }) {
                    ConfirmDialog(title: "Delete “\(viewModel.actionPendingDeleteName)”?",
                                  message: "This action will be permanently deleted. This can’t be undone.",
                                  confirmTitle: "Delete Action",
                                  onCancel: { viewModel.confirmingActionDelete = false },
                                  onConfirm: viewModel.confirmDeleteAction)
                }
            }
        }
        .animation(.easeOut(duration: 0.16), value: viewModel.isNamingFolder)
        .animation(.easeOut(duration: 0.16), value: viewModel.isRenamingFolder)
        .animation(.easeOut(duration: 0.16), value: viewModel.confirmingFolderDelete)
        .animation(.easeOut(duration: 0.16), value: viewModel.confirmingActionDelete)
    }
}

/// The Library toolbar's type filter — a custom segmented control matching the
/// design (icon + label, accent-filled active segment).
struct FilterSegmented: View {
    @Binding var selection: LibraryViewModel.Filter

    var body: some View {
        HStack(spacing: 2) {
            seg(.all, "square.grid.2x2")
            seg(.snippets, "text.alignleft")
            seg(.actions, "bolt.fill")
        }
        .padding(2)
        .background(Theme.fieldBackground, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private func seg(_ value: LibraryViewModel.Filter, _ icon: String) -> some View {
        let on = selection == value
        return Button { selection = value } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.ui(11, .semibold))
                Text(value.title).font(.ui(12.5, .semibold))
            }
            .foregroundStyle(on ? Theme.accentInk : Theme.secondaryText)
            .padding(.horizontal, 12).frame(height: 26)
            .background(on ? Theme.accent : .clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }
}
