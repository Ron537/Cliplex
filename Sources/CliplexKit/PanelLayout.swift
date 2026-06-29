import Foundation

/// The fully-separated panel modes.
public enum PanelMode: CaseIterable {
    case clipboard
    case snippets
    case actions

    public var label: String {
        switch self {
        case .clipboard: return "Clips"
        case .snippets: return "Snippets"
        case .actions: return "Actions"
        }
    }
}

/// A unified row rendered by the panel list (a clip, a snippet, or an action).
public struct DisplayRow: Identifiable, Equatable {
    public enum Kind: Equatable {
        case clip(ClipKind)
        case snippet
        case action(ActionType)
    }

    public let kind: Kind
    public let id: Int64
    public let title: String
    public let subtitle: String
    public let pinned: Bool
    public let updatedAt: Int64
    public let folderID: Int64?

    public var isSnippet: Bool { kind == .snippet }

    public var isAction: Bool {
        if case .action = kind { return true }
        return false
    }

    public var clipKind: ClipKind? {
        if case let .clip(k) = kind { return k }
        return nil
    }

    public var actionType: ActionType? {
        if case let .action(t) = kind { return t }
        return nil
    }

    /// Stable list/scroll identity derived from content (not list position), so
    /// SwiftUI diffs rows correctly when the list changes or the mode switches.
    public var listID: String { "r:\(kindTag):\(id)" }

    private var kindTag: String {
        switch kind {
        case .clip: return "c"
        case .snippet: return "s"
        case .action: return "a"
        }
    }

    public init(clip: Clip) {
        self.kind = .clip(clip.kind)
        self.id = clip.id
        self.title = clip.preview
        self.subtitle = clip.sourceApp ?? ""
        self.pinned = clip.pinned
        self.updatedAt = clip.updatedAt
        self.folderID = nil
    }

    public init(snippet: Snippet) {
        self.kind = .snippet
        self.id = snippet.id
        self.title = snippet.title.isEmpty ? snippet.content : snippet.title
        self.subtitle = snippet.content.replacingOccurrences(of: "\n", with: " ")
        self.pinned = false
        self.updatedAt = snippet.updatedAt
        self.folderID = snippet.folderId
    }

    public init(action: ActionItem) {
        self.kind = .action(action.type)
        self.id = action.id
        self.title = action.title
        switch action.type {
        case .transform: self.subtitle = "⤳ " + (action.transform?.label ?? "Transform")
        default: self.subtitle = action.value.isEmpty ? action.type.label : action.value
        }
        self.pinned = false
        self.updatedAt = action.updatedAt
        self.folderID = action.folderId
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
/// by time (Pinned + day buckets); snippets and actions group by folder (a
/// collapsible tree). While searching, results are shown as a single flat list.
public func buildPanelLayout(
    mode: PanelMode,
    query: String,
    clips: [DisplayRow],
    snippets: [DisplayRow],
    folders: [SnippetFolder],
    collapsed: Set<Int64>,
    actions: [DisplayRow] = [],
    actionFolders: [ActionFolder] = []
) -> PanelLayout {
    let searching = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    var layout = PanelLayout()

    struct Group {
        var label: String?
        var rows: [DisplayRow]
        var folderKey: Int64?
    }
    var groups: [Group] = []

    /// Groups items into a folder tree: one group per folder (in order), plus a
    /// trailing "Uncategorized" group for unfiled items.
    func folderTree(rows: [DisplayRow], folders: [(id: Int64, name: String)]) -> [Group] {
        var byFolder: [Int64: [DisplayRow]] = [:]
        for row in rows {
            byFolder[row.folderID ?? uncategorizedFolderKey, default: []].append(row)
        }
        var result = folders.map {
            Group(label: $0.name, rows: byFolder[$0.id] ?? [], folderKey: $0.id)
        }
        if let unfiled = byFolder[uncategorizedFolderKey], !unfiled.isEmpty {
            result.append(Group(label: "Uncategorized", rows: unfiled, folderKey: uncategorizedFolderKey))
        }
        return result
    }

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
            groups = folderTree(rows: snippets, folders: folders.map { ($0.id, $0.name) })
        }
    case .actions:
        if searching {
            groups.append(Group(label: nil, rows: actions, folderKey: nil))
        } else {
            groups = folderTree(rows: actions, folders: actionFolders.map { ($0.id, $0.name) })
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
