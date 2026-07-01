#!/usr/bin/env bash
#
# Regenerate all app iconography from the vector masters in assets/branding/.
# Renders SVG -> PNG with headless Chrome (no extra deps), then assembles the
# macOS AppIcon.icns, the monochrome menu-bar template, and the site favicon.
#
#   ./scripts/gen-icons.sh
#
# Outputs:
#   Resources/AppIcon.icns
#   Resources/MenuBarIconTemplate.png, MenuBarIconTemplate@2x.png
#   site/assets/icon.svg, site/assets/favicon.png
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE"

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
[ -x "$CHROME" ] || { echo "error: Google Chrome not found at $CHROME"; exit 1; }

ICON_SVG="assets/branding/icon-master.svg"
MENU_SVG="assets/branding/menubar-master.svg"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# render <svg> <size> <out.png>  — Chrome lingers on exit, so poll then kill.
render() {
  local svg="$1" size="$2" out="$3"
  local html="$TMP/wrap-$size-$RANDOM.html"
  {
    printf '<!DOCTYPE html><html><head><style>*{margin:0;padding:0}'
    printf 'html,body{background:transparent}svg{display:block;width:%spx;height:%spx}</style></head><body>' "$size" "$size"
    cat "$svg"
    printf '</body></html>'
  } > "$html"
  rm -f "$out"
  local ud="$TMP/ud-$size-$RANDOM"
  "$CHROME" --headless --disable-gpu --no-first-run --no-default-browser-check \
    --force-device-scale-factor=1 --default-background-color=00000000 \
    --hide-scrollbars --window-size="$size,$size" --user-data-dir="$ud" \
    --screenshot="$out" "file://$html" >/dev/null 2>&1 &
  local pid=$!
  for _ in $(seq 1 60); do
    [ -s "$out" ] && break
    sleep 0.3
  done
  sleep 0.4
  kill "$pid" >/dev/null 2>&1 || true
  [ -s "$out" ] || { echo "error: failed to render $out"; exit 1; }
}

echo "==> rendering app icon PNGs"
ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"
# Render each unique pixel size once, then place under the iconset names.
for s in 16 32 64 128 256 512 1024; do
  render "$ICON_SVG" "$s" "$TMP/icon_$s.png"
  echo "    ${s}px"
done
cp "$TMP/icon_16.png"   "$ICONSET/icon_16x16.png"
cp "$TMP/icon_32.png"   "$ICONSET/icon_16x16@2x.png"
cp "$TMP/icon_32.png"   "$ICONSET/icon_32x32.png"
cp "$TMP/icon_64.png"   "$ICONSET/icon_32x32@2x.png"
cp "$TMP/icon_128.png"  "$ICONSET/icon_128x128.png"
cp "$TMP/icon_256.png"  "$ICONSET/icon_128x128@2x.png"
cp "$TMP/icon_256.png"  "$ICONSET/icon_256x256.png"
cp "$TMP/icon_512.png"  "$ICONSET/icon_256x256@2x.png"
cp "$TMP/icon_512.png"  "$ICONSET/icon_512x512.png"
cp "$TMP/icon_1024.png" "$ICONSET/icon_512x512@2x.png"

echo "==> building Resources/AppIcon.icns"
iconutil -c icns -o Resources/AppIcon.icns "$ICONSET"

echo "==> rendering menu-bar template"
render "$MENU_SVG" 18 Resources/MenuBarIconTemplate.png
render "$MENU_SVG" 36 Resources/MenuBarIconTemplate@2x.png

echo "==> updating site assets"
cp "$ICON_SVG" site/assets/icon.svg
cp "$TMP/icon_256.png" site/assets/favicon.png

echo "==> done:"
echo "    Resources/AppIcon.icns"
echo "    Resources/MenuBarIconTemplate.png (+@2x)"
echo "    site/assets/icon.svg, site/assets/favicon.png"
