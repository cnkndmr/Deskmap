#!/bin/bash
# Sıralı yerlerin (docs/bug-tables.md §D) uçtan uca testi: gerçek monitör
# gerekmez. Sanal ekranlar (vdisplay) takılıp çıkarılır, test penceresi
# (MonProbe) gerçek AX/SkyLight yönlendirmesiyle taşınır.
#
# Güvenlik:
# - Test, bu depodan derlenmiş ayrı bir Deskmap kopyasıyla ve boş, geçici bir
#   veri klasörüyle (DESKMAP_DATA_DIR) çalışır; kullanıcının rules.json'una
#   dokunulmaz. Tek kural test penceresi içindir.
# - DESKMAP_TEST_NO_DESKTOP_CHANGES=1: test kopyası hiçbir masaüstü açmaz,
#   silmez (plansız belge boş masaüstleri artık sayardı).
# - DESKMAP_LEARN_TEST_DISPLAYS=1: sanal ekranlar gerçek monitör gibi rol öğrenir.
# - Kurulu Deskmap (/Applications) çalışıyorsa önce deskmap://quit ile kapatılır,
#   sonda (hata ya da Ctrl-C dahil) yeniden açılır ve çalıştığı denetlenir.
# - Yalnız bu betiğin başlattığı süreçler PID'leriyle kapatılır.
#
# Kullanım: scripts/hooktest/places.sh [Deskmap.app yolu]
#   Varsayılan build/Deskmap.app. Erişilebilirlik izni imzaya bağlıdır: kurulu
#   kopyayla aynı kimlikle imzala (make app SIGN_IDENTITY="Apple Development: …"),
#   ad-hoc imzalı kopyada pencereler taşınamaz.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"
APP="$(cd "$(dirname "${1:-$ROOT/build/Deskmap.app}")" && pwd)/$(basename "${1:-$ROOT/build/Deskmap.app}")"
BIN="$APP/Contents/MacOS/Deskmap"
INSTALLED="/Applications/Deskmap.app"
INSTALLED_BIN="$INSTALLED/Contents/MacOS/Deskmap"
CLI="$ROOT/scripts/deskmap"
DATA="$(mktemp -d)"
OUT="$(mktemp -d)"
export DESKMAP_DATA_DIR="$DATA" DESKMAP_APP="$APP"

[ -x "$BIN" ] || { echo "places: $BIN missing (make app SIGN_IDENTITY=…)"; exit 2; }
[ "$BIN" != "$INSTALLED_BIN" ] || { echo "places: give the test build, not the installed copy"; exit 2; }
if ! codesign -dv --verbose=2 "$APP" 2>&1 | grep -q "^Authority=Apple Development"; then
    echo "places: $APP is not signed with an Apple Development identity;"
    echo "        Accessibility (TCC) would not apply. Build with:"
    echo "        make app SIGN_IDENTITY=\"Apple Development: …\""
    exit 2
fi
if ioreg -n Root -d1 -a 2>/dev/null | grep -q CGSSessionScreenIsLocked; then
    echo "places: the screen is locked; windows can't be moved. Unlock and run again."
    exit 2
fi
[ -x "$DIR/vdisplay" ] || clang -fobjc-arc -framework Foundation -framework CoreGraphics "$DIR/vdisplay.m" -o "$DIR/vdisplay"
[ -x "$DIR/MonProbe" ] || swiftc -O "$DIR/MonProbe.swift" -o "$DIR/MonProbe"

# Çalışan Deskmap kopyaları: yalnız kurulu kopya beklenir.
pids_at() { for p in $(pgrep -x Deskmap); do [ "$(ps -o comm= -p "$p")" = "$1" ] && echo "$p"; done; }
for p in $(pgrep -x Deskmap); do
    path=$(ps -o comm= -p "$p")
    if [ "$path" != "$INSTALLED_BIN" ]; then
        echo "places: another Deskmap copy is running ($p: $path); stop it first"; exit 2
    fi
done
WAS_RUNNING=0
[ -n "$(pids_at "$INSTALLED_BIN")" ] && WAS_RUNNING=1

A=""; B=""; C=""; WIN=""; TEST_PID=""
restore() {
    for p in $A $B $C $WIN; do kill "$p" 2>/dev/null; done
    wait 2>/dev/null
    if [ -n "$TEST_PID" ] && kill -0 "$TEST_PID" 2>/dev/null; then
        open -g -a "$APP" "deskmap://quit"
        for _ in $(seq 20); do kill -0 "$TEST_PID" 2>/dev/null || break; sleep 0.25; done
        kill "$TEST_PID" 2>/dev/null
    fi
    if [ "$WAS_RUNNING" -eq 1 ]; then
        open -g -a "$INSTALLED"
        for _ in $(seq 40); do [ -n "$(pids_at "$INSTALLED_BIN")" ] && break; sleep 0.25; done
        p=$(pids_at "$INSTALLED_BIN")
        if [ -n "$p" ]; then echo "RESTORED installed Deskmap running: pid $p $INSTALLED_BIN"
        else echo "WARNING installed Deskmap did not start again: open $INSTALLED"; fi
    fi
    sleep 1; rm -rf "$DATA" 2>/dev/null || { sleep 2; rm -rf "$DATA"; }
    echo "logs: $OUT"
}
trap restore EXIT
trap 'exit 130' INT TERM

if [ "$WAS_RUNNING" -eq 1 ]; then
    open -g -a "$INSTALLED" "deskmap://quit"
    for _ in $(seq 40); do [ -z "$(pids_at "$INSTALLED_BIN")" ] && break; sleep 0.25; done
    [ -z "$(pids_at "$INSTALLED_BIN")" ] || { echo "places: installed Deskmap did not quit"; exit 2; }
fi

# Kurulu kopya yeni kapandıysa Launch Services ilk açmayı bazen yutar: üç deneme.
sleep 1
for attempt in 1 2 3; do
    open -n -g -a "$APP" --env DESKMAP_DATA_DIR="$DATA" --env DESKMAP_LEARN_TEST_DISPLAYS=1 \
        --env DESKMAP_TEST_NO_DESKTOP_CHANGES=1 2> "$OUT/open.log" || sed 's/^/    open: /' "$OUT/open.log"
    for _ in $(seq 40); do TEST_PID=$(pids_at "$BIN"); [ -n "$TEST_PID" ] && break; sleep 0.25; done
    [ -n "$TEST_PID" ] && break
    sleep 2
done
[ -n "$TEST_PID" ] || { echo "places: the test build did not start"; exit 2; }
for _ in $(seq 40); do [ -f "$DATA/status.json" ] && break; sleep 0.25; done
echo "test build: pid $TEST_PID, data $DATA"

fail=0
ok()   { echo "PASS $1"; }
bad()  { echo "FAIL $1"; fail=1; }
info() { echo "INFO $1"; }
status() { "$CLI" status > /dev/null 2>&1   # status.json'u şimdi yazdırır
    python3 - "$DATA/status.json" "$@" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
what = sys.argv[2]
if what == "role":                      # role <uuid> → rol
    print(next((sc["id"] for sc in s["screens"] if sc.get("uuid") == sys.argv[3]), "-"))
elif what == "held":
    print(" ".join(s.get("heldRoles", [])))
elif what == "windows":
    print(len(s.get("windows", [])))
elif what == "place":                   # MonProbe penceresinin place alanı
    print(next((w.get("place") or "-" for w in s["windows"] if w["app"] == "MonProbe"), "-"))
elif what == "listed":                  # MonProbe penceresi listede mi
    print("yes" if any(w["app"] == "MonProbe" for w in s.get("windows", [])) else "no")
elif what == "rule":                    # test kuralının monitörlü yerleri
    r = next((r for r in s["rules"] if r["id"] == "PLACES-TEST"), None)
    print(" ".join(d["screen"] for d in ([r["docked"]] + r.get("dockedNext", [])) if d) if r else "-")
PY
}
# Sanal ekranların UUID'leri seriye göre (MonProbe list).
# macOS aynı adlı ekranları "Deskmap Test Display (1)", "(2)" diye adlandırır.
uuid_of() { "$DIR/MonProbe" list | grep 'name="Deskmap Test Display' | grep "serial=$1 " \
    | sed -E 's/.*uuid=([^ ]+) .*/\1/' | head -1; }
# Test penceresinin şu an durduğu ekranın UUID öneki (MonProbe window izi).
window_uuid() { tail -1 "$OUT/window.log" | sed -E 's/.*uuid=([^ ]+) .*/\1/'; }
wait_window_on() {  # wait_window_on <uuid> <saniye>
    local want="${1:0:8}"
    for _ in $(seq $(( ${2:-20} * 2 ))); do [ "$(window_uuid)" = "$want" ] && return 0; sleep 0.5; done
    return 1
}
cli() { "$CLI" "$@" > "$OUT/cli.log" 2>&1 || { echo "    cli: $*"; sed 's/^/    /' "$OUT/cli.log"; }; }
rule_json() {  # rule_json <ilk rol> [sonraki roller…]
    python3 - "$@" <<'PY'
import json, sys
roles = sys.argv[1:]
place = lambda r: {"screen": r, "desktop": 1, "layout": {"x": 0, "y": 0, "w": 0.5, "h": 0.5}}
rule = {"id": "PLACES-TEST", "appName": "MonProbe", "bundleID": "", "tokens": ["MonProbe"],
        "docked": place(roles[0])}
if len(roles) > 1:
    rule["dockedNext"] = [place(r) for r in roles[1:]]
print(json.dumps(rule, separators=(",", ":")))
PY
}
set_rule() {  # yalnız test penceresinin kuralı: sil, yenisini ekle, eklendiğini doğrula
    [ "$(status rule)" != "-" ] && cli rule rm PLACES-TEST
    open -g -a "$APP" "deskmap://rule-add?json=$(rule_json "$@" \
        | python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.stdin.read().strip()))')"
    for _ in $(seq 20); do [ "$(status rule)" = "$*" ] && return 0; sleep 0.5; done
    bad "rule not added: want '$*', have '$(status rule)'"
}

# 1. İki monitör (seri 1 ve 2): roller ilk bağlanışta öğrenilir.
"$DIR/vdisplay" 0 1920 1080 1 > /dev/null & A=$!; sleep 4
"$DIR/vdisplay" 0 1920 1080 2 > /dev/null & B=$!; sleep 6
UA=$(uuid_of 1); UB=$(uuid_of 2)
RA=$(status role "$UA"); RB=$(status role "$UB")
echo "    monitor A ${UA:0:8} = $RA, monitor B ${UB:0:8} = $RB, held: $(status held)"
[ "$RA" != "-" ] && [ "$RB" != "-" ] && [ "$RA" != "$RB" ] && ok "two virtual monitors get two roles" \
    || { bad "roles not learned (is DESKMAP_LEARN_TEST_DISPLAYS honoured?)"; exit 1; }
# A ilk monitör: kendiliğinden öğrenilir. B sonra geldi: onay bekler (K6);
# "sıranın sonuna ekle" ile onaylanır.
[ -n "$(status held)" ] && ok "second monitor waits for a choice" || info "second monitor was not held"
cli screen-role "${UB:0:8}" "$RB"
sleep 2
[ -z "$(status held)" ] && ok "second monitor confirmed (add to the end)" || bad "B still held: $(status held)"

# Pencere kendini hiçbir sanal ekrana koymaz (99): yalnız Deskmap taşır.
"$DIR/MonProbe" window 280 99 > "$OUT/window.log" & WIN=$!
# İlk tarama çok uygulamalı masada birkaç saniye sürer: test penceresi
# listelenene dek bekle (en çok 45 sn).
listed=0
for _ in $(seq 45); do [ "$(status listed)" = "yes" ] && { listed=1; break; }; sleep 1; done
if [ "$listed" -eq 0 ]; then
    if /usr/bin/log show --last 3m --predicate "processID == $TEST_PID" --style compact 2>/dev/null \
        | grep -q "accessibility trusted: false"; then
        bad "no Accessibility permission for $APP"
        echo "    Grant it in System Settings › Privacy & Security › Accessibility (Deskmap),"
        echo "    or sign the build with the same identity as the installed copy."
    else
        bad "the test window was never listed (scan too slow?)"
    fi
    exit 1
fi
ok "the test window is listed (Accessibility works)"

# 2. Liste: önce B, sonra A. İkisi de bağlı → B (D1.3).
set_rule "$RB" "$RA"
wait_window_on "$UB" 20 && ok "first connected place wins: Deskmap moved the window to B" \
    || bad "window not on B (on $(window_uuid))"
[ "$(status place)" = "1" ] && ok "status.json place = 1" || bad "status place = $(status place)"

# 3. B'yi çıkar → listedeki sonraki yer A (D1.5).
kill "$B"; wait "$B" 2>/dev/null; B=""; sleep 2
wait_window_on "$UA" 25 && ok "unplug B: window goes to the next place (A)" || bad "after unplug not on A (on $(window_uuid))"
[ "$(status place)" = "2" ] && ok "status.json place = 2" || bad "status place = $(status place)"

# 4. B'yi yeniden tak → B'ye döner (D1.7).
"$DIR/vdisplay" 0 1920 1080 2 > /dev/null & B=$!; sleep 2
wait_window_on "$UB" 30 && ok "replug B: window goes back to B" || bad "after replug not on B (on $(window_uuid))"

# 5. Yedek: tek yer hiç bağlanmamış bir rolde → rol sırasında ilk bağlı monitör (K4).
set_rule "external-5"
FIRST=$( [ "$RA" = "external" ] && echo "$UA" || echo "$UB" )
wait_window_on "$FIRST" 20 && ok "fallback: no place connected → first monitor in role order" \
    || bad "fallback not on the first monitor (on $(window_uuid))"
[ "$(status place)" = "fallback" ] && ok "status.json place = fallback" || bad "status place = $(status place)"

# 6. Rol takası (K5): liste B, A; B'yi A'nın rolüne seç → roller ve düzen yer değiştirir.
set_rule "$RB" "$RA"
wait_window_on "$UB" 20 || info "window not on B before the swap"
cli screen-role "${UB:0:8}" "$RA"
sleep 3
[ "$(status role "$UB")" = "$RA" ] && [ "$(status role "$UA")" = "$RB" ] && ok "swap: roles traded" \
    || bad "swap: roles A=$(status role "$UA") B=$(status role "$UB")"
wait_window_on "$UA" 25 && ok "swap: the layout followed the role (window on A)" || bad "after swap not on A (on $(window_uuid))"
# Geri al.
cli screen-role "${UA:0:8}" "$RA"; sleep 3

# 7. Onay bekleyen yeni monitör (D2.1): C takılır, rolü onay bekler, ona pencere gitmez.
"$DIR/vdisplay" 0 1920 1080 3 > /dev/null & C=$!; sleep 6
UC=$(uuid_of 3); RC=$(status role "$UC")
HELD=$(status held)
echo "    monitor C ${UC:0:8} = $RC, held: $HELD"
[ -n "$HELD" ] && [[ " $HELD " == *" $RC "* ]] && ok "new monitor waits for a choice" || bad "new monitor not on hold"
set_rule "$RC" "$RA"
sleep 4
wait_window_on "$UA" 10 && ok "held monitor gets no window (stays on A)" || bad "window moved while C is on hold (on $(window_uuid))"
# Onayla → pencere C'ye gider.
cli screen-role "${UC:0:8}" "$RC"
wait_window_on "$UC" 25 && ok "confirmed: window goes to C" || bad "after confirming C not on C (on $(window_uuid))"

echo "window trace:"; awk '{$1=""; print "   "$0}' "$OUT/window.log" | uniq -c | tail -20
[ $fail -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit $fail
