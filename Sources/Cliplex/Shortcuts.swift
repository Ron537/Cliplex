import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Opens the panel in Clipboard mode. Defaults to ⌘⇧V (matching the prior
    /// build); the user can rebind it in Settings.
    static let openCliplex = Self("openCliplex", default: .init(.v, modifiers: [.command, .shift]))

    /// Opens the panel focused on the Snippets tab. No default — opt-in.
    static let openSnippets = Self("openSnippets")
}
