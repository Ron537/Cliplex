# Cliplex

A lightweight, privacy-first **clipboard history + snippets** manager for macOS.
A fast, native menu-bar app: instant full-text search, a panel that opens right
at your cursor, snippet folders, and one-keystroke paste. No telemetry, nothing
leaves your machine.

## Highlights

- **Clipboard history** — text, rich text, images, files, and color swatches,
  with most-recently-used ordering and pinning.
- **Snippets** — reusable text organized into folders, shown as a collapsible
  tree.
- **Instant search** — SQLite FTS5 as-you-type over both history and snippets.
- **Cursor-anchored panel** — a non-activating panel that opens where your mouse
  is and never steals focus, so paste lands in the app you were using.
- **Quick paste** — ⌘1–⌘0 for the top items; ⏎ to paste the selection.
- **Privacy by default** — concealed/password clips and configured apps are
  never stored; the database is entirely local.

## Stack

- **Swift** (Swift Package Manager), macOS 14+
- **AppKit** menu-bar agent + **SwiftUI** content
- **[GRDB.swift](https://github.com/groue/GRDB.swift)** — SQLite + FTS5
- No App Sandbox (a clipboard manager must read the global pasteboard and
  synthesize ⌘V via Accessibility)

## Project layout

| Path | Purpose |
|------|---------|
| `Sources/CliplexKit/` | Testable, UI-independent core: storage (`Database`), models, FTS `Search`, `MacClipboard`, `ClipboardMonitor`, `Capture` (privacy filter), `Settings`, `Accessibility`, `Paste` (CGEvent ⌘V), `PanelLayout` |
| `Sources/Cliplex/` | The menu-bar app: status item, `CarbonHotKey`, `PanelController`, SwiftUI panel + manager windows, `Theme`, `LoginItem` |
| `Tests/CliplexKitTests/` | Swift Testing suite |
| `Resources/` | `Info.plist`, `Cliplex.entitlements` |
| `scripts/` | Build/bundle/sign and test helpers |
| `docs/` | Research and design references |

## Build & run

```bash
# Build, bundle, and sign Cliplex.app (creates a self-signed dev cert on first run)
./scripts/build-app.sh
open build/Cliplex.app

# Run the tests
./scripts/test.sh
```

The keyboard shortcut to open the panel is **⌘⇧V**. Auto-paste needs
**Accessibility** permission (System Settings → Privacy & Security →
Accessibility); the app signs with a stable self-signed certificate so the grant
persists across rebuilds.

### Toolchain notes (Command Line Tools, no full Xcode)

The scripts inject what the Command Line Tools toolchain needs; if you invoke
`swift` directly you may need them too:

- A `safe.bareRepository=all` git override (the machine's global config may set
  it to `explicit`, which blocks SwiftPM's bare dependency repos).
- Framework/library search paths for the Swift Testing runtime — see
  `scripts/test.sh`.

With full Xcode installed, `swift build` / `swift test` work without extra flags.

## Privacy

See [PRIVACY.md](PRIVACY.md). In short: everything is stored locally in
`~/Library/Application Support/com.rborysowski.cliplex/cliplex.db`, there is no
network access, and password-manager / concealed clips are ignored.

## License

[MIT](LICENSE).
