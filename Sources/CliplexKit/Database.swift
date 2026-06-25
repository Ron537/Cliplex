import Foundation
import CryptoKit
import GRDB

/// Errors surfaced by ``ClipStore``.
public enum StoreError: Error, Equatable {
    case notFound
    case invalid(String)
}

/// SQLite-backed storage for clipboard history, snippets, and settings.
///
/// Uses SQLite with FTS5 full-text indexes (kept in sync via triggers) for the
/// instant as-you-type search that powers Cliplex's panel. The database is
/// entirely local; nothing is ever sent over the network.
///
/// The schema is created with `IF NOT EXISTS`, so this opens cleanly on a fresh
/// database *and* on one previously created by the Rust/Tauri build (same
/// tables), giving seamless data continuity.
public final class ClipStore {
    private let dbQueue: DatabaseQueue

    /// Opens (creating if needed) the database at `path` and sets up the schema.
    public init(path: String) throws {
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
        }
        dbQueue = try DatabaseQueue(path: path, configuration: config)
        try setupSchema()
    }

    /// Opens an in-memory database (used for tests).
    public init() throws {
        dbQueue = try DatabaseQueue()
        try setupSchema()
    }

    private func setupSchema() throws {
        try dbQueue.write { db in
            try db.execute(sql: Self.schemaSQL)
            // Mark the schema version (matching the Rust build's `user_version`),
            // so a database first created by Cliplex is recognized as v1 by any
            // tool that gates migrations on it.
            try db.execute(sql: "PRAGMA user_version = 1")
        }
        migrateHashesIfNeeded()
    }

    /// The prior Rust build hashed clip content with BLAKE3; this build uses
    /// SHA-256. To keep deduplication working against an imported history, the
    /// first time we open such a database we recompute each clip's
    /// `content_hash` from its stored assets. Guarded by a settings flag so it
    /// runs at most once.
    ///
    /// This is best-effort and **never throws**: a failure here must not prevent
    /// the app from starting. Rows whose recomputed hash would collide with
    /// another row (genuine duplicate content the old build didn't dedupe) are
    /// left untouched rather than violating the `UNIQUE(content_hash)`
    /// constraint.
    private func migrateHashesIfNeeded() {
        do {
            try dbQueue.write { db in
                let done = try String.fetchOne(
                    db, sql: "SELECT value FROM settings WHERE key = ?", arguments: ["hash_algo"])
                guard done != "sha256" else { return }

                let ids = try Int64.fetchAll(db, sql: "SELECT id FROM clips ORDER BY id")
                for id in ids {
                    let assets = try Row.fetchAll(
                        db,
                        sql: "SELECT uti, bytes, idx FROM clip_assets WHERE clip_id = ? ORDER BY idx",
                        arguments: [id]
                    ).map { ClipAsset(uti: $0["uti"], bytes: $0["bytes"], idx: $0["idx"]) }
                    guard !assets.isEmpty else { continue }

                    let newHash = Self.hashAssets(assets)
                    let current = try String.fetchOne(
                        db, sql: "SELECT content_hash FROM clips WHERE id = ?", arguments: [id])
                    if current == newHash { continue }

                    // Leave genuine duplicates in place rather than colliding.
                    let collides = try Int64.fetchOne(
                        db,
                        sql: "SELECT id FROM clips WHERE content_hash = ? AND id <> ? LIMIT 1",
                        arguments: [newHash, id]) != nil
                    if collides { continue }

                    try db.execute(
                        sql: "UPDATE clips SET content_hash = ? WHERE id = ?",
                        arguments: [newHash, id])
                }

                try db.execute(
                    sql: """
                        INSERT INTO settings (key, value) VALUES ('hash_algo', 'sha256')
                        ON CONFLICT(key) DO UPDATE SET value = excluded.value
                        """)
            }
        } catch {
            // Non-fatal: the app still works; dedup of legacy clips may be
            // imperfect until they age out of history.
        }
    }

    // MARK: - Clipboard history

    /// Inserts a clip, or — if identical content already exists — bumps it to
    /// the top of the history. Returns the resulting stored clip.
    @discardableResult
    public func addClip(_ new: NewClip) throws -> Clip {
        guard !new.assets.isEmpty else {
            throw StoreError.invalid("clip has no assets")
        }
        let hash = Self.hashAssets(new.assets)

        return try dbQueue.write { db in
            // Strictly-increasing recency stamp so most-recently-used ordering
            // is deterministic even when multiple clips arrive within the same
            // millisecond (real wall-clock time is kept for created_at).
            let maxUpdated = try Int64.fetchOne(
                db, sql: "SELECT COALESCE(MAX(updated_at), 0) FROM clips") ?? 0
            let now = max(nowMillis(), maxUpdated + 1)

            if let id = try Int64.fetchOne(
                db, sql: "SELECT id FROM clips WHERE content_hash = ?", arguments: [hash]) {
                try db.execute(
                    sql: "UPDATE clips SET updated_at = ? WHERE id = ?",
                    arguments: [now, id])
                return try Self.fetchClip(db, id: id)
            }

            try db.execute(
                sql: """
                    INSERT INTO clips (content_hash, kind, preview, source_app, pinned, created_at, updated_at)
                    VALUES (?, ?, ?, ?, 0, ?, ?)
                    """,
                arguments: [hash, new.kind.rawValue, new.preview, new.sourceApp, now, now])
            let clipID = db.lastInsertedRowID

            for (i, asset) in new.assets.enumerated() {
                let idx = asset.idx != 0 ? asset.idx : Int64(i)
                try db.execute(
                    sql: "INSERT INTO clip_assets (clip_id, uti, bytes, idx) VALUES (?, ?, ?, ?)",
                    arguments: [clipID, asset.uti, asset.bytes, idx])
            }
            return try Self.fetchClip(db, id: clipID)
        }
    }

    /// Returns a single clip by id.
    public func clip(id: Int64) throws -> Clip {
        try dbQueue.read { db in try Self.fetchClip(db, id: id) }
    }

    /// Lists clips, pinned first then most-recently-used.
    public func listClips(limit: Int64, offset: Int64 = 0) throws -> [Clip] {
        try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, content_hash, kind, preview, source_app, pinned, created_at, updated_at
                    FROM clips
                    ORDER BY pinned DESC, updated_at DESC, id DESC
                    LIMIT ? OFFSET ?
                    """,
                arguments: [limit, offset]
            ).map(Self.clip(from:))
        }
    }

    /// Full-text search over clip previews. Falls back to a plain listing when
    /// the query has no usable tokens.
    public func searchClips(_ query: String, limit: Int64) throws -> [Clip] {
        guard let fts = Search.buildFTSQuery(query) else {
            return try listClips(limit: limit)
        }
        return try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT c.id, c.content_hash, c.kind, c.preview, c.source_app, c.pinned, c.created_at, c.updated_at
                    FROM clips c
                    JOIN clips_fts f ON c.id = f.rowid
                    WHERE clips_fts MATCH ?
                    ORDER BY c.pinned DESC, bm25(clips_fts), c.updated_at DESC, c.id DESC
                    LIMIT ?
                    """,
                arguments: [fts, limit]
            ).map(Self.clip(from:))
        }
    }

    /// Returns the format payloads for a clip, ordered by index.
    public func clipAssets(clipID: Int64) throws -> [ClipAsset] {
        try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT uti, bytes, idx FROM clip_assets WHERE clip_id = ? ORDER BY idx",
                arguments: [clipID]
            ).map { row in
                ClipAsset(uti: row["uti"], bytes: row["bytes"], idx: row["idx"])
            }
        }
    }

    /// Pins or unpins a clip so it is exempt from pruning and shown first.
    public func setPinned(id: Int64, pinned: Bool) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE clips SET pinned = ? WHERE id = ?",
                arguments: [pinned ? 1 : 0, id])
            if db.changesCount == 0 { throw StoreError.notFound }
        }
    }

    /// Deletes a single clip (and its assets, via cascade).
    public func deleteClip(id: Int64) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM clips WHERE id = ?", arguments: [id])
            if db.changesCount == 0 { throw StoreError.notFound }
        }
    }

    /// Clears history. When `includePinned` is false, pinned clips are kept.
    @discardableResult
    public func clearClips(includePinned: Bool) throws -> Int {
        try dbQueue.write { db in
            if includePinned {
                try db.execute(sql: "DELETE FROM clips")
            } else {
                try db.execute(sql: "DELETE FROM clips WHERE pinned = 0")
            }
            return db.changesCount
        }
    }

    /// Removes the oldest unpinned clips, keeping at most `maxItems` of them.
    @discardableResult
    public func pruneClips(maxItems: Int64) throws -> Int {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    DELETE FROM clips
                    WHERE pinned = 0
                      AND id NOT IN (
                        SELECT id FROM clips WHERE pinned = 0
                        ORDER BY updated_at DESC, id DESC LIMIT ?
                      )
                    """,
                arguments: [max(maxItems, 0)])
            return db.changesCount
        }
    }

    /// Total number of clips (for diagnostics/tests).
    public func countClips() throws -> Int64 {
        try dbQueue.read { db in
            try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM clips") ?? 0
        }
    }

    /// Number of pinned clips. Used so the panel can show `maxHistory` unpinned
    /// clips *plus* all pinned ones, matching what pruning actually retains.
    public func countPinned() throws -> Int64 {
        try dbQueue.read { db in
            try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM clips WHERE pinned = 1") ?? 0
        }
    }

    // MARK: - Snippet folders

    /// Creates a snippet folder, appended after existing folders.
    @discardableResult
    public func addFolder(name: String) throws -> SnippetFolder {
        try dbQueue.write { db in
            let order = try Int64.fetchOne(
                db, sql: "SELECT COALESCE(MAX(sort_order), -1) + 1 FROM snippet_folders") ?? 0
            try db.execute(
                sql: "INSERT INTO snippet_folders (name, sort_order, created_at) VALUES (?, ?, ?)",
                arguments: [name, order, nowMillis()])
            return try Self.fetchFolder(db, id: db.lastInsertedRowID)
        }
    }

    /// Returns a single folder by id.
    public func folder(id: Int64) throws -> SnippetFolder {
        try dbQueue.read { db in try Self.fetchFolder(db, id: id) }
    }

    /// Lists folders in display order.
    public func listFolders() throws -> [SnippetFolder] {
        try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT id, name, sort_order, created_at FROM snippet_folders ORDER BY sort_order, id"
            ).map(Self.folder(from:))
        }
    }

    /// Renames a folder.
    public func renameFolder(id: Int64, name: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE snippet_folders SET name = ? WHERE id = ?",
                arguments: [name, id])
            if db.changesCount == 0 { throw StoreError.notFound }
        }
    }

    /// Deletes a folder and its snippets (cascade).
    public func deleteFolder(id: Int64) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM snippet_folders WHERE id = ?", arguments: [id])
            if db.changesCount == 0 { throw StoreError.notFound }
        }
    }

    // MARK: - Snippets

    /// Creates a snippet, appended within its folder.
    @discardableResult
    public func addSnippet(folderID: Int64?, title: String, content: String) throws -> Snippet {
        try dbQueue.write { db in
            let order = try Int64.fetchOne(
                db,
                sql: "SELECT COALESCE(MAX(sort_order), -1) + 1 FROM snippets WHERE folder_id IS ?",
                arguments: [folderID]) ?? 0
            let now = nowMillis()
            try db.execute(
                sql: """
                    INSERT INTO snippets (folder_id, title, content, sort_order, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: [folderID, title, content, order, now, now])
            return try Self.fetchSnippet(db, id: db.lastInsertedRowID)
        }
    }

    /// Returns a single snippet by id.
    public func snippet(id: Int64) throws -> Snippet {
        try dbQueue.read { db in try Self.fetchSnippet(db, id: id) }
    }

    /// Lists snippets, optionally filtered to a folder.
    public func listSnippets(folderID: Int64?) throws -> [Snippet] {
        try dbQueue.read { db in
            if let folderID {
                return try Row.fetchAll(
                    db,
                    sql: """
                        SELECT id, folder_id, title, content, sort_order, created_at, updated_at
                        FROM snippets WHERE folder_id IS ? ORDER BY sort_order, id
                        """,
                    arguments: [folderID]
                ).map(Self.snippet(from:))
            }
            return try Row.fetchAll(
                db,
                sql: """
                    SELECT id, folder_id, title, content, sort_order, created_at, updated_at
                    FROM snippets ORDER BY folder_id, sort_order, id
                    """
            ).map(Self.snippet(from:))
        }
    }

    /// Updates a snippet's title and content.
    public func updateSnippet(id: Int64, title: String, content: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE snippets SET title = ?, content = ?, updated_at = ? WHERE id = ?",
                arguments: [title, content, nowMillis(), id])
            if db.changesCount == 0 { throw StoreError.notFound }
        }
    }

    /// Deletes a snippet.
    public func deleteSnippet(id: Int64) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM snippets WHERE id = ?", arguments: [id])
            if db.changesCount == 0 { throw StoreError.notFound }
        }
    }

    /// Persists a new folder display order (assigns `sort_order = position`).
    public func setFolderOrder(_ orderedIDs: [Int64]) throws {
        try dbQueue.write { db in
            for (index, id) in orderedIDs.enumerated() {
                try db.execute(
                    sql: "UPDATE snippet_folders SET sort_order = ? WHERE id = ?",
                    arguments: [index, id])
            }
        }
    }

    /// Persists a new snippet display order (assigns `sort_order = position`).
    public func setSnippetOrder(_ orderedIDs: [Int64]) throws {
        try dbQueue.write { db in
            for (index, id) in orderedIDs.enumerated() {
                try db.execute(
                    sql: "UPDATE snippets SET sort_order = ? WHERE id = ?",
                    arguments: [index, id])
            }
        }
    }

    /// Full-text search over snippet titles and contents.
    public func searchSnippets(_ query: String, limit: Int64) throws -> [Snippet] {
        try dbQueue.read { db in
            guard let fts = Search.buildFTSQuery(query) else {
                return try Row.fetchAll(
                    db,
                    sql: """
                        SELECT id, folder_id, title, content, sort_order, created_at, updated_at
                        FROM snippets ORDER BY folder_id, sort_order, id LIMIT ?
                        """,
                    arguments: [limit]
                ).map(Self.snippet(from:))
            }
            return try Row.fetchAll(
                db,
                sql: """
                    SELECT s.id, s.folder_id, s.title, s.content, s.sort_order, s.created_at, s.updated_at
                    FROM snippets s
                    JOIN snippets_fts f ON s.id = f.rowid
                    WHERE snippets_fts MATCH ?
                    ORDER BY bm25(snippets_fts)
                    LIMIT ?
                    """,
                arguments: [fts, limit]
            ).map(Self.snippet(from:))
        }
    }

    // MARK: - Settings

    /// Reads a setting value by key.
    public func setting(_ key: String) throws -> String? {
        try dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM settings WHERE key = ?", arguments: [key])
        }
    }

    /// Inserts or updates a setting.
    public func setSetting(_ key: String, _ value: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO settings (key, value) VALUES (?, ?)
                    ON CONFLICT(key) DO UPDATE SET value = excluded.value
                    """,
                arguments: [key, value])
        }
    }

    // MARK: - Row mapping

    private static func fetchClip(_ db: Database, id: Int64) throws -> Clip {
        guard let row = try Row.fetchOne(
            db,
            sql: """
                SELECT id, content_hash, kind, preview, source_app, pinned, created_at, updated_at
                FROM clips WHERE id = ?
                """,
            arguments: [id]) else {
            throw StoreError.notFound
        }
        return clip(from: row)
    }

    private static func fetchFolder(_ db: Database, id: Int64) throws -> SnippetFolder {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT id, name, sort_order, created_at FROM snippet_folders WHERE id = ?",
            arguments: [id]) else {
            throw StoreError.notFound
        }
        return folder(from: row)
    }

    private static func fetchSnippet(_ db: Database, id: Int64) throws -> Snippet {
        guard let row = try Row.fetchOne(
            db,
            sql: """
                SELECT id, folder_id, title, content, sort_order, created_at, updated_at
                FROM snippets WHERE id = ?
                """,
            arguments: [id]) else {
            throw StoreError.notFound
        }
        return snippet(from: row)
    }

    private static func clip(from row: Row) -> Clip {
        Clip(
            id: row["id"],
            contentHash: row["content_hash"],
            kind: ClipKind.lenient(row["kind"]),
            preview: row["preview"],
            sourceApp: row["source_app"],
            pinned: (row["pinned"] as Int64) != 0,
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    private static func folder(from row: Row) -> SnippetFolder {
        SnippetFolder(
            id: row["id"],
            name: row["name"],
            sortOrder: row["sort_order"],
            createdAt: row["created_at"]
        )
    }

    private static func snippet(from row: Row) -> Snippet {
        Snippet(
            id: row["id"],
            folderId: row["folder_id"],
            title: row["title"],
            content: row["content"],
            sortOrder: row["sort_order"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    /// Computes the content hash used to deduplicate clips (SHA-256 over each
    /// asset's UTI and bytes, with separators).
    private static func hashAssets(_ assets: [ClipAsset]) -> String {
        var hasher = SHA256()
        for asset in assets {
            hasher.update(data: Data(asset.uti.utf8))
            hasher.update(data: Data([0]))
            hasher.update(data: asset.bytes)
            hasher.update(data: Data([0]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Initial schema: tables, FTS5 indexes, and sync triggers. Idempotent so it
    /// is safe to run on every open and on databases created by the Rust build.
    private static let schemaSQL = """
    CREATE TABLE IF NOT EXISTS clips (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        content_hash  TEXT NOT NULL UNIQUE,
        kind          TEXT NOT NULL,
        preview       TEXT NOT NULL,
        source_app    TEXT,
        pinned        INTEGER NOT NULL DEFAULT 0,
        created_at    INTEGER NOT NULL,
        updated_at    INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_clips_order ON clips(pinned DESC, updated_at DESC);

    CREATE TABLE IF NOT EXISTS clip_assets (
        id       INTEGER PRIMARY KEY AUTOINCREMENT,
        clip_id  INTEGER NOT NULL REFERENCES clips(id) ON DELETE CASCADE,
        uti      TEXT NOT NULL,
        bytes    BLOB NOT NULL,
        idx      INTEGER NOT NULL DEFAULT 0
    );
    CREATE INDEX IF NOT EXISTS idx_clip_assets_clip ON clip_assets(clip_id);

    CREATE VIRTUAL TABLE IF NOT EXISTS clips_fts USING fts5(
        preview,
        content='clips',
        content_rowid='id'
    );
    CREATE TRIGGER IF NOT EXISTS clips_ai AFTER INSERT ON clips BEGIN
        INSERT INTO clips_fts(rowid, preview) VALUES (new.id, new.preview);
    END;
    CREATE TRIGGER IF NOT EXISTS clips_ad AFTER DELETE ON clips BEGIN
        INSERT INTO clips_fts(clips_fts, rowid, preview) VALUES('delete', old.id, old.preview);
    END;
    CREATE TRIGGER IF NOT EXISTS clips_au AFTER UPDATE ON clips BEGIN
        INSERT INTO clips_fts(clips_fts, rowid, preview) VALUES('delete', old.id, old.preview);
        INSERT INTO clips_fts(rowid, preview) VALUES (new.id, new.preview);
    END;

    CREATE TABLE IF NOT EXISTS snippet_folders (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        name        TEXT NOT NULL,
        sort_order  INTEGER NOT NULL DEFAULT 0,
        created_at  INTEGER NOT NULL
    );

    CREATE TABLE IF NOT EXISTS snippets (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        folder_id   INTEGER REFERENCES snippet_folders(id) ON DELETE CASCADE,
        title       TEXT NOT NULL,
        content     TEXT NOT NULL,
        sort_order  INTEGER NOT NULL DEFAULT 0,
        created_at  INTEGER NOT NULL,
        updated_at  INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_snippets_folder ON snippets(folder_id, sort_order, id);

    CREATE VIRTUAL TABLE IF NOT EXISTS snippets_fts USING fts5(
        title,
        content,
        content='snippets',
        content_rowid='id'
    );
    CREATE TRIGGER IF NOT EXISTS snippets_ai AFTER INSERT ON snippets BEGIN
        INSERT INTO snippets_fts(rowid, title, content) VALUES (new.id, new.title, new.content);
    END;
    CREATE TRIGGER IF NOT EXISTS snippets_ad AFTER DELETE ON snippets BEGIN
        INSERT INTO snippets_fts(snippets_fts, rowid, title, content)
        VALUES('delete', old.id, old.title, old.content);
    END;
    CREATE TRIGGER IF NOT EXISTS snippets_au AFTER UPDATE ON snippets BEGIN
        INSERT INTO snippets_fts(snippets_fts, rowid, title, content)
        VALUES('delete', old.id, old.title, old.content);
        INSERT INTO snippets_fts(rowid, title, content) VALUES (new.id, new.title, new.content);
    END;

    CREATE TABLE IF NOT EXISTS settings (
        key    TEXT PRIMARY KEY,
        value  TEXT NOT NULL
    );
    """
}
