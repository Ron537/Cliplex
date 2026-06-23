# Contributing to Cliplex

Thanks for your interest in improving Cliplex!

## Getting started

Cliplex is a native macOS app built with Swift Package Manager (macOS 14+). You
need the Swift toolchain — either full Xcode, or the Command Line Tools
(`xcode-select --install`).

```bash
./scripts/build-app.sh   # build + bundle + sign, then `open build/Cliplex.app`
./scripts/test.sh        # run the test suite
```

## Project layout

- `Sources/CliplexKit` — testable, UI-independent core: storage (GRDB / SQLite +
  FTS5), models, search, clipboard capture, the monitor, capture/privacy filter,
  settings, accessibility, paste injection, and the panel layout logic. Put
  logic here when it doesn't need the view layer — it's the easiest part to unit
  test.
- `Sources/Cliplex` — the menu-bar agent: status item, global hotkey, the
  non-activating panel, the SwiftUI panel/manager views, theming, and the login
  item.
- `Tests/CliplexKitTests` — Swift Testing tests for the core.

## Checks (must pass before a PR)

```bash
swift build      # no warnings
./scripts/test.sh
```

CI runs `swift build` and `swift test` on macOS for every push and pull request.

## Conventions

- Keep UI-independent logic in `CliplexKit` and cover it with tests.
- Prefer small, well-documented types; comment the *why*, not the *what*.
- No telemetry or network calls — Cliplex is local-only by design.
