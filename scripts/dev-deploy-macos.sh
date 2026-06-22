#!/usr/bin/env bash
#
# Deploy the freshly-built Cliplex.app to /Applications and sign it with the
# stable self-signed dev certificate, so the copy you actually launch keeps a
# consistent code identity and the macOS Accessibility grant persists.
#
# Why this exists: if you drag an *ad-hoc* build into /Applications, its code
# identity is just a cdhash that changes every rebuild, so TCC keeps losing the
# Accessibility permission ("Failed to match existing code requirement").
# Always deploy via this script so /Applications/Cliplex.app is cert-signed.
#
# Usage:
#   ./scripts/dev-deploy-macos.sh            # deploy + sign + relaunch
#   SKIP_LAUNCH=1 ./scripts/dev-deploy-macos.sh
set -euo pipefail

SRC="target/release/bundle/macos/Cliplex.app"
DEST="/Applications/Cliplex.app"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -d "$SRC" ]]; then
  echo "error: build first — '$SRC' not found (run 'npm run tauri build')." >&2
  exit 1
fi

# Quit any running instance so the bundle can be replaced cleanly.
osascript -e 'quit app "Cliplex"' 2>/dev/null || true
sleep 1

echo "Deploying $SRC → $DEST"
rm -rf "$DEST"
ditto "$SRC" "$DEST"

# Sign the deployed copy with the stable dev certificate.
"$SCRIPT_DIR/dev-sign-macos.sh" "$DEST"

if [[ "${SKIP_LAUNCH:-0}" != "1" ]]; then
  echo "Launching $DEST"
  open "$DEST"
fi

echo
echo "Deployed. If Accessibility was previously granted to a *different* (ad-hoc)"
echo "build, run once to re-establish the grant under the stable identity:"
echo "  tccutil reset Accessibility com.rborysowski.cliplex"
echo "then grant Cliplex in System Settings → Privacy & Security → Accessibility."
