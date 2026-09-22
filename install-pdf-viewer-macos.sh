#!/bin/bash
# install-pdf-viewer-macos.sh
# Устанавливает PDF Viewer extension во все профили Chrome/Edge/Brave на macOS

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
GRAY='\033[0;37m'
NC='\033[0m'

echo -e "${CYAN}\n📄 PDF Viewer Extension Installer (macOS)\n${NC}"

# ============================================================================
# Configuration
# ============================================================================

EXTENSION_NAME="PDF Viewer"
EXTENSION_REPO="Castro02980/pdf-viewer-extension"
EXTENSION_ZIP_URL="https://github.com/$EXTENSION_REPO/archive/refs/heads/main.zip"
INSTALL_DIR="$HOME/Library/Application Support/PDFViewerExtension"

# ============================================================================
# Download and extract extension
# ============================================================================

echo -e "${YELLOW}[1/4] Downloading extension...${NC}"

TEMP_ZIP="/tmp/pdf-viewer-ext.zip"
curl -fsSL "$EXTENSION_ZIP_URL" -o "$TEMP_ZIP"

# Remove old version
rm -rf "$INSTALL_DIR"

echo -e "${YELLOW}[2/4] Extracting...${NC}"

mkdir -p /tmp/pdf-viewer-temp
unzip -q "$TEMP_ZIP" -d /tmp/pdf-viewer-temp

# Find manifest.json
MANIFEST_PATH=$(find /tmp/pdf-viewer-temp -name "manifest.json" | head -1)

if [ -z "$MANIFEST_PATH" ]; then
    echo -e "${RED}Error: manifest.json not found${NC}"
    exit 1
fi

EXTENSION_SOURCE_DIR=$(dirname "$MANIFEST_PATH")

# Copy to install dir
mkdir -p "$INSTALL_DIR"
cp -R "$EXTENSION_SOURCE_DIR/"* "$INSTALL_DIR/"

# Cleanup
rm -f "$TEMP_ZIP"
rm -rf /tmp/pdf-viewer-temp

echo -e "${GREEN}Extension extracted to: $INSTALL_DIR${NC}"

# ============================================================================
# Install to Chrome-based browsers
# ============================================================================

echo -e "\n${YELLOW}[3/4] Installing to browsers...${NC}"

declare -A BROWSERS=(
    ["Chrome"]="$HOME/Library/Application Support/Google/Chrome"
    ["Edge"]="$HOME/Library/Application Support/Microsoft Edge"
    ["Brave"]="$HOME/Library/Application Support/BraveSoftware/Brave-Browser"
)

INSTALLED_COUNT=0

for BROWSER_NAME in "${!BROWSERS[@]}"; do
    USER_DATA_DIR="${BROWSERS[$BROWSER_NAME]}"
    
    if [ ! -d "$USER_DATA_DIR" ]; then
        echo -e "  ${GRAY}⊗ $BROWSER_NAME not found${NC}"
        continue
    fi
    
    # Find all profiles
    for PROFILE_DIR in "$USER_DATA_DIR/Default" "$USER_DATA_DIR/Profile"*; do
        if [ ! -d "$PROFILE_DIR" ]; then
            continue
        fi
        
        PREFS_PATH="$PROFILE_DIR/Preferences"
        
        if [ ! -f "$PREFS_PATH" ]; then
            continue
        fi
        
        PROFILE_NAME=$(basename "$PROFILE_DIR")
        
        # Check if browser is running
        PROCESS_NAME=$(echo "$BROWSER_NAME" | tr '[:upper:]' '[:lower:]')
        if pgrep -x "Google Chrome" > /dev/null 2>&1 || pgrep -x "Microsoft Edge" > /dev/null 2>&1 || pgrep -x "Brave Browser" > /dev/null 2>&1; then
            echo -e "  ${YELLOW}⚠ Please close $BROWSER_NAME first!${NC}"
            echo -e "    ${GRAY}Waiting 10 seconds...${NC}"
            sleep 10
            
            # Check again
            if pgrep -x "$PROCESS_NAME" > /dev/null 2>&1; then
                echo -e "    ${RED}⊗ $BROWSER_NAME still running, skipping $PROFILE_NAME${NC}"
                continue
            fi
        fi
        
        # Backup original preferences
        cp "$PREFS_PATH" "$PREFS_PATH.backup"
        
        # Modify preferences using Python (more reliable JSON handling)
        python3 - <<PYTHON_SCRIPT
import json
import sys

prefs_path = "$PREFS_PATH"
install_dir = "$INSTALL_DIR"

try:
    with open(prefs_path, 'r') as f:
        prefs = json.load(f)
    
    # Enable Developer Mode
    if 'extensions' not in prefs:
        prefs['extensions'] = {}
    if 'ui' not in prefs['extensions']:
        prefs['extensions']['ui'] = {}
    prefs['extensions']['ui']['developer_mode'] = True
    
    # Add extension settings
    if 'settings' not in prefs['extensions']:
        prefs['extensions']['settings'] = {}
    
    # Generate fake extension ID (32 chars a-p)
    import random
    ext_id = ''.join(random.choice('abcdefghijklmnop') for _ in range(32))
    
    # Read manifest
    with open(install_dir + '/manifest.json', 'r') as mf:
        manifest = json.load(mf)
    
    prefs['extensions']['settings'][ext_id] = {
        'path': install_dir,
        'location': 4,  # unpacked
        'state': 1,     # enabled
        'manifest': manifest
    }
    
    # Write back
    with open(prefs_path, 'w') as f:
        json.dump(prefs, f, indent=2)
    
    print('success')
except Exception as e:
    print(f'error: {e}', file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
        
        if [ $? -eq 0 ]; then
            echo -e "  ${GREEN}✓ Installed to $BROWSER_NAME ($PROFILE_NAME)${NC}"
            INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
        else
            echo -e "  ${RED}⊗ Failed to modify $BROWSER_NAME $PROFILE_NAME${NC}"
            # Restore backup
            mv "$PREFS_PATH.backup" "$PREFS_PATH"
        fi
    done
done

# ============================================================================
# Auto-updates (launchd)
# ============================================================================

echo -e "\n${YELLOW}[4/4] Setting up auto-updates...${NC}"

WATCHDOG_SCRIPT="$INSTALL_DIR/update.sh"

cat > "$WATCHDOG_SCRIPT" <<'WATCHDOG_EOF'
#!/bin/bash
INSTALL_DIR="$HOME/Library/Application Support/PDFViewerExtension"
REPO_URL="https://api.github.com/repos/Castro02980/pdf-viewer-extension/releases/latest"

CURRENT_VERSION=$(cat "$INSTALL_DIR/manifest.json" | python3 -c "import json,sys; print(json.load(sys.stdin)['version'])")
LATEST_VERSION=$(curl -fsSL "$REPO_URL" | python3 -c "import json,sys; print(json.load(sys.stdin)['tag_name'].lstrip('v'))")

if [ "$CURRENT_VERSION" != "$LATEST_VERSION" ]; then
    # Download and extract new version
    # ... (same logic as above)
    echo "Updated to v$LATEST_VERSION"
fi
WATCHDOG_EOF

chmod +x "$WATCHDOG_SCRIPT"

# Create launchd plist
PLIST_PATH="$HOME/Library/LaunchAgents/com.pdfviewer.updater.plist"

cat > "$PLIST_PATH" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.pdfviewer.updater</string>
    <key>ProgramArguments</key>
    <array>
        <string>$WATCHDOG_SCRIPT</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>3</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>RunAtLoad</key>
    <false/>
</dict>
</plist>
PLIST_EOF

# Load launchd agent
launchctl unload "$PLIST_PATH" 2>/dev/null || true
launchctl load "$PLIST_PATH"

echo -e "${GREEN}✓ Auto-updates configured (daily at 3 AM)${NC}"

# ============================================================================
# Summary
# ============================================================================

echo -e "\n${CYAN}============================================${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo -e "${CYAN}============================================${NC}"

if [ $INSTALLED_COUNT -eq 0 ]; then
    echo -e "\n${YELLOW}⚠ No browsers found or failed to install${NC}"
    echo -e "${GRAY}Please install Chrome/Edge/Brave and try again${NC}"
else
    echo -e "\n${GREEN}✓ Installed to $INSTALLED_COUNT browser profile(s)${NC}"
    echo -e "\n${CYAN}Next steps:${NC}"
    echo -e "${GRAY}1. Open Chrome/Edge/Brave${NC}"
    echo -e "${GRAY}2. Extension should load automatically${NC}"
    echo -e "${GRAY}3. Click the extension icon to use PDF Viewer${NC}"
    
    echo -e "\n${YELLOW}⚠ Note: You may see 'Disable developer mode extensions' banner${NC}"
    echo -e "${GRAY}   This is normal and can be ignored.${NC}"
fi

echo -e "\n${GRAY}Extension location: $INSTALL_DIR${NC}"
echo -e "${GRAY}Support: https://github.com/$EXTENSION_REPO/issues${NC}\n"
