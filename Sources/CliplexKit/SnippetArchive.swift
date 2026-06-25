import Foundation

/// A portable JSON representation of the entire snippet library (folders + their
/// snippets, plus uncategorized snippets), used for import/export.
public struct SnippetArchive: Codable, Equatable {
    public struct Item: Codable, Equatable {
        public var title: String
        public var content: String

        public init(title: String, content: String) {
            self.title = title
            self.content = content
        }
    }

    public struct Folder: Codable, Equatable {
        public var name: String
        public var snippets: [Item]

        public init(name: String, snippets: [Item]) {
            self.name = name
            self.snippets = snippets
        }
    }

    public var version: Int
    public var folders: [Folder]
    public var unfiled: [Item]

    public init(version: Int = 1, folders: [Folder], unfiled: [Item]) {
        self.version = version
        self.folders = folders
        self.unfiled = unfiled
    }
}

/// Import/export of the snippet library to/from JSON.
public enum SnippetIO {
    /// Serializes every folder and snippet (display order preserved) to JSON.
    public static func export(from store: ClipStore) throws -> Data {
        let folders = try store.listFolders()
        let all = try store.listSnippets(folderID: nil)
        let byFolder = Dictionary(grouping: all, by: { $0.folderId })

        let folderArchives = folders.map { folder in
            SnippetArchive.Folder(
                name: folder.name,
                snippets: (byFolder[folder.id] ?? []).map { SnippetArchive.Item(title: $0.title, content: $0.content) }
            )
        }
        let unfiled = (byFolder[nil] ?? []).map { SnippetArchive.Item(title: $0.title, content: $0.content) }

        let archive = SnippetArchive(folders: folderArchives, unfiled: unfiled)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(archive)
    }

    /// Adds the archive's folders/snippets to `store`. Existing folders with a
    /// matching name are reused (so importing merges rather than duplicating
    /// folders); snippets are always appended.
    public static func importing(_ data: Data, into store: ClipStore) throws {
        let archive = try JSONDecoder().decode(SnippetArchive.self, from: data)

        var folderIDByName: [String: Int64] = [:]
        for folder in try store.listFolders() where folderIDByName[folder.name] == nil {
            folderIDByName[folder.name] = folder.id
        }

        for folder in archive.folders {
            let folderID: Int64
            if let existing = folderIDByName[folder.name] {
                folderID = existing
            } else {
                let created = try store.addFolder(name: folder.name)
                folderID = created.id
                folderIDByName[folder.name] = created.id
            }
            for item in folder.snippets {
                _ = try store.addSnippet(folderID: folderID, title: item.title, content: item.content)
            }
        }

        for item in archive.unfiled {
            _ = try store.addSnippet(folderID: nil, title: item.title, content: item.content)
        }
    }
}
