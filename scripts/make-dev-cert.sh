#!/usr/bin/env bash
#
# Create the stable, self-signed code-signing certificate Cliplex is signed with
# in development. A certificate (rather than ad-hoc signing) gives the app a
# fixed code identity, so the macOS Accessibility grant persists across rebuilds.
#
# Idempotent: does nothing if the certificate already exists.
set -euo pipefail

CERT_NAME="Cliplex Dev (self-signed)"

if security find-certificate -c "$CERT_NAME" >/dev/null 2>&1; then
  echo "Certificate '$CERT_NAME' already exists."
  exit 0
fi

echo "Creating self-signed certificate: $CERT_NAME"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

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

# macOS `security` cannot verify PKCS#12 files produced with OpenSSL 3's default
# (SHA-256) MAC and an empty password. Use a password + SHA-1 MAC + legacy PBE.
P12_PASS="cliplex"
openssl pkcs12 -export -inkey "$TMP_DIR/key.pem" -in "$TMP_DIR/cert.pem" \
  -out "$TMP_DIR/cert.p12" -passout "pass:$P12_PASS" \
  -macalg sha1 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES >/dev/null 2>&1

security import "$TMP_DIR/cert.p12" -k ~/Library/Keychains/login.keychain-db \
  -P "$P12_PASS" -A

echo "Certificate created. (codesign may warn about an untrusted root — that is"
echo " expected and does not affect signing or Accessibility-permission persistence.)"
