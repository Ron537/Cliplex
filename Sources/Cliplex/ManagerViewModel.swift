import AppKit
import CliplexKit
import UniformTypeIdentifiers

/// State + actions for the manager window (snippets CRUD and settings).
@MainActor
final class ManagerViewModel: ObservableObject {
    // Snippets
    @Published var folders: [SnippetFolder] = []
    @Published var selectedFolderID: Int64?
    @Published var snippets: [Snippet] = []
    @Published var selectedSnippetID: Int64?
    @Published var draftTitle = ""
    @Published var draftContent = ""
    @Published var newFolderName = ""
    /// True while composing a brand-new snippet that hasn't been saved yet. The
    /// database row is created only on the first save, so abandoning a draft
    /// never leaves an empty "Untitled" behind.
    @Published private(set) var isDraft = false

    // Dialogs
    @Published var isNamingFolder = false
    @Published var isRenamingFolder = false
    @Published var renameFolderName = ""
    @Published var confirmingFolderDelete = false
    @Published var confirmingSnippetDelete = false
    @Published private(set) var folderPendingDelete: SnippetFolder?
    @Published private(set) var folderPendingDeleteCount = 0
    @Published private(set) var snippetPendingDelete: Snippet?
    private var folderBeingRenamed: SnippetFolder?

    /// The persisted snapshot of the snippet currently open (used to detect
    /// unsaved edits). Nil while composing a draft.
    private var editingSnippet: Snippet?

    // Settings
    @Published var settings: AppSettings
    @Published var autostartEnabled: Bool

    private let services: AppServices

    init(services: AppServices) {
        self.services = services
        self.settings = services.settings
        self.autostartEnabled = LoginItem.isEnabled
        loadFolders()
        loadSnippets()
    }

    var selectedFolderName: String {
        guard let id = selectedFolderID else { return "All snippets" }
        return folders.first { $0.id == id }?.name ?? ""
    }

    /// Whether the editor is open (composing a draft or editing a saved snippet).
    var isEditing: Bool { isDraft || selectedSnippetID != nil }

    /// Whether the editor holds changes that haven't been saved.
    var hasUnsavedChanges: Bool {
        if isDraft { return !draftTitle.isEmpty || !draftContent.isEmpty }
        guard let snippet = editingSnippet else { return false }
        return draftTitle != snippet.title || draftContent != snippet.content
    }

    var draftLineCount: Int {
        draftContent.isEmpty ? 0 : draftContent.split(separator: "\n", omittingEmptySubsequences: false).count
    }
    var draftCharCount: Int { draftContent.count }

    var folderPendingDeleteName: String { folderPendingDelete?.name ?? "" }

    var folderPendingDeleteCountText: String {
        folderPendingDeleteCount == 1 ? "1 snippet" : "\(folderPendingDeleteCount) snippets"
    }

    var snippetPendingDeleteName: String {
        let title = (snippetPendingDelete?.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Untitled" : title
    }

    // MARK: - Snippets

    /// Total snippets across all folders (for the Library toolbar count).
    var totalSnippetCount: Int { (try? services.store.countSnippets(folderID: nil)) ?? 0 }

    /// Number of snippets in a specific folder (for the rail row count).
    func count(inFolder id: Int64) -> Int { (try? services.store.countSnippets(folderID: id)) ?? 0 }

    func loadFolders() {
        folders = (try? services.store.listFolders()) ?? []
    }

    func loadSnippets() {
        snippets = (try? services.store.listSnippets(folderID: selectedFolderID)) ?? []
    }

    func selectFolder(_ id: Int64?) {
        commitPendingEdits()
        selectedFolderID = id
        clearEditor()
        loadSnippets()
    }

    func openSnippet(_ snippet: Snippet) {
        guard snippet.id != selectedSnippetID || isDraft else { return }
        commitPendingEdits()
        isDraft = false
        selectedSnippetID = snippet.id
        editingSnippet = snippet
        draftTitle = snippet.title
        draftContent = snippet.content
    }

    /// Saves in-flight edits before the editor is replaced, so navigating away
    /// never silently loses work: a non-empty draft is created, and changes to a
    /// saved snippet are persisted. An empty draft is simply dropped.
    private func commitPendingEdits() {
        if isDraft {
            let hasContent = !draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !draftContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if hasContent { saveSnippet() }
        } else if hasUnsavedChanges {
            saveSnippet()
        }
    }

    /// Opens the "New Folder" naming dialog.
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
        guard !name.isEmpty, let folder = try? services.store.addFolder(name: name) else { return }
        newFolderName = ""
        isNamingFolder = false
        loadFolders()
        selectFolder(folder.id)
    }

    /// Opens the rename dialog for a folder, pre-filled with its current name.
    func requestRenameFolder(_ folder: SnippetFolder) {
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
        try? services.store.renameFolder(id: folder.id, name: name)
        folderBeingRenamed = nil
        loadFolders()
    }

    // MARK: - Import / Export

    /// Exports all folders and snippets to a JSON file chosen by the user.
    func exportSnippets() {
        let data: Data
        do {
            data = try SnippetIO.export(from: services.store)
        } catch {
            presentError("Could not export snippets", error)
            return
        }
        let panel = NSSavePanel()
        panel.title = "Export Snippets"
        panel.nameFieldStringValue = "cliplex-snippets.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url)
        } catch {
            presentError("Could not save the export file", error)
        }
    }

    /// Imports folders and snippets from a JSON file, merging into the library.
    func importSnippets() {
        let panel = NSOpenPanel()
        panel.title = "Import Snippets"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            presentError("Could not read the file", error)
            return
        }
        do {
            try SnippetIO.importing(data, into: services.store)
        } catch {
            presentError("Could not import snippets", error)
            return
        }
        loadFolders()
        loadSnippets()
    }

    private func presentError(_ title: String, _ error: Error) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }

    /// Asks for confirmation before deleting a folder (the hovered one).
    func requestDeleteFolder(_ folder: SnippetFolder) {
        folderPendingDelete = folder
        folderPendingDeleteCount = (try? services.store.countSnippets(folderID: folder.id)) ?? 0
        confirmingFolderDelete = true
    }

    func confirmDeleteFolder() {
        confirmingFolderDelete = false
        guard let folder = folderPendingDelete else { return }
        // Release the folder's global shortcut and those of the snippets it
        // cascade-deletes, so no orphaned hotkeys linger.
        let childIDs = (try? services.store.listSnippets(folderID: folder.id))?.map(\.id) ?? []
        try? services.store.deleteFolder(id: folder.id)
        ShortcutCenter.shared.reset(.snippetFolder, folder.id)
        childIDs.forEach { ShortcutCenter.shared.reset(.snippet, $0) }
        folderPendingDelete = nil
        loadFolders()
        // The open snippet may have lived in this folder (cascade-deleted) — clear
        // the editor so a later Save doesn't silently fail on a missing row.
        if editingSnippet?.folderId == folder.id {
            clearEditor()
        }
        if selectedFolderID == folder.id {
            selectFolder(nil)
        } else {
            loadSnippets()
        }
    }

    /// Begins composing a new snippet inline. Nothing is written to the database
    /// until ``saveSnippet()``; until then this is just an in-memory draft shown
    /// at the top of the list.
    func newSnippet() {
        commitPendingEdits()
        isDraft = true
        selectedSnippetID = nil
        editingSnippet = nil
        draftTitle = ""
        draftContent = ""
    }

    func saveSnippet() {
        let title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = title.isEmpty ? "Untitled" : title

        if isDraft {
            // Don't persist a completely empty draft.
            guard !title.isEmpty || !draftContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return }
            guard let snippet = try? services.store.addSnippet(
                folderID: selectedFolderID, title: resolvedTitle, content: draftContent) else { return }
            // Adopt the saved snippet as the editor's current item. (Set state
            // directly rather than via openSnippet(), which would re-enter the
            // commit logic.)
            isDraft = false
            selectedSnippetID = snippet.id
            editingSnippet = snippet
            draftTitle = snippet.title
            draftContent = snippet.content
            loadSnippets()
        } else {
            guard let id = selectedSnippetID else { return }
            try? services.store.updateSnippet(id: id, title: resolvedTitle, content: draftContent)
            loadSnippets()
            if let updated = try? services.store.snippet(id: id) {
                editingSnippet = updated
                draftTitle = updated.title
                draftContent = updated.content
            }
        }
    }

    /// Discards an unsaved draft (no confirmation needed — it was never saved).
    func discardDraft() {
        clearEditor()
    }

    /// The folder of the snippet currently open in the editor (nil for drafts /
    /// uncategorized). Used by the inspector's Folder picker.
    var editingSnippetFolderID: Int64? { editingSnippet?.folderId }

    /// Moves the open (saved) snippet to another folder.
    func moveEditingSnippet(to folderID: Int64?) {
        guard let snippet = editingSnippet, snippet.folderId != folderID else { return }
        try? services.store.setSnippetFolder(id: snippet.id, folderID: folderID)
        if let updated = try? services.store.snippet(id: snippet.id) { editingSnippet = updated }
        loadSnippets()
    }

    /// Duplicates the open (saved) snippet and opens the copy.
    func duplicateEditingSnippet() {
        commitPendingEdits()
        guard let snippet = editingSnippet else { return }
        guard let copy = try? services.store.addSnippet(
            folderID: snippet.folderId, title: snippet.title + " copy", content: snippet.content) else { return }
        loadSnippets()
        ShortcutCenter.shared.ensureHandler(.snippet, copy.id)
        openSnippet(copy)
    }

    /// Deletes the snippet currently open in the editor (by id, so it works even
    /// after the item was moved out of the visible folder).
    func requestDeleteEditingSnippet() {
        if let snippet = editingSnippet { requestDeleteSnippet(snippet) }
    }

    /// Asks for confirmation before deleting a saved snippet (the hovered one).
    func requestDeleteSnippet(_ snippet: Snippet) {
        snippetPendingDelete = snippet
        confirmingSnippetDelete = true
    }

    func confirmDeleteSnippet() {
        confirmingSnippetDelete = false
        guard let snippet = snippetPendingDelete else { return }
        try? services.store.deleteSnippet(id: snippet.id)
        ShortcutCenter.shared.reset(.snippet, snippet.id)
        snippetPendingDelete = nil
        if selectedSnippetID == snippet.id { clearEditor() }
        loadSnippets()
    }

    private func clearEditor() {
        isDraft = false
        selectedSnippetID = nil
        editingSnippet = nil
        draftTitle = ""
        draftContent = ""
    }

    // MARK: - Reordering (drag & drop)

    /// Reordering snippets only makes sense within a specific folder (the "All
    /// snippets" view is an aggregate ordered by folder).
    var canReorderSnippets: Bool { selectedFolderID != nil }

    func reorderFolder(_ sourceID: Int64, before targetID: Int64) {
        guard sourceID != targetID else { return }
        var ordered = folders
        guard let from = ordered.firstIndex(where: { $0.id == sourceID }) else { return }
        let moved = ordered.remove(at: from)
        let to = ordered.firstIndex(where: { $0.id == targetID }) ?? ordered.count
        ordered.insert(moved, at: to)
        folders = ordered
        try? services.store.setFolderOrder(ordered.map(\.id))
    }

    func reorderSnippet(_ sourceID: Int64, before targetID: Int64) {
        guard canReorderSnippets, sourceID != targetID else { return }
        var ordered = snippets
        guard let from = ordered.firstIndex(where: { $0.id == sourceID }) else { return }
        let moved = ordered.remove(at: from)
        let to = ordered.firstIndex(where: { $0.id == targetID }) ?? ordered.count
        ordered.insert(moved, at: to)
        snippets = ordered
        try? services.store.setSnippetOrder(ordered.map(\.id))
    }

    // MARK: - Settings

    /// Persists the current settings immediately (native Settings behavior),
    /// then mirrors back any normalization the store applied (e.g. clamping
    /// "Maximum history items" into range) so the field shows the effective value.
    func applySettings() {
        services.updateSettings(settings)
        if settings != services.settings {
            settings = services.settings
        }
    }

    /// Applies the launch-at-login toggle, reverting it if the OS rejects the
    /// change (e.g. an unsigned dev build).
    func applyAutostart() {
        LoginItem.set(autostartEnabled)
        let actual = LoginItem.isEnabled
        if actual != autostartEnabled { autostartEnabled = actual }
    }

    /// Clears all unpinned clipboard history.
    func clearHistory() {
        services.clearHistory()
    }
}
