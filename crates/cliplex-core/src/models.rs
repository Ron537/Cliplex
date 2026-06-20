//! Data models for clipboard history, snippets, and settings.

use serde::{Deserialize, Serialize};

/// The kind of content a clip primarily represents.
///
/// Stored as a lowercase string in SQLite for forward compatibility.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ClipKind {
    /// Plain text.
    Text,
    /// Rich text (RTF/HTML) with a plain-text preview.
    RichText,
    /// A bitmap image (PNG/TIFF, etc.).
    Image,
    /// One or more file references.
    Files,
    /// A color value (e.g. a hex code) detected in copied text.
    Color,
}

impl ClipKind {
    /// String representation persisted in the database.
    pub fn as_str(self) -> &'static str {
        match self {
            ClipKind::Text => "text",
            ClipKind::RichText => "richtext",
            ClipKind::Image => "image",
            ClipKind::Files => "files",
            ClipKind::Color => "color",
        }
    }

    /// Parse from the database string form, defaulting to [`ClipKind::Text`].
    pub fn from_str_lenient(s: &str) -> Self {
        match s {
            "richtext" => ClipKind::RichText,
            "image" => ClipKind::Image,
            "files" => ClipKind::Files,
            "color" => ClipKind::Color,
            _ => ClipKind::Text,
        }
    }
}

/// A single stored format payload belonging to a clip (e.g. the plain-text and
/// RTF representations of the same copy).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClipAsset {
    /// Platform format / uniform-type identifier (e.g. `public.utf8-plain-text`).
    pub uti: String,
    /// Raw bytes of this representation.
    pub bytes: Vec<u8>,
    /// Order within the clip (0-based).
    pub idx: i64,
}

/// A new clip to be inserted, before it receives an id / hash.
#[derive(Debug, Clone)]
pub struct NewClip {
    pub kind: ClipKind,
    /// Searchable plain-text preview / title.
    pub preview: String,
    /// Bundle id or executable name of the source app, if known.
    pub source_app: Option<String>,
    /// Format payloads. At least one is expected.
    pub assets: Vec<ClipAsset>,
}

/// A stored clipboard-history entry.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Clip {
    pub id: i64,
    pub content_hash: String,
    pub kind: ClipKind,
    pub preview: String,
    pub source_app: Option<String>,
    pub pinned: bool,
    /// Unix epoch milliseconds.
    pub created_at: i64,
    /// Unix epoch milliseconds (bumped when re-copied).
    pub updated_at: i64,
}

/// A snippet folder.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SnippetFolder {
    pub id: i64,
    pub name: String,
    pub sort_order: i64,
    pub created_at: i64,
}

/// A reusable snippet.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Snippet {
    pub id: i64,
    pub folder_id: Option<i64>,
    pub title: String,
    pub content: String,
    pub sort_order: i64,
    pub created_at: i64,
    pub updated_at: i64,
}
