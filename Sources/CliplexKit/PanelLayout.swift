import Foundation

/// The two fully-separated panel modes.
public enum PanelMode: CaseIterable {
    case clipboard
    case snippets

    public var label: String {
        switch self {
        case .clipboard: return "Clips"
        case .snippets: return "Snippets"
        }
    }
}

/// A unified row rendered by the panel list (a clip or a snippet).
public struct DisplayRow: Identifiable, Equatable {
    public enum Kind: Equatable {
        case clip(ClipKind)
        case snippet
    }

    public let kind: Kind
    public let id: Int64
    public let title: String
    public let pinned: Bool
    public let updatedAt: Int64
    public let folderID: Int64?

    public var isSnippet: Bool { kind == .snippet }

    public var clipKind: ClipKind? {
        if case let .clip(k) = kind { return k }
        return nil
    }

    /// Stable list/scroll identity derived from content (not list position), so
    /// SwiftUI diffs rows correctly when the list changes or the mode switches.
    public var listID: String { "r:\(isSnippet ? "s" : "c"):\(id)" }

    public init(clip: Clip) {
        self.kind = .clip(clip.kind)
        self.id = clip.id
        self.title = clip.preview
        self.pinned = clip.pinned
        self.updatedAt = clip.updatedAt
        self.folderID = nil
    }

    public init(snippet: Snippet) {
        self.kind = .snippet
        self.id = snippet.id
        self.title = snippet.title.isEmpty ? snippet.content : snippet.title
        self.pinned = false
        self.updatedAt = snippet.updatedAt
        self.folderID = snippet.folderId
    }
}

/// An entry in the rendered, virtualized list: either a section header or a row.
public enum PanelEntry: Identifiable {
    case header(id: String, title: String, folderKey: Int64?, collapsed: Bool)
    case row(DisplayRow, flatIndex: Int, quickIndex: Int?)

    public var id: String {
        switch self {
        case let .header(id, _, _, _): return "h:\(id)"
        case let .row(row, _, _): return row.listID
        }
    }
}

/// A keyboard-navigable item. In snippets tree mode this interleaves collapsible
/// folder headers with their rows; in every other mode it is one entry per row,
/// so a selection index maps 1:1 onto `flatRows`.
public enum NavItem: Equatable {
    case header(folderKey: Int64)
    case row(Int)
}

/// Synthetic folder key for uncategorized snippets.
public let uncategorizedFolderKey: Int64 = -1

/// The result of laying out the current data into headers + rows.
public struct PanelLayout {
    public var entries: [PanelEntry] = []
    public var flatRows: [DisplayRow] = []
    /// Ordered keyboard-navigable items (see `NavItem`).
    public var nav: [NavItem] = []

    public init(entries: [PanelEntry] = [], flatRows: [DisplayRow] = [], nav: [NavItem] = []) {
        self.entries = entries
        self.flatRows = flatRows
        self.nav = nav
    }
}

public enum TimeBucket: String, CaseIterable {
    case today = "Today"
    case yesterday = "Yesterday"
    case previous7 = "Previous 7 days"
    case older = "Older"

    public static func of(_ millis: Int64, now: Date = Date()) -> TimeBucket {
        let startToday = Calendar.current.startOfDay(for: now).timeIntervalSince1970 * 1000
        let day = 86_400_000.0
        let ms = Double(millis)
        if ms >= startToday { return .today }
        if ms >= startToday - day { return .yesterday }
        if ms >= startToday - 7 * day { return .previous7 }
        return .older
    }
}

/// Builds the grouped, flattened layout for the active mode — clipboard groups
/// by time (Pinned + day buckets); snippets group by folder (a collapsible
/// tree). While searching, results are shown as a single flat list.
public func buildPanelLayout(
    mode: PanelMode,
    query: String,
    clips: [DisplayRow],
    snippets: [DisplayRow],
    folders: [SnippetFolder],
    collapsed: Set<Int64>
) -> PanelLayout {
    let searching = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    var layout = PanelLayout()

    struct Group {
        var label: String?
        var rows: [DisplayRow]
        var folderKey: Int64?
    }
    var groups: [Group] = []

    switch mode {
    case .clipboard:
        if searching {
            groups.append(Group(label: nil, rows: clips, folderKey: nil))
        } else {
            let pinned = clips.filter(\.pinned)
            if !pinned.isEmpty {
                groups.append(Group(label: "Pinned", rows: pinned, folderKey: nil))
            }
            let unpinned = clips.filter { !$0.pinned }
            for bucket in TimeBucket.allCases {
                let rows = unpinned.filter { TimeBucket.of($0.updatedAt) == bucket }
                if !rows.isEmpty {
                    groups.append(Group(label: bucket.rawValue, rows: rows, folderKey: nil))
                }
            }
        }
    case .snippets:
        if searching {
            groups.append(Group(label: nil, rows: snippets, folderKey: nil))
        } else {
            var byFolder: [Int64: [DisplayRow]] = [:]
            for row in snippets {
                byFolder[row.folderID ?? uncategorizedFolderKey, default: []].append(row)
            }
            for folder in folders {
                groups.append(Group(label: folder.name, rows: byFolder[folder.id] ?? [], folderKey: folder.id))
            }
            if let unfiled = byFolder[uncategorizedFolderKey], !unfiled.isEmpty {
                groups.append(Group(label: "Uncategorized", rows: unfiled, folderKey: uncategorizedFolderKey))
            }
        }
    }

    for group in groups {
        let isCollapsed = group.folderKey.map { collapsed.contains($0) } ?? false
        if let label = group.label {
            layout.entries.append(
                .header(id: group.folderKey.map(String.init) ?? label,
                        title: label,
                        folderKey: group.folderKey,
                        collapsed: isCollapsed)
            )
            // Only collapsible folder headers (which carry a key) are navigable.
            if let key = group.folderKey {
                layout.nav.append(.header(folderKey: key))
            }
        }
        if isCollapsed { continue }
        for row in group.rows {
            let flatIndex = layout.flatRows.count
            let quickIndex = flatIndex < 10 ? flatIndex : nil
            layout.entries.append(.row(row, flatIndex: flatIndex, quickIndex: quickIndex))
            layout.flatRows.append(row)
            layout.nav.append(.row(flatIndex))
        }
    }
    return layout
}

/// A compact relative-time label (now / 5m / 3h / 2d / 1w).
public func relativeTime(_ millis: Int64, now: Int64 = nowMillis()) -> String {
    let seconds = max(0, Int(Double(now - millis) / 1000))
    if seconds < 60 { return "now" }
    let minutes = seconds / 60
    if minutes < 60 { return "\(minutes)m" }
    let hours = minutes / 60
    if hours < 24 { return "\(hours)h" }
    let days = hours / 24
    if days < 7 { return "\(days)d" }
    return "\(days / 7)w"
}
