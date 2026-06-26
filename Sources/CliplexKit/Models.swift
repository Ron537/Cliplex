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

/// What an ``ActionItem`` does when invoked. Stored as a lowercase string for
/// forward compatibility.
public enum ActionType: String, Codable, Sendable, CaseIterable {
    /// Open a URL (the `value`, with `{clipboard}` expanded) in the default browser.
    case openURL = "open_url"
    /// Launch an application (the `value` is a bundle id or an app path).
    case openApp = "open_app"
    /// Reveal/open a file or folder (the `value` is a filesystem path).
    case openPath = "open_path"
    /// Transform the current clipboard text in place (see ``transform``).
    case transform

    public static func lenient(_ raw: String) -> ActionType {
        ActionType(rawValue: raw) ?? .openURL
    }

    public var label: String {
        switch self {
        case .openURL: return "Open URL"
        case .openApp: return "Open App"
        case .openPath: return "Open File / Folder"
        case .transform: return "Transform Clipboard"
        }
    }

    public var symbol: String {
        switch self {
        case .openURL: return "link"
        case .openApp: return "app"
        case .openPath: return "folder"
        case .transform: return "wand.and.stars"
        }
    }
}

/// A pure, in-place transformation applied to the current clipboard text.
public enum ActionTransform: String, Codable, Sendable, CaseIterable {
    case uppercase
    case lowercase
    case titlecase
    case trim
    case base64Encode = "base64_encode"
    case base64Decode = "base64_decode"
    case urlEncode = "url_encode"
    case urlDecode = "url_decode"
    case jsonPretty = "json_pretty"
    case jsonMinify = "json_minify"
    case sha256

    public static func lenient(_ raw: String) -> ActionTransform {
        ActionTransform(rawValue: raw) ?? .uppercase
    }

    public var label: String {
        switch self {
        case .uppercase: return "UPPERCASE"
        case .lowercase: return "lowercase"
        case .titlecase: return "Title Case"
        case .trim: return "Trim Whitespace"
        case .base64Encode: return "Base64 Encode"
        case .base64Decode: return "Base64 Decode"
        case .urlEncode: return "URL Encode"
        case .urlDecode: return "URL Decode"
        case .jsonPretty: return "JSON Pretty-Print"
        case .jsonMinify: return "JSON Minify"
        case .sha256: return "SHA-256 Hash"
        }
    }
}

/// An action folder (groups ``ActionItem``s, mirroring ``SnippetFolder``).
public struct ActionFolder: Identifiable, Equatable, Sendable {
    public var id: Int64
    public var name: String
    public var sortOrder: Int64
    public var createdAt: Int64
}

/// A saved quick action.
public struct ActionItem: Identifiable, Equatable, Sendable {
    public var id: Int64
    public var folderId: Int64?
    public var title: String
    public var type: ActionType
    /// The URL template / app id-or-path / filesystem path. Empty for transforms.
    public var value: String
    /// The transform to apply (only meaningful when `type == .transform`).
    public var transform: ActionTransform?
    public var sortOrder: Int64
    public var createdAt: Int64
    public var updatedAt: Int64
}

/// Returns the current time in Unix epoch milliseconds.
public func nowMillis() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1000)
}
