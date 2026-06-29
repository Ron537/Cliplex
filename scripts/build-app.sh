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
# Code-signing identity. Defaults to the stable self-signed dev cert (which keeps
# the Accessibility grant across rebuilds). Release packaging overrides this with
# a Developer ID identity via SIGN_IDENTITY.
CERT_NAME="${SIGN_IDENTITY:-Cliplex Dev (self-signed)}"
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
# Opt-in screenshot tooling (tools/screenshots/). Off for release/CI/distribution.
BUILD_ARGS=()
if [ -n "${CLIPLEX_SCREENSHOTS:-}" ]; then
  echo "    (screenshot tooling enabled: -DCLIPLEX_SCREENSHOTS)"
  BUILD_ARGS+=(-Xswiftc -DCLIPLEX_SCREENSHOTS)
fi
swift build -c "$CONFIG" ${BUILD_ARGS[@]+"${BUILD_ARGS[@]}"}
BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/Cliplex"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$BIN_DIR" "$RES_DIR"
cp "$BIN_PATH" "$BIN_DIR/Cliplex"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Bundle the UI fonts (auto-registered via Info.plist ATSApplicationFontsPath)
# together with their OFL license texts (the SIL OFL requires the license to
# travel with the fonts on redistribution).
if [ -d Resources/Fonts ]; then
  mkdir -p "$RES_DIR/Fonts"
  cp Resources/Fonts/*.ttf "$RES_DIR/Fonts/"
  [ -d Resources/Fonts/licenses ] && cp -R Resources/Fonts/licenses "$RES_DIR/Fonts/"
fi

echo "==> signing as '$CERT_NAME'"
# Only auto-create the self-signed cert when no explicit identity was given.
if [ -z "${SIGN_IDENTITY:-}" ] && ! security find-certificate -c "$CERT_NAME" >/dev/null 2>&1; then
  echo "    dev certificate not found — creating it"
  "$HERE/scripts/make-dev-cert.sh"
fi
SIGN_ARGS=(--force --options runtime --identifier "com.rborysowski.cliplex"
  --entitlements Resources/Cliplex.entitlements --sign "$CERT_NAME")
# A secure timestamp is required for notarization; skip it for offline dev builds.
if [ -n "${SIGN_IDENTITY:-}" ]; then SIGN_ARGS+=(--timestamp); fi
codesign "${SIGN_ARGS[@]}" "$APP"

codesign -dvvv "$APP" 2>&1 | grep -E "Identifier|Authority" | sed 's/^/  /'
echo "==> built $APP"
