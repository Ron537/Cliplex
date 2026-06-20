//! Cliplex core library.
//!
//! OS-agnostic building blocks for the Cliplex clipboard manager: data models,
//! SQLite + FTS5 storage, search, deduplication, and history pruning.
//!
//! This crate intentionally has **no network dependencies** — Cliplex collects
//! no telemetry and never phones home.

pub mod db;
pub mod error;
pub mod models;
pub mod search;

pub use db::{now_ms, Database};
pub use error::{Error, Result};
pub use models::{Clip, ClipAsset, ClipKind, NewClip, Snippet, SnippetFolder};

/// Returns the semantic version of the core crate.
pub fn version() -> &'static str {
    env!("CARGO_PKG_VERSION")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn text_clip(text: &str) -> NewClip {
        NewClip {
            kind: ClipKind::Text,
            preview: text.to_string(),
            source_app: None,
            assets: vec![ClipAsset {
                uti: "public.utf8-plain-text".to_string(),
                bytes: text.as_bytes().to_vec(),
                idx: 0,
            }],
        }
    }

    #[test]
    fn version_is_reported() {
        assert!(!version().is_empty());
    }

    #[test]
    fn add_and_list_clips_is_mru_ordered() {
        let mut db = Database::open_in_memory().unwrap();
        db.add_clip(text_clip("first")).unwrap();
        db.add_clip(text_clip("second")).unwrap();
        let clips = db.list_clips(10, 0).unwrap();
        assert_eq!(clips.len(), 2);
        assert_eq!(clips[0].preview, "second");
        assert_eq!(clips[1].preview, "first");
    }

    #[test]
    fn duplicate_content_is_deduplicated_and_bumped() {
        let mut db = Database::open_in_memory().unwrap();
        let a = db.add_clip(text_clip("hello")).unwrap();
        db.add_clip(text_clip("world")).unwrap();
        let a2 = db.add_clip(text_clip("hello")).unwrap();
        assert_eq!(a.id, a2.id, "same content reuses the row");
        assert_eq!(db.count_clips().unwrap(), 2);
        // "hello" was re-copied, so it should now be first.
        let clips = db.list_clips(10, 0).unwrap();
        assert_eq!(clips[0].preview, "hello");
    }

    #[test]
    fn empty_clip_is_rejected() {
        let mut db = Database::open_in_memory().unwrap();
        let res = db.add_clip(NewClip {
            kind: ClipKind::Text,
            preview: "x".into(),
            source_app: None,
            assets: vec![],
        });
        assert!(matches!(res, Err(Error::Invalid(_))));
    }

    #[test]
    fn search_clips_matches_prefix() {
        let mut db = Database::open_in_memory().unwrap();
        db.add_clip(text_clip("apple pie recipe")).unwrap();
        db.add_clip(text_clip("banana bread")).unwrap();
        let hits = db.search_clips("app", 10).unwrap();
        assert_eq!(hits.len(), 1);
        assert_eq!(hits[0].preview, "apple pie recipe");
        // Empty query falls back to listing everything.
        assert_eq!(db.search_clips("   ", 10).unwrap().len(), 2);
    }

    #[test]
    fn assets_round_trip() {
        let mut db = Database::open_in_memory().unwrap();
        let clip = db.add_clip(text_clip("payload")).unwrap();
        let assets = db.clip_assets(clip.id).unwrap();
        assert_eq!(assets.len(), 1);
        assert_eq!(assets[0].bytes, b"payload");
    }

    #[test]
    fn pin_exempts_from_prune_and_sorts_first() {
        let mut db = Database::open_in_memory().unwrap();
        let keep = db.add_clip(text_clip("keep me")).unwrap();
        db.set_pinned(keep.id, true).unwrap();
        for i in 0..5 {
            db.add_clip(text_clip(&format!("junk {i}"))).unwrap();
        }
        let removed = db.prune_clips(2).unwrap();
        assert_eq!(removed, 3, "5 unpinned, keep newest 2 -> remove 3");
        // Pinned clip survives and is listed first.
        let clips = db.list_clips(10, 0).unwrap();
        assert!(clips.iter().any(|c| c.id == keep.id));
        assert_eq!(clips[0].id, keep.id);
        assert_eq!(db.count_clips().unwrap(), 3); // 1 pinned + 2 kept
    }

    #[test]
    fn delete_and_clear_clips() {
        let mut db = Database::open_in_memory().unwrap();
        let c = db.add_clip(text_clip("temp")).unwrap();
        db.delete_clip(c.id).unwrap();
        assert_eq!(db.count_clips().unwrap(), 0);
        assert!(matches!(db.delete_clip(c.id), Err(Error::NotFound)));

        let pinned = db.add_clip(text_clip("pinned")).unwrap();
        db.set_pinned(pinned.id, true).unwrap();
        db.add_clip(text_clip("unpinned")).unwrap();
        assert_eq!(db.clear_clips(false).unwrap(), 1); // only unpinned removed
        assert_eq!(db.count_clips().unwrap(), 1);
        db.clear_clips(true).unwrap();
        assert_eq!(db.count_clips().unwrap(), 0);
    }

    #[test]
    fn snippet_folder_and_snippet_crud() {
        let db = Database::open_in_memory().unwrap();
        let folder = db.add_folder("Email").unwrap();
        let s = db
            .add_snippet(Some(folder.id), "Signature", "Best,\nRon")
            .unwrap();
        assert_eq!(db.list_snippets(Some(folder.id)).unwrap().len(), 1);

        db.update_snippet(s.id, "Signature", "Cheers,\nRon")
            .unwrap();
        assert_eq!(db.get_snippet(s.id).unwrap().content, "Cheers,\nRon");

        // Deleting the folder cascades to its snippets.
        db.delete_folder(folder.id).unwrap();
        assert_eq!(db.list_snippets(None).unwrap().len(), 0);
    }

    #[test]
    fn search_snippets_matches_title_and_content() {
        let db = Database::open_in_memory().unwrap();
        db.add_snippet(None, "Greeting", "Hello there").unwrap();
        db.add_snippet(None, "Address", "221B Baker Street")
            .unwrap();
        assert_eq!(db.search_snippets("hello", 10).unwrap().len(), 1);
        assert_eq!(db.search_snippets("baker", 10).unwrap().len(), 1);
        assert_eq!(db.search_snippets("", 10).unwrap().len(), 2);
    }

    #[test]
    fn settings_upsert() {
        let db = Database::open_in_memory().unwrap();
        assert_eq!(db.get_setting("theme").unwrap(), None);
        db.set_setting("theme", "dark").unwrap();
        db.set_setting("theme", "light").unwrap();
        assert_eq!(db.get_setting("theme").unwrap().as_deref(), Some("light"));
    }
}
