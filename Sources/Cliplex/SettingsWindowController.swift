import AppKit
import SwiftUI

/// Hosts the Settings window — a compact, native grouped-form preferences
/// window, created lazily and reused.
@MainActor
final class SettingsWindowController {
    private let viewModel: ManagerViewModel
    private var window: NSWindow?

    init(viewModel: ManagerViewModel) {
        self.viewModel = viewModel
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Cliplex Settings"
            window.isReleasedWhenClosed = false
            window.center()
            window.contentView = NSHostingView(rootView: SettingsView(viewModel: viewModel))
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
