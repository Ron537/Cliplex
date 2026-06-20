# Clipy: How It Works, Features, and the Competitive Landscape

> Research report on **Clipy** (https://github.com/Clipy/Clipy) — a macOS clipboard manager — covering its architecture, feature set, supporting library ecosystem, how it compares to alternatives, what makes it better than others, and what is missing.

---

## Executive Summary

**Clipy** is a free, open-source (MIT) **clipboard-history + snippets menu-bar app for macOS**, written in Swift/AppKit and descended from the discontinued **ClipMenu**.[^1][^2] It works by **polling `NSPasteboard.general.changeCount` every 500 ms** (via an RxSwift timer), snapshotting any newly copied content into a model, persisting it, and surfacing it through dynamically built menu-bar `NSMenu`s triggered by **global hotkeys** (its own *Magnet* library).[^3][^4] Its signature differentiator is **snippet folders** — organized, hotkey-pasteable boilerplate text — which most free competitors lack.[^5]

Clipy is genuinely popular (**~8,600 GitHub stars**, 1.29M downloads of v1.2.1 alone) but was **effectively unmaintained from October 2018 to May 2026** — no native Apple Silicon build, no history search, no sync, and a dated cascading-menu UI.[^6][^7] In 2026 the original maintainer (**Econa77 / Shunsuke Furubayashi**) publicly revived the project: a notarized Universal Binary (v1.2.2 → v1.3.0), a **Realm → SQLite (GRDB) migration**, a CocoaPods → Swift Package Manager migration, and FTS5 search infrastructure already built at the data layer.[^8][^9][^10]

Its closest free rivals are **Maccy** (search-first, **~20,000 stars** — now the community-default recommendation) and **CopyQ** (cross-platform, scriptable, **~11,800 stars**).[^11][^12] Commercial options (**Paste**, **Raycast**, **Alfred**, **Pastebot**) add cloud sync, OCR, link previews, and polished UIs that Clipy lacks.[^13][^14][^15] **What Clipy does better:** snippet folders, lightweight native simplicity, free/MIT, and broader-macOS support. **What's missing:** built-in search, cloud/device sync, scripting, a modern UI, and (until 2026) active maintenance and Apple Silicon support.[^11][^16]

---

## 1. What Is Clipy? (Concept & Lineage)

Clipy is a **clipboard extension app**: it remembers what you copy so you can paste from a history, and lets you store reusable **snippets**.[^1] It is a menu-bar agent (no Dock icon) that you summon with a global hotkey.

**Lineage — ClipMenu → Clipy:** Clipy is a from-scratch Swift reimplementation inspired by **ClipMenu** (Naotaka Morimoto's free macOS clipboard manager, discontinued ~2013, later open-sourced). Clipy's README explicitly thanks `naotaka/ClipMenu`, the repo carries the `clipmenu` topic, and the app's internal main-menu identifier is literally `"ClipMenu"`.[^2] Clipy was created **June 2015** as an open-source "remake."[^6]

| Attribute | Value |
|---|---|
| Repo | [`Clipy/Clipy`](https://github.com/Clipy/Clipy) |
| Language | Swift / AppKit (Cocoa) |
| License | MIT (icons separately copyrighted) |
| Stars / Forks | ~8,626 / ~810 |
| Created | 2015-06-20 |
| Requirement | macOS 13 Ventura+ (revived build) |
| Last stable before revival | **1.2.1 — Oct 2018** |
| Revival | 1.2.2 draft (Jun 2026), v1.3.0 (~Jun 2026) |
| Funding | OpenCollective |

---

## 2. How Clipy Works (Architecture & Data Flow)

Clipy's source lives under `Clipy/Sources/`, organized by responsibility: `Services/`, `Repositories/`, `Database/`, `Models/`, `Managers/`, `Preferences/`, `Snippets/`.[^3]

```mermaid
graph TD
    subgraph Capture
        A[NSPasteboard.general] -->|RxSwift 500ms poll<br/>changeCount| B[ClipService.create]
        SS[Screeen ScreenShotObserver] -->|new screenshot| B
        B -->|filter enabled storeTypes<br/>skip excluded/concealed apps| C[PasteboardContent<br/>assets + SHA-256 hash]
    end
    subgraph Storage
        C -->|save| D[PasteboardHistoryRepository]
        D -->|@Dependency / @FetchAll| E[(SQLite via GRDB / SQLiteData<br/>+ FTS5 search tables)]
        E -. legacy migrate .-> R[(Realm - legacy)]
    end
    subgraph Retrieval
        E -->|observeHistories Combine| F[MenuManager]
        SR[SnippetRepository] --> F
        F --> G[NSStatusItem menu-bar menus<br/>clip / history / snippet]
    end
    subgraph Paste
        HK[HotKeyService - Magnet<br/>global hotkeys] -->|pop up| G
        G -->|select item| H[PasteService]
        H -->|writeObjects to pasteboard| A
        H -->|synth Cmd+V via CGEvent<br/>Sauce layout-correct keycode| I[Frontmost App]
    end
```

### 2.1 Clipboard capture (monitoring)
macOS has **no event-driven pasteboard API**, so Clipy **polls**. `ClipService.startMonitoring()` runs an `Observable<Int>.interval(.milliseconds(500))` timer, reads `NSPasteboard.general.changeCount`, compares to a cached `BehaviorRelay<Int>`, and on change calls `create()`.[^3] `create()` reads pasteboard types, filters them against the user's enabled `storeTypes` (and ignores concealed/transient password types per nspasteboard.org conventions), skips excluded apps via `ExcludeAppService`, then builds a `PasteboardContent`.[^3][^17] Screenshots are captured separately through the **Screeen** observer.[^4][^18]

`PasteboardContent` models a clip as an array of `Asset { type, data }` plus a **SHA-256 hash** of all type+data used as the content identity / dedup key, with lazily derived `stringValue`, `thumbnailImage`, and `colorCodeImage` (hex color swatch).[^3]

### 2.2 Storage
`ClipService.save()` computes the history ID from the content hash and honors three prefs — `copySameHistory` (skip duplicates), `overwriteSameHistory` (reuse hash vs. random UUID), and empty-string skipping — then calls `PasteboardHistoryRepository.save(...)`.[^3] The repository uses Point-Free's `@Dependency(\.defaultDatabase)` + `@FetchAll` to write/read via **SQLiteData/GRDB**, upserting a `PasteboardHistory` row plus child `PasteboardHistoryAsset` rows (one per type) and an optional thumbnail asset.[^3]

The DB lives at `<AppSupport>/<bundleID>/sqlite.db`. The schema (`@Table` structs) includes `PasteboardHistory`, `PasteboardHistoryAsset`, `PasteboardHistoryThumbnailAsset`, `SnippetFolder`/`Snippet`, and **FTS5 search tables** (`PasteboardHistorySearch`, `SnippetSearch`).[^9] History pruning runs every 30 min via `deleteOverflowingHistories(maxHistorySize:)`.[^3]

**Migration:** The codebase is **mid-migration**. Realm (the historical store) is now legacy-only; on first launch without `sqlite.db`, Clipy runs `migrateFromRealmToSQLiteData()`. Both stacks are still bundled.[^3][^8]

### 2.3 Retrieval (menu-bar UX)
`MenuManager` owns the `NSStatusItem` and three menus (`clipMenu`, `historyMenu`, `snippetMenu`). It rebuilds them reactively by subscribing to repository Combine publishers plus ~13 UserDefaults keys (throttled at 1 s). Items can show number key-equivalents (1–9/0), tooltips, inline image thumbnails, and color swatches.[^3]

### 2.4 Paste
Selecting a menu item fetches `PasteboardContent` by ID and calls `PasteService`, which writes content back to `NSPasteboard.general` (or plain-text only if a modifier is held), then **synthesizes ⌘V** using `CGEvent` keyboard events. The virtual key code comes from **Sauce** (`Sauce.shared.keyCode(for: .v, ...)`) so it's correct across keyboard layouts (QWERTY/Dvorak). This requires **Accessibility permission**.[^3][^19]

### 2.5 Hotkeys
`HotKeyService` registers global hotkeys via **Magnet**. Defaults: Main menu `⌘⇧V`, History `⌘⌃V`, Snippet `⌘⇧B`, plus optional Clear-History and per-snippet-folder hotkeys. KeyCombos are archived to UserDefaults. There's migration code from the old PTHotKey framework to Magnet (since v1.1.0).[^4][^20]

---

## 3. Feature Inventory

**Clipboard history:** configurable max size; multi-type storage with per-type opt-in; duplicate skip/overwrite/copy-again; clear-history menu item + hotkey + confirmation; reorder-after-paste.[^5][^21]

**Snippets (signature feature):** reusable text in **folders**, enable/disable, per-folder hotkeys, XML import/export, RTF preservation.[^5][^21]

**Supported data types:** `string`, `rtf`, `rtfd`, `pdf`, `filenames`, `url`, `tiff/png images` — each individually opt-in.[^5][^17]

**Menu UX:** three hotkeys/menus (main/history/snippet); inline vs. nested folding; numeric key equivalents (start at 0 or 1); title-length cap + tooltips; inline image thumbnails (configurable dims); color-code preview swatches.[^5][^3]

**Privacy/exclusion:** exclude specific apps (e.g., 1Password); ignore concealed/transient password pasteboard types; skip Universal Clipboard file URLs.[^5][^17]

**System integration:** launch-at-login (LoginServiceKit); synthetic-⌘V paste (Accessibility-gated, layout-aware via Sauce); Sparkle auto-update; auto-capture screenshots (Screeen); opt-in Firebase analytics/crash reporting.[^5][^4]

**Localization:** 6 languages — English, Japanese, German, Italian, Brazilian Portuguese, Simplified Chinese.[^5]

**Beta/modifier features:** paste-as-plain-text, delete-history-on-select, paste-and-delete.[^3]

---

## 4. The Clipy Library Ecosystem

A key reason Clipy "just works" is that the Clipy org extracted several reusable Swift libraries that form the foundation of any clipboard manager.[^22][^23]

| Library | Stars | License | Role | Status |
|---|---|---|---|---|
| [Magnet](https://github.com/Clipy/Magnet) | 451 | MIT | Global hotkeys (incl. Alfred-style double-tap), sandbox-safe | Active |
| [KeyHolder](https://github.com/Clipy/KeyHolder) | 421 | MIT | `RecordView` UI to record shortcuts (built on Magnet) | Active |
| [Sauce](https://github.com/Clipy/Sauce) | 94 | MIT | Keyboard-layout-aware keycode mapping (QWERTY/Dvorak) | Active |
| [Screeen](https://github.com/Clipy/Screeen) | 63 | MIT | Observe macOS screenshot events | Active |
| [LoginServiceKit](https://github.com/Clipy/LoginServiceKit) | 118 | Apache-2.0 | Launch-at-login management | **Archived** (deprecated API) |

**Third-party dependencies** (from the SPM `Package.resolved`):[^23]
- **RxSwift / RxCocoa 6.10.2** — the 500 ms pasteboard polling loop and reactive UserDefaults observation (the heart of monitoring).
- **GRDB.swift 7.10.0 + pointfreeco/sqlite-data 1.6.1 + swift-structured-queries** — the new SQLite persistence layer.
- **Realm-Swift 10.7.2** — legacy store, now migration-only.
- **swift-dependencies / swift-sharing (Point-Free)** — DI (`@Dependency`) and reactive DB observation (`@FetchAll`).
- **Sparkle 2.9.2** — auto-update. **PINCache 3.0.4** — legacy caching. **AEXML** — snippet XML import/export.
- **Firebase iOS SDK 12.14.0** — opt-out analytics/crash reporting (replaced Fabric/Crashlytics).
- **SwiftHEXColors / swift-tagged** — color swatches / type-safe IDs.

---

## 5. Competitive Landscape

### Verified comparison table

| Tool | Platform | License | Price | Stars | Maintained? |
|---|---|---|---|---|---|
| **Clipy** | macOS 13+ | MIT | Free | 8,626 | ✅ (revived 2026) |
| **Maccy** | macOS 14+ | MIT | Free | 20,373 | ✅ |
| **CopyQ** | Linux/Win/macOS | GPL-3.0 | Free | 11,857 | ✅ |
| **Flycut** | macOS/iOS | MIT | Free | 2,672 | ❌ (last 2022) |
| **Paste** | macOS/iOS | Closed | $29.99/yr or lifetime / Setapp | — | ✅ |
| **Pastebot** | macOS | Closed | ~$12.99 one-time | — | ✅ |
| **Raycast** | macOS | Closed | Free + Pro (~$8/mo) | — | ✅ |
| **Alfred** | macOS | Closed | Powerpack (one-time) | — | ✅ |
| **PasteNow** | macOS/iOS | Closed | Commercial (iCloud sync) | — | ✅ |

(Stars/dates from the GitHub API.)[^11][^12]

### Closest rivals

**Maccy** — the closest free competitor and **current community default**. Strengths Clipy lacks: **type-to-search / fuzzy filter**, keyboard-first navigation, modern native SwiftUI UI, pinning with permanent hotkeys, and strong privacy defaults (auto-ignores `org.nspasteboard.ConcealedType`, 1Password, etc.). Clipy beats it on **snippet folders** (Maccy has none) and supports **older macOS (13 vs. 14)**.[^11][^16]

**CopyQ** — the most *powerful* free option: cross-platform, **scriptable with a full CLI**, tabs, notes/tags, image/HTML/custom formats, Vim-like editor, advanced filtering. Clipy is simpler and more Mac-native; CopyQ's Qt UI is less "Mac-like" with a steeper learning curve.[^12]

**Raycast** — clipboard history bundled into a launcher; killer combo of **launcher + clipboard + snippets + sync** (Pro), encrypted local storage, color/link detection. Clipy is a lighter single-purpose app.[^13]

**Paste / Pastebot / Alfred / PasteNow** (commercial) — add **iCloud sync** (Paste/PasteNow/Raycast Pro), **OCR/link previews**, **pinboards/collections**, **paste-filter pipelines** (Pastebot), and **text expansion + clipboard merging** (Alfred). All exceed Clipy's feature set, at a price.[^13][^14][^15]

**Flycut** — simpler Jumpcut descendant, plain-text only, **effectively unmaintained** (last push Dec 2022). Clipy is more capable and now more active.[^11]

**Cross-platform/other-OS:** CopyQ (all), **GPaste / Pano / Klipper** (Linux), **Ditto / Windows Clipboard History Win+V** (Windows) — several offer network/cloud sync Clipy lacks.[^12]

---

## 6. What Makes Clipy Better — and What's Missing

### ✅ Where Clipy leads
- **Snippet folders** — organized, hotkey-pasteable boilerplate with RTF preservation; stronger than Maccy/Flycut/Raycast here.[^5][^16]
- **Free + open-source (MIT)** with no subscription, large installed base (1.29M downloads of one release).[^6][^7]
- **Lightweight, native Swift menu-bar simplicity** — the same virtues users praise in Maccy.[^16]
- **Broader macOS support** (13+) than Maccy (14+).[^11]
- A **clean reusable library ecosystem** (Magnet/KeyHolder/Sauce) that benefits the wider Swift community.[^22]

### ❌ Where Clipy lags / what's missing
- **No built-in history search / fuzzy search** — the #1 user request (issue #88, 69 reactions). Maccy/Raycast/Alfred all have it.[^16][^24]
- **No cloud / cross-device sync** — Paste, PasteNow, Raycast Pro, Windows, Ditto all sync; Clipy is local-only.[^7][^16]
- **No scripting/automation** — CopyQ leads decisively.[^12]
- **Dated cascading-menu UI** vs. Maccy/Raycast's searchable, keyboard-first windows.[^16]
- **Weaker privacy defaults historically** and **Firebase telemetry enabled by default** (opt-out); local history is **not encrypted**.[^7]
- **Polling-based monitoring** (500 ms) is an inherent CPU/latency trade-off (though shared by Maccy and others — it's a macOS platform limitation).[^3]
- **Was unmaintained ~7.7 years** and **lacked a native Apple Silicon build** until 2026 (Homebrew cask still pinned to 1.2.1 + Rosetta).[^7][^25]
- **Deprecated LoginServiceKit** for launch-at-login (not sandbox-compatible; Apple recommends `SMAppService`).[^22]
- Far **fewer stars/mindshare** than Maccy; rarely the top recommendation in 2024–2025 r/macapps threads.[^16]

---

## 7. The 2026 Revival Roadmap

After ~8 years dormant, maintainer **Econa77** publicly resumed development (issue [#590](https://github.com/Clipy/Clipy/issues/590), May 2026, 207 reactions).[^8]

**✅ Confirmed / shipped (2026):**
- Native **Apple Silicon / Universal Binary** (1.2.2 draft → v1.3.0, ~June 2026; Intel retained) — #603.[^25][^26]
- **Notarized** builds.[^8]
- **Realm → SQLite (GRDB/SQLiteData)** migration — #595, #607 (merged), motivated by Realm launch-crash bugs.[^9][^10]
- **CocoaPods → Swift Package Manager** — #597 (merged); min target raised to macOS 11.[^10]
- Opt-out Firebase Crashlytics; modernized paste handling; longer poll interval.[^8]
- Targeted for v1.3.0: **basic Universal Clipboard** support.[^8]

**🔜 Planned / strongly indicated (not yet shipped):**
- **History search** — canonical #88 reassigned to the maintainer (#496 folded in); **FTS5 tables + triggers already built and unit-tested** at the data layer, just not wired to UI.[^9][^24]
- **iCloud/CloudKit sync** — a working `SyncEngine` scaffold exists but is gated `startImmediately: false`; named as a post-1.3.0 goal. SQLiteData/GRDB was chosen partly to enable it.[^9][^10]
- **SwiftUI adoption** + app-icon redesign (post-1.3.0); improved localization workflow.[^8]

**❌ Still unaddressed:**
- No plan to replace deprecated **LoginServiceKit** with **SMAppService**.[^10]
- No **sandboxing** or **Mac App Store** plan.[^27]
- Search and CloudKit sync have **no committed release/date**.[^9]

---

## 8. Confidence Assessment

**High confidence (verified from primary sources — code, GitHub API, READMEs, release data):**
- Clipy's architecture, polling mechanism, paste flow, dependency graph, and library ecosystem (read directly from source on the `develop` branch).[^3][^4][^23]
- Feature set, license, lineage, star/fork counts, release dates, and the 2018→2026 maintenance gap.[^5][^6][^7]
- The 2026 roadmap items, FTS5 search infra, and CloudKit scaffold (read from issues, merged PRs, and schema/test files).[^8][^9][^10]
- Competitor star counts, platforms, and licensing (GitHub API + official sites).[^11][^12]

**Medium confidence (search-extracted, not full-page reads):**
- Reddit community-sentiment quotes and upvote counts were obtained via search-engine Q&A cards (Reddit blocked direct fetches). Direction (Maccy = current default) is consistent across multiple threads but individual quotes weren't verified against full pages.[^16]
- Some commercial-tool prices (e.g., Pastebot App Store price) are approximate.[^14]

**Low confidence / gaps (unverified this session):**
- Ditto (Windows), CrushClip, Klipper, CopyClip, and Jumpcut details (sites unreachable or not fetched) — treat as background context.[^12]
- Exact AlternativeTo like-counts for rivals (client-side rendered).
- OCR claims for individual tools were not independently verified.
- Specific default values (max history size, inline item counts) were not pulled from the defaults-registration file.

**Key assumptions:** Findings reflect the `develop` branch and the in-progress v1.3.0 work as of mid-June 2026; the historical "classic" Clipy (pre-2026) used a pure Carthage + Realm + RxSwift stack without the SQLite/Point-Free layer.

---

## Footnotes

[^1]: [Clipy/Clipy README](https://github.com/Clipy/Clipy/blob/develop/README.md) — "Clipboard extension app for macOS."
[^2]: README "Special Thanks" crediting [`naotaka/ClipMenu`](https://github.com/naotaka/ClipMenu); repo `clipmenu` topic; `Clipy/Sources/Constants.swift` (`Menu.clip = "ClipMenu"`).
[^3]: `Clipy/Sources/Services/ClipService.swift` (500 ms RxSwift poll of `changeCount`, `create()`, `save()`); `Clipy/Sources/Models/PasteboardContent.swift` (Asset + SHA-256); `Clipy/Sources/Repositories/PasteboardHistoryRepository.swift`; `Clipy/Sources/Managers/MenuManager.swift`; `Clipy/Sources/Services/PasteService.swift`; `Clipy/Sources/AppDelegate.swift` — all at commit `25f1eb889c6b484e3cd31f049e6be864ba108353`.
[^4]: `Clipy/Sources/Services/HotKeyService.swift:18-26,108-145` — Magnet `HotKey`/`HotKeyCenter`, default combos, PTHotKey→Magnet migration.
[^5]: `Clipy/Sources/Constants.swift` (UserDefaults/HotKey/Beta keys); `Clipy/Sources/Models/PasteboardAvailableType.swift:18-25`; clipy-app.com feature blurb.
[^6]: GitHub API `repos/Clipy/Clipy` — created 2015-06-20, stars 8,626, forks 810, MIT.
[^7]: GitHub API `repos/Clipy/Clipy/releases` — 1.2.1 published 2018-10-10 (1,299,315 downloads); [PRIVACY.md](https://raw.githubusercontent.com/Clipy/Clipy/develop/PRIVACY.md) (Firebase on by default; local history not encrypted).
[^8]: [Issue #590 — Resuming Clipy development](https://github.com/Clipy/Clipy/issues/590) (207 reactions; SPM migration; SQLite; notarization; iCloud sync named as post-1.3.0).
[^9]: `Clipy/Sources/Database/SQLiteDataSchema.swift:48-95` (FTS5 `PasteboardHistorySearch`/`SnippetSearch`); `SQLiteDataDatabase.swift:60-72` (CloudKit `SyncEngine`, `startImmediately:false`); `SQLiteDataMigrator.swift` (FTS5 virtual tables + triggers); `ClipyTests/Database/*Tests.swift`.
[^10]: [PR #607 — Add SQLiteData initial setup](https://github.com/Clipy/Clipy/pull/607) (merged); [Issue #595 — Migrate Realm→SQLite via GRDB](https://github.com/Clipy/Clipy/issues/595) (closed); [PR #597 — CocoaPods→SwiftPM](https://github.com/Clipy/Clipy/pull/597) (merged).
[^11]: GitHub API — [`p0deje/Maccy`](https://github.com/p0deje/Maccy) (20,373★, macOS 14+), [`TermiT/Flycut`](https://github.com/TermiT/Flycut) (2,672★, last push 2022-12-23).
[^12]: GitHub API — [`hluk/CopyQ`](https://github.com/hluk/CopyQ) (11,857★, GPL-3.0, cross-platform); AlternativeTo CopyQ description; GPaste/[Pano](https://github.com/oae/gnome-shell-pano) (Linux).
[^13]: [Raycast Clipboard History](https://www.raycast.com/core-features/clipboard-history); [Paste pricing](https://pasteapp.io/pricing) ($29.99/yr or lifetime / Setapp).
[^14]: [Pastebot](https://tapbots.com/pastebot/) (Quick Paste Menu, sequential paste, filters); [Alfred Clipboard](https://www.alfredapp.com/help/features/clipboard/) (retention, snippets, merging).
[^15]: [PasteNow](https://pastenow.app) (iCloud sync, lists, HEX color); ClipBook (clipbook.app).
[^16]: r/macapps threads — ["Which clipboard history app should I use?"](https://www.reddit.com/r/macapps/comments/1hihxdx/which_clipboard_history_app_should_i_use/) (top answer Maccy, 41 upvotes); ["Clipboard manager recommendations"](https://www.reddit.com/r/macapps/comments/1m5s1tn/clipboard_manager_app_recommendations_whywhy_nots/); [Maccy README](https://raw.githubusercontent.com/p0deje/Maccy/master/README.md); [AlternativeTo Clipy](https://alternativeto.net/software/clipy/about/) / [Maccy](https://alternativeto.net/software/maccy/about/). *(Reddit quotes via search-engine Q&A extraction, not full-page reads.)*
[^17]: `Clipy/Sources/Models/PasteboardAvailableType.swift:27-55` (concealed/transient type skipping, Universal Clipboard URL skip); `ExcludeAppService`.
[^18]: [`Clipy/Screeen`](https://github.com/Clipy/Screeen) README — `ScreenShotObserver`; `AppDelegate.swift:281-285`.
[^19]: [`Clipy/Sauce`](https://github.com/Clipy/Sauce) README — `Sauce.shared.keyCode(for:)` layout-correct keycodes; `PasteService.swift` synthetic ⌘V via `CGEvent`.
[^20]: [`Clipy/Magnet`](https://github.com/Clipy/Magnet) README — `KeyCombo`, `HotKey`, `HotKeyCenter`, double-tap support.
[^21]: clipy-app.com "主な機能"; `Constants.swift` snippet XML import/export + per-folder hotkeys.
[^22]: GitHub API for [`Clipy/Magnet`](https://github.com/Clipy/Magnet), [`Clipy/KeyHolder`](https://github.com/Clipy/KeyHolder), [`Clipy/Sauce`](https://github.com/Clipy/Sauce), [`Clipy/Screeen`](https://github.com/Clipy/Screeen), [`Clipy/LoginServiceKit`](https://github.com/Clipy/LoginServiceKit) (archived; README warns of deprecated pre-10.11 API, recommends SMAppService).
[^23]: `Clipy.xcodeproj/.../swiftpm/Package.resolved` — RxSwift 6.10.2, GRDB 7.10.0, sqlite-data 1.6.1, Realm 10.7.2, Sparkle 2.9.2, PINCache 3.0.4, Firebase 12.14.0, swift-dependencies 1.12.0.
[^24]: [Issue #88 — type to search history](https://github.com/Clipy/Clipy/issues/88) (69 reactions, assigned to maintainer); [Issue #496](https://github.com/Clipy/Clipy/issues/496) closed as duplicate of #88.
[^25]: [Issue #603 — Rosetta 2 EOL / Apple Silicon build](https://github.com/Clipy/Clipy/issues/603); Homebrew cask [`Casks/c/clipy.rb`](https://github.com/Homebrew/homebrew-cask/blob/master/Casks/c/clipy.rb) (version 1.2.1, `requires_rosetta`).
[^26]: Issue #590 maintainer comments confirming Universal Binary (Intel + Apple Silicon), v1.3.0 targeted ~June 20–22, 2026.
[^27]: No open issue/PR proposes sandboxing, Mac App Store distribution, or SMAppService migration (verified via targeted search on the repo).
