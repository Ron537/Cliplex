import AppKit
import SwiftUI

/// Hosts the Snippets window. A standard titled window, created lazily and
/// reused; it owns the folders + snippets editing UI.
@MainActor
final class SnippetsWindowController {
    private let viewModel: ManagerViewModel
    private var window: NSWindow?

    init(viewModel: ManagerViewModel) {
        self.viewModel = viewModel
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 860, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Snippets"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 760, height: 480)
            window.center()
            window.contentView = NSHostingView(rootView: SnippetsView(viewModel: viewModel))
            self.window = window
        } else {
            // Refresh in case data changed while the window was closed.
            viewModel.loadFolders()
            viewModel.loadSnippets()
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
