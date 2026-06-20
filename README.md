# Cliplex

**Cliplex** is a fast, private, cross-platform **clipboard manager** — clipboard
history and snippets in a single panel with **instant unified search**. A modern,
lightweight take on tools like Clipy.

> _Cliplex = **Clip**board + multi**plex**._

- ⚡️ **Fast & tiny** — Rust core + SQLite/FTS5 search + a ~38 KB SolidJS UI in a
  Tauri shell. The macOS app bundle is **~4.4 MB** (vs ~150 MB for Electron apps).
- 🔎 **One panel, instant search** — history and snippets together; just start
  typing to filter, press <kbd>Enter</kbd> to paste.
- 🧩 **Snippets** — reusable text organised into folders.
- 🔒 **Private by default** — no telemetry, no network. Password/concealed clips
  and common password managers are ignored automatically. See [PRIVACY.md](./PRIVACY.md).
- 🖥 **Cross-platform** — macOS, Windows, and Linux from one codebase.

## Usage

Press the global hotkey to summon the panel anywhere:

| Action | Shortcut |
|--------|----------|
| Open / close the panel | <kbd>⌘⇧V</kbd> (macOS) · <kbd>Ctrl⇧V</kbd> (Windows/Linux) |
| Move selection | <kbd>↑</kbd> / <kbd>↓</kbd> |
| Paste selected | <kbd>Enter</kbd> |
| Quick-paste Nth item | <kbd>⌘</kbd>/<kbd>Ctrl</kbd> + <kbd>1</kbd>–<kbd>9</kbd> |
| Delete selected clip | <kbd>⌘</kbd>/<kbd>Ctrl</kbd> + <kbd>⌫</kbd> |
| Pin / unpin clip | <kbd>⌘</kbd>/<kbd>Ctrl</kbd> + <kbd>P</kbd> |
| Switch filter (all / clipboard / snippets) | <kbd>Tab</kbd> |
| Close panel | <kbd>Esc</kbd> |

Start typing at any time to search. Manage snippets and preferences from the tray
menu → **Snippets & Settings…**.

The tray icon lives in your menu bar / system tray: left-click toggles the panel,
right-click opens the menu.

## Install

### From releases
Download the installer for your OS from the
[Releases](https://github.com/Ron537/cliplex/releases) page
(`.dmg` for macOS, `.msi`/`.exe` for Windows, `.AppImage`/`.deb`/`.rpm` for Linux).

### Build from source
Prerequisites: [Rust](https://www.rust-lang.org/tools/install), Node.js 20+, and
the [Tauri system prerequisites](https://tauri.app/start/prerequisites/) for your OS.

```bash
npm install
npm run tauri dev     # run in development
npm run tauri build   # produce an installer for your platform
```

### First-run permissions
To paste into other apps, Cliplex synthesizes the paste shortcut, which requires
**Accessibility** permission on macOS (System Settings → Privacy & Security →
Accessibility). On Linux/Wayland, input injection may require a compositor helper.

## Architecture

```
cliplex/
├── crates/
│   ├── cliplex-core/      # OS-agnostic: SQLite+FTS5 storage, search, models, pruning
│   └── cliplex-platform/  # OS-specific: clipboard monitor, concealed-type detection, paste injection
├── src-tauri/             # Tauri 2 shell: commands, tray, global hotkey, panel + manager windows
└── frontend/              # SolidJS + TypeScript UI (built to ../dist)
```

**How it works:** a background monitor watches the clipboard (native
`NSPasteboard` change-count on macOS; portable fallback elsewhere), filters out
concealed/excluded clips, and stores them in a local SQLite database with FTS5
full-text indexes. The SolidJS panel queries that database for instant search and
pastes the selection by writing it back to the clipboard and synthesizing the
paste keystroke.

| Layer | Choice |
|-------|--------|
| Shell | Tauri 2 |
| Core / platform | Rust (Cargo workspace) |
| Storage & search | SQLite + FTS5 (`rusqlite`) |
| Frontend | SolidJS + TypeScript + Vite |
| Paste injection | `enigo` |

## Development

```bash
# Rust
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
cargo fmt --all

# Frontend
npx tsc --noEmit
npm run build
```

See [CONTRIBUTING.md](./CONTRIBUTING.md).

## Privacy

Cliplex makes **no network requests** and collects **no telemetry**. History is
stored locally and is not yet encrypted at rest (rely on OS full-disk encryption;
optional SQLCipher is on the roadmap). Details in [PRIVACY.md](./PRIVACY.md).

## Roadmap

- Optional encryption at rest (SQLCipher)
- Native Windows/Linux clipboard backends (sequence-number change detection,
  concealed-format and active-window detection)
- List virtualization for very large histories
- Image thumbnails and color swatches in the panel

## License

MIT — see [LICENSE](./LICENSE).
