# Contributing to Cliplex

Thanks for your interest in improving Cliplex!

## Getting started

Install [Rust](https://www.rust-lang.org/tools/install), Node.js 20+, and the
[Tauri prerequisites](https://tauri.app/start/prerequisites/) for your OS, then:

```bash
npm install
npm run tauri dev
```

## Project layout

- `crates/cliplex-core` — OS-agnostic storage, search, models. Add logic here when
  it doesn't need OS APIs; it's the easiest layer to unit-test.
- `crates/cliplex-platform` — OS-specific clipboard access behind the
  `ClipboardBackend` trait. New OS backends go here.
- `src-tauri` — the Tauri app: commands, monitor, tray, windows.
- `frontend` — SolidJS UI (`App.tsx` is the panel, `Manager.tsx` is the
  snippets/settings window).

## Checks (must pass before a PR)

```bash
cargo fmt --all
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
npx tsc --noEmit
npm run build
```

CI runs these on macOS, Windows, and Linux.

## Guidelines

- Keep the **privacy guarantees** intact: no telemetry, no network calls.
- Prefer adding testable logic to `cliplex-core` over the Tauri layer.
- Match the existing code style; keep commits focused with clear messages.
- For new OS clipboard support, implement the `ClipboardBackend` trait and the
  capture/inject paths rather than special-casing the app layer.

## Good first issues

- Native Windows / Linux clipboard backends (change detection + concealed-format
  detection + active-window detection).
- List virtualization for very large histories.
- Image thumbnails / color swatches in the panel.
- Additional localizations.
