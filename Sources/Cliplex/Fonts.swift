import SwiftUI
import CoreText

/// Registers the bundled UI fonts (Hanken Grotesk, Bricolage Grotesque, JetBrains
/// Mono) at launch. `ATSApplicationFontsPath` in Info.plist already auto-registers
/// them for a normal bundle launch; this is a belt-and-suspenders fallback that
/// also covers running the executable directly.
enum AppFonts {
    static func register() {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Fonts", isDirectory: true),
              let urls = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil) else { return }
        for url in urls where url.pathExtension.lowercased() == "ttf" {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

extension Font {
    /// Body / UI text — Hanken Grotesk.
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Hanken Grotesk", fixedSize: size).weight(weight)
    }
    /// Display / headings & wordmark — Bricolage Grotesque.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .custom("Bricolage Grotesque", fixedSize: size).weight(weight)
    }
    /// Monospace — JetBrains Mono.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("JetBrains Mono", fixedSize: size).weight(weight)
    }
}
