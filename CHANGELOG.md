# Changelog

All notable changes to Cliplex are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-07-02

### Features

- Pause and resume clipboard capture from the menu-bar menu; the icon dims while paused.
- Optionally clear your history on quit (Settings → Privacy). Pinned clips are kept.
- Install via Homebrew: `brew install --cask ron537/tap/cliplex`.
- New Cliplex app icon and a matching menu-bar mark.

## [0.1.0] - 2026-07-01

First public release.

### Features

- **Clipboard history** — text, rich text, images, files, and color swatches
  with most-recently-used ordering and pinning.
- **Snippets** — reusable text organized into folders, with `{clipboard}`
  expansion at paste time.
- **Quick actions** — open a URL, app, or path, or transform the clipboard
  (Base64, JSON pretty/minify, URL-encode/decode, case, trim, SHA-256).
- **Instant search** — SQLite FTS5 as-you-type across history, snippets, and
  actions.
- **Cursor-anchored quick panel** (⌘⇧V) — non-activating, opens at the mouse,
  with an optional compact row mode.
- **Unified Library** window to manage snippets and actions side by side.
- **Per-item & per-folder global shortcuts** for snippets and actions.
- **Privacy by default** — concealed/transient/auto-generated clips and a
  configurable app-exclusion list (password managers) are never stored; the
  database is entirely local with no network access or telemetry.
- Native macOS menu-bar app (AppKit + SwiftUI), bundled fonts, light/dark theme.

[Unreleased]: https://github.com/Ron537/Cliplex/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/Ron537/Cliplex/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/Ron537/Cliplex/releases/tag/v0.1.0
