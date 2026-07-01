# Releasing Cliplex

Cliplex ships a **free, ad-hoc-signed** `Cliplex.dmg` — no Apple Developer
account required. Releases are automated by
[`.github/workflows/release.yml`](.github/workflows/release.yml), which runs when
you push a version tag.

## Cutting a release

```bash
# 1. Bump the version in Resources/Info.plist (CFBundleShortVersionString
#    and CFBundleVersion) and update CHANGELOG.md.
# 2. Tag and push:
git tag v0.1.0
git push origin v0.1.0
```

The workflow builds the app, packages an ad-hoc-signed DMG, and publishes a
GitHub Release with the DMG attached. No secrets are needed.

## Building a DMG locally (optional)

```bash
VERSION=v0.1.0 ./scripts/package-release.sh
# → dist/Cliplex-0.1.0.dmg
```

## What "ad-hoc signed" means for users

Ad-hoc builds **run fine** but are **not notarized**, so macOS shows a one-time
Gatekeeper prompt the first time a *downloaded* build is opened. The README
[Install → First launch](README.md#first-launch) section documents the
**Open Anyway** / `xattr -dr com.apple.quarantine` steps. (Building from source
is never quarantined.)

## Updating the Homebrew cask

This is **automated**: after each tagged release, the `update-tap` job in
[`.github/workflows/release.yml`](.github/workflows/release.yml) bumps
`version` + `sha256` in `Casks/cliplex.rb` in the tap
([Ron537/homebrew-tap](https://github.com/Ron537/homebrew-tap)) and pushes.

**One-time setup** — the job needs a token that can push to the *tap* repo (the
default `GITHUB_TOKEN` only has access to this repo):

1. Create a **fine-grained personal access token** (GitHub → Settings →
   Developer settings → Fine-grained tokens) scoped to **only** the
   `Ron537/homebrew-tap` repository, with **Contents: Read and write**.
2. Add it to this repo as an Actions secret named **`HOMEBREW_TAP_TOKEN`**
   (Settings → Secrets and variables → Actions → New repository secret).

If the secret is absent the job simply no-ops (releases still succeed); update
the cask manually with `shasum -a 256 dist/Cliplex-<version>.dmg`.

## Future: notarized builds (optional, paid)

To remove the Gatekeeper prompt entirely you need an **Apple Developer Program**
membership ($99/yr) for a *Developer ID Application* certificate. The build
scripts already support it: pass a real identity via `SIGN_IDENTITY` (e.g.
`SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"`), then notarize and
staple the DMG with `xcrun notarytool submit --wait` + `xcrun stapler staple`.
You'd re-add a signing/notarization job to the release workflow with these
secrets: a base64 `.p12`, its password, a keychain password, your signing
identity, and `notarytool` credentials (Apple ID + app-specific password +
Team ID).
