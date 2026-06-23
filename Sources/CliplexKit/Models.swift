import Foundation

/// The kind of content a clip primarily represents. Stored as a lowercase
/// string in SQLite for forward compatibility.
public enum ClipKind: String, Codable, Sendable {
    case text
    case richtext
    case image
    case files
    case color

    /// Parses the database string form, defaulting to ``text``.
    public static func lenient(_ raw: String) -> ClipKind {
        ClipKind(rawValue: raw) ?? .text
    }
}

/// A single stored format payload belonging to a clip (e.g. the plain-text and
/// RTF representations of the same copy).
public struct ClipAsset: Equatable, Sendable {
    /// Uniform-type identifier (e.g. `public.utf8-plain-text`).
    public var uti: String
    /// Raw bytes of this representation.
    public var bytes: Data
    /// Order within the clip (0-based).
    public var idx: Int64

    public init(uti: String, bytes: Data, idx: Int64 = 0) {
        self.uti = uti
        self.bytes = bytes
        self.idx = idx
    }
}

/// A new clip to be inserted, before it receives an id / hash.
public struct NewClip: Sendable {
    public var kind: ClipKind
    /// Searchable plain-text preview / title.
    public var preview: String
    /// Bundle id or executable name of the source app, if known.
    public var sourceApp: String?
    /// Format payloads. At least one is expected.
    public var assets: [ClipAsset]

    public init(kind: ClipKind, preview: String, sourceApp: String?, assets: [ClipAsset]) {
        self.kind = kind
        self.preview = preview
        self.sourceApp = sourceApp
        self.assets = assets
    }
}

/// A stored clipboard-history entry.
public struct Clip: Identifiable, Equatable, Sendable {
    public var id: Int64
    public var contentHash: String
    public var kind: ClipKind
    public var preview: String
    public var sourceApp: String?
    public var pinned: Bool
    /// Unix epoch milliseconds.
    public var createdAt: Int64
    /// Unix epoch milliseconds (bumped when re-copied).
    public var updatedAt: Int64
}

/// A snippet folder.
public struct SnippetFolder: Identifiable, Equatable, Sendable {
    public var id: Int64
    public var name: String
    public var sortOrder: Int64
    public var createdAt: Int64
}

/// A reusable snippet.
public struct Snippet: Identifiable, Equatable, Sendable {
    public var id: Int64
    public var folderId: Int64?
    public var title: String
    public var content: String
    public var sortOrder: Int64
    public var createdAt: Int64
    public var updatedAt: Int64
}

/// Returns the current time in Unix epoch milliseconds.
public func nowMillis() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1000)
}
