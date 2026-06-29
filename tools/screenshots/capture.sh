#!/usr/bin/env bash
#
# Regenerate the marketing screenshots in assets/screenshots/ from a clean,
# generic demo dataset (tools/screenshots/seed.sql) — never your real clipboard.
#
# How it works:
#   1. Builds Cliplex.app with the opt-in `CLIPLEX_SCREENSHOTS` flag, which
#      compiles in a tiny capture hook (excluded from every normal/release build).
#   2. Creates a throwaway SQLite database (via CLIPLEX_DB_PATH) and seeds it.
#   3. Launches the app once per surface; the hook renders that window to a PNG
#      using NSView.cacheDisplay (no Screen Recording permission required) and
#      quits.
#
# Usage:
#   ./tools/screenshots/capture.sh            # writes to assets/screenshots/
#   ./tools/screenshots/capture.sh /tmp/out   # custom output directory
#
# Run this for every major release to keep the README visuals current.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$HERE"

OUT_DIR="${1:-assets/screenshots}"
SEED="tools/screenshots/seed.sql"
DEMO_DB="$(mktemp -d)/cliplex-demo.db"
SHOT_DIR="$(mktemp -d)"
TARGETS=(library settings panel)

command -v sqlite3 >/dev/null || { echo "error: sqlite3 not found"; exit 1; }

echo "==> quitting any running Cliplex"
osascript -e 'quit app "Cliplex"' >/dev/null 2>&1 || true
sleep 1

echo "==> building Cliplex.app with screenshot tooling"
CLIPLEX_SCREENSHOTS=1 ./scripts/build-app.sh >/dev/null
BIN="build/Cliplex.app/Contents/MacOS/Cliplex"

echo "==> creating + seeding demo database"
# A first run against the empty path lets the app create the schema (+ FTS).
CLIPLEX_DB_PATH="$DEMO_DB" CLIPLEX_SCREENSHOT=library \
  CLIPLEX_SCREENSHOT_DIR="$(mktemp -d)" "$BIN" >/dev/null 2>&1 &
for _ in $(seq 1 30); do
  if sqlite3 "$DEMO_DB" "SELECT 1 FROM snippets LIMIT 1;" >/dev/null 2>&1; then break; fi
  sleep 0.5
done
sqlite3 "$DEMO_DB" < "$SEED"
echo "    seeded: $(sqlite3 "$DEMO_DB" 'SELECT count(*) FROM snippets') snippets, \
$(sqlite3 "$DEMO_DB" 'SELECT count(*) FROM actions') actions, \
$(sqlite3 "$DEMO_DB" 'SELECT count(*) FROM clips') clips"

echo "==> capturing"
mkdir -p "$OUT_DIR"
for target in "${TARGETS[@]}"; do
  CLIPLEX_DB_PATH="$DEMO_DB" CLIPLEX_SCREENSHOT="$target" \
    CLIPLEX_SCREENSHOT_DIR="$SHOT_DIR" "$BIN" >/dev/null 2>&1 &
  # The hook renders after ~1.5s then self-terminates; give it margin.
  for _ in $(seq 1 16); do
    [ -f "$SHOT_DIR/$target.png" ] && break
    sleep 0.5
  done
  if [ -f "$SHOT_DIR/$target.png" ]; then
    cp "$SHOT_DIR/$target.png" "$OUT_DIR/$target.png"
    echo "    $OUT_DIR/$target.png"
  else
    echo "    WARNING: $target.png was not produced"
  fi
done

echo "==> done. Rebuild a normal app with: ./scripts/build-app.sh"
