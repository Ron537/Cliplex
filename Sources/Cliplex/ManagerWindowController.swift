import AppKit
import SwiftUI

/// Hosts the manager window (Snippets & Settings). A standard titled window,
/// created lazily and reused.
@MainActor
final class ManagerWindowController {
    private let services: AppServices
    private var window: NSWindow?
    private var viewModel: ManagerViewModel?

    init(services: AppServices) {
        self.services = services
    }

    func show() {
        if window == nil {
            let viewModel = ManagerViewModel(services: services)
            self.viewModel = viewModel

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 860, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Cliplex"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.center()
            window.contentView = NSHostingView(rootView: ManagerView(viewModel: viewModel))
            self.window = window
        } else {
            // Refresh data in case it changed while the window was closed.
            viewModel?.loadFolders()
            viewModel?.loadSnippets()
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
