#!/bin/bash
# `deskmap apply` uçtan uca testi, yalnız test penceresi (HookProbe) kurallarıyla.
# 1) Profil yazılmamış dosya etkin profili düzenler: öteki kurallar kalır,
#    HookProbe kuralı eklenir/güncellenir, --undo eski hâline döndürür.
# 2) `profile:` + `replace: true` ayrı profili kurar; --undo geri döner.
# Sonunda test profili silinir ve rules.json'un (kurallar, profiller, etkin
# profil) başlangıçla aynı olduğu denetlenir. Deskmap çalışıyor olmalı.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
CLI="$DIR/../deskmap"
RULES="$HOME/Library/Application Support/Deskmap/rules.json"
OUT="$(mktemp -d)"
cp "$RULES" "$OUT/rules.before"
[ -x "$DIR/HookProbe" ] || swiftc -O "$DIR/HookProbe.swift" -o "$DIR/HookProbe"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=1; }
st()  { "$CLI" status --json | python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }
ACTIVE=$(st 'd.get("profile")'); COUNT=$(st 'len(d["rules"])')

printf 'windows:\n  - app: HookProbe\n    place: builtin/1 left-half\n' > "$OUT/a.yaml"
printf 'windows:\n  - app: HookProbe\n    docked: external/1 right-third\n    undocked: builtin/1 bottom-right\n' > "$OUT/b.yaml"
printf 'profile: Deskmap Test\nreplace: true\nwindows:\n  - app: HookProbe\n    place: builtin/1 top-left\n' > "$OUT/c.yaml"

"$DIR/HookProbe" idle 90 > /dev/null & PROBE=$!
cleanup() {
    kill $PROBE 2>/dev/null
    python3 - "$RULES" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
d["profiles"] = [x for x in d["profiles"] if x["name"] != "Deskmap Test"]
json.dump(d, open(p, "w"), indent=2, ensure_ascii=False)
PY
    "$CLI" reload
}
trap cleanup EXIT
sleep 5

"$CLI" apply "$OUT/a.yaml" --dry-run > "$OUT/dry"
grep -q "'$ACTIVE' (active): edit" "$OUT/dry" && grep -q "+ HookProbe" "$OUT/dry" && ok "dry run edits active profile" || { bad "dry run"; cat "$OUT/dry"; }
[ "$(st 'len(d["rules"])')" == "$COUNT" ] && ok "dry run changes nothing" || bad "dry run changed rules"

"$CLI" apply "$OUT/a.yaml" > "$OUT/a.out"; code=$?; sed 's/^/    /' "$OUT/a.out"
[ $code -eq 0 ] && grep -q "1/1 window(s) in place" "$OUT/a.out" && ok "apply a: in place (left-half)" || bad "apply a (exit $code)"
[ "$(st 'd.get("profile")')" == "$ACTIVE" ] && ok "still on '$ACTIVE'" || bad "profile switched"
[ "$(st 'len(d["rules"])')" == "$((COUNT + 1))" ] && ok "one rule added, others kept" || bad "rule count $(st 'len(d["rules"])') (want $((COUNT + 1)))"
ID1=$(st '[r["id"] for r in d["rules"] if r["appName"]=="HookProbe"][0]')

"$CLI" apply "$OUT/b.yaml" > "$OUT/b.out"; code=$?; sed 's/^/    /' "$OUT/b.out"
[ $code -eq 0 ] && grep -q "1/1 window(s) in place" "$OUT/b.out" && ok "apply b: in place" || bad "apply b (exit $code)"
[ "$(st 'len(d["rules"])')" == "$((COUNT + 1))" ] && [ "$(st '[r["id"] for r in d["rules"] if r["appName"]=="HookProbe"][0]')" == "$ID1" ] \
    && ok "same rule updated (id kept)" || bad "rule not updated in place"
"$CLI" check "$OUT/b.yaml" > /dev/null && ok "check" || bad "check"

"$CLI" apply "$OUT/c.yaml" > "$OUT/c.out"; code=$?; sed 's/^/    /' "$OUT/c.out"
[ $code -eq 0 ] && [ "$(st 'd.get("profile")')" == "Deskmap Test" ] && [ "$(st 'len(d["rules"])')" == "1" ] \
    && ok "named profile + replace" || bad "named profile (exit $code)"

for i in 1 2 3; do "$CLI" apply --undo | sed 's/^/    /'; done
[ "$(st 'd.get("profile")')" == "$ACTIVE" ] && [ "$(st 'len(d["rules"])')" == "$COUNT" ] && ok "undo ×3 back to '$ACTIVE' ($COUNT rules)" || bad "undo"

cleanup; trap - EXIT; sleep 1
python3 - "$OUT/rules.before" "$RULES" <<'PY' && ok "rules.json same as before" || bad "rules.json differs"
import json, sys
a, b = (json.load(open(p)) for p in sys.argv[1:])
keys = ("rules", "profiles", "activeProfileID", "enabled", "plannedDesktops")
diff = [k for k in keys if a.get(k) != b.get(k)]
print("    differs:", diff) if diff else None
sys.exit(1 if diff else 0)
PY
[ $fail -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit $fail
