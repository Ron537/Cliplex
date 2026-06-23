import AppKit
import CliplexKit

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

    // Settings
    @Published var settings: AppSettings
    @Published var autostartEnabled: Bool
    @Published var settingsSaved = false

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

    // MARK: - Snippets

    func loadFolders() {
        folders = (try? services.store.listFolders()) ?? []
    }

    func loadSnippets() {
        snippets = (try? services.store.listSnippets(folderID: selectedFolderID)) ?? []
    }

    func selectFolder(_ id: Int64?) {
        selectedFolderID = id
        clearEditor()
        loadSnippets()
    }

    func openSnippet(_ snippet: Snippet) {
        selectedSnippetID = snippet.id
        draftTitle = snippet.title
        draftContent = snippet.content
    }

    func createFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let folder = try? services.store.addFolder(name: name) else { return }
        newFolderName = ""
        loadFolders()
        selectFolder(folder.id)
    }

    func deleteSelectedFolder() {
        guard let id = selectedFolderID else { return }
        try? services.store.deleteFolder(id: id)
        loadFolders()
        selectFolder(nil)
    }

    func newSnippet() {
        guard let snippet = try? services.store.addSnippet(
            folderID: selectedFolderID, title: "Untitled", content: "") else { return }
        loadSnippets()
        openSnippet(snippet)
    }

    func saveSnippet() {
        guard let id = selectedSnippetID else { return }
        let title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        try? services.store.updateSnippet(id: id, title: title.isEmpty ? "Untitled" : title, content: draftContent)
        loadSnippets()
    }

    func deleteSnippet() {
        guard let id = selectedSnippetID else { return }
        try? services.store.deleteSnippet(id: id)
        clearEditor()
        loadSnippets()
    }

    private func clearEditor() {
        selectedSnippetID = nil
        draftTitle = ""
        draftContent = ""
    }

    // MARK: - Settings

    func saveSettings() {
        services.updateSettings(settings)
        LoginItem.set(autostartEnabled)
        autostartEnabled = LoginItem.isEnabled
        settingsSaved = true
    }

    func markSettingsDirty() {
        settingsSaved = false
    }
}
