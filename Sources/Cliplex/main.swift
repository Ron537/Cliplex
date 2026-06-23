import AppKit

// Cliplex runs as a menu-bar agent (no Dock icon). Drive the lifecycle from an
// explicit NSApplication setup on the main actor so the SwiftPM executable
// controls the activation policy before the app finishes launching.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
