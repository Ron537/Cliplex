import ApplicationServices

/// macOS Accessibility (AX) trust checks.
///
/// Synthesizing keystrokes requires the app to be trusted for Accessibility.
/// These helpers check trust *without* prompting (so the app can decide whether
/// to inject) and trigger the system prompt only when needed — avoiding the
/// "popup on every paste" loop.
public enum Accessibility {
    /// Whether this process is trusted for Accessibility (no prompt).
    public static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Triggers the system Accessibility prompt if the app is not yet trusted.
    public static func prompt() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
