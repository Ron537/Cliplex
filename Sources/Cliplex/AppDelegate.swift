import AppKit
import Carbon.HIToolbox
import CliplexKit

/// Owns the app lifecycle: services, the menu-bar item, the global hotkey, the
/// clipboard panel, and the manager window.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var services: AppServices!
    private var statusItem: NSStatusItem?
    private var hotKey: CarbonHotKey?
    private var panel: PanelController!
    private var manager: ManagerWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            services = try AppServices()
        } catch {
            presentFatal(error)
            return
        }

        applyAppearance()
        let viewModel = PanelViewModel(services: services)
        panel = PanelController(viewModel: viewModel)

        installStatusItem()
        installHotKey()
        services.startMonitoring()

        NotificationCenter.default.addObserver(
            self, selector: #selector(applyAppearance),
            name: .cliplexSettingsChanged, object: nil)
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
        addItem(menu, "Open Cliplex", #selector(togglePanel))
        addItem(menu, "Snippets & Settings…", #selector(openManager))
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

    private func installHotKey() {
        // Default: ⌘⇧V, matching the previous build.
        hotKey = CarbonHotKey(keyCode: UInt32(kVK_ANSI_V), modifiers: [.command, .shift]) { [weak self] in
            MainActor.assumeIsolated { self?.togglePanel() }
        }
    }

    @objc private func togglePanel() {
        panel.toggleAtCursor()
    }

    @objc private func openManager() {
        if manager == nil {
            manager = ManagerWindowController(services: services)
        }
        manager?.show()
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
