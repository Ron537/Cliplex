import Foundation
import Testing
@testable import CliplexKit

@Suite struct SnippetArchiveTests {
    @Test func exportThenImportRoundTrips() throws {
        let source = try ClipStore()
        let work = try source.addFolder(name: "Work")
        let personal = try source.addFolder(name: "Personal")
        _ = try source.addSnippet(folderID: work.id, title: "W1", content: "select 1")
        _ = try source.addSnippet(folderID: work.id, title: "W2", content: "select 2")
        _ = try source.addSnippet(folderID: personal.id, title: "P1", content: "hi")
        _ = try source.addSnippet(folderID: nil, title: "Loose", content: "loose content")

        let data = try SnippetIO.export(from: source)

        // Import into a fresh store and verify structure + order.
        let dest = try ClipStore()
        try SnippetIO.importing(data, into: dest)

        let folders = try dest.listFolders()
        #expect(folders.map(\.name) == ["Work", "Personal"])

        let workID = folders.first { $0.name == "Work" }!.id
        #expect(try dest.listSnippets(folderID: workID).map(\.title) == ["W1", "W2"])

        let all = try dest.listSnippets(folderID: nil)
        #expect(all.contains { $0.title == "Loose" && $0.folderId == nil })
        #expect(all.count == 4)
    }

    @Test func importMergesIntoExistingFolderByName() throws {
        let store = try ClipStore()
        let work = try store.addFolder(name: "Work")
        _ = try store.addSnippet(folderID: work.id, title: "Existing", content: "x")

        let archive = SnippetArchive(
            folders: [.init(name: "Work", snippets: [.init(title: "Imported", content: "y")])],
            unfiled: []
        )
        let data = try JSONEncoder().encode(archive)
        try SnippetIO.importing(data, into: store)

        // No duplicate "Work" folder; both snippets present.
        #expect(try store.listFolders().filter { $0.name == "Work" }.count == 1)
        #expect(try store.listSnippets(folderID: work.id).map(\.title) == ["Existing", "Imported"])
    }
}
