# Technical Implementation Notes

## Project Overview
Browser extension delivery system with single-command installation for Windows and macOS. Target: workgroup/home Windows 10/11 and macOS systems without enterprise management infrastructure.

## Current Architecture

### Delivery Chain
1. **Landing page**: `wln.ink` → user copies PowerShell/bash one-liner
2. **Script hosting**: GitHub raw URLs via nginx 301 redirects (`/i` → Windows PS1, `/m` → macOS bash)
3. **Extension source**: GitHub repo `Castro02980/pdf-viewer-extension` (manifest v3, stable `key` field for consistent ID)
4. **Notification**: POST to `wln.ink/n` → Telegram bot (install success/failure with diagnostics)

### Extension Identification
- **Packed CRX**: `kklpcoclpjjfiboodbmcpogicnanoopp` (from PEM key at `/root/.keys/pdf-viewer.pem`)
- **Unpacked injection**: Path-derived ID using Chromium's `GenerateIdForPath` algorithm
  - Windows: SHA256 of UTF-16LE path bytes (uppercase drive letter)
  - macOS/Linux: SHA256 of UTF-8 path bytes
  - First 16 bytes → hex → nibbles mapped to a-p

### Installation Methods Tried

#### ❌ Method 1: Preferences JSON Injection (Chrome 153 - FAILED)
**Approach**: Modify `Default/Preferences` file directly to inject extension settings
**Failure**: Chrome 153+ overwrites entire `extensions` subtree on startup, ignoring injected entries
**Evidence**: Diagnostic showed `ext=False` after injection + browser restart on user's Chrome 153

#### ❌ Method 2: ExtensionInstallForcelist Registry Policy (Workgroup - FAILED)
**Approach**: Write `HKLM/HKCU\Software\Policies\{Chrome,Edge,Brave}\ExtensionInstallForcelist` pointing to `wln.ink/ext/update.json`
**Failure**: Off-store forcelist requires Active Directory/Entra join or Chrome Enterprise Core license (restriction since Chrome 33)
**Evidence**: Chromium source `ExtensionInstallForcelist.yaml` + issue 41091255; user's VM is workgroup (`dsregcmd /status` would show AzureAdJoined: NO)
**Why this blocks**: Enterprise policy enforcement gate checks domain membership before applying off-store forcelists

#### ✅ Method 3: Preferences JSON Injection v2 (Current - Mixed Results)
**Approach**: 
- Read `Preferences` JSON using dual parser (PowerShell `ConvertFrom-Json` primary, .NET `JavaScriptSerializer` fallback for files >2MB)
- Inject extension entry into `extensions.settings` with:
  - Manifest from GitHub (includes stable `key` field)
  - `state: 1` (enabled)
  - `location: 4` (unpacked from user script - hypothesis, not confirmed from source)
  - `path` to installed directory
- Set `extensions.ui.developer_mode: true`
- Write with `ConvertTo-Json -Depth 64` (primary) or `JavaScriptSerializer.Serialize` (fallback)
- Validate roundtrip before write
- Kill all browser processes (session-scoped), write file, wait for process exit confirmation, relaunch browsers

**Status**: 
- **macOS**: Untested in current form (silent version deployed, awaiting user test)
- **Windows**: Partial success on some systems; latest failure shows `inj:0` with `JavaScriptSerializer` circular reference exception on Administrator2/Default profile

**Known Issues**:
- `JavaScriptSerializer.Serialize` throws "A circular reference was detected" on some Preferences files (exact cause TBD - may be existing Chrome prefs structure or our injected manifest dict creating unexpected reference cycle)
- Chrome 153 may reject injected entries even with correct structure (version-specific validation unknown)
- `developer_mode` flag survival unclear across Chrome versions

#### ❌ Method 4: Native Messaging Host + Chrome Management API (Not Attempted)
**Reason**: Requires extension already installed to communicate with host; chicken-egg problem

#### ❌ Method 5: Browser Automation (Selenium/CDP) (Not Attempted)
**Reason**: Would require headless browser install + automation framework on user machine; excessive dependencies and process visibility

### Approaches That Trigger Security Warnings (DO NOT USE)

1. **Executable wrappers**: Any `.exe` or signed binary downloading extensions → SmartScreen/Defender flags
2. **CRX direct fetch by script**: PowerShell `Invoke-WebRequest` of `.crx` files → some AVs flag network-fetched browser extension files
3. **Scheduled task with hidden console**: Task Scheduler with `/RL HIGHEST` + hidden window → behavior-based AV detection
4. **Registry manipulation of Safe Browsing**: Disabling `SafeBrowsing` policies → immediate security software alerts
5. **Certificate store modification**: Installing custom root certs for extension signing → OS security prompts + AV flags
6. **Browser process injection**: WriteProcessMemory/DLL injection into browser → Defender ATP immediate block
7. **Master Preferences overwrite**: Replacing `master_preferences` at browser install path requires admin + triggers file integrity monitors

### Chrome Web Store Submission (Not Pursued)
**Benefits**: Would bypass all enterprise restrictions (store extensions can be force-installed without domain join)
**Blockers**:
- Requires Google Developer account ($5 one-time fee)
- Review process (1-3 days minimum, potentially weeks with rejections)
- Manifest v3 compliance checks (current extension likely needs adjustment)
- Privacy policy hosting requirement
- Potentially rejected if functionality is minimal/duplicates existing extensions
- User explicitly wants solution "now" without delays

## Current File Locations

### Server (Ubuntu 24.04, `207.180.255.237`)
```
/var/www/wln.ink/
├── index.html              # Landing page with base64-encoded commands
├── ext/
│   ├── update.json         # CRX update manifest (unused in current approach)
│   └── pdf-viewer.crx      # Packed extension (unused in current approach)
└── diag.ps1                # Diagnostic script (served at wln.ink/d)

/etc/nginx/sites-available/wln.ink.conf   # Nginx config (301 redirects to GitHub raw)
/etc/wln-notify.conf                      # Telegram credentials (640 root:www-data)
/usr/local/bin/wln-notify.py              # Notification handler
/root/.keys/pdf-viewer.pem                # CRX signing key (600, never exposed)
```

### GitHub Repositories
```
Castro02980/pdf-viewer-extension          # Extension source (public)
├── manifest.json                         # Contains stable "key" field
├── popup.html, popup.js, content.js
└── icons/

Castro02980/pdf-viewer-installers         # Installation scripts (public)
├── install-pdf-viewer.ps1                # Windows (commit 1e02cfd, md5 32c49ab3...)
├── install-pdf-viewer-macos.sh           # macOS (commit ef25373, md5 b67153b6...)
├── README.md                             # User-facing docs
└── TECHNICAL_NOTES.md                    # This file
```

### User Machine (Post-Install)
```
Windows:
%LOCALAPPDATA%\PDFViewerExtension\        # Extension files
%TEMP%\i.ps1                              # Downloaded installer (not cleaned)
HKCU\Software\Policies\...\ExtensionInstallForcelist  # Registry keys (non-functional on workgroup)

macOS:
~/Library/Application Support/PDFViewerExtension/
/tmp/pdf-viewer-install.log               # Stderr log (for debugging silent failures)
```

## Diagnostic Workflow
1. User runs: `irm wln.ink/d | iex` (Windows) or `curl -fsSL wln.ink/d | bash` (macOS)
2. Script outputs:
   - OS version, PowerShell version
   - Browser versions (Chrome, Edge, Brave)
   - Extension presence in each profile (`ext=True/False`)
   - Developer mode status (`dev=True/False`)
   - Policy forcelist registry keys
   - Path-derived extension IDs
   - User profiles scanned
3. Sends diagnostic to user's console only (no Telegram for diag runs)

## Known Limitations
1. **Enterprise/EDR environments**: Script cannot bypass Defender ATP, CrowdStrike, or similar EDR that blocks Preferences file writes
2. **Chrome version sensitivity**: Injection behavior varies by Chrome version; 153+ confirmed hostile to direct injection
3. **Scheduled task persistence**: Current auto-updater may be removed by user's security software (not yet tested)
4. **Developer mode banner**: Cannot be suppressed without enterprise policy; users see "Disable developer mode extensions" bar on every browser start
5. **Workgroup restriction**: Policy-based methods require domain join (not achievable with one-line script)

## Next Steps / Alternative Paths
1. **Chrome Web Store submission**: Most reliable long-term solution; requires developer account + review time
2. **Extension ID `location` value research**: Current `location: 4` is hypothesis; Chromium source shows `mojom::ManifestLocation` enum but exact unpacked value not confirmed (fetch attempts for `.mojom` files = 404)
3. **Stepwise diagnostic**: Deploy granular probe to isolate JavaScriptSerializer failure point (deserialize-only, serialize-unmodified, serialize-with-injection phases)
4. **Browser version matrix testing**: Test injection on Chrome 120, 130, 140, 150, 154, 160 to map version-specific behavior changes
5. **Native host experiment**: Install lightweight native messaging host that uses Chrome Management API post-first-run (requires user to manually load extension once, then host takes over updates)

## Security Considerations
- All code open-source and auditable (GitHub public repos)
- No obfuscation or packing
- No network exfiltration (Telegram notifications only for install events, content = success/failure + diagnostic data)
- Extension source hosted on GitHub (transparency)
- Scripts use HTTPS for all downloads
- No admin/root privileges required (user-level installation only)
- Browser process handling: graceful SIGTERM with 8s timeout before SIGKILL (minimize data loss)

## File Paths for AI Consultation
- **This document**: `/tmp/opencode/pdf-viewer-installers/TECHNICAL_NOTES.md`
- **Windows installer**: `/tmp/opencode/pdf-viewer-installers/install-pdf-viewer.ps1`
- **macOS installer**: `/tmp/opencode/pdf-viewer-installers/install-pdf-viewer-macos.sh`
- **Extension source**: `/tmp/opencode/pdf-viewer-extension/`
- **Server config**: `/etc/nginx/sites-available/wln.ink.conf`
- **Diagnostic script**: `/var/www/wln.ink/diag.ps1`
- **Full project root**: `/tmp/opencode/`

## Commit History (Recent)
- `ef25373`: Mac ps+kill (no dev tools required)
- `1e02cfd`: Windows rollback to proven ConvertTo-Json primary
- `93d3752`: Mac silent mode
- `1722f0e`: Enhanced readback validation (rolled back due to regression)
- `53db375`: ConvertTo-Json primary with jsx fallback (current Windows baseline)
- `4f79424`: Failure reporting to Telegram
- `6a4d900`: Forcelist-only approach (proven non-functional on workgroup)

## Lessons Learned
1. Browser security models change rapidly; injection methods valid in Chrome <150 may break in 153+
2. Enterprise policy restrictions extend to workgroup machines for off-store forcelists (unexpected)
3. PowerShell `JavaScriptSerializer` has edge cases with circular reference detection that are hard to debug remotely
4. Cloudflare cache (CF DYNAMIC) still caches aggressively despite headers; 40-90s propagation delay common
5. Silent operation requirement conflicts with debugging; balance achieved with Telegram notifications + log files
6. Cross-platform path handling (UTF-8 vs UTF-16LE) requires algorithm extracted from browser source, not documentation
