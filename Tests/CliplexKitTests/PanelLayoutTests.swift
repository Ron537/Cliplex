import Foundation
import Testing
@testable import CliplexKit

@Suite struct PanelLayoutTests {
    private func clipRow(id: Int64, at updatedAt: Int64, pinned: Bool = false) -> DisplayRow {
        DisplayRow(clip: Clip(
            id: id, contentHash: "h\(id)", kind: .text, preview: "c\(id)",
            sourceApp: nil, pinned: pinned, createdAt: updatedAt, updatedAt: updatedAt))
    }

    private func snippetRow(id: Int64, folder: Int64?) -> DisplayRow {
        DisplayRow(snippet: Snippet(
            id: id, folderId: folder, title: "s\(id)", content: "x",
            sortOrder: 0, createdAt: 0, updatedAt: 0))
    }

    // MARK: - Time buckets

    @Test func timeBucketBoundaries() {
        let now = Date()
        let startToday = Calendar.current.startOfDay(for: now)
        func ms(_ date: Date) -> Int64 { Int64(date.timeIntervalSince1970 * 1000) }

        #expect(TimeBucket.of(ms(now), now: now) == .today)
        #expect(TimeBucket.of(ms(startToday.addingTimeInterval(-3600)), now: now) == .yesterday)
        #expect(TimeBucket.of(ms(startToday.addingTimeInterval(-3 * 86_400)), now: now) == .previous7)
        #expect(TimeBucket.of(ms(startToday.addingTimeInterval(-30 * 86_400)), now: now) == .older)
    }

    @Test func relativeTimeLabels() {
        let now: Int64 = 1_000_000_000_000
        #expect(relativeTime(now - 30_000, now: now) == "now")
        #expect(relativeTime(now - 120_000, now: now) == "2m")
        #expect(relativeTime(now - 3 * 3_600_000, now: now) == "3h")
        #expect(relativeTime(now - 2 * 86_400_000, now: now) == "2d")
        #expect(relativeTime(now - 14 * 86_400_000, now: now) == "2w")
    }

    // MARK: - Clipboard layout

    @Test func clipboardGroupsPinnedThenTime() {
        let now = nowMillis()
        let rows = [
            clipRow(id: 1, at: now, pinned: true),
            clipRow(id: 2, at: now),
            clipRow(id: 3, at: now),
        ]
        let layout = buildPanelLayout(
            mode: .clipboard, query: "", clips: rows, snippets: [], folders: [], collapsed: [])

        // Pinned group first, then Today.
        let headers = layout.entries.compactMap { entry -> String? in
            if case let .header(_, title, _, _) = entry { return title }
            return nil
        }
        #expect(headers == ["Pinned", "Today"])
        // Flat order: pinned (id 1) first, then the two Today rows.
        #expect(layout.flatRows.map(\.id) == [1, 2, 3])
    }

    @Test func searchingShowsFlatListNoHeaders() {
        let now = nowMillis()
        let rows = [clipRow(id: 1, at: now, pinned: true), clipRow(id: 2, at: now)]
        let layout = buildPanelLayout(
            mode: .clipboard, query: "foo", clips: rows, snippets: [], folders: [], collapsed: [])
        let headers = layout.entries.contains { if case .header = $0 { return true }; return false }
        #expect(!headers)
        #expect(layout.flatRows.map(\.id) == [1, 2])
    }

    @Test func quickIndexOnlyForFirstTen() {
        let now = nowMillis()
        let rows = (1...12).map { clipRow(id: Int64($0), at: now) }
        let layout = buildPanelLayout(
            mode: .clipboard, query: "", clips: rows, snippets: [], folders: [], collapsed: [])
        var quick: [Int?] = []
        for entry in layout.entries {
            if case let .row(_, _, q) = entry { quick.append(q) }
        }
        #expect(quick.count == 12)
        #expect(quick.prefix(10).allSatisfy { $0 != nil })
        // 11th and 12th rows have no quick key.
        #expect(quick[10] == nil)
        #expect(quick[11] == nil)
    }

    // MARK: - Snippet folder tree

    @Test func snippetsGroupByFolderWithUncategorized() {
        let folders = [
            SnippetFolder(id: 1, name: "Work", sortOrder: 0, createdAt: 0),
            SnippetFolder(id: 2, name: "Personal", sortOrder: 1, createdAt: 0),
        ]
        let snippets = [
            snippetRow(id: 10, folder: 1),
            snippetRow(id: 11, folder: 2),
            snippetRow(id: 12, folder: nil),
        ]
        let layout = buildPanelLayout(
            mode: .snippets, query: "", clips: [], snippets: snippets, folders: folders, collapsed: [])
        let headers = layout.entries.compactMap { entry -> String? in
            if case let .header(_, title, _, _) = entry { return title }
            return nil
        }
        #expect(headers == ["Work", "Personal", "Uncategorized"])
        #expect(layout.flatRows.map(\.id) == [10, 11, 12])
    }

    @Test func collapsedFolderHidesItsRows() {
        let folders = [SnippetFolder(id: 1, name: "Work", sortOrder: 0, createdAt: 0)]
        let snippets = [snippetRow(id: 10, folder: 1), snippetRow(id: 11, folder: 1)]
        let layout = buildPanelLayout(
            mode: .snippets, query: "", clips: [], snippets: snippets, folders: folders, collapsed: [1])
        // Header still shown, but its rows are excluded from the flat list.
        #expect(layout.entries.count == 1)
        #expect(layout.flatRows.isEmpty)
    }

    @Test func emptyFolderStillShownAsHeader() {
        let folders = [SnippetFolder(id: 1, name: "Empty", sortOrder: 0, createdAt: 0)]
        let layout = buildPanelLayout(
            mode: .snippets, query: "", clips: [], snippets: [], folders: folders, collapsed: [])
        let headers = layout.entries.compactMap { entry -> String? in
            if case let .header(_, title, _, _) = entry { return title }
            return nil
        }
        #expect(headers == ["Empty"])
        #expect(layout.flatRows.isEmpty)
    }

    // MARK: - Keyboard-navigable items

    @Test func snippetTreeNavInterleavesHeadersAndRows() {
        let folders = [
            SnippetFolder(id: 1, name: "Work", sortOrder: 0, createdAt: 0),
            SnippetFolder(id: 2, name: "Personal", sortOrder: 1, createdAt: 0),
        ]
        let snippets = [
            snippetRow(id: 10, folder: 1),
            snippetRow(id: 11, folder: 1),
            snippetRow(id: 12, folder: 2),
        ]
        let layout = buildPanelLayout(
            mode: .snippets, query: "", clips: [], snippets: snippets, folders: folders, collapsed: [])
        // Folder headers are navigable and interleaved with their rows.
        #expect(layout.nav == [
            .header(folderKey: 1), .row(0), .row(1),
            .header(folderKey: 2), .row(2),
        ])
    }

    @Test func collapsedFolderHeaderStaysNavigableWithoutItsRows() {
        let folders = [
            SnippetFolder(id: 1, name: "Work", sortOrder: 0, createdAt: 0),
            SnippetFolder(id: 2, name: "Personal", sortOrder: 1, createdAt: 0),
        ]
        let snippets = [snippetRow(id: 10, folder: 1), snippetRow(id: 11, folder: 2)]
        let layout = buildPanelLayout(
            mode: .snippets, query: "", clips: [], snippets: snippets, folders: folders, collapsed: [1])
        // Collapsed folder keeps a navigable header (so it can be re-expanded).
        #expect(layout.nav == [
            .header(folderKey: 1),
            .header(folderKey: 2), .row(0),
        ])
    }

    @Test func clipboardNavIsRowsOnly() {
        let now = nowMillis()
        let rows = [clipRow(id: 1, at: now, pinned: true), clipRow(id: 2, at: now)]
        let layout = buildPanelLayout(
            mode: .clipboard, query: "", clips: rows, snippets: [], folders: [], collapsed: [])
        // Time/Pinned headers are not navigable: selection maps 1:1 onto rows.
        #expect(layout.nav == [.row(0), .row(1)])
    }
}
