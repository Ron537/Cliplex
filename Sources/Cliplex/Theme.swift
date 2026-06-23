import SwiftUI
import AppKit

/// Cliplex's blue palette, resolved dynamically for light/dark appearances so a
/// single set of semantic colors works in both. System materials provide the
/// translucent menu background.
enum Theme {
    /// Primary accent (blue), matching the prior build (#4d9bff dark / #0a84ff light).
    static let accent = dynamic(dark: 0x4D9BFF, light: 0x0A84FF)
    /// Ink color for content drawn on top of the accent fill.
    static let accentInk = dynamic(dark: 0x06203F, light: 0xFFFFFF)

    static let selectionBackground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDark ? NSColor(hex: 0x4D9BFF, alpha: 0.18) : NSColor(hex: 0x0A84FF, alpha: 0.16)
    })

    static let primaryText = Color(nsColor: .labelColor)
    static let secondaryText = Color(nsColor: .secondaryLabelColor)
    static let mutedText = Color(nsColor: .tertiaryLabelColor)
    static let hairline = Color(nsColor: .separatorColor)
    static let fieldBackground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDark ? NSColor(white: 1, alpha: 0.06) : NSColor(white: 0, alpha: 0.05)
    })

    static let imageTag = dynamic(dark: 0x5FD0E0, light: 0x0E8FA8)
    static let filesTag = dynamic(dark: 0xE6B860, light: 0xB8860B)

    private static func dynamic(dark: Int, light: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.isDark ? NSColor(hex: dark) : NSColor(hex: light) })
    }
}

extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}

extension NSColor {
    convenience init(hex: Int, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Color {
    /// Parses a `#RGB` / `#RRGGBB` string into a color (for clip swatches).
    init?(hexString: String) {
        let trimmed = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "#" else { return nil }
        var hex = String(trimmed.dropFirst())
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        guard hex.count == 6, let value = Int(hex, radix: 16) else { return nil }
        self.init(nsColor: NSColor(hex: value))
    }
}
