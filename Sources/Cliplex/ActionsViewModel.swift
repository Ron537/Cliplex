import AppKit
import CliplexKit

/// State + actions for the Actions manager window: action folders, the action
/// list, and the inline editor (title + type + value/transform). Mirrors the
/// snippets half of ``ManagerViewModel`` but for quick actions.
@MainActor
final class ActionsViewModel: ObservableObject {
    // Folders & list
    @Published var folders: [ActionFolder] = []
    @Published var selectedFolderID: Int64?
    @Published var actions: [ActionItem] = []
    @Published var selectedActionID: Int64?

    // Editor draft fields
    @Published var draftTitle = ""
    @Published var draftType: ActionType = .openURL
    @Published var draftValue = ""
    @Published var draftTransform: ActionTransform = .uppercase
    /// True while composing a brand-new action not yet written to the database.
    @Published private(set) var isDraft = false

    // Dialogs
    @Published var newFolderName = ""
    @Published var isNamingFolder = false
    @Published var renameFolderName = ""
    @Published var isRenamingFolder = false
    @Published var confirmingFolderDelete = false
    @Published var confirmingActionDelete = false
    @Published private(set) var folderPendingDelete: ActionFolder?
    @Published private(set) var folderPendingDeleteCount = 0
    @Published private(set) var actionPendingDelete: ActionItem?
    private var folderBeingRenamed: ActionFolder?

    /// The persisted snapshot of the action currently open (to detect edits).
    private var editingAction: ActionItem?

    private let services: AppServices

    init(services: AppServices) {
        self.services = services
        loadFolders()
        loadActions()
    }

    // MARK: - Derived

    var selectedFolderName: String {
        guard let id = selectedFolderID else { return "All actions" }
        return folders.first { $0.id == id }?.name ?? ""
    }

    var isEditing: Bool { isDraft || selectedActionID != nil }

    var hasUnsavedChanges: Bool {
        if isDraft {
            return !draftTitle.isEmpty || !draftValue.isEmpty
        }
        guard let action = editingAction else { return false }
        return draftTitle != action.title
            || draftType != action.type
            || draftValue != action.value
            || (draftType == .transform && draftTransform != (action.transform ?? .uppercase))
    }

    /// Whether the value field applies to the current type (transforms have none).
    var draftUsesValue: Bool { draftType != .transform }

    var folderPendingDeleteName: String { folderPendingDelete?.name ?? "" }

    var folderPendingDeleteCountText: String {
        folderPendingDeleteCount == 1 ? "1 action" : "\(folderPendingDeleteCount) actions"
    }

    var actionPendingDeleteName: String {
        let title = (actionPendingDelete?.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Untitled" : title
    }

    /// Whether reordering applies (only within a specific folder).
    var canReorderActions: Bool { selectedFolderID != nil }

    // MARK: - Loading

    /// Total actions across all folders (for the Library toolbar count).
    var totalActionCount: Int { (try? services.store.countActions(folderID: nil)) ?? 0 }

    /// Number of actions in a specific folder (for the rail row count).
    func count(inFolder id: Int64) -> Int { (try? services.store.countActions(folderID: id)) ?? 0 }

    func loadFolders() {
        folders = (try? services.store.listActionFolders()) ?? []
    }

    func loadActions() {
        actions = (try? services.store.listActions(folderID: selectedFolderID)) ?? []
    }

    func selectFolder(_ id: Int64?) {
        commitPendingEdits()
        selectedFolderID = id
        clearEditor()
        loadActions()
    }

    // MARK: - Editor

    func openAction(_ action: ActionItem) {
        guard action.id != selectedActionID || isDraft else { return }
        commitPendingEdits()
        isDraft = false
        selectedActionID = action.id
        editingAction = action
        draftTitle = action.title
        draftType = action.type
        draftValue = action.value
        draftTransform = action.transform ?? .uppercase
    }

    /// Begins composing a new action inline. Nothing is persisted until `save()`.
    func newAction() {
        commitPendingEdits()
        isDraft = true
        selectedActionID = nil
        editingAction = nil
        draftTitle = ""
        draftType = .openURL
        draftValue = ""
        draftTransform = .uppercase
    }

    func save() {
        let title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = title.isEmpty ? "Untitled" : title
        let trimmedValue = draftValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let transform: ActionTransform? = draftType == .transform ? draftTransform : nil
        // Transforms have no value; don't carry a stale URL/path into the row
        // (it would also linger in the FTS index).
        let persistedValue = draftType == .transform ? "" : trimmedValue

        if isDraft {
            // Don't persist an empty draft.
            guard draftHasContent else { return }
            guard let action = try? services.store.addAction(
                folderID: selectedFolderID, title: resolvedTitle, type: draftType,
                value: persistedValue, transform: transform) else { return }
            isDraft = false
            selectedActionID = action.id
            editingAction = action
            adoptDraft(from: action)
            loadActions()
        } else {
            guard let id = selectedActionID else { return }
            try? services.store.updateAction(
                id: id, title: resolvedTitle, type: draftType, value: persistedValue, transform: transform)
            loadActions()
            if let updated = try? services.store.action(id: id) {
                editingAction = updated
                adoptDraft(from: updated)
            }
        }
    }

    private func adoptDraft(from action: ActionItem) {
        draftTitle = action.title
        draftType = action.type
        draftValue = action.value
        draftTransform = action.transform ?? .uppercase
    }

    func discardDraft() {
        clearEditor()
    }

    /// The folder of the action currently open in the editor. Used by the
    /// inspector's Folder picker.
    var editingActionFolderID: Int64? { editingAction?.folderId }

    /// Moves the open (saved) action to another folder.
    func moveEditingAction(to folderID: Int64?) {
        guard let action = editingAction, action.folderId != folderID else { return }
        try? services.store.setActionFolder(id: action.id, folderID: folderID)
        if let updated = try? services.store.action(id: action.id) { editingAction = updated }
        loadActions()
    }

    /// Duplicates the open (saved) action and opens the copy.
    func duplicateEditingAction() {
        commitPendingEdits()
        guard let action = editingAction else { return }
        guard let copy = try? services.store.addAction(
            folderID: action.folderId, title: action.title + " copy", type: action.type,
            value: action.value, transform: action.transform) else { return }
        loadActions()
        ShortcutCenter.shared.ensureHandler(.action, copy.id)
        openAction(copy)
    }

    /// Deletes the action currently open in the editor (by id, so it works even
    /// after the item was moved out of the visible folder).
    func requestDeleteEditingAction() {
        if let action = editingAction { requestDeleteAction(action) }
    }

    /// Whether the current draft has enough to be worth persisting. A transform
    /// is fully specified by its type, but still needs a name so an abandoned
    /// "switch type → click away" doesn't leave an "Untitled" transform behind;
    /// open actions need a title or a value.
    private var draftHasContent: Bool {
        let title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = draftValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if draftType == .transform { return !title.isEmpty }
        return !title.isEmpty || !value.isEmpty
    }

    /// Saves in-flight edits before the editor is replaced, so navigating away
    /// never silently loses work. An empty draft is simply dropped.
    private func commitPendingEdits() {
        if isDraft {
            if draftHasContent { save() }
        } else if hasUnsavedChanges {
            save()
        }
    }

    private func clearEditor() {
        isDraft = false
        selectedActionID = nil
        editingAction = nil
        draftTitle = ""
        draftType = .openURL
        draftValue = ""
        draftTransform = .uppercase
    }

    // MARK: - Folder dialogs

    func promptNewFolder() {
        newFolderName = ""
        isNamingFolder = true
    }

    func cancelNewFolder() {
        newFolderName = ""
        isNamingFolder = false
    }

    func createFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let folder = try? services.store.addActionFolder(name: name) else { return }
        newFolderName = ""
        isNamingFolder = false
        loadFolders()
        selectFolder(folder.id)
    }

    func requestRenameFolder(_ folder: ActionFolder) {
        folderBeingRenamed = folder
        renameFolderName = folder.name
        isRenamingFolder = true
    }

    func cancelRenameFolder() {
        renameFolderName = ""
        isRenamingFolder = false
    }

    func confirmRenameFolder() {
        defer { isRenamingFolder = false }
        let name = renameFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let folder = folderBeingRenamed else { return }
        try? services.store.renameActionFolder(id: folder.id, name: name)
        folderBeingRenamed = nil
        loadFolders()
    }

    func requestDeleteFolder(_ folder: ActionFolder) {
        folderPendingDelete = folder
        folderPendingDeleteCount = (try? services.store.countActions(folderID: folder.id)) ?? 0
        confirmingFolderDelete = true
    }

    func confirmDeleteFolder() {
        confirmingFolderDelete = false
        guard let folder = folderPendingDelete else { return }
        let childIDs = (try? services.store.listActions(folderID: folder.id))?.map(\.id) ?? []
        try? services.store.deleteActionFolder(id: folder.id)
        ShortcutCenter.shared.reset(.actionFolder, folder.id)
        childIDs.forEach { ShortcutCenter.shared.reset(.action, $0) }
        folderPendingDelete = nil
        // Clear the editor if the open action lived in this (cascade-deleted) folder.
        if editingAction?.folderId == folder.id { clearEditor() }
        if selectedFolderID == folder.id {
            selectFolder(nil)
        } else {
            loadActions()
        }
    }

    // MARK: - Action delete

    func requestDeleteAction(_ action: ActionItem) {
        actionPendingDelete = action
        confirmingActionDelete = true
    }

    func confirmDeleteAction() {
        confirmingActionDelete = false
        guard let action = actionPendingDelete else { return }
        try? services.store.deleteAction(id: action.id)
        ShortcutCenter.shared.reset(.action, action.id)
        actionPendingDelete = nil
        if selectedActionID == action.id { clearEditor() }
        loadActions()
    }

    // MARK: - Reordering

    func reorderFolder(_ sourceID: Int64, before targetID: Int64) {
        guard sourceID != targetID else { return }
        var ordered = folders
        guard let from = ordered.firstIndex(where: { $0.id == sourceID }) else { return }
        let moved = ordered.remove(at: from)
        let to = ordered.firstIndex(where: { $0.id == targetID }) ?? ordered.count
        ordered.insert(moved, at: to)
        folders = ordered
        try? services.store.setActionFolderOrder(ordered.map(\.id))
    }

    func reorderAction(_ sourceID: Int64, before targetID: Int64) {
        guard canReorderActions, sourceID != targetID else { return }
        var ordered = actions
        guard let from = ordered.firstIndex(where: { $0.id == sourceID }) else { return }
        let moved = ordered.remove(at: from)
        let to = ordered.firstIndex(where: { $0.id == targetID }) ?? ordered.count
        ordered.insert(moved, at: to)
        actions = ordered
        try? services.store.setActionOrder(ordered.map(\.id))
    }
}
