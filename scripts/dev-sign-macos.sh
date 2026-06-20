#!/usr/bin/env bash
#
# Sign Cliplex.app with a stable, self-signed certificate so that the macOS
# Accessibility permission *persists across rebuilds*.
#
# Why: an ad-hoc / linker-signed binary's code identity (cdhash) changes every
# build, so macOS keeps re-asking for Accessibility permission. Signing with a
# certificate gives a stable Designated Requirement, so you grant the permission
# once and it sticks — even after you rebuild.
#
# Usage:
#   ./scripts/dev-sign-macos.sh [path/to/Cliplex.app]
#
# With no argument it signs the most recent release bundle.
set -euo pipefail

CERT_NAME="Cliplex Dev (self-signed)"
APP_PATH="${1:-target/release/bundle/macos/Cliplex.app}"
ENTITLEMENTS="src-tauri/entitlements/cliplex.entitlements"

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: app bundle not found at: $APP_PATH" >&2
  echo "Build it first with: npm run tauri build" >&2
  exit 1
fi

# 1. Create the self-signed code-signing certificate once (in the login keychain).
if ! security find-certificate -c "$CERT_NAME" >/dev/null 2>&1; then
  echo "Creating self-signed certificate: $CERT_NAME"
  TMP_DIR="$(mktemp -d)"
  cat >"$TMP_DIR/cert.conf" <<EOF
[ req ]
distinguished_name = dn
prompt = no
x509_extensions = v3
[ dn ]
CN = $CERT_NAME
[ v3 ]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
EOF
  openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$TMP_DIR/key.pem" -out "$TMP_DIR/cert.pem" \
    -days 3650 -config "$TMP_DIR/cert.conf" >/dev/null 2>&1
  # macOS `security` cannot verify PKCS#12 files produced with OpenSSL 3's
  # default (SHA-256) MAC and an empty password. Use a password + SHA-1 MAC +
  # legacy PBE so the import succeeds.
  P12_PASS="cliplex"
  openssl pkcs12 -export -inkey "$TMP_DIR/key.pem" -in "$TMP_DIR/cert.pem" \
    -out "$TMP_DIR/cert.p12" -passout "pass:$P12_PASS" \
    -macalg sha1 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES >/dev/null 2>&1
  security import "$TMP_DIR/cert.p12" -k ~/Library/Keychains/login.keychain-db \
    -P "$P12_PASS" -A
  rm -rf "$TMP_DIR"
  echo "Certificate created."
  echo "(codesign may warn about an untrusted root — that is expected and does"
  echo " not affect signing or Accessibility-permission persistence.)"
fi

# 2. Sign the app (deep) with a stable identifier and entitlements.
echo "Signing $APP_PATH …"
codesign --force --deep \
  --sign "$CERT_NAME" \
  --identifier "com.rborysowski.cliplex" \
  --entitlements "$ENTITLEMENTS" \
  "$APP_PATH"

codesign -dvvv "$APP_PATH" 2>&1 | grep -E "Identifier|Authority|Signature" | sed 's/^/  /'

echo
echo "Done. Now:"
echo "  1. Remove any old Cliplex entry from System Settings → Privacy & Security → Accessibility."
echo "  2. Launch the app, trigger a paste, and grant Accessibility when asked."
echo "  3. Relaunch Cliplex once. The permission will now persist across rebuilds"
echo "     as long as you re-run this script after each build."
