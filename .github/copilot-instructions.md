# Copilot instructions for Cliplex

Cliplex is a native macOS **menu-bar clipboard manager** (history + snippets +
quick actions, with FTS5 search). Pure Swift; AppKit agent shell + SwiftUI
content; local-only, no telemetry, no network.

## Build, run, test

Always export the git override first (the machine's global git config sets
`safe.bareRepository=explicit`, which blocks SwiftPM's bare dependency repos):

```bash
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all
```

- **Build:** `swift build` (the scripts inject the env above for you).
- **Build + bundle + sign + run:** `./scripts/build-app.sh && open build/Cliplex.app`.
- **Tests:** `./scripts/test.sh` — *not* `swift test` directly. The active
  toolchain is the **Command Line Tools** (no full Xcode), so the script points
  the compiler/linker at the Swift Testing runtime framework paths. It forwards
  args, so run a **single test/suite** with `--filter`:
  ```bash
  ./scripts/test.sh --filter SearchTests           # one suite
  ./scripts/test.sh --filter emptyInputYieldsNil    # one test
  ```
- There is **no linter**; CONTRIBUTING requires a warning-free `swift build` plus
  `./scripts/test.sh`. CI runs both on `macos-15`.
- **Release (free, ad-hoc):** `./scripts/package-release.sh` → `dist/Cliplex-*.dmg`.
  Tagging `v*` triggers `.github/workflows/release.yml`. See `RELEASING.md`.

## Architecture (the big picture)

Two SPM targets, deliberately split:

- **`Sources/CliplexKit/`** — UI-independent, fully testable core. `ClipStore`
  (`Database.swift`, GRDB/SQLite + FTS5 kept in sync by triggers), `Models`,
  `Search`, `MacClipboard`, `ClipboardMonitor`, `Capture` (privacy filter),
  `Settings`, `Accessibility`, `Paste` (synthesizes ⌘V via CGEvent),
  `ActionLogic`, `PanelLayout`, `SnippetArchive`. **Put new logic here and unit-test it.**
- **`Sources/Cliplex/`** — the AppKit/SwiftUI menu-bar app. No business logic that
  belongs in the kit.

Key flow & seams (require reading several files):

- **Lifecycle:** `main.swift` sets `.accessory` activation (menu-bar agent, no
  Dock icon) and installs `AppDelegate`, which owns the status item, hotkeys,
  the panel, and the Library/Settings windows.
- **`AppServices`** is the single bridge between the UI and `CliplexKit`: it owns
  the `ClipStore`, the `ClipboardMonitor`, and cached `AppSettings`, and exposes
  every action the UI performs. UI layers never touch `ClipStore` directly.
- **Capture is poll-based:** macOS has no pasteboard event API, so
  `ClipboardMonitor` polls `NSPasteboard.changeCount`. On a new clip it stores
  via `ClipStore` and posts `.cliplexHistoryChanged`. Open windows refresh by
  observing `.cliplexHistoryChanged` / `.cliplexSettingsChanged` — that
  NotificationCenter pair is the app's refresh mechanism.
- **The quick panel (⌘⇧V):** `PanelController` shows a non-activating `NSPanel`
  at the cursor that never steals focus; rows come from `PanelLayout.DisplayRow`.
- **Library window** composes two existing view models: `LibraryViewModel` wraps
  `ManagerViewModel` (snippets) + `ActionsViewModel` (actions) and re-publishes
  their changes — reuse them rather than re-querying the store.
- **Dynamic global shortcuts:** `ShortcutCenter` (a `@MainActor` singleton)
  registers per-snippet/per-action/per-folder hotkeys via the
  `KeyboardShortcuts` package using `Name("cliplex_<kind>_<id>")`. `onKeyUp`
  appends handlers, so registration is guarded to run once per name; call
  `reset(kind:id:)` when deleting an item.

## Conventions specific to this codebase

- **Testing:** Swift Testing (`import Testing`, `@Suite`, `@Test`), not XCTest.
  `ClipStore` has an in-memory `init()` for tests.
- **Fonts:** never `Font.system(...)`. Use the bundled-font helpers in
  `Fonts.swift`: `Font.ui` (Hanken Grotesk, body), `Font.display` (Bricolage
  Grotesque, headings/wordmark), `Font.mono` (JetBrains Mono). Fonts live in
  `Resources/Fonts/` (auto-registered via Info.plist `ATSApplicationFontsPath`);
  `build-app.sh` copies them — keep their `licenses/` (SIL OFL) shipping too.
- **Colors:** use semantic tokens from `Theme` (e.g. `Theme.accent`,
  `snippetAccent` teal, `actionAccent` violet), which resolve per light/dark
  appearance. Don't hardcode `Color(...)`.
- **Privacy is a hard rule:** no network calls, no telemetry, no analytics —
  ever. `Capture` drops concealed/transient/auto-generated pasteboard types and
  clips from `defaultExcludedApps` (password managers). Don't weaken this.
- **Data continuity:** `SettingsKey` values and the SQLite schema/`user_version`
  intentionally match an earlier Rust/Tauri build so existing databases open
  seamlessly. Don't rename keys or break the schema casually; note stale
  references to "Rust/Tauri" in comments — the app is now pure Swift.
- **DB location & override:** `~/Library/Application Support/com.rborysowski.cliplex/cliplex.db`.
  Set `CLIPLEX_DB_PATH` to point at a throwaway DB (used by tests and tooling).
- **Concurrency:** UI/app types are `@MainActor`; kit value types are `Sendable`.

## Gotchas

- `swift test` fails on the CLT toolchain without the framework paths — use
  `./scripts/test.sh`.
- The `KeyboardShortcuts` dependency is pinned `1.12.0..<1.16.0` (≥1.16 uses
  `#Preview` macros the CLT toolchain can't build). Don't bump past that.
- `build-app.sh` signs with a **stable self-signed cert** so the Accessibility
  grant (needed for auto-paste) survives rebuilds; release builds sign **ad-hoc**
  (`SIGN_IDENTITY=-`). Auto-paste needs Accessibility permission granted once.
- **Screenshot tooling** (`tools/screenshots/`, `ScreenshotMode.swift`) is gated
  behind the `CLIPLEX_SCREENSHOTS` compile flag and is **excluded from normal/
  release builds** — never reference it from shipping code paths.

## Versioning and changelog policy

Cliplex follows [Semantic Versioning](https://semver.org/) and keeps a
[Keep a Changelog](https://keepachangelog.com/)-style `CHANGELOG.md`. Treat the
changelog as **part of every user-facing change**, maintained in the *same
commit* — the user shouldn't have to remember it.

When a change is user-visible, before pushing:

1. Pick the bump from the staged changes:
   - **PATCH** — bug fixes, refactors, docs/CI-only, dependency bumps with no
     behavior change, performance tweaks.
   - **MINOR** — new user-visible features, settings, shortcuts, actions/transforms.
   - **MAJOR** — breaking changes to the DB schema/`SettingsKey` shape or the
     snippet-archive format. Pre-1.0 these may land in a MINOR bump, but call
     them out explicitly.
2. Update **both** `CFBundleShortVersionString` and `CFBundleVersion` in
   `Resources/Info.plist` (surgically — don't let PlistBuddy reformat the file;
   the Settings footer reads this value live).
3. Move the entries from `[Unreleased]` into a new dated section
   (`## [x.y.z] - YYYY-MM-DD`), refresh the comparison links at the bottom, and
   re-create an empty `[Unreleased]`.
4. Keep the bump in the same commit as the change.
5. After a release-worthy version, suggest tagging `vX.Y.Z` so the release
   workflow publishes the DMG.

Skip the bump only when the user says so (infra-only / WIP push).

### Changelog content rules (customer-facing)

`CHANGELOG.md` is read by **end users**, not contributors — write from what they
will notice, not what changed in the code.

- Use **only** these sections, in this order, omitting empties: `### Features`,
  `### Improvements`, `### Bug Fixes`, `### Performance`.
- No `Internal`, `Refactor`, `Chores`, `Security`, or `CI` sections unless the
  user actually experiences it.
- One short bullet per entry (one line ideally). Lead with the benefit; cut file
  names, type/IPC/store names, line counts, and code-review attribution. No "we
  replaced X with Y."
- Replace internal jargon with the user-facing surface ("the quick panel", "the
  Library window", "Settings → Appearance").
- The same rules apply to `[Unreleased]` entries.

