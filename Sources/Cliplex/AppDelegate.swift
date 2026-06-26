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
    private var snippetsWindow: SnippetsWindowController?
    private var settingsWindow: SettingsWindowController?
    private var actionsViewModel: ActionsViewModel?
    private var actionsWindow: ActionsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        services.startMonitoring()

        NotificationCenter.default.addObserver(
            self, selector: #selector(applyAppearance),
            name: .cliplexSettingsChanged, object: nil)
    }

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
            button.image = NSImage(
                systemSymbolName: "doc.on.clipboard",
                accessibilityDescription: "Cliplex")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        addItem(menu, "Open Cliplex", #selector(openClipboardPanel))
        addItem(menu, "Open Snippets", #selector(openSnippetsPanel))
        addItem(menu, "Open Actions", #selector(openActionsPanel))
        menu.addItem(.separator())
        addItem(menu, "Snippets…", #selector(openSnippets))
        addItem(menu, "Actions…", #selector(openActions))
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

    @objc private func openSnippets() {
        if snippetsWindow == nil {
            snippetsWindow = SnippetsWindowController(viewModel: sharedManagerViewModel())
        }
        snippetsWindow?.show()
    }

    @objc private func openActions() {
        if actionsWindow == nil {
            let viewModel = ActionsViewModel(services: services)
            actionsViewModel = viewModel
            actionsWindow = ActionsWindowController(viewModel: viewModel)
        }
        actionsWindow?.show()
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(viewModel: sharedManagerViewModel())
        }
        settingsWindow?.show()
    }

    /// The Snippets and Settings windows share one view model so state stays
    /// coherent between them.
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
