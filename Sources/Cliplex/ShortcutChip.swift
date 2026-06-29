import SwiftUI
import CliplexKit
import KeyboardShortcuts

/// Posted by KeyboardShortcuts whenever any shortcut changes (the library posts
/// this internally; we observe it to refresh chips live).
private let shortcutDidChange = Notification.Name("KeyboardShortcuts_shortcutByNameDidChange")

/// A compact, clickable keyboard-shortcut chip used on folder rows, item rows,
/// and in the inspector. Shows the assigned combo (mono, accent) or a dashed
/// "Set" placeholder; clicking opens a small popover with the system recorder
/// and a Clear button. Assigning installs the matching global handler.
struct ShortcutChip: View {
    let kind: ShortcutCenter.Kind
    let id: Int64
    /// `large` is used in the inspector; rows use the default size.
    var large = false
    var placeholder = "Set"

    @State private var combo: String?
    @State private var presenting = false
    @State private var hovering = false

    private var name: KeyboardShortcuts.Name { ShortcutCenter.shared.name(kind, id) }
    private var assigned: Bool { combo != nil }

    var body: some View {
        Button { presenting = true } label: {
            HStack(spacing: 4) {
                if let combo {
                    KeyComboView(combo: combo, accent: true)
                } else {
                    Image(systemName: "command")
                        .font(.ui(large ? 10 : 9, .semibold))
                    Text(placeholder)
                        .font(.ui(large ? 11.5 : 10.5, .semibold))
                }
            }
            .frame(height: large ? 28 : 22)
            .padding(.horizontal, large ? 10 : 7)
            .foregroundStyle(assigned ? Theme.accent : Theme.mutedText)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(assigned ? Theme.accent.opacity(0.14) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(
                        assigned ? Theme.accent.opacity(0.34) : Theme.hairline,
                        style: StrokeStyle(lineWidth: 1, dash: assigned ? [] : [3, 2])
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(assigned ? "Change shortcut" : "Assign a shortcut")
        .popover(isPresented: $presenting, arrowEdge: .bottom) { recorderPopover }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: shortcutDidChange)) { _ in refresh() }
    }

    private var recorderPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.ui(12, .semibold))
                .foregroundStyle(Theme.primaryText)
            KeyboardShortcuts.Recorder(for: name) { _ in
                ShortcutCenter.shared.ensureHandler(kind, id)
                refresh()
            }
            HStack {
                Text("Press a key combination")
                    .font(.ui(10.5))
                    .foregroundStyle(Theme.mutedText)
                Spacer()
                if assigned {
                    Button("Clear") {
                        KeyboardShortcuts.reset(name)
                        refresh()
                    }
                    .buttonStyle(.plain)
                    .font(.ui(11, .semibold))
                    .foregroundStyle(Color(nsColor: NSColor(hex: 0xFF5A5A)))
                }
            }
        }
        .padding(14)
        .frame(width: 240)
    }

    private var title: String {
        switch kind {
        case .snippet: return "Paste this snippet"
        case .action: return "Run this action"
        case .snippetFolder, .actionFolder: return "Open this folder"
        }
    }

    private func refresh() {
        combo = KeyboardShortcuts.getShortcut(for: name)?.description
    }
}

/// Renders a shortcut string (e.g. "⌘⇧V") as a row of small key caps.
struct KeyComboView: View {
    let combo: String
    var accent = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(caps.enumerated()), id: \.offset) { _, cap in
                Text(cap)
                    .font(.ui(11, .semibold))
                    .frame(minWidth: 15, minHeight: 17)
                    .padding(.horizontal, 2)
                    .foregroundStyle(accent ? Theme.accent : Theme.secondaryText)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill((accent ? Theme.accent : Theme.primaryText).opacity(0.12))
                    )
            }
        }
    }

    /// Splits a combo into caps: each modifier glyph is its own cap, and the
    /// trailing key (which may be multiple chars, e.g. "F2") is one cap.
    private var caps: [String] {
        let modifiers: Set<Character> = ["⌘", "⇧", "⌥", "⌃", "⇪"]
        var result: [String] = []
        var rest = ""
        for ch in combo {
            if modifiers.contains(ch) {
                result.append(String(ch))
            } else {
                rest.append(ch)
            }
        }
        if !rest.isEmpty { result.append(rest) }
        return result.isEmpty ? [combo] : result
    }
}
