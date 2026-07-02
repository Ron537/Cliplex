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

    /// Whether the clipboard monitor is currently capturing.
    var isMonitoring: Bool { monitor.isRunning }

    /// Pauses or resumes clipboard capturing. Resuming does not capture whatever
    /// is already on the pasteboard — only clips copied afterwards.
    func setMonitoring(_ enabled: Bool) {
        if enabled {
            guard !monitor.isRunning else { return }
            monitor.start(capturingCurrent: false)
        } else {
            monitor.stop()
        }
    }

    /// Clears unpinned history on quit when the corresponding setting is enabled.
    func clearHistoryOnQuitIfNeeded() {
        guard settings.clearHistoryOnQuit else { return }
        _ = try? store.pruneClips(maxItems: 0)
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

        // Match snippet title/content (FTS)…
        let byContent = (try? store.searchSnippets(trimmed, limit: 200)) ?? []
        // …and also snippets whose *folder name* matches the query.
        let folders = (try? store.listFolders()) ?? []
        let matchingFolderIDs = folders.filter {
            $0.name.range(of: trimmed, options: .caseInsensitive) != nil
        }.map(\.id)
        let byFolder = matchingFolderIDs.flatMap { (try? store.listSnippets(folderID: $0)) ?? [] }

        // Merge, de-duplicated by id (content matches first).
        var seen = Set<Int64>()
        return (byContent + byFolder).filter { seen.insert($0.id).inserted }
    }

    func actionFolders() -> [ActionFolder] {
        (try? store.listActionFolders()) ?? []
    }

    func actions(query: String) -> [ActionItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return (try? store.listActions(folderID: nil)) ?? []
        }

        // Match action title/value (FTS)…
        let byContent = (try? store.searchActions(trimmed, limit: 200)) ?? []
        // …and also actions whose *folder name* matches the query.
        let folders = (try? store.listActionFolders()) ?? []
        let matchingFolderIDs = folders.filter {
            $0.name.range(of: trimmed, options: .caseInsensitive) != nil
        }.map(\.id)
        let byFolder = matchingFolderIDs.flatMap { (try? store.listActions(folderID: $0)) ?? [] }

        var seen = Set<Int64>()
        return (byContent + byFolder).filter { seen.insert($0.id).inserted }
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

    /// Writes a snippet's content to the clipboard and pastes it. `{clipboard}`
    /// is expanded with the current clipboard text so snippets can wrap whatever
    /// you copied last.
    func pasteSnippet(id: Int64, hidePanel: @escaping () -> Void) {
        guard let snippet = try? store.snippet(id: id) else { return }
        var content = snippet.content
        if content.contains("{clipboard}") {
            content = content.replacingOccurrences(of: "{clipboard}", with: currentClipboardText() ?? "")
        }
        guard clipboard.write([ClipAsset(uti: UTI.text, bytes: Data(content.utf8))]) else {
            hidePanel()
            return
        }
        finishPaste(hidePanel: hidePanel)
    }

    // MARK: - Actions

    /// The outcome of running a quick action, so the panel can show feedback.
    enum ActionOutcome {
        /// A URL/app/path was opened. The panel should just close.
        case opened
        /// The clipboard was transformed in place; carries a short toast message.
        case transformed(String)
        /// Something failed; carries a short toast message.
        case failed(String)
    }

    /// Runs a saved action: opens a URL/app/path, or transforms the clipboard
    /// text in place. `{clipboard}` in URL/app/path values is expanded with the
    /// current clipboard text (URL-encoded for URLs).
    func runAction(id: Int64) -> ActionOutcome {
        guard let action = try? store.action(id: id) else {
            return .failed("action not found")
        }
        let clipboardText = currentClipboardText() ?? ""

        switch action.type {
        case .openURL:
            guard let url = ActionLogic.resolvedURL(template: action.value, clipboard: clipboardText) else {
                return .failed("invalid URL")
            }
            guard NSWorkspace.shared.open(url) else { return .failed("couldn't open URL") }
            return .opened

        case .openApp:
            return openApp(action.value, clipboard: clipboardText)

        case .openPath:
            let expanded = ActionLogic.expand(action.value, clipboard: clipboardText, urlEncoded: false)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let path = (expanded as NSString).expandingTildeInPath
            guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else {
                return .failed("path not found")
            }
            guard NSWorkspace.shared.open(URL(fileURLWithPath: path)) else {
                return .failed("couldn't open path")
            }
            return .opened

        case .transform:
            guard let transform = action.transform else { return .failed("no transform set") }
            guard !clipboardText.isEmpty else { return .failed("clipboard is empty") }
            guard let result = ActionLogic.apply(transform, to: clipboardText) else {
                return .failed("can't \(transform.label.lowercased()) this")
            }
            guard clipboard.write([ClipAsset(uti: UTI.text, bytes: Data(result.utf8))]) else {
                return .failed("couldn't update clipboard")
            }
            return .transformed(transform.label.lowercased())
        }
    }

    /// Opens an app referenced either by bundle identifier or by a path.
    private func openApp(_ value: String, clipboard text: String) -> ActionOutcome {
        let raw = ActionLogic.expand(value, clipboard: text, urlEncoded: false)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return .failed("no app set") }

        // A path (…/Foo.app) → open directly; otherwise treat it as a bundle id.
        if raw.contains("/") || raw.lowercased().hasSuffix(".app") {
            let path = (raw as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: path) {
                guard NSWorkspace.shared.open(URL(fileURLWithPath: path)) else {
                    return .failed("couldn't open app")
                }
                return .opened
            }
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: raw) {
            guard NSWorkspace.shared.open(url) else { return .failed("couldn't open app") }
            return .opened
        }
        return .failed("app not found")
    }

    /// The current clipboard's plain text, if any (used by `{clipboard}` and
    /// transforms).
    private func currentClipboardText() -> String? {
        NSPasteboard.general.string(forType: .string)
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

    /// Removes all unpinned clipboard history (pinned clips are kept).
    func clearHistory() {
        _ = try? store.pruneClips(maxItems: 0)
        NotificationCenter.default.post(name: .cliplexHistoryChanged, object: nil)
    }

    func updateSettings(_ new: AppSettings) {        try? new.save(to: store)
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

    /// `~/Library/Application Support/com.ron537.cliplex/cliplex.db`,
    /// matching the prior build so existing history/snippets are reused.
    private static func databasePath() -> String {
        // General-purpose override used by the test suite and the screenshot
        // tooling (tools/screenshots/) to point Cliplex at a throwaway database.
        if let override = ProcessInfo.processInfo.environment["CLIPLEX_DB_PATH"], !override.isEmpty {
            return override
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("com.ron537.cliplex", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("cliplex.db").path
    }
}
