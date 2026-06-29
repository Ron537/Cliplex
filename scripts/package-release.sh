#!/usr/bin/env bash
#
# Build a Developer ID-signed Cliplex.app and package it as a distributable DMG.
# Notarization + stapling are performed by the release workflow
# (.github/workflows/release.yml); this script produces the artifacts it submits.
#
# Required env:
#   SIGN_IDENTITY   e.g. "Developer ID Application: Your Name (TEAMID)"
# Optional env:
#   VERSION         marketing version (defaults to the git tag/short sha)
#
# Output (in dist/):
#   Cliplex.app, Cliplex-<version>.dmg
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE"

: "${SIGN_IDENTITY:?set SIGN_IDENTITY to your Developer ID Application identity}"
VERSION="${VERSION:-$(git describe --tags --always 2>/dev/null || echo dev)}"
VERSION="${VERSION#v}"

DIST="dist"
APP="$DIST/Cliplex.app"
DMG="$DIST/Cliplex-$VERSION.dmg"

echo "==> building + signing Cliplex.app ($VERSION) with '$SIGN_IDENTITY'"
SIGN_IDENTITY="$SIGN_IDENTITY" ./scripts/build-app.sh

rm -rf "$DIST"
mkdir -p "$DIST"
cp -R build/Cliplex.app "$APP"

echo "==> verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "==> building DMG"
STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/Cliplex.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Cliplex" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

echo "==> done:"
echo "    $APP"
echo "    $DMG"
