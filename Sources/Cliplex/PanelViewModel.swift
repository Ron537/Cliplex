import AppKit
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
    func onShow() {
        query = ""
        selection = 0
        needsAccessibility = !Accessibility.isTrusted
        reload()
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
        if selection >= layout.flatRows.count {
            selection = max(0, layout.flatRows.count - 1)
        }
    }

    // MARK: - Derived

    var rowCount: Int { layout.flatRows.count }
    var hasFolders: Bool { !folders.isEmpty }

    /// Stable scroll identity of the selected row (used by `ScrollViewReader`),
    /// matching the row's `ForEach` identity.
    var selectedScrollID: String? {
        guard selection >= 0, selection < layout.flatRows.count else { return nil }
        return layout.flatRows[selection].listID
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
    }

    func cycleMode(forward: Bool) {
        switchMode(to: mode == .clipboard ? .snippets : .clipboard)
    }

    func move(_ delta: Int) {
        guard rowCount > 0 else { return }
        selection = min(rowCount - 1, max(0, selection + delta))
        scrollToken += 1
    }

    /// Selects a row without auto-scrolling (used for click).
    func select(_ index: Int) {
        selection = index
    }

    /// Hover selection that only takes effect on real pointer movement. The
    /// pointer location is compared against the last hover location so that
    /// rows scrolling *under a stationary cursor* (e.g. during keyboard nav)
    /// don't hijack the selection.
    func hoverMoved(to location: CGPoint, index: Int) {
        guard location != lastHoverLocation else { return }
        lastHoverLocation = location
        selection = index
    }

    func activateSelection() {
        paste(rowAt: selection)
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
        if collapsed.contains(key) { collapsed.remove(key) } else { collapsed.insert(key) }
        rebuild()
    }

    func requestAccessibility() {
        Accessibility.prompt()
    }

    private var selectedRow: DisplayRow? {
        guard selection >= 0, selection < layout.flatRows.count else { return nil }
        return layout.flatRows[selection]
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
