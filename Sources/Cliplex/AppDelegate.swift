import AppKit
import CliplexKit
import KeyboardShortcuts

/// Owns the app lifecycle: services, the menu-bar item, the global hotkeys, the
/// clipboard panel, and the manager windows.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var services: AppServices!
    private var statusItem: NSStatusItem?
    private var panel: PanelController!
    private var managerViewModel: ManagerViewModel?
    private var libraryViewModel: LibraryViewModel?
    private var libraryWindow: LibraryWindowController?
    private var settingsWindow: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppFonts.register()
        do {
            services = try AppServices()
        } catch {
            presentFatal(error)
            return
        }

        applyAppearance()
        installMainMenu()
        let viewModel = PanelViewModel(services: services)
        viewModel.requestSettings = { [weak self] in self?.openSettings() }
        panel = PanelController(viewModel: viewModel)

        installStatusItem()
        installShortcuts()
        ShortcutCenter.shared.configure(services: services) { [weak self] mode, folderID in
            self?.panel.present(mode: mode, focusFolder: folderID)
        }

        // Don't capture the live clipboard when rendering screenshots/GIFs —
        // it would pollute the generic demo database with real clips.
        #if CLIPLEX_SCREENSHOTS
        let screenshotMode = ScreenshotMode.requestedTarget != nil
        #else
        let screenshotMode = false
        #endif
        if !screenshotMode {
            services.startMonitoring()
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(applyAppearance),
            name: .cliplexSettingsChanged, object: nil)

        #if CLIPLEX_SCREENSHOTS
        if let target = ScreenshotMode.requestedTarget {
            runScreenshotMode(target)
        }
        #endif
    }

    #if CLIPLEX_SCREENSHOTS
    /// Screenshot-tooling entry point. Compiled ONLY when the executable is built
    /// with `-D CLIPLEX_SCREENSHOTS` (see `tools/screenshots/`); never present in
    /// release or distributed builds. Opens the requested window, renders it to a
    /// PNG, and quits. See `ScreenshotMode` for the reusable rendering primitive.
    private func runScreenshotMode(_ target: String) {
        NSApp.appearance = NSAppearance(named: .darkAqua)

        if target == "gif" {
            runDemoGif()
            return
        }
        if target == "snippetgif" {
            runCreateGif(flow: .snippet)
            return
        }
        if target == "actiongif" {
            runCreateGif(flow: .action)
            return
        }

        var explicitView: NSView?
        var window: NSWindow?
        switch target {
        case "settings":
            openSettings()
            window = settingsWindow?.window
        case "panel":
            panel.present(mode: .clipboard, focusFolder: nil)
            explicitView = panel.debugContentView
        default:
            window = showLibrary().window
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            window?.appearance = NSAppearance(named: .darkAqua)
            let view = explicitView ?? window?.contentView
                ?? NSApp.windows.first { $0.isVisible && $0.contentView != nil }?.contentView
            if let view { ScreenshotMode.write(view, named: target) }
            NSApp.terminate(nil)
        }
    }

    /// Drives the quick panel through a scripted walkthrough (clipboard history →
    /// type-to-search → snippets → actions), capturing one real-app frame per
    /// step. `tools/screenshots/capture-demo-gif.sh` stitches them into the GIF.
    private func runDemoGif() {
        panel.present(mode: .clipboard, focusFolder: nil)
        panel.debugContentView?.window?.appearance = NSAppearance(named: .darkAqua)
        let vm = panel.debugViewModel
        guard let view = panel.debugContentView else { NSApp.terminate(nil); return }

        // (frame-name, mutation applied before the frame is captured).
        // Character-by-character typing frames zip by fast in assembly; the
        // main states (full lists + filtered results) are held longer.
        let steps: [(String, () -> Void)] = [
            ("01", {}),                                              // clipboard history
            ("02", { vm.query = "s" }),
            ("03", { vm.query = "se" }),
            ("04", { vm.query = "sel" }),
            ("05", { vm.query = "sele" }),
            ("06", { vm.query = "selec" }),
            ("07", { vm.query = "select" }),                         // filtered result
            ("08", { vm.query = ""; vm.switchMode(to: .snippets) }), // snippets
            ("09", { vm.query = "e" }),
            ("10", { vm.query = "em" }),
            ("11", { vm.query = "ema" }),
            ("12", { vm.query = "emai" }),
            ("13", { vm.query = "email" }),                          // filtered snippets
            ("14", { vm.query = ""; vm.switchMode(to: .actions) }),  // actions
        ]

        var i = 0
        func next() {
            guard i < steps.count else { NSApp.terminate(nil); return }
            let (name, apply) = steps[i]
            i += 1
            apply()
            // Wait out the 60 ms query debounce + SwiftUI re-render, then capture.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                ScreenshotMode.write(view, named: "frame-\(name)")
                next()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { next() }
    }

    /// Drives the Library window through creating a snippet and an action with
    /// character-by-character typing, capturing a frame per step. Frames are
    /// named `frame-<idx>-<role>` (role = type | beat | hold) so the assembler
    /// can time typing fast and hold the milestones. See `capture-demo-gif.sh`.
    private enum CreateFlow { case snippet, action }

    private func runCreateGif(flow: CreateFlow) {
        let focus: LibraryViewModel.Domain = (flow == .snippet) ? .snippet : .action
        let controller = showLibrary(focus: focus)
        controller.window?.appearance = NSAppearance(named: .darkAqua)
        guard let vm = libraryViewModel, let view = controller.window?.contentView else {
            NSApp.terminate(nil); return
        }
        let snip = vm.snippets
        let act = vm.actions

        // (settle-delay, role, mutation)
        typealias Step = (Double, String, () -> Void)
        var steps: [Step] = []
        func hold(_ apply: @escaping () -> Void) { steps.append((0.4, "hold", apply)) }
        func beat(_ apply: @escaping () -> Void) { steps.append((0.3, "beat", apply)) }
        // Types `full` one character at a time, calling `set` with each prefix.
        func typeInto(_ full: String, _ set: @escaping (String) -> Void) {
            var acc = ""
            for ch in full {
                acc.append(ch)
                let cur = acc
                steps.append((0.13, "type", { set(cur) }))
            }
        }

        switch flow {
        case .snippet:
            beat({})                                    // library (snippets)
            beat({ vm.newSnippet() })                   // empty snippet editor
            typeInto("Out of office") { snip.draftTitle = $0 }
            typeInto("Out of office until Monday. For anything urgent, contact {clipboard}.") {
                snip.draftContent = $0
            }
            hold({})                                    // hold final content ({clipboard} chip)
            hold({ snip.saveSnippet() })                // saved → appears in list
        case .action:
            beat({})                                    // library (actions)
            beat({ vm.newAction() })                    // empty action editor (Open URL)
            typeInto("Repo issues") { act.draftTitle = $0 }
            typeInto("https://github.com/{clipboard}/issues") { act.draftValue = $0 }
            hold({})                                    // hold final URL ({clipboard} chip)
            hold({ act.save() })                        // saved → appears in list
        }

        var idx = 0
        var i = 0
        func next() {
            guard i < steps.count else { NSApp.terminate(nil); return }
            let (delay, role, apply) = steps[i]
            i += 1
            idx += 1
            apply()
            let name = "frame-\(String(format: "%03d", idx))-\(role)"
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                ScreenshotMode.write(view, named: name)
                next()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { next() }
    }
    #endif

    /// Installs a minimal main menu. As a menu-bar agent the bar isn't shown,
    /// but the Edit menu's key equivalents are what make Cut/Copy/Paste/Undo/
    /// Select All work inside text fields (snippet editor, search, dialogs).
    private func installMainMenu() {
        let mainMenu = NSMenu()

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")

        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        editItem.submenu = editMenu
        NSApp.mainMenu = mainMenu
    }

    // MARK: - Menu bar

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            // Prefer the bundled monochrome menu-bar mark; fall back to an SF
            // Symbol when running the raw executable (resources not present).
            let image = NSImage(named: "MenuBarIconTemplate")
                ?? NSImage(systemSymbolName: "doc.on.clipboard",
                           accessibilityDescription: "Cliplex")
            image?.isTemplate = true
            button.image = image
        }

        let menu = NSMenu()
        addItem(menu, "Open Cliplex", #selector(openClipboardPanel))
        addItem(menu, "Open Snippets", #selector(openSnippetsPanel))
        addItem(menu, "Open Actions", #selector(openActionsPanel))
        menu.addItem(.separator())
        addItem(menu, "Library…", #selector(openLibrary))
        addItem(menu, "Settings…", #selector(openSettings), key: ",")
        menu.addItem(.separator())
        addItem(menu, "Quit Cliplex", #selector(quit), key: "q")
        item.menu = menu
        statusItem = item
    }

    private func addItem(_ menu: NSMenu, _ title: String, _ action: Selector, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    private func installShortcuts() {
        KeyboardShortcuts.onKeyUp(for: .openCliplex) { [weak self] in
            MainActor.assumeIsolated { self?.panel.toggleAtCursor(mode: .clipboard) }
        }
        KeyboardShortcuts.onKeyUp(for: .openSnippets) { [weak self] in
            MainActor.assumeIsolated { self?.panel.toggleAtCursor(mode: .snippets) }
        }
        KeyboardShortcuts.onKeyUp(for: .openActions) { [weak self] in
            MainActor.assumeIsolated { self?.panel.toggleAtCursor(mode: .actions) }
        }
    }

    @objc private func openClipboardPanel() {
        panel.toggleAtCursor(mode: .clipboard)
    }

    @objc private func openSnippetsPanel() {
        panel.toggleAtCursor(mode: .snippets)
    }

    @objc private func openActionsPanel() {
        panel.toggleAtCursor(mode: .actions)
    }

    @objc private func openLibrary() {
        showLibrary()
    }

    @discardableResult
    private func showLibrary(focus: LibraryViewModel.Domain? = nil) -> LibraryWindowController {
        let controller: LibraryWindowController
        if let existing = libraryWindow {
            controller = existing
        } else {
            let viewModel = LibraryViewModel(services: services)
            libraryViewModel = viewModel
            controller = LibraryWindowController(viewModel: viewModel)
            libraryWindow = controller
        }
        controller.show(focus: focus)
        return controller
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(viewModel: sharedManagerViewModel())
        }
        settingsWindow?.show()
    }

    /// The Settings window shares one manager view model for its bindings.
    private func sharedManagerViewModel() -> ManagerViewModel {
        if let viewModel = managerViewModel { return viewModel }
        let viewModel = ManagerViewModel(services: services)
        managerViewModel = viewModel
        return viewModel
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Appearance

    @objc private func applyAppearance() {
        switch services.settings.theme {
        case .system:
            NSApp.appearance = nil
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        }
    }

    private func presentFatal(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Cliplex could not start"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .critical
        alert.runModal()
        NSApp.terminate(nil)
    }
}
