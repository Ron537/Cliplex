# Cliplex

A lightweight, privacy-first **clipboard manager** for macOS, Windows, and Linux —
clipboard history + snippets with **instant unified search**. A modern, faster,
cross-platform take on tools like Clipy.

> **Cliplex** = *Clipboard* + *multiplex*.

## Highlights

- **Unified panel** — one window shows your clipboard history and snippets; start
  typing to filter instantly, press <kbd>Enter</kbd> to paste.
- **Fast & light** — Rust core + SQLite/FTS5 search + a tiny SolidJS UI in a Tauri
  shell. Small bundle, low memory, quick startup.
- **Privacy by default** — concealed/password clips are ignored, you control an
  app-exclusion list, and there is **no telemetry and no network access**.
- **Cross-platform** — macOS, Windows, and Linux from a single codebase.

## Architecture

```
cliplex/
├── crates/
│   ├── cliplex-core/      # OS-agnostic: storage, search, models, dedup, pruning
│   └── cliplex-platform/  # OS-specific: clipboard monitor, concealed-type, paste
├── src-tauri/             # Tauri 2 shell: commands, tray, hotkey, panel window
└── frontend/              # SolidJS + TypeScript UI (built to ../dist)
```

## Tech stack

| Layer | Choice |
|-------|--------|
| Shell | Tauri 2 |
| Core / platform | Rust (Cargo workspace) |
| Storage & search | SQLite + FTS5 |
| Frontend | SolidJS + TypeScript + Vite |

## Development

Prerequisites: [Rust](https://www.rust-lang.org/tools/install), Node.js 20+, and the
[Tauri system prerequisites](https://tauri.app/start/prerequisites/) for your OS.

```bash
npm install        # install frontend deps
npm run tauri dev  # run the app (builds Rust + serves the UI)
```

Build a release bundle:

```bash
npm run tauri build
```

## License

MIT
