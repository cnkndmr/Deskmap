#!/bin/bash
# İkinci harici monitör ölçümü: gerçek monitör gerekmez. İki sanal ekran (aynı ad
# ve model, farklı seri) takılır, biri çıkarılıp yeniden takılır, sonra aynı seriyle
# üçüncüsü (EDID'i aynı iki monitör) eklenir. Ölçülen: UUID'ler ayrı mı, yeniden
# takınca UUID / ekran kimliği aynı mı, yeniden yapılandırma olayları, çıkarılan
# ekrandaki pencereyi macOS nereye koyuyor ve geri götürüyor mu, Deskmap'in rolleri.
# Deskmap çalışıyor olmalı; yönlendirme test boyunca duraklatılır (run.sh gibi) ve
# sonunda sürdürülür. Sanal ekranlar "Deskmap Test Display" adını taşır: Deskmap
# onları hatırlamaz, öğrenmez (rules.json'da iz kalmaz).
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
CLI="$DIR/../deskmap"
OUT="$(mktemp -d)"
[ -x "$DIR/vdisplay" ] || clang -fobjc-arc -framework Foundation -framework CoreGraphics "$DIR/vdisplay.m" -o "$DIR/vdisplay"
[ -x "$DIR/MonProbe" ] || swiftc -O "$DIR/MonProbe.swift" -o "$DIR/MonProbe"
pgrep -x Deskmap >/dev/null || { echo "Deskmap is not running"; exit 1; }
A=""; B=""; C=""; W=""; WIN=""
cleanup() {
    for p in $A $B $C $W $WIN; do kill "$p" 2>/dev/null; done
    wait 2>/dev/null
    open -g "deskmap://resume"
}
trap cleanup EXIT
open -g "deskmap://pause"; sleep 1
fail=0
ok()   { echo "PASS $1"; }
bad()  { echo "FAIL $1"; fail=1; }
info() { echo "INFO $1"; }
uuids() { "$DIR/MonProbe" list | grep 'name="Deskmap Test Display"' | sed -E 's/.*id=([0-9]+) uuid=([^ ]+) .*serial=([0-9]+).*/\3 \2 \1/' | sort; }

"$DIR/MonProbe" watch 120 > "$OUT/reconfig.log" & W=$!
"$DIR/vdisplay" 0 1920 1080 1 > /dev/null & A=$!; sleep 4
"$DIR/vdisplay" 0 2560 1440 2 > /dev/null & B=$!; sleep 5
uuids > "$OUT/two.txt"; cat "$OUT/two.txt" | sed 's/^/    serial uuid id: /'
[ "$(wc -l < "$OUT/two.txt")" -eq 2 ] && [ "$(cut -d' ' -f2 "$OUT/two.txt" | sort -u | wc -l)" -eq 2 ] \
    && ok "same model, different serials: two different UUIDs" || bad "two displays, two UUIDs"
"$CLI" screens | sed 's/^/    deskmap: /'

# Pencere 2. sanal ekranda (soldan sağa). Ekranı çıkar, yeniden tak.
"$DIR/MonProbe" window 40 2 > "$OUT/window.log" & WIN=$!; sleep 4
B_UUID=$(awk '$1==2{print $2}' "$OUT/two.txt"); B_ID=$(awk '$1==2{print $3}' "$OUT/two.txt")
kill "$B"; wait "$B" 2>/dev/null; B=""; sleep 6
tail -1 "$OUT/window.log" | sed 's/^/    after unplug: /'
grep -q "uuid=${B_UUID:0:8}" <(tail -1 "$OUT/window.log") && bad "window left on a removed display" \
    || ok "unplug: macOS moved the window off the removed display"
"$DIR/vdisplay" 0 2560 1440 2 > /dev/null & B=$!; sleep 6
uuids > "$OUT/replug.txt"
R_UUID=$(awk '$1==2{print $2}' "$OUT/replug.txt"); R_ID=$(awk '$1==2{print $3}' "$OUT/replug.txt")
[ "$R_UUID" = "$B_UUID" ] && ok "replug: same UUID ($B_UUID)" || bad "replug: UUID changed $B_UUID -> $R_UUID"
[ "$R_ID" = "$B_ID" ] && info "replug: same display id $B_ID" || info "replug: display id changed $B_ID -> $R_ID (so never store the id)"
tail -1 "$OUT/window.log" | grep -q "uuid=${B_UUID:0:8}" && info "replug: macOS moved the window back" \
    || info "replug: macOS did not move the window back (Deskmap's pin has to)"

# EDID'i aynı iki monitör: A ile aynı seri.
"$DIR/vdisplay" 0 1920 1080 1 > /dev/null & C=$!; sleep 6
uuids > "$OUT/dup.txt"; sed 's/^/    serial uuid id: /' "$OUT/dup.txt"
n=$(awk '$1==1' "$OUT/dup.txt" | wc -l | tr -d ' '); u=$(awk '$1==1{print $2}' "$OUT/dup.txt" | sort -u | wc -l | tr -d ' ')
if [ "$n" -eq 2 ] && [ "$u" -eq 2 ]; then ok "identical EDID: macOS still gives two UUIDs"
elif [ "$n" -eq 2 ]; then info "identical EDID: both share one UUID (Deskmap counts them once)"
else info "identical EDID: only $n display(s) appeared"; fi
"$CLI" screens | sed 's/^/    deskmap: /'
kill "$C"; wait "$C" 2>/dev/null; C=""
kill "$A" "$B"; wait "$A" "$B" 2>/dev/null; A=""; B=""; sleep 4
echo "reconfiguration events:"; awk '{$1=""; print "   "$0}' "$OUT/reconfig.log" | sort | uniq -c | sort -rn | head -12
echo "window trace:"; awk '{$1=""; print "   "$0}' "$OUT/window.log" | uniq -c
echo "logs: $OUT"
[ $fail -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit $fail
