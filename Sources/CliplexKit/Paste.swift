import CoreGraphics

/// Synthesizes the macOS paste shortcut (⌘V) into the frontmost application.
///
/// We post key-down/key-up for the `V` key with the Command flag set *directly
/// on the key events* rather than synthesizing a separate Command press/release.
/// Posting the modifier as a distinct event is racy on modern macOS — the flag
/// can leak or arrive out of order, so the target app sees a bare keystroke
/// (e.g. a stray "select all") instead of a paste. Setting the flag on the key
/// event itself is atomic, and is what native clipboard managers do.
///
/// Requires Accessibility permission; callers should check ``Accessibility``
/// first. Must be invoked on the main thread.
public enum Paste {
    /// Virtual key code for `V` (`kVK_ANSI_V`).
    private static let keyV: CGKeyCode = 0x09

    public enum PasteError: Error {
        case notTrusted
        case eventCreationFailed
    }

    public static func injectPaste() throws {
        guard Accessibility.isTrusted else { throw PasteError.notTrusted }
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            throw PasteError.eventCreationFailed
        }
        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false)
        else {
            throw PasteError.eventCreationFailed
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
    }
}
