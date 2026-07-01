# Security Policy

Cliplex handles some of the most sensitive data on your machine — everything you
copy. We take that responsibility seriously. This document explains the security
model and how to report a vulnerability.

## Reporting a vulnerability

**Please do not open a public issue for security problems.**

Use GitHub's private reporting:
[**Report a vulnerability**](https://github.com/Ron537/Cliplex/security/advisories/new).

We aim to acknowledge a report within **72 hours** and to provide a remediation
timeline after triage. Coordinated disclosure is appreciated — please give us a
reasonable window to ship a fix before any public write-up.

When reporting, please include:

- Cliplex version (and macOS version).
- A clear description and, if possible, steps to reproduce or a proof of concept.
- The impact you believe the issue has.

## Security model

Cliplex is a local-only macOS menu-bar app. By design:

- **No network access.** Cliplex makes no network requests — no analytics, no
  crash reporting, no sync, no auto-update telemetry. All data stays on device.
- **Local storage.** History and snippets live in a SQLite database at
  `~/Library/Application Support/com.ron537.cliplex/cliplex.db`. It is **not
  encrypted at rest** in this release; protect it with FileVault. Optional
  SQLCipher encryption is planned.
- **No App Sandbox.** A clipboard manager must read the global pasteboard and
  synthesize ⌘V. Cliplex therefore runs unsandboxed and requests
  **Accessibility** permission, used solely to inject the paste keystroke into
  the frontmost app.
- **Pasteboard privacy filter.** Clips marked concealed/transient/auto-generated
  via the [nspasteboard.org](http://nspasteboard.org) convention are never
  stored, and a configurable app-exclusion list (password managers by default)
  is respected. See [PRIVACY.md](PRIVACY.md).

## Sensitive capabilities (by design)

These are intentional and necessary for the app to function. They are documented
here so reviewers understand the trust boundary:

| Capability | Why | Scope |
|------------|-----|-------|
| Reads the global pasteboard | To build clipboard history | Honors the privacy filter and exclusion list |
| Synthesizes ⌘V via CGEvent | To paste into other apps | Only when you trigger a paste |
| Requires Accessibility permission | Required for the above | Used only for paste injection |
| Launches at login (optional) | Convenience | Off unless you enable it |

## Supported versions

Cliplex is pre-1.0. Security fixes are applied to the latest release on `main`.
Once 1.0 ships, this section will list supported version ranges.

## Hardening guidance for users

- Enable **FileVault** so the local database is encrypted at rest.
- Keep the password-manager exclusion list enabled.
- Review the history-size limit so old clips are pruned automatically.
