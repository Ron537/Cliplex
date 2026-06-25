import AppKit
import SwiftUI
import CliplexKit

/// A borderless panel that can still become key (borderless `NSWindow`s return
/// `false` from `canBecomeKey` by default, which would block typing in the
/// search field).
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Hosts the clipboard panel: a borderless, non-activating panel shown at the
/// mouse cursor (Clipy-style).
///
/// Because the panel is a `.nonactivatingPanel`, showing it does **not** make
/// Cliplex the active application — the app the user was typing in stays
/// frontmost. That removes the "remember the previous app and re-activate it
/// before pasting" dance the Tauri build needed.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let viewModel: PanelViewModel
    private var panel: KeyablePanel?
    private var keyMonitor: Any?

    static let size = NSSize(width: 380, height: 460)

    init(viewModel: PanelViewModel) {
        self.viewModel = viewModel
        super.init()
        viewModel.requestHide = { [weak self] in self?.hide() }
    }

    func toggleAtCursor(mode: PanelMode) {
        let panel = panel ?? makePanel()
        if panel.isVisible {
            // Same mode toggles closed; a different mode switches in place.
            if viewModel.mode == mode {
                hide()
            } else {
                viewModel.switchMode(to: mode)
                DispatchQueue.main.async { [weak self] in self?.viewModel.focusSearch() }
            }
        } else {
            viewModel.onShow(mode: mode)
            positionAtCursor(panel)
            panel.makeKeyAndOrderFront(nil)
            installKeyMonitor()
            // Focus the search field once the panel is key.
            DispatchQueue.main.async { [weak self] in self?.viewModel.focusSearch() }
        }
    }

    func hide() {
        removeKeyMonitor()
        panel?.orderOut(nil)
    }

    private func makePanel() -> KeyablePanel {
        let panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.delegate = self

        let hosting = NSHostingView(rootView: PanelView(viewModel: viewModel))
        hosting.frame = NSRect(origin: .zero, size: Self.size)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        self.panel = panel
        return panel
    }

    // MARK: - Keyboard

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // The local key monitor is delivered on the main thread. Reduce the
            // event to Sendable value data before crossing into the view model.
            let key = PanelViewModel.KeyPress(
                keyCode: Int(event.keyCode),
                command: event.modifierFlags.contains(.command),
                shift: event.modifierFlags.contains(.shift),
                characters: event.charactersIgnoringModifiers
            )
            let handled = MainActor.assumeIsolated { self.viewModel.handleKeyDown(key) }
            return handled ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    // MARK: - Positioning

    /// Places the panel's top-left corner at the mouse location, clamped to the
    /// screen that contains the cursor. Screen coordinates are global with a
    /// bottom-left origin, which is scale-independent and therefore correct
    /// across displays with different backing scales.
    private func positionAtCursor(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else {
            panel.setFrameTopLeftPoint(mouse)
            return
        }

        var topLeft = mouse
        if topLeft.x + Self.size.width > visible.maxX {
            topLeft.x = visible.maxX - Self.size.width
        }
        topLeft.x = max(topLeft.x, visible.minX)
        if topLeft.y - Self.size.height < visible.minY {
            topLeft.y = visible.minY + Self.size.height
        }
        topLeft.y = min(topLeft.y, visible.maxY)

        panel.setFrameTopLeftPoint(topLeft)
    }
}
