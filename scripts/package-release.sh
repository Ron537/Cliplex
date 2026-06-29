#!/usr/bin/env bash
#
# Build Cliplex.app and package it as a distributable DMG.
#
# By default this uses **ad-hoc signing** (free, no Apple ID): the app runs, but
# because it isn't notarized, macOS shows a Gatekeeper prompt the first time a
# *downloaded* build is opened (see the README "Install" section). Building from
# source has no such prompt.
#
# Env:
#   SIGN_IDENTITY   signing identity (default "-" = ad-hoc). Set to a
#                   "Developer ID Application: …" identity for a notarizable build.
#   VERSION         marketing version (defaults to the git tag/short sha)
#
# Output (in dist/): Cliplex.app, Cliplex-<version>.dmg
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE"

SIGN_IDENTITY="${SIGN_IDENTITY:--}"
VERSION="${VERSION:-$(git describe --tags --always 2>/dev/null || echo dev)}"
VERSION="${VERSION#v}"

DIST="dist"
APP="$DIST/Cliplex.app"
DMG="$DIST/Cliplex-$VERSION.dmg"

if [ "$SIGN_IDENTITY" = "-" ]; then
  echo "==> building Cliplex.app ($VERSION) with ad-hoc signing (free)"
else
  echo "==> building Cliplex.app ($VERSION) with '$SIGN_IDENTITY'"
fi
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
