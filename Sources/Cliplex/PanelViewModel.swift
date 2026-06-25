import AppKit
import SwiftUI
import Combine
import Carbon.HIToolbox
import CliplexKit

/// Drives the panel UI: holds the query/mode/selection, loads data from
/// `AppServices`, builds the grouped layout, and handles keyboard commands.
@MainActor
final class PanelViewModel: ObservableObject {
    @Published var query = ""
    @Published private(set) var mode: PanelMode = .clipboard
    @Published private(set) var layout = PanelLayout()
    @Published var selection = 0
    /// Bumped only by keyboard navigation, so the list auto-scrolls for arrow
    /// keys but not when the selection follows the mouse on hover.
    @Published private(set) var scrollToken = 0
    @Published private(set) var needsAccessibility = false
    @Published var toast: String?
    /// Bumped whenever the panel is shown, so the view can re-focus the field.
    @Published var showToken = 0

    /// Set by the panel controller to dismiss the window.
    var requestHide: () -> Void = {}
    /// Set by the app delegate to open the Settings window.
    var requestSettings: () -> Void = {}

    private let services: AppServices
    private var collapsed: Set<Int64> = []
    private var clipRows: [DisplayRow] = []
    private var snippetRows: [DisplayRow] = []
    private var folders: [SnippetFolder] = []
    private var cancellables: Set<AnyCancellable> = []
    private var toastWork: DispatchWorkItem?
    private var lastHoverLocation = CGPoint(x: -1, y: -1)

    init(services: AppServices) {
        self.services = services

        $query
            .removeDuplicates()
            .debounce(for: .milliseconds(60), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .cliplexHistoryChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reloadIfClipboard() }
            .store(in: &cancellables)
    }

    // MARK: - Lifecycle

    /// Called each time the panel is shown: resets state and reloads data.
    func onShow(mode: PanelMode) {
        self.mode = mode
        query = ""
        selection = 0
        needsAccessibility = !Accessibility.isTrusted
        reload()
        selectFirstRow()
        scrollToken += 1
    }

    /// Moves keyboard focus to the search field. Called after the panel becomes
    /// key, so SwiftUI's `FocusState` actually takes effect.
    func focusSearch() {
        showToken += 1
    }

    private func reloadIfClipboard() {
        if mode == .clipboard { reload() }
    }

    private func reload() {
        switch mode {
        case .clipboard:
            clipRows = services.clips(query: query).map(DisplayRow.init(clip:))
        case .snippets:
            folders = services.folders()
            snippetRows = services.snippets(query: query).map(DisplayRow.init(snippet:))
        }
        rebuild()
    }

    private func rebuild() {
        layout = buildPanelLayout(
            mode: mode,
            query: query,
            clips: clipRows,
            snippets: snippetRows,
            folders: folders,
            collapsed: collapsed
        )
        if selection >= layout.nav.count {
            selection = max(0, layout.nav.count - 1)
        }
    }

    // MARK: - Derived

    /// Number of pasteable rows (clips/snippets), used for the status label.
    var rowCount: Int { layout.flatRows.count }
    /// Number of keyboard-navigable items (rows plus tree headers).
    var navCount: Int { layout.nav.count }

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var navSelection: NavItem? {
        guard selection >= 0, selection < layout.nav.count else { return nil }
        return layout.nav[selection]
    }

    /// Stable scroll identity of the selected item (used by `ScrollViewReader`),
    /// matching the entry's `ForEach` identity (a row's `listID` or a header id).
    var selectedScrollID: String? {
        switch navSelection {
        case let .row(i):
            guard i >= 0, i < layout.flatRows.count else { return nil }
            return layout.flatRows[i].listID
        case let .header(key):
            return "h:\(key)"
        case nil:
            return nil
        }
    }

    func isRowSelected(_ flatIndex: Int) -> Bool {
        if case let .row(i) = navSelection { return i == flatIndex }
        return false
    }

    func isHeaderSelected(_ folderKey: Int64) -> Bool {
        if case let .header(key) = navSelection { return key == folderKey }
        return false
    }

    var statusText: String {
        "\(rowCount) \(mode == .clipboard ? "clips" : "snippets")"
    }

    // MARK: - Actions

    func switchMode(to newMode: PanelMode) {
        guard newMode != mode else { return }
        mode = newMode
        selection = 0
        reload()
        selectFirstRow()
        scrollToken += 1
    }

    func cycleMode(forward: Bool) {
        switchMode(to: mode == .clipboard ? .snippets : .clipboard)
    }

    func move(_ delta: Int) {
        guard navCount > 0 else { return }
        selection = min(navCount - 1, max(0, selection + delta))
        scrollToken += 1
    }

    /// Selects a row (by its `flatRows` index) without auto-scrolling. Used for
    /// clicks/hover, which target rows rather than tree headers.
    func selectRow(_ flatIndex: Int) {
        if let n = layout.nav.firstIndex(of: .row(flatIndex)) { selection = n }
    }

    /// Hover selection that only takes effect on real pointer movement. The
    /// pointer location is compared against the last hover location so that
    /// rows scrolling *under a stationary cursor* (e.g. during keyboard nav)
    /// don't hijack the selection.
    func hoverMoved(to location: CGPoint, index flatIndex: Int) {
        guard location != lastHoverLocation else { return }
        lastHoverLocation = location
        selectRow(flatIndex)
    }

    func activateSelection() {
        switch navSelection {
        case let .row(i):
            paste(rowAt: i)
        case let .header(key):
            toggleFolder(key)
        case nil:
            break
        }
    }

    func quickPaste(_ index: Int) {
        paste(rowAt: index)
    }

    private func paste(rowAt index: Int) {
        guard index >= 0, index < layout.flatRows.count else { return }
        let row = layout.flatRows[index]
        let hide = requestHide
        switch row.kind {
        case .clip:
            services.pasteClip(id: row.id, hidePanel: hide)
        case .snippet:
            services.pasteSnippet(id: row.id, hidePanel: hide)
        }
    }

    func togglePinSelected() {
        guard let row = selectedRow, case .clip = row.kind else { return }
        services.togglePin(clipID: row.id, pinned: !row.pinned)
    }

    func saveSnippetFromSelected() {
        guard let row = selectedRow, case .clip = row.kind else { return }
        if let error = services.addSnippetFromClip(id: row.id) {
            showToast(error)
        } else {
            showToast("saved as snippet")
        }
    }

    func toggleFolder(_ key: Int64) {
        setCollapsed(key, !collapsed.contains(key))
    }

    /// Opens the Settings window, dismissing the panel first.
    func openSettings() {
        requestHide()
        requestSettings()
    }

    // MARK: - Tree navigation (snippets)

    /// Left arrow: collapse the selected folder, or jump from a snippet to its
    /// parent folder header. Returns `true` when handled (so the key is consumed
    /// instead of moving the search-field cursor).
    func collapseOrParent() -> Bool {
        guard mode == .snippets, !isSearching else { return false }
        switch navSelection {
        case let .header(key):
            if !collapsed.contains(key) { setCollapsed(key, true) }
        case let .row(i):
            let key = layout.flatRows[i].folderID ?? uncategorizedFolderKey
            selectHeader(key)
        case nil:
            break
        }
        return true
    }

    /// Right arrow: expand a collapsed folder ("if collapsed and I get to it,
    /// expand it"), or step into an expanded folder's first row.
    func expandOrChild() -> Bool {
        guard mode == .snippets, !isSearching else { return false }
        switch navSelection {
        case let .header(key):
            if collapsed.contains(key) { setCollapsed(key, false) }
            else { moveToFirstChild(key) }
        case .row, nil:
            break
        }
        return true
    }

    private func setCollapsed(_ key: Int64, _ value: Bool) {
        if value { collapsed.insert(key) } else { collapsed.remove(key) }
        withAnimation(.easeOut(duration: 0.18)) {
            rebuild()
            // Keep the toggled folder selected as its rows appear/disappear.
            if let n = layout.nav.firstIndex(of: .header(folderKey: key)) { selection = n }
        }
        scrollToken += 1
    }

    /// Selects the first pasteable row, skipping any leading folder headers, so
    /// opening a tab lands on a snippet/clip ready to paste rather than a header.
    private func selectFirstRow() {
        if let n = layout.nav.firstIndex(where: { if case .row = $0 { return true }; return false }) {
            selection = n
        } else {
            selection = 0
        }
    }

    private func selectHeader(_ key: Int64) {
        if let n = layout.nav.firstIndex(of: .header(folderKey: key)) {
            selection = n
            scrollToken += 1
        }
    }

    private func moveToFirstChild(_ key: Int64) {
        guard let header = layout.nav.firstIndex(of: .header(folderKey: key)) else { return }
        let next = header + 1
        guard next < layout.nav.count, case let .row(i) = layout.nav[next] else { return }
        let folderKey = layout.flatRows[i].folderID ?? uncategorizedFolderKey
        guard folderKey == key else { return }
        selection = next
        scrollToken += 1
    }

    func requestAccessibility() {
        Accessibility.prompt()
    }

    private var selectedRow: DisplayRow? {
        guard case let .row(i) = navSelection, i >= 0, i < layout.flatRows.count else { return nil }
        return layout.flatRows[i]
    }

    private func showToast(_ message: String) {
        toast = message
        toastWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
    }

    // MARK: - Keyboard

    /// A key event reduced to `Sendable` value data, so it can cross into the
    /// main-actor view model without capturing the non-`Sendable` `NSEvent`.
    struct KeyPress: Sendable {
        let keyCode: Int
        let command: Bool
        let shift: Bool
        let characters: String?
    }

    /// Handles a key event while the panel is key. Returns `true` when the event
    /// was consumed (so the local monitor swallows it); plain typing falls
    /// through to the search field.
    func handleKeyDown(_ key: KeyPress) -> Bool {
        switch key.keyCode {
        case kVK_DownArrow:
            move(1); return true
        case kVK_UpArrow:
            move(-1); return true
        case kVK_LeftArrow:
            return collapseOrParent()
        case kVK_RightArrow:
            return expandOrChild()
        case kVK_Return, kVK_ANSI_KeypadEnter:
            activateSelection(); return true
        case kVK_Escape:
            requestHide(); return true
        case kVK_Tab:
            cycleMode(forward: !key.shift); return true
        default:
            break
        }

        if key.command {
            switch key.characters {
            case "p": togglePinSelected(); return true
            case "s": saveSnippetFromSelected(); return true
            default:
                if let digit = key.characters, digit.count == 1, let value = Int(digit) {
                    // ⌘1…⌘9 → rows 0…8, ⌘0 → row 9.
                    quickPaste(value == 0 ? 9 : value - 1)
                    return true
                }
            }
        }
        return false
    }
}
