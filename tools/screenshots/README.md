# Screenshot tooling

Reusable pipeline for regenerating the marketing screenshots in
[`assets/screenshots/`](../../assets/screenshots) from a **clean, generic demo
dataset** — never your real clipboard history. Run it for every major release so
the README visuals stay current.

```bash
./tools/screenshots/capture.sh
```

This (re)builds the app, seeds a throwaway database, captures each surface, and
writes `library.png`, `settings.png`, and `panel.png` into `assets/screenshots/`.

## How it stays out of the shipped app

The actual capture needs to run **inside** the app process (it renders real
SwiftUI views), but none of it ships:

- All capture code is guarded by `#if CLIPLEX_SCREENSHOTS` — see
  [`Sources/Cliplex/ScreenshotMode.swift`](../../Sources/Cliplex/ScreenshotMode.swift)
  and the one gated hook in `AppDelegate`.
- That flag is passed **only** by this script
  (`CLIPLEX_SCREENSHOTS=1 ./scripts/build-app.sh` → `-Xswiftc -DCLIPLEX_SCREENSHOTS`).
- Release, CI, and distributed builds never set it, so the screenshot code is
  not compiled into the app bundle at all.

Rendering uses `NSView.cacheDisplay`, which asks the view to draw itself into a
bitmap. Unlike `screencapture`/`CGWindowList`, it needs **no Screen Recording
permission**, so it works headlessly (including in CI).

## Environment variables

| Variable | Used by | Purpose |
|----------|---------|---------|
| `CLIPLEX_SCREENSHOTS` | `scripts/build-app.sh` | Compile in the capture hook |
| `CLIPLEX_SCREENSHOT` | the app | Which surface to capture: `library` \| `settings` \| `panel` |
| `CLIPLEX_SCREENSHOT_DIR` | the app | Output directory for the PNG |
| `CLIPLEX_DB_PATH` | the app | Point Cliplex at a throwaway database (general override; also used by tests) |

## Editing the demo data

The demo content lives in [`seed.sql`](seed.sql) — folders, snippets, actions,
and clipboard history with realistic but fictional content (system apps only, so
source-app names resolve everywhere). Edit it and re-run `capture.sh`.

## Requirements

- macOS with the Swift toolchain (Command Line Tools or Xcode).
- `sqlite3` on `PATH` (ships with macOS).
