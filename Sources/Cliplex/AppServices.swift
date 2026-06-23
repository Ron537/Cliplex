import AppKit
import CliplexKit

/// Notifications posted when shared state changes, so open windows refresh.
extension Notification.Name {
    static let cliplexHistoryChanged = Notification.Name("cliplex.historyChanged")
    static let cliplexSettingsChanged = Notification.Name("cliplex.settingsChanged")
}

/// The bridge between the UI and `CliplexKit`: owns the database, the clipboard
/// monitor, and the cached settings, and exposes all the actions the panel and
/// manager windows perform.
final class AppServices {
    let store: ClipStore
    private let clipboard = MacClipboard()
    private(set) var settings: AppSettings
    private var monitor: ClipboardMonitor!

    /// Search/listing limit derived from `maxHistory`, so "Maximum history
    /// items" directly bounds what the panel shows.
    var historyLimit: Int64 { settings.maxHistory }

    init() throws {
        store = try ClipStore(path: AppServices.databasePath())
        settings = AppSettings.load(from: store)
        monitor = ClipboardMonitor(
            store: store,
            clipboard: clipboard,
            settingsProvider: { [weak self] in self?.settings ?? AppSettings() },
            onChange: {
                NotificationCenter.default.post(name: .cliplexHistoryChanged, object: nil)
            }
        )
    }

    func startMonitoring() {
        monitor.start()
    }

    // MARK: - Reads

    func clips(query: String) -> [Clip] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // Pruning keeps `maxHistory` unpinned clips *plus* all pinned ones, so
        // the listing limit is widened by the pinned count; otherwise pinned
        // clips would push the oldest retained unpinned clips out of view.
        let limit = historyLimit + ((try? store.countPinned()) ?? 0)
        if trimmed.isEmpty {
            return (try? store.listClips(limit: limit)) ?? []
        }
        return (try? store.searchClips(trimmed, limit: limit)) ?? []
    }

    func folders() -> [SnippetFolder] {
        (try? store.listFolders()) ?? []
    }

    func snippets(query: String) -> [Snippet] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return (try? store.listSnippets(folderID: nil)) ?? []
        }
        return (try? store.searchSnippets(trimmed, limit: 200)) ?? []
    }

    // MARK: - Clip actions

    func togglePin(clipID: Int64, pinned: Bool) {
        try? store.setPinned(id: clipID, pinned: pinned)
        NotificationCenter.default.post(name: .cliplexHistoryChanged, object: nil)
    }

    func deleteClip(id: Int64) {
        try? store.deleteClip(id: id)
        NotificationCenter.default.post(name: .cliplexHistoryChanged, object: nil)
    }

    /// Creates a snippet from a stored clip's text. Returns an error message on
    /// failure (e.g. the clip has no text).
    @discardableResult
    func addSnippetFromClip(id: Int64) -> String? {
        guard let assets = try? store.clipAssets(clipID: id) else { return "couldn't read clip" }
        guard let textAsset = assets.first(where: { $0.uti == UTI.text }) else {
            return "this clip has no text to save as a snippet"
        }
        let text = String(decoding: textAsset.bytes, as: UTF8.self)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "this clip has no text to save as a snippet"
        }
        _ = try? store.addSnippet(folderID: nil, title: Self.snippetTitle(text), content: text)
        return nil
    }

    // MARK: - Paste

    /// Writes a clip back to the clipboard and pastes it into the frontmost app.
    func pasteClip(id: Int64, hidePanel: @escaping () -> Void) {
        guard let assets = try? store.clipAssets(clipID: id), !assets.isEmpty else { return }
        guard clipboard.write(assets) else { hidePanel(); return }
        finishPaste(hidePanel: hidePanel)
    }

    /// Writes a snippet's content to the clipboard and pastes it.
    func pasteSnippet(id: Int64, hidePanel: @escaping () -> Void) {
        guard let snippet = try? store.snippet(id: id) else { return }
        guard clipboard.write([ClipAsset(uti: UTI.text, bytes: Data(snippet.content.utf8))]) else {
            hidePanel()
            return
        }
        finishPaste(hidePanel: hidePanel)
    }

    /// Hides the panel and, when enabled and permitted, injects ⌘V.
    ///
    /// The panel is a non-activating window, so the previously focused app stays
    /// frontmost — no app re-activation dance is needed (unlike the Tauri build).
    /// A short delay lets key focus settle back onto that app before pasting.
    private func finishPaste(hidePanel: @escaping () -> Void) {
        hidePanel()
        guard settings.pasteOnSelect else { return }
        guard Accessibility.isTrusted else {
            promptForAccessibilityOnce()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            try? Paste.injectPaste()
        }
    }

    private var didPromptForAccessibility = false
    private func promptForAccessibilityOnce() {
        guard !didPromptForAccessibility else { return }
        didPromptForAccessibility = true
        Accessibility.prompt()
    }

    // MARK: - Settings

    func updateSettings(_ new: AppSettings) {
        try? new.save(to: store)
        settings = AppSettings.load(from: store)
        // Enforce a lowered history cap immediately rather than waiting for the
        // next captured clip.
        _ = try? store.pruneClips(maxItems: settings.maxHistory)
        NotificationCenter.default.post(name: .cliplexSettingsChanged, object: nil)
        NotificationCenter.default.post(name: .cliplexHistoryChanged, object: nil)
    }

    // MARK: - Helpers

    /// Derives a short snippet title from its content (first non-empty line,
    /// truncated to 40 characters).
    static func snippetTitle(_ content: String) -> String {
        let line = content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty }) ?? "Untitled"
        if line.count > 40 {
            return String(line.prefix(40)) + "…"
        }
        return line
    }

    /// `~/Library/Application Support/com.rborysowski.cliplex/cliplex.db`,
    /// matching the prior build so existing history/snippets are reused.
    private static func databasePath() -> String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("com.rborysowski.cliplex", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("cliplex.db").path
    }
}
