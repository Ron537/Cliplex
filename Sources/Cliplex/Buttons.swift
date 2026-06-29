import SwiftUI

/// A subtle bordered "ghost" button used in editors/footers.
struct GhostButton: View {
    let title: String
    var accent = false
    var danger = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.ui(12, .medium))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(danger ? Color(nsColor: NSColor(hex: 0xFF5A5A)) : (accent ? Theme.accent : Theme.secondaryText))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .fixedSize()
    }
}

/// A menu row used in the New popover, with a hover highlight (a plain view so
/// it avoids `@State` inside a `ButtonStyle`).
struct NewMenuRow: View {
    let title: String
    let icon: String
    let color: Color
    var kbd: String?
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.ui(12)).foregroundStyle(color)
                    .frame(width: 26, height: 26)
                    .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 7))
                Text(title).font(.ui(13, .medium)).foregroundStyle(Theme.primaryText)
                Spacer()
                if let kbd { Text(kbd).font(.mono(11)).foregroundStyle(Theme.mutedText) }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(hover ? Theme.accent.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// The filled accent primary button (Save, etc).
struct PrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.ui(12.5, .semibold))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(Theme.accentInk)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .fixedSize()
    }
}
