import SwiftUI

/// The Cliplex wordmark glyph — the "duplicate" motif from the app icon: two
/// overlapping rounded cards (bright blue front, deeper blue back) with a soft
/// cast shadow. Drawn in SwiftUI so it stays crisp at any size in-app.
struct BrandMark: View {
    var size: CGFloat = 24

    private var card: CGFloat { size * 0.64 }
    private var radius: CGFloat { card * 0.30 }
    private var shift: CGFloat { size * 0.13 }

    private var front: LinearGradient {
        LinearGradient(colors: [Color(nsColor: NSColor(hex: 0x5DA8FF)),
                                Color(nsColor: NSColor(hex: 0x2E79E6))],
                       startPoint: .top, endPoint: .bottom)
    }
    private var back: LinearGradient {
        LinearGradient(colors: [Color(nsColor: NSColor(hex: 0x3F82DE)),
                                Color(nsColor: NSColor(hex: 0x265FB8))],
                       startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(back)
                .frame(width: card, height: card)
                .offset(x: shift, y: -shift)
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(front)
                .frame(width: card, height: card)
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(.white.opacity(0.22), lineWidth: max(1, size * 0.03))
                )
                .offset(x: -shift, y: shift)
                .shadow(color: .black.opacity(0.28), radius: size * 0.07, y: size * 0.045)
        }
        .frame(width: size, height: size)
    }
}
