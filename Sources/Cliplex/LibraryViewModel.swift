import AppKit
import CliplexKit
import Combine

/// The unified Library window's model. It composes the existing
/// ``ManagerViewModel`` (snippets) and ``ActionsViewModel`` (actions) and adds a
/// type filter plus the notion of an "active domain" — which side currently owns
/// the item list and inspector. The two sub-models keep all the CRUD/draft logic.
@MainActor
final class LibraryViewModel: ObservableObject {
    enum Domain { case snippet, action }
    enum Filter: CaseIterable { case all, snippets, actions
        var title: String {
            switch self { case .all: return "All"; case .snippets: return "Snippets"; case .actions: return "Actions" }
        }
    }

    let snippets: ManagerViewModel
    let actions: ActionsViewModel

    @Published var filter: Filter = .all {
        didSet {
            // Keep the active list/inspector in a domain the filter actually shows.
            switch filter {
            case .snippets: if activeDomain != .snippet { selectSnippetFolder(nil) }
            case .actions: if activeDomain != .action { selectActionFolder(nil) }
            case .all: break
            }
        }
    }
    @Published private(set) var activeDomain: Domain = .snippet
    @Published var query = ""

    private var bag: Set<AnyCancellable> = []

    init(services: AppServices) {
        snippets = ManagerViewModel(services: services)
        actions = ActionsViewModel(services: services)
        // Re-publish child changes so the unified view refreshes.
        snippets.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        actions.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        // Start with the first snippet folder ("All snippets") active.
        snippets.selectFolder(nil)
    }

    // MARK: - Counts (for the toolbar pill)

    var folderCount: Int { snippets.folders.count + actions.folders.count }
    var itemCount: Int { snippets.totalSnippetCount + actions.totalActionCount }

    // MARK: - Rail visibility

    var showsSnippets: Bool { filter != .actions }
    var showsActions: Bool { filter != .snippets }

    // MARK: - Selection

    var snippetFolderActive: Bool { activeDomain == .snippet }
    var actionFolderActive: Bool { activeDomain == .action }

    func isSnippetFolderSelected(_ id: Int64?) -> Bool {
        activeDomain == .snippet && snippets.selectedFolderID == id
    }
    func isActionFolderSelected(_ id: Int64?) -> Bool {
        activeDomain == .action && actions.selectedFolderID == id
    }

    func selectSnippetFolder(_ id: Int64?) {
        activeDomain = .snippet
        snippets.selectFolder(id)
    }
    func selectActionFolder(_ id: Int64?) {
        activeDomain = .action
        actions.selectFolder(id)
    }

    func activeDomainSelectSnippet(_ snippet: Snippet) {
        activeDomain = .snippet
        snippets.openSnippet(snippet)
    }
    func activeDomainSelectAction(_ action: ActionItem) {
        activeDomain = .action
        actions.openAction(action)
    }

    // MARK: - Active list / header

    var listTitle: String {
        activeDomain == .snippet ? snippets.selectedFolderName : actions.selectedFolderName
    }
    var listIsSnippets: Bool { activeDomain == .snippet }

    /// The active list filtered by the search query (title/content/value).
    var visibleSnippets: [Snippet] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return snippets.snippets }
        return snippets.snippets.filter {
            $0.title.lowercased().contains(q) || $0.content.lowercased().contains(q)
        }
    }
    var visibleActions: [ActionItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return actions.actions }
        return actions.actions.filter {
            $0.title.lowercased().contains(q) || $0.value.lowercased().contains(q)
        }
    }

    var listCount: Int {
        activeDomain == .snippet ? snippets.snippets.count : actions.actions.count
    }

    // MARK: - New menu

    func newSnippet() {
        if filter == .actions { filter = .all }
        activeDomain = .snippet
        snippets.newSnippet()
    }
    func newAction() {
        if filter == .snippets { filter = .all }
        activeDomain = .action
        actions.newAction()
    }
    func newSnippetFolder() {
        if filter == .actions { filter = .all }
        activeDomain = .snippet
        snippets.promptNewFolder()
    }
    func newActionFolder() {
        if filter == .snippets { filter = .all }
        activeDomain = .action
        actions.promptNewFolder()
    }

    func reload() {
        snippets.loadFolders(); snippets.loadSnippets()
        actions.loadFolders(); actions.loadActions()
        ShortcutCenter.shared.syncAll()
    }

    /// Brings a domain to the front (used when opened from a folder shortcut /
    /// the "Snippets…/Actions…" menu items).
    func focusDomain(_ domain: Domain) {
        switch domain {
        case .snippet: filter = .all; selectSnippetFolder(nil)
        case .action: filter = .all; selectActionFolder(nil)
        }
    }
}
