#!/usr/bin/env bash
#
# Run Cliplex in development with a STABLE code identity so the macOS
# Accessibility permission persists (auto-paste works in dev).
#
# `npm run tauri dev` ad-hoc-signs the debug binary with a new identity on every
# recompile, so macOS forgets the Accessibility grant. This script instead:
#   1. builds the frontend (so the embedded UI is current),
#   2. builds the debug binary,
#   3. cert-signs it with the stable self-signed "Cliplex Dev" certificate,
#   4. runs it.
#
# Grant Accessibility once; because the certificate (and therefore the
# Designated Requirement) is stable, the grant keeps working every time you
# re-run this — even after Rust changes. Re-run this script after each change.
#
# Note: this loads the built frontend from dist/ (no Vite HMR). Use plain
# `npm run tauri dev` for fast UI iteration, and this script when you need
# auto-paste / Accessibility to work in development.
set -euo pipefail

echo "[1/4] Building frontend → dist/ …"
npm run build --silent

echo "[2/4] Building debug binary …"
cargo build --manifest-path src-tauri/Cargo.toml

echo "[3/4] Signing debug binary with stable cert …"
./scripts/dev-sign-macos.sh target/debug/cliplex

echo "[4/4] Launching …"
exec target/debug/cliplex
