#!/bin/bash
#
# PDF Viewer Extension Installer for Chrome (macOS)
# Uses Enterprise Policy for reliable installation
#

set -euo pipefail

EXT_ID="kklpcoclpjjfiboodbmcpogicnanoopp"
VERSION="1.0.0"
CRX_URL="https://github.com/Castro02980/pdf-viewer-installers/releases/download/v${VERSION}/pdf-viewer-extension.crx"

TMP_DIR="/tmp/pdf-viewer-install-$$"
TMP_CRX="$TMP_DIR/extension.crx"
TMP_UPDATE_XML="$TMP_DIR/updates.xml"

INSTALL_BASE="/Library/Application Support/ChromeExtensions/PDFViewer"
POLICY_FILE="/Library/Managed Preferences/com.google.Chrome.plist"

echo "=== PDF Viewer Extension Installer for Chrome ==="
echo ""
echo "Extension ID: $EXT_ID"
echo "Version: $VERSION"
echo ""

# Part 1: Non-sudo operations
echo "[1/3] Downloading extension package..."
mkdir -p "$TMP_DIR"

if command -v curl >/dev/null 2>&1; then
    if ! curl -fsSL -o "$TMP_CRX" "$CRX_URL" 2>/dev/null; then
        echo "ERROR: Failed to download CRX from $CRX_URL"
        echo "Please check your internet connection or try again later."
        rm -rf "$TMP_DIR"
        exit 1
    fi
else
    echo "ERROR: curl not found. Please install curl and try again."
    exit 1
fi

echo "Downloaded: $(du -h "$TMP_CRX" | cut -f1)"

echo "[2/3] Preparing update manifest..."
cat > "$TMP_UPDATE_XML" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<gupdate xmlns="http://www.google.com/update2/response" protocol="2.0">
  <app appid="$EXT_ID">
    <updatecheck codebase="file://$INSTALL_BASE/extension.crx" version="$VERSION" />
  </app>
</gupdate>
EOF

echo "Files prepared in $TMP_DIR"
echo ""

# Part 2: Sudo operations
echo "[3/3] Installing to system directories..."
echo ""
echo "Administrator privileges are required to install the extension."
echo "The installer will:"
echo "  - Copy files to $INSTALL_BASE"
echo "  - Configure Chrome policy in $POLICY_FILE"
echo ""
echo "Please enter your password when prompted:"
echo ""

if ! sudo -v; then
    echo ""
    echo "ERROR: Administrator privileges denied."
    echo "Installation cannot continue without sudo access."
    rm -rf "$TMP_DIR"
    exit 1
fi

# Keep sudo alive
(while true; do sudo -n true; sleep 50; kill -0 "$$" || exit; done 2>/dev/null) &
SUDO_KEEP_ALIVE_PID=$!

# Create directories
sudo mkdir -p "$INSTALL_BASE"
sudo mkdir -p "/Library/Managed Preferences"

# Install CRX
sudo cp "$TMP_CRX" "$INSTALL_BASE/extension.crx"
sudo chmod 644 "$INSTALL_BASE/extension.crx"
sudo chown root:wheel "$INSTALL_BASE/extension.crx"

# Install update manifest
sudo cp "$TMP_UPDATE_XML" "$INSTALL_BASE/updates.xml"
sudo chmod 644 "$INSTALL_BASE/updates.xml"
sudo chown root:wheel "$INSTALL_BASE/updates.xml"

# Configure policy
sudo python3 - "$POLICY_FILE" "$EXT_ID" "file://$INSTALL_BASE/updates.xml" << 'PYTHON_EOF'
import plistlib
import sys
import os
import grp
import tempfile
from pathlib import Path

policy_path = Path(sys.argv[1])
extension_id = sys.argv[2]
update_url = sys.argv[3]

# Load existing or create new
policy = {}
if policy_path.exists():
    try:
        with policy_path.open("rb") as f:
            policy = plistlib.load(f)
        # Backup existing
        import shutil
        backup = str(policy_path) + ".backup"
        shutil.copy2(policy_path, backup)
    except Exception as e:
        print(f"Warning: Could not read existing policy: {e}", file=sys.stderr)
        policy = {}

# Configure ExtensionSettings
settings = policy.get("ExtensionSettings", {})
if not isinstance(settings, dict):
    settings = {}

settings[extension_id] = {
    "installation_mode": "force_installed",
    "update_url": update_url,
}

policy["ExtensionSettings"] = settings

# Write atomically
fd, tmp = tempfile.mkstemp(
    prefix="com.google.Chrome.",
    suffix=".plist",
    dir=str(policy_path.parent)
)

try:
    with os.fdopen(fd, "wb") as f:
        plistlib.dump(policy, f, fmt=plistlib.FMT_XML)
    
    os.chmod(tmp, 0o644)
    os.chown(tmp, 0, grp.getgrnam("wheel").gr_gid)
    os.replace(tmp, policy_path)
    
    print(f"Policy configured: {policy_path}")
except Exception as e:
    os.unlink(tmp)
    raise
PYTHON_EOF

# Stop sudo keep-alive
kill "$SUDO_KEEP_ALIVE_PID" 2>/dev/null || true

echo ""
echo "Installation complete!"
echo ""
echo "Files installed:"
echo "  - $INSTALL_BASE/extension.crx"
echo "  - $INSTALL_BASE/updates.xml"
echo "  - $POLICY_FILE"
echo ""

# Cleanup
rm -rf "$TMP_DIR"

# Restart Chrome
if pgrep -q "Google Chrome"; then
    echo "Restarting Chrome to apply changes..."
    pkill "Google Chrome" 2>/dev/null || true
    sleep 2
fi

if [ -d "/Applications/Google Chrome.app" ]; then
    open -a "Google Chrome" 2>/dev/null &
    echo "Chrome started."
    echo ""
fi

echo "Verification steps:"
echo "1. Open chrome://policy and click 'Reload policies'"
echo "2. Check that ExtensionSettings appears with status 'OK'"
echo "3. Open chrome://extensions to see the extension"
echo ""
echo "The extension is installed via Enterprise Policy and will:"
echo "  - Auto-install for all Chrome users on this Mac"
echo "  - Persist across Chrome updates"
echo "  - Cannot be disabled by regular users"
echo ""

exit 0
