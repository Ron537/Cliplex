import SwiftUI
import AppKit

/// A dimmed full-bleed backdrop hosting a centered dialog card. Tapping the
/// backdrop dismisses. Used instead of native `.alert`s for an in-theme look.
struct DialogScrim<Content: View>: View {
    let onDismiss: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)

            content
                .padding(18)
                .frame(width: 300)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.hairline, lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.4), radius: 26, y: 12)
        }
        .transition(.opacity)
    }
}

/// A destructive confirmation dialog (delete folder / snippet).
struct ConfirmDialog: View {
    let title: String
    let message: String
    let confirmTitle: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    private let danger = Color(nsColor: NSColor(hex: 0xFF5A5A))

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(danger.opacity(0.14)).frame(width: 38, height: 38)
                Image(systemName: "trash")
                    .font(.ui(15, .semibold))
                    .foregroundStyle(danger)
            }
            VStack(spacing: 5) {
                Text(title)
                    .font(.display(16, .bold))
                    .foregroundStyle(Theme.primaryText)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.ui(12))
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                DialogButton(title: "Cancel", kind: .secondary, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                DialogButton(title: confirmTitle, kind: .destructive, action: onConfirm)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 2)
        }
    }
}

/// A single-text-field dialog (e.g. New Folder / Rename Folder).
struct InputDialog: View {
    var icon: String = "folder.badge.plus"
    let title: String
    let placeholder: String
    @Binding var text: String
    let confirmTitle: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @FocusState private var focused: Bool

    private var isEmpty: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.14)).frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.ui(14, .semibold))
                    .foregroundStyle(Theme.accent)
            }
            Text(title)
                .font(.display(16, .bold))
                .foregroundStyle(Theme.primaryText)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.ui(13))
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(Theme.fieldBackground, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(focused ? Theme.accent.opacity(0.6) : Theme.hairline, lineWidth: 1)
                )
                .focused($focused)
                .onSubmit { if !isEmpty { onConfirm() } }

            HStack(spacing: 8) {
                DialogButton(title: "Cancel", kind: .secondary, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                DialogButton(title: confirmTitle, kind: .primary, enabled: !isEmpty, action: onConfirm)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 2)
        }
        .onAppear { focused = true }
    }
}

/// A styled dialog button (replaces native alert buttons).
struct DialogButton: View {
    enum Kind { case secondary, primary, destructive }

    let title: String
    let kind: Kind
    var enabled: Bool = true
    let action: () -> Void
    @State private var hovering = false

    private let danger = Color(nsColor: NSColor(hex: 0xFF5A5A))

    var body: some View {
        Button(action: { if enabled { action() } }) {
            Text(title)
                .font(.ui(12, .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .foregroundStyle(foreground)
                .background(background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = enabled && $0 }
    }

    private var foreground: Color {
        guard enabled else { return Theme.mutedText }
        switch kind {
        case .secondary: return Theme.primaryText
        case .primary: return Theme.accentInk
        case .destructive: return .white
        }
    }

    private var background: Color {
        guard enabled else { return Theme.fieldBackground }
        switch kind {
        case .secondary: return hovering ? Theme.accent.opacity(0.10) : Theme.fieldBackground
        case .primary: return hovering ? Theme.accent.opacity(0.85) : Theme.accent
        case .destructive: return hovering ? danger.opacity(0.85) : danger
        }
    }

    private var border: Color {
        if !enabled { return Theme.hairline }
        return kind == .secondary ? Theme.hairline : .clear
    }
}

/// A small icon button revealed on row hover. Neutral by default — brightens
/// (not red) under the pointer — so the list doesn't read as alarming.
struct HoverIconButton: View {
    let systemName: String
    var help: String = ""
    let visible: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.ui(11))
                .foregroundStyle(hovering ? Theme.primaryText : Theme.mutedText)
        }
        .buttonStyle(.plain)
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// A thin, draggable separator between resizable panes, colored to match the
/// app's other hairline borders. The visible line is 1px; a wider invisible
/// hit area makes it easy to grab and shows the horizontal-resize cursor.
struct PaneResizer: View {
    @Binding var width: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    @State private var dragStart: CGFloat?
    @State private var cursorPushed = false

    var body: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .overlay {
                Color.clear
                    .frame(width: 11)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside, !cursorPushed {
                            NSCursor.resizeLeftRight.push()
                            cursorPushed = true
                        } else if !inside, cursorPushed {
                            NSCursor.pop()
                            cursorPushed = false
                        }
                    }
                    .onDisappear {
                        if cursorPushed { NSCursor.pop(); cursorPushed = false }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                if dragStart == nil { dragStart = width }
                                let base = dragStart ?? width
                                width = min(maxWidth, max(minWidth, base + value.translation.width))
                            }
                            .onEnded { _ in dragStart = nil }
                    )
            }
    }
}

/// Makes a row draggable to reorder a list. The payload is namespaced by `kind`
/// ("folder" / "snippet") and carries the row id, so a folder drag can never be
/// mistaken for a snippet drag (their id spaces overlap) and foreign text drops
/// are ignored. A drop inserts the dragged item before this one. A `nil` id
/// disables dragging (e.g. the "All snippets" pseudo-folder, or the snippet list
/// while viewing the aggregate).
struct ReorderDrag: ViewModifier {
    let kind: String
    let id: Int64?
    let onDrop: (_ source: Int64, _ target: Int64) -> Void
    @State private var targeted = false

    func body(content: Content) -> some View {
        if let id {
            content
                .draggable("\(kind):\(id)")
                .dropDestination(for: String.self) { items, _ in
                    guard let source = Self.parse(items.first, kind: kind), source != id else {
                        return false
                    }
                    onDrop(source, id)
                    return true
                } isTargeted: { targeted = $0 }
                .overlay(alignment: .top) {
                    if targeted {
                        Rectangle()
                            .fill(Theme.accent)
                            .frame(height: 2)
                            .padding(.horizontal, 6)
                    }
                }
        } else {
            content
        }
    }

    /// Parses a `"kind:id"` payload, returning the id only when `kind` matches.
    private static func parse(_ payload: String?, kind: String) -> Int64? {
        guard let payload else { return nil }
        let parts = payload.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, parts[0] == kind else { return nil }
        return Int64(parts[1])
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
