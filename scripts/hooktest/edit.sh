#!/bin/bash
# Profil adı, dışa aktarma, masaüstü sırası ve "şu anki boyutu kullan" testi.
# Geçici "Deskmap Test" profilinde çalışır (apply ile kurulur, --undo ile
# dönülür, sonunda silinir); masaüstü sırası yalnız etkin olmayan modda
# denenir (gerçek masaüstleri yer değiştirmesin). Sonunda rules.json'un
# başlangıçla aynı olduğu denetlenir. Deskmap çalışıyor olmalı.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
CLI="$DIR/../deskmap"
RULES="$HOME/Library/Application Support/Deskmap/rules.json"
OUT="$(mktemp -d)"
cp "$RULES" "$OUT/rules.before"
[ -x "$DIR/HookProbe" ] || swiftc -O "$DIR/HookProbe.swift" -o "$DIR/HookProbe"
[ -x "$DIR/resize" ] || swiftc -O "$DIR/resize.swift" -o "$DIR/resize"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=1; }
st()  { "$CLI" status --json | python3 -c "import json,sys; d=json.load(sys.stdin); R={r['appName']:r for r in d['rules']}; print($1)"; }
ACTIVE=$(st 'd.get("profile")'); ACOUNT=$(st 'len(d["rules"])')
MODE=$(st 'd["mode"]'); OTHER=$([ "$MODE" == docked ] && echo undocked || echo docked)

"$DIR/HookProbe" idle 90 > /dev/null & PROBE=$!
cleanup() {
    kill $PROBE 2>/dev/null
    "$CLI" profile "$ACTIVE" 2>/dev/null
    python3 - "$RULES" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
d["profiles"] = [x for x in d["profiles"] if not x["name"].startswith("Deskmap Test")]
json.dump(d, open(p, "w"), indent=2, ensure_ascii=False)
PY
    "$CLI" reload
}
trap cleanup EXIT
sleep 5
# Pencere ekranda açık olan masaüstünde kalsın: AX başka masaüstündeki
# pencereyi listelemez, boyutlandırma yardımcısı onu bulamaz.
HERE=$("$CLI" windows --app HookProbe --json | python3 -c "import json,sys; print(json.load(sys.stdin)[0].get('desktop') or 1)")
cat > "$OUT/t.yaml" <<YAML
profile: Deskmap Test
replace: true
windows:
  - app: HookProbe
    $MODE: builtin/$HERE full
    $OTHER: builtin/1 full
  - app: ZZNoSuchApp
    place: builtin/3 full
YAML
"$CLI" apply "$OUT/t.yaml" > /dev/null
[ "$(st 'd.get("profile")')" == "Deskmap Test" ] && ok "test profile active" || { bad "test profile"; exit 1; }

# 1. Profil adı
"$CLI" profile-rename "Deskmap Test" "Deskmap Test Ğü" && [ "$(st 'd.get("profile")')" == "Deskmap Test Ğü" ] \
    && ok "rename (non-ASCII)" || bad "rename"
"$CLI" profile-rename "Deskmap Test Ğü" "$ACTIVE" 2>/dev/null && bad "rename onto existing name" || ok "rename onto existing name refused"
"$CLI" profile-rename "Deskmap Test Ğü" "Deskmap Test" && [ "$(st 'd.get("profile")')" == "Deskmap Test" ] \
    && ok "rename back" || bad "rename back"
"$CLI" profile-rename "NoSuchProfile" "X" 2>/dev/null && bad "rename unknown" || ok "rename unknown refused"

# 2. Dışa aktarma
"$CLI" export "$OUT/t.deskmap.json" > /dev/null && python3 -c "
import json,sys; d=json.load(open('$OUT/t.deskmap.json')); sys.exit(0 if d['name']=='Deskmap Test' and len(d['rules'])==2 and d.get('screens') else 1)" \
    && ok "export active profile" || bad "export active"
"$CLI" export "$OUT/a.deskmap.json" --profile "$ACTIVE" > /dev/null && python3 -c "
import json,sys; d=json.load(open('$OUT/a.deskmap.json')); sys.exit(0 if d['name']=='$ACTIVE' and len(d['rules'])==$ACOUNT else 1)" \
    && ok "export named profile ($ACOUNT rules)" || bad "export named"
"$CLI" export /nonexistent-dir/x.json 2>/dev/null && bad "export to bad path" || ok "export to bad path fails"

# 3. Masaüstü sırası (etkin olmayan mod: $OTHER)
"$CLI" desktop-move builtin 1 3 --mode "$OTHER"
[ "$(st "R['HookProbe']['$OTHER']['desktop'], R['ZZNoSuchApp']['$OTHER']['desktop']")" == "3 2" ] \
    && ok "desktop 1 → 3 renumbers rules (1→3, 3→2)" || bad "desktop move: $(st "R['HookProbe']['$OTHER']['desktop'], R['ZZNoSuchApp']['$OTHER']['desktop']")"
[ "$(st "R['HookProbe']['$MODE']['desktop']")" == "$HERE" ] && ok "live mode untouched" || bad "live mode changed"
"$CLI" desktop-move builtin 3 1 --mode "$OTHER"
[ "$(st "R['HookProbe']['$OTHER']['desktop'], R['ZZNoSuchApp']['$OTHER']['desktop']")" == "1 3" ] \
    && ok "move back restores" || bad "move back"
"$CLI" desktop-move builtin 1 40 --mode "$OTHER" 2>/dev/null && bad "move past last desktop" || ok "move past last desktop refused"

# 4. Şu anki boyut ve konumu kullan
read VX VY VW VH PH <<< "$("$CLI" status --json | python3 -c "
import json,sys; d=json.load(sys.stdin); s=[x for x in d['screens'] if x['id']=='builtin'][0]; print(*s['visible'], d['primaryHeight'])")"
TOP=$(python3 -c "print($PH - ($VY + $VH))")
X=$(python3 -c "print($VX + 100)"); Y=$(python3 -c "print($TOP + 100)")
"$DIR/resize" "$X" "$Y" 600 500 "$PROBE" || bad "resize helper"; sleep 1.5
"$CLI" save-layout HookProbe | sed 's/^/    /'
python3 - <<PY && ok "save-layout stores current frame" || bad "save-layout"
import json, subprocess, sys
d = json.loads(subprocess.run(["$CLI", "status", "--json"], capture_output=True, text=True).stdout)
lay = next(r for r in d["rules"] if r["appName"] == "HookProbe")["$MODE"]["layout"]
want = {"x": 100 / $VW, "y": 100 / $VH, "w": 600 / $VW, "h": 500 / $VH}
off = max(abs(lay[k] - want[k]) for k in want)
print(f"    layout {lay}  want ≈ { {k: round(v, 3) for k, v in want.items()} }  off {off:.3f}")
sys.exit(0 if off < 0.02 else 1)
PY
"$CLI" save-layout ZZNoSuchApp 2>/dev/null && bad "save-layout without window" || ok "save-layout without window refused"

"$CLI" apply --undo > /dev/null
[ "$(st 'd.get("profile")')" == "$ACTIVE" ] && ok "back to '$ACTIVE'" || bad "undo"
cleanup; trap - EXIT; sleep 1
python3 - "$OUT/rules.before" "$RULES" <<'PY' && ok "rules.json same as before" || bad "rules.json differs"
import json, sys
a, b = (json.load(open(p)) for p in sys.argv[1:])
diff = [k for k in ("rules", "profiles", "activeProfileID", "enabled", "plannedDesktops") if a.get(k) != b.get(k)]
print("    differs:", diff) if diff else None
sys.exit(1 if diff else 0)
PY
[ $fail -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit $fail
