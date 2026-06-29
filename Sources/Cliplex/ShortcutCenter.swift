import AppKit
import CliplexKit
import KeyboardShortcuts

/// Registers and routes the *dynamic* per-item / per-folder global shortcuts.
///
/// Each snippet, snippet folder, action, and action folder can carry its own
/// global hotkey. The shortcut value itself is stored by `KeyboardShortcuts`
/// (in `UserDefaults`, keyed by a stable `Name`); this center owns the *handlers*
/// that fire when those hotkeys are pressed:
///
/// - snippet item → paste the snippet into the frontmost app
/// - action item → run the action (open URL/app/path, or transform the clipboard)
/// - snippet/action folder → open the panel focused on that folder
///
/// Handlers are registered once per `Name` (registering the same name twice with
/// `onKeyUp` would fire it twice). They're (re)synced at launch for everything
/// that already has a shortcut, and on demand the moment the user assigns one.
@MainActor
final class ShortcutCenter {
    static let shared = ShortcutCenter()

    enum Kind: String {
        case snippet, snippetFolder, action, actionFolder
    }

    private weak var services: AppServices?
    private var openFolder: ((PanelMode, Int64) -> Void)?
    private var registered: Set<String> = []

    private init() {}

    func configure(services: AppServices, openFolder: @escaping (PanelMode, Int64) -> Void) {
        self.services = services
        self.openFolder = openFolder
        syncAll()
    }

    /// The stable `KeyboardShortcuts.Name` for a given item/folder id.
    func name(_ kind: Kind, _ id: Int64) -> KeyboardShortcuts.Name {
        KeyboardShortcuts.Name("cliplex_\(kind.rawValue)_\(id)")
    }

    /// Ensures the global handler for this id is installed (idempotent). Call
    /// when the user assigns a shortcut to a newly created item/folder.
    func ensureHandler(_ kind: Kind, _ id: Int64) {
        let n = name(kind, id)
        guard registered.insert(n.rawValue).inserted else { return }
        KeyboardShortcuts.onKeyUp(for: n) { [weak self] in
            MainActor.assumeIsolated { self?.fire(kind, id) }
        }
    }

    /// Registers handlers for every existing item/folder so persisted shortcuts
    /// keep working across launches.
    func syncAll() {
        guard let store = services?.store else { return }
        for f in (try? store.listFolders()) ?? [] { ensureHandler(.snippetFolder, f.id) }
        for s in (try? store.listSnippets(folderID: nil)) ?? [] { ensureHandler(.snippet, s.id) }
        for f in (try? store.listActionFolders()) ?? [] { ensureHandler(.actionFolder, f.id) }
        for a in (try? store.listActions(folderID: nil)) ?? [] { ensureHandler(.action, a.id) }
    }

    /// Clears a shortcut assignment (used when an item/folder is deleted).
    func reset(_ kind: Kind, _ id: Int64) {
        KeyboardShortcuts.reset(name(kind, id))
    }

    /// Whether a shortcut is currently assigned to this id (drives chip reveal).
    func hasShortcut(_ kind: Kind, _ id: Int64) -> Bool {
        KeyboardShortcuts.getShortcut(for: name(kind, id)) != nil
    }

    private func fire(_ kind: Kind, _ id: Int64) {
        guard let services else { return }
        switch kind {
        case .snippet:
            services.pasteSnippet(id: id, hidePanel: {})
        case .action:
            _ = services.runAction(id: id)
        case .snippetFolder:
            openFolder?(.snippets, id)
        case .actionFolder:
            openFolder?(.actions, id)
        }
    }
}
