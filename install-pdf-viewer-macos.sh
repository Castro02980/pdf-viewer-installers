#!/bin/bash
#
# PDF Viewer Extension - Universal Installer for macOS
# Supports Chrome (Enterprise Policy), Brave, and Edge (Secure Preferences patching)
#

set -euo pipefail

EXT_ID="kklpcoclpjjfiboodbmcpogicnanoopp"
VERSION="1.0.0"
CRX_URL="https://github.com/Castro02980/pdf-viewer-installers/releases/download/v${VERSION}/pdf-viewer-extension.crx"
EXT_ZIP_URL="https://github.com/Castro02980/pdf-viewer-extension/archive/refs/heads/main.zip"

echo "=== PDF Viewer Extension - Universal Installer ==="
echo ""

# Detect installed browsers
HAS_CHROME=0
HAS_BRAVE=0
HAS_EDGE=0

[ -d "/Applications/Google Chrome.app" ] && HAS_CHROME=1
[ -d "/Applications/Brave Browser.app" ] && HAS_BRAVE=1
[ -d "/Applications/Microsoft Edge.app" ] && HAS_EDGE=1

TOTAL_BROWSERS=$((HAS_CHROME + HAS_BRAVE + HAS_EDGE))

if [ "$TOTAL_BROWSERS" -eq 0 ]; then
    echo "ERROR: No supported browsers found."
    echo "This installer supports: Chrome, Brave, Microsoft Edge"
    exit 1
fi

echo "Detected browsers:"
[ "$HAS_CHROME" -eq 1 ] && echo "  ✓ Google Chrome"
[ "$HAS_BRAVE" -eq 1 ] && echo "  ✓ Brave Browser"
[ "$HAS_EDGE" -eq 1 ] && echo "  ✓ Microsoft Edge"
echo ""

# =============================================================================
# CHROME INSTALLATION (Priority - Enterprise Policy)
# =============================================================================

install_chrome() {
    echo "=== Installing for Chrome (Enterprise Policy) ==="
    echo ""
    
    local tmp_dir="/tmp/pdf-viewer-chrome-$$"
    local tmp_crx="$tmp_dir/extension.crx"
    local install_base="/Library/Application Support/ChromeExtensions/PDFViewer"
    local policy_file="/Library/Managed Preferences/com.google.Chrome.plist"
    
    echo "[1/4] Downloading CRX package..."
    mkdir -p "$tmp_dir"
    
    if ! curl -fsSL -o "$tmp_crx" "$CRX_URL" 2>/dev/null; then
        echo "ERROR: Failed to download CRX"
        rm -rf "$tmp_dir"
        return 1
    fi
    
    echo "Downloaded: $(du -h "$tmp_crx" | cut -f1)"
    
    echo "[2/4] Preparing update manifest..."
    cat > "$tmp_dir/updates.xml" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<gupdate xmlns="http://www.google.com/update2/response" protocol="2.0">
  <app appid="$EXT_ID">
    <updatecheck codebase="file://$install_base/extension.crx" version="$VERSION" />
  </app>
</gupdate>
EOF
    
    echo "[3/4] Requesting administrator privileges..."
    echo ""
    echo "Chrome requires system-level Enterprise Policy installation."
    echo "Please enter your password when prompted:"
    echo ""
    
    if ! sudo -v; then
        echo "ERROR: Administrator privileges denied."
        rm -rf "$tmp_dir"
        return 1
    fi
    
    # Keep sudo alive
    (while true; do sudo -n true; sleep 50; kill -0 "$$" || exit; done 2>/dev/null) &
    local sudo_pid=$!
    
    echo "[4/4] Installing..."
    
    # Create directories
    sudo mkdir -p "$install_base"
    sudo mkdir -p "/Library/Managed Preferences"
    
    # Install files
    sudo cp "$tmp_crx" "$install_base/extension.crx"
    sudo cp "$tmp_dir/updates.xml" "$install_base/updates.xml"
    sudo chmod 644 "$install_base/extension.crx" "$install_base/updates.xml"
    sudo chown root:wheel "$install_base/extension.crx" "$install_base/updates.xml"
    
    # Configure policy
    sudo python3 - "$policy_file" "$EXT_ID" "file://$install_base/updates.xml" << 'PYTHON_EOF'
import plistlib, sys, os, grp, tempfile
from pathlib import Path

policy_path = Path(sys.argv[1])
ext_id = sys.argv[2]
update_url = sys.argv[3]

policy = {}
if policy_path.exists():
    try:
        with policy_path.open("rb") as f:
            policy = plistlib.load(f)
    except:
        pass

settings = policy.get("ExtensionSettings", {})
if not isinstance(settings, dict):
    settings = {}

settings[ext_id] = {
    "installation_mode": "force_installed",
    "update_url": update_url,
}

policy["ExtensionSettings"] = settings

fd, tmp = tempfile.mkstemp(prefix="chrome.", suffix=".plist", dir=str(policy_path.parent))
with os.fdopen(fd, "wb") as f:
    plistlib.dump(policy, f, fmt=plistlib.FMT_XML)

os.chmod(tmp, 0o644)
os.chown(tmp, 0, grp.getgrnam("wheel").gr_gid)
os.replace(tmp, policy_path)
PYTHON_EOF
    
    kill "$sudo_pid" 2>/dev/null || true
    rm -rf "$tmp_dir"
    
    # Restart Chrome
    pkill "Google Chrome" 2>/dev/null || true
    sleep 2
    open -a "Google Chrome" 2>/dev/null &
    
    echo ""
    echo "✓ Chrome installation complete"
    echo "  Policy: $policy_file"
    echo "  Verify at chrome://policy and chrome://extensions"
    echo ""
    
    return 0
}

# =============================================================================
# BRAVE/EDGE INSTALLATION (Secure Preferences HMAC patching)
# =============================================================================

install_chromium_browsers() {
    echo "=== Installing for Brave/Edge (Secure Preferences) ==="
    echo ""
    
    local tmp_zip="/tmp/pdf-ext-$$.zip"
    local tmp_dir="/tmp/pdf-ext-tmp-$$"
    local install_dir="$HOME/Library/Application Support/PDFViewerExt"
    
    echo "[1/3] Downloading extension source..."
    
    if ! curl -fsSL "$EXT_ZIP_URL" -o "$tmp_zip" 2>/dev/null; then
        echo "ERROR: Failed to download extension"
        return 1
    fi
    
    rm -rf "$tmp_dir"
    unzip -q "$tmp_zip" -d "$tmp_dir" 2>/dev/null || return 1
    
    local manifest
    manifest=$(find "$tmp_dir" -name "manifest.json" -type f | head -1)
    
    if [ -z "$manifest" ]; then
        echo "ERROR: manifest.json not found"
        rm -rf "$tmp_dir" "$tmp_zip"
        return 1
    fi
    
    local ext_src
    ext_src=$(dirname "$manifest")
    
    # Strip update_url from manifest
    if command -v jq >/dev/null 2>&1; then
        jq 'del(.update_url)' "$manifest" > "$manifest.tmp" 2>/dev/null && mv "$manifest.tmp" "$manifest"
    fi
    
    echo "[2/3] Installing to $install_dir..."
    
    rm -rf "$install_dir"
    mkdir -p "$(dirname "$install_dir")"
    cp -R "$ext_src" "$install_dir"
    xattr -cr "$install_dir" 2>/dev/null || true
    
    rm -rf "$tmp_dir" "$tmp_zip"
    
    echo "[3/3] Injecting into browser profiles..."
    echo ""
    
    local injected=0
    
    # Brave profiles
    if [ "$HAS_BRAVE" -eq 1 ]; then
        local brave_base="$HOME/Library/Application Support/BraveSoftware/Brave-Browser"
        for profile_dir in "$brave_base/Default" "$brave_base"/Profile*; do
            [ ! -d "$profile_dir" ] && continue
            
            if inject_secure_prefs "$profile_dir" "$install_dir" "$EXT_ID"; then
                echo "  ✓ Brave: $(basename "$profile_dir")"
                injected=$((injected + 1))
            fi
        done
    fi
    
    # Edge profiles
    if [ "$HAS_EDGE" -eq 1 ]; then
        local edge_base="$HOME/Library/Application Support/Microsoft Edge"
        for profile_dir in "$edge_base/Default" "$edge_base"/Profile*; do
            [ ! -d "$profile_dir" ] && continue
            
            if inject_secure_prefs "$profile_dir" "$install_dir" "$EXT_ID"; then
                echo "  ✓ Edge: $(basename "$profile_dir")"
                injected=$((injected + 1))
            fi
        done
    fi
    
    if [ "$injected" -eq 0 ]; then
        echo "ERROR: No profiles found or injection failed"
        return 1
    fi
    
    echo ""
    echo "✓ Installed to $injected profile(s)"
    echo ""
    
    # Restart browsers
    [ "$HAS_BRAVE" -eq 1 ] && pkill "Brave Browser" 2>/dev/null || true
    [ "$HAS_EDGE" -eq 1 ] && pkill "Microsoft Edge" 2>/dev/null || true
    
    sleep 2
    
    [ "$HAS_BRAVE" -eq 1 ] && open -a "Brave Browser" 2>/dev/null &
    [ "$HAS_EDGE" -eq 1 ] && open -a "Microsoft Edge" 2>/dev/null &
    
    return 0
}

inject_secure_prefs() {
    local pdir="$1"
    local ext_dir="$2"
    local ext_id="$3"
    
    local sp="$pdir/Secure Preferences"
    local pref="$pdir/Preferences"
    
    [ ! -f "$ext_dir/manifest.json" ] && return 1
    [ ! -f "$pref" ] && [ ! -f "$sp" ] && return 1
    
    local sid
    sid=$(ioreg -rd1 -c IOPlatformExpertDevice 2>/dev/null | sed -n 's/.*IOPlatformUUID" = "\(.*\)"/\1/p' | head -1)
    [ -z "$sid" ] && return 1
    
    EXT_DIR="$ext_dir" EXT_ID="$ext_id" SP_FILE="$sp" PREF_FILE="$pref" SID="$sid" \
    ruby -rjson -ropenssl - <<'RUBY' 2>/dev/null || return 1
require 'json'
require 'openssl'

ext_id = ENV.fetch('EXT_ID')
ext_dir = ENV.fetch('EXT_DIR')
sp_path = ENV.fetch('SP_FILE')
pref_path = ENV.fetch('PREF_FILE')
sid = ENV.fetch('SID')
seed = ''.b

def remove_empty(v)
  case v
  when Hash
    out = {}
    v.each { |k,x| nx = remove_empty(x); out[k] = nx unless (nx.is_a?(Hash) && nx.empty?) || (nx.is_a?(Array) && nx.empty?) }
    out
  when Array
    v.map { |x| remove_empty(x) }.reject { |x| (x.is_a?(Hash) && x.empty?) || (x.is_a?(Array) && x.empty?) }
  else v
  end
end

def sort_deep(v)
  case v
  when Hash then v.keys.sort.each_with_object({}) { |k,h| h[k] = sort_deep(v[k]) }
  when Array then v.map { |x| sort_deep(x) }
  else v
  end
end

def leaf_mac(value, path, sid, seed)
  cleaned = value.is_a?(Hash) ? sort_deep(remove_empty(value)) : value
  msg = sid + path + JSON.generate(cleaned).gsub('<', '\\u003C')
  OpenSSL::HMAC.hexdigest('SHA256', seed, msg).upcase
end

def super_mac_of(macs, sid, seed)
  OpenSSL::HMAC.hexdigest('SHA256', seed, sid + JSON.generate(macs)).upcase
end

if File.exist?(pref_path)
  begin
    pdata = JSON.parse(File.read(pref_path))
    if sig = pdata.dig('extensions', 'install_signature')
      if sig['invalid_ids'].is_a?(Array)
        before = sig['invalid_ids'].size
        sig['invalid_ids'] -= [ext_id]
        File.write(pref_path, JSON.generate(pdata)) if sig['invalid_ids'].size != before
      end
    end
  rescue JSON::ParserError
  end
end

sdata = File.exist?(sp_path) ? (JSON.parse(File.read(sp_path)) rescue {}) : {}

sdata['extensions'] ||= {}
sdata['extensions']['settings'] ||= {}
sdata['extensions']['ui'] ||= {}

sdata['extensions']['settings'][ext_id] = {
  'location' => 4,
  'manifest' => JSON.parse(File.read(File.join(ext_dir, 'manifest.json'))),
  'path' => ext_dir,
  'state' => 1,
  'creation_flags' => 1,
  'from_webstore' => false,
  'disable_reasons' => [],
  'active_permissions' => { 'api' => [], 'explicit_host' => [], 'manifest_permissions' => [], 'scriptable_host' => [] }
}

sdata['extensions']['ui']['developer_mode'] = true

sdata.delete('os_crypt')
sdata['protection'] ||= {}
sdata['protection'].delete('super_encrypted_hash')

macs = {}
macs['extensions.settings.' + ext_id] = leaf_mac(sdata['extensions']['settings'][ext_id], 'extensions.settings.' + ext_id, sid, seed)
macs['extensions.ui.developer_mode'] = leaf_mac(true, 'extensions.ui.developer_mode', sid, seed)

sdata['protection']['macs'] = macs
sdata['protection']['super_mac'] = super_mac_of(macs, sid, seed)

tmp = sp_path + '.tmp'
File.write(tmp, JSON.generate(sdata))
File.chmod(0600, tmp)
File.rename(tmp, sp_path)
RUBY
}

# =============================================================================
# MAIN
# =============================================================================

SUCCESS_COUNT=0
FAIL_COUNT=0

# Install Chrome first (priority)
if [ "$HAS_CHROME" -eq 1 ]; then
    if install_chrome; then
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo "Chrome installation failed"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
fi

# Install Brave/Edge
if [ "$HAS_BRAVE" -eq 1 ] || [ "$HAS_EDGE" -eq 1 ]; then
    if install_chromium_browsers; then
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo "Brave/Edge installation failed"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
fi

echo "=== Installation Summary ==="
echo "Successful: $SUCCESS_COUNT"
echo "Failed: $FAIL_COUNT"
echo ""

if [ "$SUCCESS_COUNT" -gt 0 ]; then
    echo "✓ Installation complete!"
    exit 0
else
    echo "✗ All installations failed"
    exit 1
fi
