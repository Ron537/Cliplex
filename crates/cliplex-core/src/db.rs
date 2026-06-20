//! SQLite-backed storage for clipboard history, snippets, and settings.
//!
//! Uses SQLite with FTS5 full-text indexes (kept in sync via triggers) for the
//! instant as-you-type search that powers Cliplex's unified panel. The database
//! is entirely local; nothing is ever sent over the network.

use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};

use rusqlite::{params, Connection, OptionalExtension, Row};

use crate::error::{Error, Result};
use crate::models::{Clip, ClipAsset, ClipKind, NewClip, Snippet, SnippetFolder};
use crate::search::build_fts_query;

/// Current schema version. Bump and add a migration step when the schema changes.
const SCHEMA_VERSION: i64 = 1;

/// Returns the current time in Unix epoch milliseconds.
pub fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

/// Computes the content hash used to deduplicate clips.
fn hash_assets(assets: &[ClipAsset]) -> String {
    let mut hasher = blake3::Hasher::new();
    for asset in assets {
        hasher.update(asset.uti.as_bytes());
        hasher.update(&[0]);
        hasher.update(&asset.bytes);
        hasher.update(&[0]);
    }
    hasher.finalize().to_hex().to_string()
}

/// Handle to the Cliplex database.
pub struct Database {
    conn: Connection,
}

impl Database {
    /// Opens (creating if needed) the database at `path` and runs migrations.
    pub fn open<P: AsRef<Path>>(path: P) -> Result<Self> {
        let conn = Connection::open(path)?;
        conn.pragma_update(None, "journal_mode", "WAL")?;
        Self::from_conn(conn)
    }

    /// Opens an in-memory database (used for tests).
    pub fn open_in_memory() -> Result<Self> {
        Self::from_conn(Connection::open_in_memory()?)
    }

    fn from_conn(conn: Connection) -> Result<Self> {
        conn.pragma_update(None, "foreign_keys", "ON")?;
        conn.busy_timeout(std::time::Duration::from_secs(5))?;
        let db = Database { conn };
        db.migrate()?;
        Ok(db)
    }

    fn migrate(&self) -> Result<()> {
        let version: i64 = self
            .conn
            .pragma_query_value(None, "user_version", |r| r.get(0))?;
        if version < 1 {
            self.conn.execute_batch(SCHEMA_V1)?;
        }
        self.conn
            .pragma_update(None, "user_version", SCHEMA_VERSION)?;
        Ok(())
    }

    // ----- Clipboard history -------------------------------------------------

    /// Inserts a clip, or — if identical content already exists — bumps it to
    /// the top of the history. Returns the resulting stored clip.
    pub fn add_clip(&mut self, new: NewClip) -> Result<Clip> {
        if new.assets.is_empty() {
            return Err(Error::Invalid("clip has no assets".into()));
        }
        let hash = hash_assets(&new.assets);
        // Strictly-increasing recency stamp so most-recently-used ordering is
        // deterministic even when multiple clips arrive within the same
        // millisecond (real wall-clock time is kept for created_at).
        let now = self.next_recency()?;

        if let Some(id) = self.clip_id_by_hash(&hash)? {
            self.conn.execute(
                "UPDATE clips SET updated_at = ?1 WHERE id = ?2",
                params![now, id],
            )?;
            return self.get_clip(id);
        }

        let tx = self.conn.transaction()?;
        tx.execute(
            "INSERT INTO clips (content_hash, kind, preview, source_app, pinned, created_at, updated_at)
             VALUES (?1, ?2, ?3, ?4, 0, ?5, ?5)",
            params![hash, new.kind.as_str(), new.preview, new.source_app, now],
        )?;
        let clip_id = tx.last_insert_rowid();
        {
            let mut stmt = tx.prepare(
                "INSERT INTO clip_assets (clip_id, uti, bytes, idx) VALUES (?1, ?2, ?3, ?4)",
            )?;
            for (i, asset) in new.assets.iter().enumerate() {
                let idx = if asset.idx != 0 { asset.idx } else { i as i64 };
                stmt.execute(params![clip_id, asset.uti, asset.bytes, idx])?;
            }
        }
        tx.commit()?;
        self.get_clip(clip_id)
    }

    /// Returns a strictly-increasing recency value: at least the current time in
    /// milliseconds, but always greater than the newest existing `updated_at`.
    fn next_recency(&self) -> Result<i64> {
        let max: i64 =
            self.conn
                .query_row("SELECT COALESCE(MAX(updated_at), 0) FROM clips", [], |r| {
                    r.get(0)
                })?;
        Ok(now_ms().max(max + 1))
    }

    fn clip_id_by_hash(&self, hash: &str) -> Result<Option<i64>> {
        Ok(self
            .conn
            .query_row(
                "SELECT id FROM clips WHERE content_hash = ?1",
                params![hash],
                |r| r.get(0),
            )
            .optional()?)
    }

    /// Returns a single clip by id.
    pub fn get_clip(&self, id: i64) -> Result<Clip> {
        self.conn
            .query_row(
                "SELECT id, content_hash, kind, preview, source_app, pinned, created_at, updated_at
                 FROM clips WHERE id = ?1",
                params![id],
                map_clip,
            )
            .optional()?
            .ok_or(Error::NotFound)
    }

    /// Lists clips, pinned first then most-recently-used.
    pub fn list_clips(&self, limit: i64, offset: i64) -> Result<Vec<Clip>> {
        let mut stmt = self.conn.prepare(
            "SELECT id, content_hash, kind, preview, source_app, pinned, created_at, updated_at
             FROM clips
             ORDER BY pinned DESC, updated_at DESC, id DESC
             LIMIT ?1 OFFSET ?2",
        )?;
        let rows = stmt.query_map(params![limit, offset], map_clip)?;
        Ok(rows.collect::<rusqlite::Result<Vec<_>>>()?)
    }

    /// Full-text search over clip previews. Falls back to a plain listing when
    /// the query has no usable tokens.
    pub fn search_clips(&self, query: &str, limit: i64) -> Result<Vec<Clip>> {
        let Some(fts) = build_fts_query(query) else {
            return self.list_clips(limit, 0);
        };
        let mut stmt = self.conn.prepare(
            "SELECT c.id, c.content_hash, c.kind, c.preview, c.source_app, c.pinned, c.created_at, c.updated_at
             FROM clips c
             JOIN clips_fts f ON c.id = f.rowid
             WHERE clips_fts MATCH ?1
             ORDER BY c.pinned DESC, bm25(clips_fts), c.updated_at DESC, c.id DESC
             LIMIT ?2",
        )?;
        let rows = stmt.query_map(params![fts, limit], map_clip)?;
        Ok(rows.collect::<rusqlite::Result<Vec<_>>>()?)
    }

    /// Returns the format payloads for a clip, ordered by index.
    pub fn clip_assets(&self, clip_id: i64) -> Result<Vec<ClipAsset>> {
        let mut stmt = self
            .conn
            .prepare("SELECT uti, bytes, idx FROM clip_assets WHERE clip_id = ?1 ORDER BY idx")?;
        let rows = stmt.query_map(params![clip_id], |r| {
            Ok(ClipAsset {
                uti: r.get(0)?,
                bytes: r.get(1)?,
                idx: r.get(2)?,
            })
        })?;
        Ok(rows.collect::<rusqlite::Result<Vec<_>>>()?)
    }

    /// Pins or unpins a clip so it is exempt from pruning and shown first.
    pub fn set_pinned(&self, id: i64, pinned: bool) -> Result<()> {
        let n = self.conn.execute(
            "UPDATE clips SET pinned = ?1 WHERE id = ?2",
            params![pinned as i64, id],
        )?;
        if n == 0 {
            return Err(Error::NotFound);
        }
        Ok(())
    }

    /// Deletes a single clip (and its assets, via cascade).
    pub fn delete_clip(&self, id: i64) -> Result<()> {
        let n = self
            .conn
            .execute("DELETE FROM clips WHERE id = ?1", params![id])?;
        if n == 0 {
            return Err(Error::NotFound);
        }
        Ok(())
    }

    /// Clears history. When `include_pinned` is false, pinned clips are kept.
    pub fn clear_clips(&self, include_pinned: bool) -> Result<usize> {
        let n = if include_pinned {
            self.conn.execute("DELETE FROM clips", [])?
        } else {
            self.conn
                .execute("DELETE FROM clips WHERE pinned = 0", [])?
        };
        Ok(n)
    }

    /// Removes the oldest unpinned clips, keeping at most `max_items` of them.
    pub fn prune_clips(&self, max_items: i64) -> Result<usize> {
        let n = self.conn.execute(
            "DELETE FROM clips
             WHERE pinned = 0
               AND id NOT IN (
                 SELECT id FROM clips WHERE pinned = 0
                 ORDER BY updated_at DESC, id DESC LIMIT ?1
               )",
            params![max_items.max(0)],
        )?;
        Ok(n)
    }

    /// Total number of clips (for diagnostics/tests).
    pub fn count_clips(&self) -> Result<i64> {
        Ok(self
            .conn
            .query_row("SELECT COUNT(*) FROM clips", [], |r| r.get(0))?)
    }

    // ----- Snippet folders ---------------------------------------------------

    /// Creates a snippet folder, appended after existing folders.
    pub fn add_folder(&self, name: &str) -> Result<SnippetFolder> {
        let now = now_ms();
        let order: i64 = self.conn.query_row(
            "SELECT COALESCE(MAX(sort_order), -1) + 1 FROM snippet_folders",
            [],
            |r| r.get(0),
        )?;
        self.conn.execute(
            "INSERT INTO snippet_folders (name, sort_order, created_at) VALUES (?1, ?2, ?3)",
            params![name, order, now],
        )?;
        self.get_folder(self.conn.last_insert_rowid())
    }

    /// Returns a single folder by id.
    pub fn get_folder(&self, id: i64) -> Result<SnippetFolder> {
        self.conn
            .query_row(
                "SELECT id, name, sort_order, created_at FROM snippet_folders WHERE id = ?1",
                params![id],
                map_folder,
            )
            .optional()?
            .ok_or(Error::NotFound)
    }

    /// Lists folders in display order.
    pub fn list_folders(&self) -> Result<Vec<SnippetFolder>> {
        let mut stmt = self.conn.prepare(
            "SELECT id, name, sort_order, created_at FROM snippet_folders ORDER BY sort_order, id",
        )?;
        let rows = stmt.query_map([], map_folder)?;
        Ok(rows.collect::<rusqlite::Result<Vec<_>>>()?)
    }

    /// Renames a folder.
    pub fn rename_folder(&self, id: i64, name: &str) -> Result<()> {
        let n = self.conn.execute(
            "UPDATE snippet_folders SET name = ?1 WHERE id = ?2",
            params![name, id],
        )?;
        if n == 0 {
            return Err(Error::NotFound);
        }
        Ok(())
    }

    /// Deletes a folder and its snippets (cascade).
    pub fn delete_folder(&self, id: i64) -> Result<()> {
        let n = self
            .conn
            .execute("DELETE FROM snippet_folders WHERE id = ?1", params![id])?;
        if n == 0 {
            return Err(Error::NotFound);
        }
        Ok(())
    }

    // ----- Snippets ----------------------------------------------------------

    /// Creates a snippet, appended within its folder.
    pub fn add_snippet(
        &self,
        folder_id: Option<i64>,
        title: &str,
        content: &str,
    ) -> Result<Snippet> {
        let now = now_ms();
        let order: i64 = self.conn.query_row(
            "SELECT COALESCE(MAX(sort_order), -1) + 1 FROM snippets WHERE folder_id IS ?1",
            params![folder_id],
            |r| r.get(0),
        )?;
        self.conn.execute(
            "INSERT INTO snippets (folder_id, title, content, sort_order, created_at, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?5)",
            params![folder_id, title, content, order, now],
        )?;
        self.get_snippet(self.conn.last_insert_rowid())
    }

    /// Returns a single snippet by id.
    pub fn get_snippet(&self, id: i64) -> Result<Snippet> {
        self.conn
            .query_row(
                "SELECT id, folder_id, title, content, sort_order, created_at, updated_at
                 FROM snippets WHERE id = ?1",
                params![id],
                map_snippet,
            )
            .optional()?
            .ok_or(Error::NotFound)
    }

    /// Lists snippets, optionally filtered to a folder.
    pub fn list_snippets(&self, folder_id: Option<i64>) -> Result<Vec<Snippet>> {
        let (sql, has_filter) = match folder_id {
            Some(_) => (
                "SELECT id, folder_id, title, content, sort_order, created_at, updated_at
                 FROM snippets WHERE folder_id IS ?1 ORDER BY sort_order, id",
                true,
            ),
            None => (
                "SELECT id, folder_id, title, content, sort_order, created_at, updated_at
                 FROM snippets ORDER BY folder_id, sort_order, id",
                false,
            ),
        };
        let mut stmt = self.conn.prepare(sql)?;
        let rows = if has_filter {
            stmt.query_map(params![folder_id], map_snippet)?
                .collect::<rusqlite::Result<Vec<_>>>()?
        } else {
            stmt.query_map([], map_snippet)?
                .collect::<rusqlite::Result<Vec<_>>>()?
        };
        Ok(rows)
    }

    /// Updates a snippet's title and content.
    pub fn update_snippet(&self, id: i64, title: &str, content: &str) -> Result<()> {
        let n = self.conn.execute(
            "UPDATE snippets SET title = ?1, content = ?2, updated_at = ?3 WHERE id = ?4",
            params![title, content, now_ms(), id],
        )?;
        if n == 0 {
            return Err(Error::NotFound);
        }
        Ok(())
    }

    /// Deletes a snippet.
    pub fn delete_snippet(&self, id: i64) -> Result<()> {
        let n = self
            .conn
            .execute("DELETE FROM snippets WHERE id = ?1", params![id])?;
        if n == 0 {
            return Err(Error::NotFound);
        }
        Ok(())
    }

    /// Full-text search over snippet titles and contents.
    pub fn search_snippets(&self, query: &str, limit: i64) -> Result<Vec<Snippet>> {
        let Some(fts) = build_fts_query(query) else {
            let mut stmt = self.conn.prepare(
                "SELECT id, folder_id, title, content, sort_order, created_at, updated_at
                 FROM snippets ORDER BY folder_id, sort_order, id LIMIT ?1",
            )?;
            let rows = stmt.query_map(params![limit], map_snippet)?;
            return Ok(rows.collect::<rusqlite::Result<Vec<_>>>()?);
        };
        let mut stmt = self.conn.prepare(
            "SELECT s.id, s.folder_id, s.title, s.content, s.sort_order, s.created_at, s.updated_at
             FROM snippets s
             JOIN snippets_fts f ON s.id = f.rowid
             WHERE snippets_fts MATCH ?1
             ORDER BY bm25(snippets_fts)
             LIMIT ?2",
        )?;
        let rows = stmt.query_map(params![fts, limit], map_snippet)?;
        Ok(rows.collect::<rusqlite::Result<Vec<_>>>()?)
    }

    // ----- Settings ----------------------------------------------------------

    /// Reads a setting value by key.
    pub fn get_setting(&self, key: &str) -> Result<Option<String>> {
        Ok(self
            .conn
            .query_row(
                "SELECT value FROM settings WHERE key = ?1",
                params![key],
                |r| r.get(0),
            )
            .optional()?)
    }

    /// Inserts or updates a setting.
    pub fn set_setting(&self, key: &str, value: &str) -> Result<()> {
        self.conn.execute(
            "INSERT INTO settings (key, value) VALUES (?1, ?2)
             ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            params![key, value],
        )?;
        Ok(())
    }
}

fn map_clip(row: &Row<'_>) -> rusqlite::Result<Clip> {
    let kind: String = row.get(2)?;
    let pinned: i64 = row.get(5)?;
    Ok(Clip {
        id: row.get(0)?,
        content_hash: row.get(1)?,
        kind: ClipKind::from_str_lenient(&kind),
        preview: row.get(3)?,
        source_app: row.get(4)?,
        pinned: pinned != 0,
        created_at: row.get(6)?,
        updated_at: row.get(7)?,
    })
}

fn map_folder(row: &Row<'_>) -> rusqlite::Result<SnippetFolder> {
    Ok(SnippetFolder {
        id: row.get(0)?,
        name: row.get(1)?,
        sort_order: row.get(2)?,
        created_at: row.get(3)?,
    })
}

fn map_snippet(row: &Row<'_>) -> rusqlite::Result<Snippet> {
    Ok(Snippet {
        id: row.get(0)?,
        folder_id: row.get(1)?,
        title: row.get(2)?,
        content: row.get(3)?,
        sort_order: row.get(4)?,
        created_at: row.get(5)?,
        updated_at: row.get(6)?,
    })
}

/// Initial schema: tables, FTS5 indexes, and sync triggers.
const SCHEMA_V1: &str = r#"
CREATE TABLE clips (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    content_hash  TEXT NOT NULL UNIQUE,
    kind          TEXT NOT NULL,
    preview       TEXT NOT NULL,
    source_app    TEXT,
    pinned        INTEGER NOT NULL DEFAULT 0,
    created_at    INTEGER NOT NULL,
    updated_at    INTEGER NOT NULL
);
CREATE INDEX idx_clips_order ON clips(pinned DESC, updated_at DESC);

CREATE TABLE clip_assets (
    id       INTEGER PRIMARY KEY AUTOINCREMENT,
    clip_id  INTEGER NOT NULL REFERENCES clips(id) ON DELETE CASCADE,
    uti      TEXT NOT NULL,
    bytes    BLOB NOT NULL,
    idx      INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX idx_clip_assets_clip ON clip_assets(clip_id);

CREATE VIRTUAL TABLE clips_fts USING fts5(
    preview,
    content='clips',
    content_rowid='id'
);
CREATE TRIGGER clips_ai AFTER INSERT ON clips BEGIN
    INSERT INTO clips_fts(rowid, preview) VALUES (new.id, new.preview);
END;
CREATE TRIGGER clips_ad AFTER DELETE ON clips BEGIN
    INSERT INTO clips_fts(clips_fts, rowid, preview) VALUES('delete', old.id, old.preview);
END;
CREATE TRIGGER clips_au AFTER UPDATE ON clips BEGIN
    INSERT INTO clips_fts(clips_fts, rowid, preview) VALUES('delete', old.id, old.preview);
    INSERT INTO clips_fts(rowid, preview) VALUES (new.id, new.preview);
END;

CREATE TABLE snippet_folders (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT NOT NULL,
    sort_order  INTEGER NOT NULL DEFAULT 0,
    created_at  INTEGER NOT NULL
);

CREATE TABLE snippets (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    folder_id   INTEGER REFERENCES snippet_folders(id) ON DELETE CASCADE,
    title       TEXT NOT NULL,
    content     TEXT NOT NULL,
    sort_order  INTEGER NOT NULL DEFAULT 0,
    created_at  INTEGER NOT NULL,
    updated_at  INTEGER NOT NULL
);
CREATE INDEX idx_snippets_folder ON snippets(folder_id, sort_order, id);

CREATE VIRTUAL TABLE snippets_fts USING fts5(
    title,
    content,
    content='snippets',
    content_rowid='id'
);
CREATE TRIGGER snippets_ai AFTER INSERT ON snippets BEGIN
    INSERT INTO snippets_fts(rowid, title, content) VALUES (new.id, new.title, new.content);
END;
CREATE TRIGGER snippets_ad AFTER DELETE ON snippets BEGIN
    INSERT INTO snippets_fts(snippets_fts, rowid, title, content)
    VALUES('delete', old.id, old.title, old.content);
END;
CREATE TRIGGER snippets_au AFTER UPDATE ON snippets BEGIN
    INSERT INTO snippets_fts(snippets_fts, rowid, title, content)
    VALUES('delete', old.id, old.title, old.content);
    INSERT INTO snippets_fts(rowid, title, content) VALUES (new.id, new.title, new.content);
END;

CREATE TABLE settings (
    key    TEXT PRIMARY KEY,
    value  TEXT NOT NULL
);
"#;
