# Releasing Cliplex

Cliplex ships as a **signed + notarized** `Cliplex.dmg` so users can install it
without Gatekeeper warnings. Releases are automated by
[`.github/workflows/release.yml`](.github/workflows/release.yml), which runs when
you push a version tag.

## One-time setup

You need an **Apple Developer Program** membership ($99/yr) to get a *Developer
ID Application* certificate (required to distribute signed apps outside the App
Store).

1. **Create a Developer ID Application certificate** in your Apple Developer
   account and export it from Keychain Access as a `.p12` (with a password).
2. **Create an app-specific password** for notarization at
   <https://appleid.apple.com> → Sign-In and Security → App-Specific Passwords.
3. **Find your Team ID** (Apple Developer → Membership) and your signing identity
   string, e.g. `Developer ID Application: Your Name (ABCDE12345)`
   (`security find-identity -v -p codesigning`).
4. Add these **GitHub Actions secrets** (repo → Settings → Secrets and variables
   → Actions):

   | Secret | Value |
   |--------|-------|
   | `DEVELOPER_ID_CERT_P12_BASE64` | `base64 -i cert.p12` output |
   | `DEVELOPER_ID_CERT_PASSWORD` | The `.p12` export password |
   | `SIGN_IDENTITY` | `Developer ID Application: Your Name (TEAMID)` |
   | `KEYCHAIN_PASSWORD` | Any random string (temp keychain on the runner) |
   | `AC_APPLE_ID` | Your Apple ID email |
   | `AC_PASSWORD` | The app-specific password from step 2 |
   | `AC_TEAM_ID` | Your 10-character Team ID |

## Cutting a release

```bash
# 1. Update CHANGELOG.md (move "Unreleased" items under the new version).
# 2. Tag and push:
git tag v0.1.0
git push origin v0.1.0
```

The workflow builds, signs, notarizes, staples, and publishes a GitHub Release
with the DMG attached.

## Building a signed DMG locally (optional)

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  VERSION=v0.1.0 ./scripts/package-release.sh
# → dist/Cliplex-0.1.0.dmg   (notarize separately with `xcrun notarytool`)
```

## Updating the Homebrew cask

After a release, update the cask in your tap (see
[`tools/homebrew/cliplex.rb`](tools/homebrew/cliplex.rb)) with the new `version`
and `sha256` (`shasum -a 256 dist/Cliplex-<version>.dmg`).
