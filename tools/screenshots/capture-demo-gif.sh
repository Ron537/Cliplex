#!/usr/bin/env bash
#
# Regenerate an animated demo GIF from the generic demo dataset, rendered from
# the REAL app via NSView.cacheDisplay (no Screen Recording permission needed),
# then stitched into a crossfaded GIF with ffmpeg.
#
# Two modes:
#   panel   (default) — the quick panel: history → type-to-search → snippets → actions
#   snippet            — the Library window: create an "Out of office" snippet
#   action             — the Library window: create a "Repo issues" URL action
#
# Usage:
#   ./tools/screenshots/capture-demo-gif.sh                  # panel -> assets/demo.gif
#   CLIPLEX_GIF_MODE=snippet ./tools/screenshots/capture-demo-gif.sh
#   CLIPLEX_GIF_MODE=action  ./tools/screenshots/capture-demo-gif.sh /tmp/x.gif
#   CLIPLEX_GIF_WIDTH=320 ./tools/screenshots/capture-demo-gif.sh    # override width
#
# Requirements: Swift toolchain, sqlite3, ffmpeg, python3 + Pillow.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$HERE"

MODE="${CLIPLEX_GIF_MODE:-panel}"
case "$MODE" in
  panel)   TARGET=gif;        LAST=frame-14; DEFW=380; DEFOUT="assets/demo.gif" ;;
  snippet) TARGET=snippetgif; LAST=frame-10; DEFW=760; DEFOUT="assets/demo-snippet.gif" ;;
  action)  TARGET=actiongif;  LAST=frame-10; DEFW=760; DEFOUT="assets/demo-action.gif" ;;
  *) echo "error: unknown CLIPLEX_GIF_MODE '$MODE' (use panel|snippet|action)"; exit 1 ;;
esac
OUT="${1:-$DEFOUT}"
WIDTH="${CLIPLEX_GIF_WIDTH:-$DEFW}"

SEED="tools/screenshots/seed.sql"
DEMO_DB="$(mktemp -d)/cliplex-demo.db"
FRAMES="$(mktemp -d)"
SEQ="$(mktemp -d)"

command -v ffmpeg >/dev/null || { echo "error: ffmpeg not found (brew install ffmpeg)"; exit 1; }
python3 -c "import PIL" 2>/dev/null || { echo "error: Pillow not found (pip install Pillow)"; exit 1; }

echo "==> [$MODE] quitting any running Cliplex"
osascript -e 'quit app "Cliplex"' >/dev/null 2>&1 || true
sleep 1

echo "==> building Cliplex.app with screenshot tooling"
CLIPLEX_SCREENSHOTS=1 ./scripts/build-app.sh >/dev/null
BIN="build/Cliplex.app/Contents/MacOS/Cliplex"

echo "==> creating + seeding demo database"
CLIPLEX_DB_PATH="$DEMO_DB" CLIPLEX_SCREENSHOT=library \
  CLIPLEX_SCREENSHOT_DIR="$(mktemp -d)" "$BIN" >/dev/null 2>&1 &
for _ in $(seq 1 30); do
  sqlite3 "$DEMO_DB" "SELECT 1 FROM snippets LIMIT 1;" >/dev/null 2>&1 && break
  sleep 0.5
done
sqlite3 "$DEMO_DB" < "$SEED"

echo "==> rendering walkthrough frames ($TARGET)"
CLIPLEX_DB_PATH="$DEMO_DB" CLIPLEX_SCREENSHOT="$TARGET" \
  CLIPLEX_SCREENSHOT_DIR="$FRAMES" "$BIN" >/dev/null 2>&1 &
# Wait until the frame count stops growing (rendering complete).
count_frames() { find "$FRAMES" -maxdepth 1 -name 'frame-*.png' 2>/dev/null | wc -l | tr -d ' '; }
prev=-1
for _ in $(seq 1 80); do
  cur=$(count_frames)
  if [ "$cur" -gt 0 ] && [ "$cur" -eq "$prev" ]; then break; fi
  prev="$cur"
  sleep 0.6
done
sleep 0.5
COUNT=$(count_frames)
echo "    $COUNT frames"

echo "==> expanding holds + crossfades"
FRAMES_DIR="$FRAMES" SEQ_DIR="$SEQ" MODE="$MODE" python3 - <<'PY'
import os, glob
from PIL import Image

mode = os.environ["MODE"]
frames_dir = os.environ["FRAMES_DIR"]
seq_dir    = os.environ["SEQ_DIR"]
paths = sorted(glob.glob(os.path.join(frames_dir, "frame-*.png")))
imgs = [Image.open(p).convert("RGB") for p in paths]
w, h = imgs[0].size
imgs = [im if im.size == (w, h) else im.resize((w, h)) for im in imgs]

# Per-frame (hold, crossfade-to-next) in frames @ 20 fps.
if mode == "panel":
    # main states held long / slow xfade; character typing zips by fast.
    PLAN = [
        (26, 4),
        (2, 1), (2, 1), (2, 1), (2, 1), (2, 1),   # typing "select"
        (30, 11),
        (26, 4),
        (2, 1), (2, 1), (2, 1), (2, 1),           # typing "email"
        (30, 11),
        (30, 13),
    ]
else:  # create — per-frame role encoded in the filename (frame-NNN-<role>.png).
    ROLE_TIMING = {"type": (1, 0), "beat": (12, 4), "hold": (28, 8)}
    PLAN = []
    for p in paths:
        role = os.path.basename(p)[:-4].split("-")[-1]   # strip .png, take role
        PLAN.append(ROLE_TIMING.get(role, (16, 6)))

if len(PLAN) != len(imgs):
    raise SystemExit(f"PLAN has {len(PLAN)} entries but {len(imgs)} frames were rendered")

out = []
n = len(imgs)
for i, im in enumerate(imgs):
    hold, xfade = PLAN[i]
    out += [im] * hold
    nxt = imgs[(i + 1) % n]
    for k in range(1, xfade + 1):
        out.append(Image.blend(im, nxt, k / (xfade + 1)))

for idx, im in enumerate(out, 1):
    im.save(os.path.join(seq_dir, f"seq_{idx:04d}.png"))
print(f"    {len(out)} sequence frames from {n} states")
PY

echo "==> encoding GIF with ffmpeg (palette-optimized)"
mkdir -p "$(dirname "$OUT")"
PALETTE="$SEQ/palette.png"
ffmpeg -y -framerate 20 -i "$SEQ/seq_%04d.png" \
  -vf "scale=${WIDTH}:-1:flags=lanczos,palettegen=max_colors=128:stats_mode=diff" "$PALETTE" >/dev/null 2>&1
ffmpeg -y -framerate 20 -i "$SEQ/seq_%04d.png" -i "$PALETTE" \
  -lavfi "scale=${WIDTH}:-1:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle" \
  "$OUT" >/dev/null 2>&1

echo "==> done: $OUT ($(du -h "$OUT" | awk '{print $1}'))"
echo "    Rebuild a normal app with: ./scripts/build-app.sh"
