import AppKit
import SwiftUI

/// Hosts the Settings window — a compact, native grouped-form preferences
/// window, created lazily and reused.
@MainActor
final class SettingsWindowController {
    private let viewModel: ManagerViewModel
    private(set) var window: NSWindow?

    init(viewModel: ManagerViewModel) {
        self.viewModel = viewModel
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Cliplex Settings"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 700, height: 540)
            window.center()
            window.contentView = NSHostingView(rootView: SettingsView(viewModel: viewModel))
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
