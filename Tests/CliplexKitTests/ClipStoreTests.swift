import Foundation
import Testing
@testable import CliplexKit

@Suite struct SearchTests {
    @Test func emptyInputYieldsNil() {
        #expect(Search.buildFTSQuery("") == nil)
        #expect(Search.buildFTSQuery("   \t") == nil)
    }

    @Test func tokensArePrefixMatched() {
        #expect(Search.buildFTSQuery("hello") == "\"hello\"*")
        #expect(Search.buildFTSQuery("hello world") == "\"hello\"* \"world\"*")
    }

    @Test func quotesAreEscaped() {
        #expect(Search.buildFTSQuery("a\"b") == "\"a\"\"b\"*")
    }
}

@Suite struct ClipStoreTests {
    private func makeStore() throws -> ClipStore { try ClipStore() }

    private func textClip(_ text: String, app: String? = nil) -> NewClip {
        NewClip(
            kind: .text,
            preview: text,
            sourceApp: app,
            assets: [ClipAsset(uti: "public.utf8-plain-text", bytes: Data(text.utf8))]
        )
    }

    @Test func emptyClipIsRejected() throws {
        let store = try makeStore()
        let empty = NewClip(kind: .text, preview: "x", sourceApp: nil, assets: [])
        #expect(throws: StoreError.invalid("clip has no assets")) {
            try store.addClip(empty)
        }
    }

    @Test func assetsRoundTrip() throws {
        let store = try makeStore()
        let clip = try store.addClip(
            NewClip(
                kind: .richtext,
                preview: "hi",
                sourceApp: "com.example",
                assets: [
                    ClipAsset(uti: "public.utf8-plain-text", bytes: Data("hi".utf8), idx: 0),
                    ClipAsset(uti: "public.rtf", bytes: Data("{\\rtf1 hi}".utf8), idx: 1)
                ]
            )
        )
        let assets = try store.clipAssets(clipID: clip.id)
        #expect(assets.count == 2)
        #expect(assets[0].uti == "public.utf8-plain-text")
        #expect(assets[1].uti == "public.rtf")
        #expect(assets[0].bytes == Data("hi".utf8))
    }

    @Test func addAndListClipsIsMRUOrdered() throws {
        let store = try makeStore()
        let a = try store.addClip(textClip("a"))
        let b = try store.addClip(textClip("b"))
        let c = try store.addClip(textClip("c"))
        let listed = try store.listClips(limit: 10)
        #expect(listed.map(\.id) == [c.id, b.id, a.id])
    }

    @Test func duplicateContentIsDeduplicatedAndBumped() throws {
        let store = try makeStore()
        let a = try store.addClip(textClip("dup"))
        _ = try store.addClip(textClip("other"))
        let again = try store.addClip(textClip("dup"))
        #expect(a.id == again.id)
        #expect(try store.countClips() == 2)
        let listed = try store.listClips(limit: 10)
        #expect(listed.first?.id == a.id)
    }

    @Test func pinExemptsFromPruneAndSortsFirst() throws {
        let store = try makeStore()
        let pinned = try store.addClip(textClip("keep"))
        try store.setPinned(id: pinned.id, pinned: true)
        for i in 0..<5 { _ = try store.addClip(textClip("n\(i)")) }
        let removed = try store.pruneClips(maxItems: 2)
        #expect(removed == 3)
        let listed = try store.listClips(limit: 10)
        #expect(listed.contains { $0.id == pinned.id })
        #expect(listed.first?.id == pinned.id)
        #expect(try store.countPinned() == 1)
    }

    @Test func deleteAndClearClips() throws {
        let store = try makeStore()
        let a = try store.addClip(textClip("a"))
        let pinned = try store.addClip(textClip("b"))
        try store.setPinned(id: pinned.id, pinned: true)
        try store.deleteClip(id: a.id)
        #expect(try store.countClips() == 1)
        let cleared = try store.clearClips(includePinned: false)
        #expect(cleared == 0)
        #expect(try store.countClips() == 1)
        _ = try store.clearClips(includePinned: true)
        #expect(try store.countClips() == 0)
    }

    @Test func deleteMissingClipThrows() throws {
        let store = try makeStore()
        #expect(throws: StoreError.notFound) {
            try store.deleteClip(id: 999)
        }
    }

    @Test func searchClipsMatchesPrefix() throws {
        let store = try makeStore()
        _ = try store.addClip(textClip("hello world"))
        _ = try store.addClip(textClip("goodbye"))
        let hits = try store.searchClips("hel", limit: 10)
        #expect(hits.count == 1)
        #expect(hits.first?.preview == "hello world")
    }

    @Test func snippetFolderAndSnippetCRUD() throws {
        let store = try makeStore()
        let folder = try store.addFolder(name: "Work")
        #expect(try store.listFolders().count == 1)

        let snip = try store.addSnippet(folderID: folder.id, title: "Sig", content: "Best, Ron")
        #expect(try store.listSnippets(folderID: folder.id).map(\.id) == [snip.id])

        try store.updateSnippet(id: snip.id, title: "Signature", content: "Cheers")
        #expect(try store.snippet(id: snip.id).title == "Signature")

        try store.renameFolder(id: folder.id, name: "Personal")
        #expect(try store.folder(id: folder.id).name == "Personal")

        // Deleting the folder cascades to its snippets.
        try store.deleteFolder(id: folder.id)
        #expect(try store.listFolders().isEmpty)
        #expect(throws: StoreError.notFound) {
            try store.snippet(id: snip.id)
        }
    }

    @Test func searchSnippetsMatchesTitleAndContent() throws {
        let store = try makeStore()
        _ = try store.addSnippet(folderID: nil, title: "Address", content: "1 Infinite Loop")
        _ = try store.addSnippet(folderID: nil, title: "Phone", content: "555-1234")
        #expect(try store.searchSnippets("infinite", limit: 10).count == 1)
        #expect(try store.searchSnippets("phone", limit: 10).count == 1)
    }

    @Test func uncategorizedSnippetsListed() throws {
        let store = try makeStore()
        let folder = try store.addFolder(name: "F")
        _ = try store.addSnippet(folderID: nil, title: "loose", content: "x")
        _ = try store.addSnippet(folderID: folder.id, title: "filed", content: "y")
        #expect(try store.listSnippets(folderID: nil).count == 2)
        #expect(try store.listSnippets(folderID: folder.id).count == 1)
    }

    @Test func reopenPreservesDataAndDedups() throws {
        let path = NSTemporaryDirectory() + "cliplex-test-\(UUID().uuidString).db"
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: path + suffix)
            }
        }
        let first = try ClipStore(path: path)
        _ = try first.addClip(textClip("persist"))
        #expect(try first.countClips() == 1)

        // Reopening the same file preserves data (and the idempotent schema /
        // hash migration must not corrupt it).
        let second = try ClipStore(path: path)
        #expect(try second.countClips() == 1)
        _ = try second.addClip(textClip("persist"))
        #expect(try second.countClips() == 1, "identical content should dedupe across reopen")
    }
}
