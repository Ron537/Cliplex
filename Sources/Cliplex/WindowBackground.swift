import SwiftUI

/// The window backdrop: a soft diagonal gradient with a faint accent glow in the
/// top-right, matching the mockup's atmospheric dark-blue background.
struct WindowBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Theme.bgTop, Theme.bgBottom],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .overlay(alignment: .topTrailing) {
            RadialGradient(
                colors: [Theme.accent.opacity(0.12), .clear],
                center: .topTrailing, startRadius: 0, endRadius: 560
            )
            .frame(width: 900, height: 600)
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}
