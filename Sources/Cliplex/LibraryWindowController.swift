import AppKit
import SwiftUI

/// Hosts the unified Library window (snippets + actions). Created lazily and
/// reused; refreshes its data when re-shown.
@MainActor
final class LibraryWindowController {
    private let viewModel: LibraryViewModel
    private(set) var window: NSWindow?

    init(viewModel: LibraryViewModel) {
        self.viewModel = viewModel
    }

    func show(focus: LibraryViewModel.Domain? = nil) {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 980, height: 620),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Library"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = false
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 880, height: 560)
            window.center()
            window.contentView = NSHostingView(rootView: LibraryView(library: viewModel))
            self.window = window
        } else {
            viewModel.reload()
        }
        if let focus { viewModel.focusDomain(focus) }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
