#!/usr/bin/env bash
#
# Build the native Swift Cliplex, assemble a .app bundle, and sign it with the
# stable self-signed dev certificate so the macOS Accessibility grant persists
# across rebuilds (a self-signed cert gives a fixed code identity; ad-hoc signing
# changes the cdhash every build and loses the grant).
#
# Usage:
#   ./scripts/build-app.sh            # release build + bundle + sign
#   CONFIG=debug ./scripts/build-app.sh
set -euo pipefail

CONFIG="${CONFIG:-release}"
CERT_NAME="Cliplex Dev (self-signed)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE"

# SwiftPM needs this because the machine's global git config sets
# safe.bareRepository=explicit, which blocks SwiftPM's bare dependency repos.
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=safe.bareRepository
export GIT_CONFIG_VALUE_0=all

APP="build/Cliplex.app"
BIN_DIR="$APP/Contents/MacOS"
RES_DIR="$APP/Contents/Resources"

echo "==> swift build ($CONFIG)"
swift build -c "$CONFIG"
BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/Cliplex"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$BIN_DIR" "$RES_DIR"
cp "$BIN_PATH" "$BIN_DIR/Cliplex"
cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "==> signing as '$CERT_NAME'"
if ! security find-certificate -c "$CERT_NAME" >/dev/null 2>&1; then
  echo "    dev certificate not found — creating it"
  "$HERE/scripts/make-dev-cert.sh"
fi
codesign --force --options runtime \
  --sign "$CERT_NAME" \
  --identifier "com.rborysowski.cliplex" \
  --entitlements Resources/Cliplex.entitlements \
  "$APP"

codesign -dvvv "$APP" 2>&1 | grep -E "Identifier|Authority" | sed 's/^/  /'
echo "==> built $APP"
