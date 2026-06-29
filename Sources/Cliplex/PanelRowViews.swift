import SwiftUI
import AppKit
import CliplexKit

/// Resolves an app bundle identifier to its display name (e.g.
/// `com.microsoft.edgemac` → "Microsoft Edge"), cached per process.
enum AppNames {
    private static var cache: [String: String] = [:]

    static func name(for bundleID: String) -> String {
        let id = bundleID.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty else { return "" }
        if let cached = cache[id] { return cached }
        var name = id
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            name = url.deletingPathExtension().lastPathComponent
        }
        cache[id] = name
        return name
    }
}

/// A clip/snippet/action row in concept-B style: a colored icon tile, title +
/// subtitle (two lines), and trailing quick-key/time. `compact` drops to a
/// single line with a smaller icon.
struct RowView: View {
    let row: DisplayRow
    let quickIndex: Int?
    let selected: Bool
    let indented: Bool
    var compact: Bool = false

    private var accent: Color {
        if row.isAction { return Theme.actionAccent }
        if row.isSnippet { return Theme.snippetAccent }
        return Theme.secondaryText
    }
    private var iconSize: CGFloat { compact ? 20 : 28 }
    private var rowHeight: CGFloat { compact ? 30 : 42 }

    /// Clip subtitles store the source-app bundle id; show its friendly name.
    /// Snippet/action subtitles are already human-readable.
    private var subtitleText: String {
        if row.clipKind != nil { return AppNames.name(for: row.subtitle) }
        return row.subtitle
    }

    var body: some View {
        HStack(spacing: 9) {
            iconTile
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title.isEmpty ? "Untitled" : row.title)
                    .font(.ui(13)).foregroundStyle(Theme.primaryText).lineLimit(1).truncationMode(.tail)
                if !compact, !subtitleText.isEmpty {
                    Text(subtitleText).font(.mono(10.5)).foregroundStyle(Theme.mutedText).lineLimit(1).truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if row.pinned { Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(Theme.accent) }
            if let quickIndex { Text("⌘\((quickIndex + 1) % 10)").font(.mono(10)).foregroundStyle(selected ? Theme.accent : Theme.mutedText) }
            else if !compact { Text(relativeTime(row.updatedAt)).font(.mono(10)).foregroundStyle(Theme.mutedText).monospacedDigit() }
        }
        .padding(.horizontal, 9)
        .frame(height: rowHeight)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(selected ? Theme.selectionBackground : .clear))
        .padding(.horizontal, 6).padding(.leading, indented ? 12 : 0)
        .overlay(alignment: .leading) {
            if indented { Rectangle().fill(Theme.hairline).frame(width: 1).padding(.vertical, 6).padding(.leading, 10) }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var iconTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: compact ? 5 : 7).fill(accent.opacity(0.14)).frame(width: iconSize, height: iconSize)
            if row.clipKind == .color, let color = Color(hexString: row.title) {
                RoundedRectangle(cornerRadius: 3).fill(color).frame(width: iconSize - 12, height: iconSize - 12)
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.black.opacity(0.25), lineWidth: 0.5))
            } else {
                Image(systemName: glyph).font(.system(size: compact ? 10 : 13, weight: .medium)).foregroundStyle(accent)
            }
        }
    }

    private var glyph: String {
        if let a = row.actionType { return a.symbol }
        if row.isSnippet { return "text.alignleft" }
        switch row.clipKind {
        case .image: return "photo"; case .files: return "doc"; case .color: return "paintpalette"
        case .text, .richtext, .none: return row.title.hasPrefix("http") ? "link" : "doc.on.clipboard"
        }
    }
}

/// A section header: an uppercase time/section label, or a tappable, collapsible
/// snippet-folder header with a chevron.
struct HeaderView: View {
    let title: String
    let folderKey: Int64?
    let collapsed: Bool
    var selected: Bool = false
    let onToggle: (Int64) -> Void

    var body: some View {
        if let folderKey {
            Button {
                onToggle(folderKey)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .rotationEffect(.degrees(collapsed ? -90 : 0))
                        .animation(.easeOut(duration: 0.18), value: collapsed)
                    Text(title)
                        .font(.ui(11, .semibold))
                        .foregroundStyle(Theme.secondaryText)
                    Spacer()
                }
                .padding(.horizontal, 15)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? Theme.selectionBackground : .clear)
                        .padding(.horizontal, 6)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Text(title.uppercased())
                .font(.ui(9.5, .bold)).tracking(1.2)
                .foregroundStyle(Theme.mutedText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 15)
                .frame(height: 24, alignment: .bottom)
                .padding(.bottom, 4)
        }
    }
}
