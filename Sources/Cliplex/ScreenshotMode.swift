import AppKit

#if CLIPLEX_SCREENSHOTS
/// Off-by-default screenshot tooling.
///
/// This type — and every call site that references it — is compiled **only** when
/// the executable is built with the `CLIPLEX_SCREENSHOTS` Swift flag
/// (`-Xswiftc -DCLIPLEX_SCREENSHOTS`). Release, CI, and distributed builds never
/// pass that flag, so none of this code ships in the app bundle. The capture
/// pipeline lives in `tools/screenshots/`.
///
/// Rendering uses `NSView.cacheDisplay`, which asks the view to draw itself into
/// a bitmap. Unlike `screencapture`/`CGWindowList`, it needs **no Screen
/// Recording permission**, so it works from a plain shell in CI.
enum ScreenshotMode {
    /// Env var naming the surface to capture: `library` | `settings` | `panel`.
    static let targetEnvKey = "CLIPLEX_SCREENSHOT"
    /// Env var overriding where PNGs are written (defaults to `/tmp/cliplex-shots`).
    static let outputEnvKey = "CLIPLEX_SCREENSHOT_DIR"

    static var requestedTarget: String? {
        let value = ProcessInfo.processInfo.environment[targetEnvKey]
        return (value?.isEmpty == false) ? value : nil
    }

    static var outputDirectory: String {
        ProcessInfo.processInfo.environment[outputEnvKey] ?? "/tmp/cliplex-shots"
    }

    /// Renders an on-screen view to a PNG and writes `<outputDirectory>/<name>.png`.
    @discardableResult
    static func write(_ view: NSView, named name: String) -> Bool {
        try? FileManager.default.createDirectory(
            atPath: outputDirectory, withIntermediateDirectories: true)
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            NSLog("[screenshot] could not allocate bitmap for \(name)")
            return false
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            NSLog("[screenshot] PNG encoding failed for \(name)")
            return false
        }
        let path = "\(outputDirectory)/\(name).png"
        do {
            try data.write(to: URL(fileURLWithPath: path))
            NSLog("[screenshot] wrote \(path)")
            return true
        } catch {
            NSLog("[screenshot] write failed for \(name): \(error)")
            return false
        }
    }
}
#endif
