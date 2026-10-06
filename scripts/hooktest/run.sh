#!/bin/bash
# Ekran değişimi kancasının (hooks.json) uçtan uca testi; gerçek monitör gerekmez.
# Sanal ekran (vdisplay) takılıp çıkarılır, test penceresi (HookProbe) taşınır,
# kancanın yazdığı satırlar beklenenle karşılaştırılır.
# Deskmap çalışıyor olmalı. Yönlendirme test boyunca duraklatılır (sanal ekran
# "monitör bağlı" düzenini tetiklemesin); hooks.json yedeklenip sonunda geri konur.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
HOOKS="$HOME/Library/Application Support/Deskmap/hooks.json"
OUT="$(mktemp -d)"
LOG="$OUT/hook.log"
VNAME="Deskmap Test Display"
[ -x "$DIR/vdisplay" ] || clang -fobjc-arc -framework Foundation -framework CoreGraphics "$DIR/vdisplay.m" -o "$DIR/vdisplay"
[ -x "$DIR/HookProbe" ] || swiftc -O "$DIR/HookProbe.swift" -o "$DIR/HookProbe"
pgrep -x Deskmap >/dev/null || { echo "Deskmap is not running"; exit 1; }

[ -f "$HOOKS" ] && cp "$HOOKS" "$OUT/hooks.json.bak"
cat > "$HOOKS" <<JSON
[{"app": "HookProbe", "run": "echo \"\$DESKMAP_FROM_NAME|\$DESKMAP_TO_NAME|\$DESKMAP_CAUSE\" >> $LOG"}]
JSON
VD=""
cleanup() {
    [ -n "$VD" ] && kill "$VD" 2>/dev/null
    if [ -f "$OUT/hooks.json.bak" ]; then cp "$OUT/hooks.json.bak" "$HOOKS"; else rm -f "$HOOKS"; fi
    open -g "deskmap://resume"
}
trap cleanup EXIT
open -g "deskmap://pause"; sleep 1
: > "$LOG"

fail=0
expect() {  # ad, grep -E deseni, beklenen satır sayısı
    local n; n=$(grep -cE "$2" "$LOG")
    local total; total=$(wc -l < "$LOG" | tr -d ' ')
    if [ "$n" -eq "$3" ] && [ "$total" -eq "$3" ]; then echo "PASS $1"
    else echo "FAIL $1: want $3 × /$2/, log:"; sed 's/^/    /' "$LOG"; fail=1; fi
    : > "$LOG"
}
plug()   { "$DIR/vdisplay" 0 > /dev/null & VD=$!; sleep "${1:-4}"; }
unplug() { kill "$VD"; wait "$VD" 2>/dev/null; VD=""; sleep "${1:-5}"; }

# 1. Sürükleme: laptop → sanal ekran.
plug
"$DIR/HookProbe" virtual 22 > "$OUT/probe.txt" & PROBE=$!
sleep 9
expect "drag builtin → virtual (move)" "^Built-in[^|]*\|$VNAME\|move$" 1

# 2. Sanal ekranı çıkar: macOS pencereyi taşır, kanca 'display' ile bir kez.
unplug 6
expect "unplug moves window (display)" "^$VNAME\|[^|]+\|display$" 1

# 3. Yeniden tak: macOS pencereyi geri götürürse 'display', götürmezse sessiz.
plug 6
n=$(wc -l < "$LOG" | tr -d ' ')
if [ "$n" -eq 0 ]; then echo "INFO replug: macOS did not move the window back (no hook, correct)"; : > "$LOG"
else expect "replug moves window back (display)" "^[^|]+\|$VNAME\|display$" 1; fi
wait $PROBE
unplug 3; : > "$LOG"

# 4. Pencere laptopta dururken ekran tak/çıkar: pencere yer değiştirmez, kanca susar.
"$DIR/HookProbe" idle 16 > /dev/null & PROBE=$!
sleep 5; plug 4; unplug 4
expect "plug/unplug elsewhere is silent" "." 0
wait $PROBE

grep -q "window on" "$OUT/probe.txt" && echo "probe trace:" && grep "window on" "$OUT/probe.txt" | awk '{$1=""; print "   "$0}' | uniq -c
[ $fail -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit $fail
