#!/bin/bash
# `deskmap apply` uçtan uca testi. Yalnız test penceresi (HookProbe) için
# kural içeren "Deskmap Test" profilini kurar, pencerenin yerine gittiğini ve
# raporu denetler, `apply --undo` ile önceki profile döner. Sonunda öteki
# profillerin kurallarının değişmediğini denetler. Deskmap çalışıyor olmalı.
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
BEFORE_PROFILE=$("$CLI" status --json | python3 -c "import json,sys; print(json.load(sys.stdin).get('profile',''))")
MODE=$("$CLI" status --json | python3 -c "import json,sys; print(json.load(sys.stdin)['mode'])")

cat > "$OUT/a.yaml" <<YAML
profile: Deskmap Test
windows:
  - app: HookProbe
    place: builtin/1 left-half
YAML
cat > "$OUT/b.yaml" <<YAML
profile: Deskmap Test
windows:
  - app: HookProbe
    docked: external/1 right-third
    undocked: builtin/1 bottom-right
YAML

"$DIR/HookProbe" idle 80 > /dev/null & PROBE=$!
trap 'kill $PROBE 2>/dev/null' EXIT
sleep 5

"$CLI" apply "$OUT/a.yaml" --dry-run > "$OUT/dry" && grep -q "HookProbe" "$OUT/dry" && ok "dry run lists rule" || bad "dry run"
[ "$("$CLI" status --json | python3 -c "import json,sys; print(json.load(sys.stdin).get('profile'))")" == "$BEFORE_PROFILE" ] \
    && ok "dry run changes nothing" || bad "dry run switched profile"

"$CLI" apply "$OUT/a.yaml" > "$OUT/a.out"; code=$?
cat "$OUT/a.out" | sed 's/^/    /'
[ $code -eq 0 ] && grep -q "1/1 window(s) in place" "$OUT/a.out" && ok "apply a: window in place (left-half)" || bad "apply a (exit $code)"
[ "$("$CLI" status --json | python3 -c "import json,sys; print(json.load(sys.stdin).get('profile'))")" == "Deskmap Test" ] \
    && ok "profile switched" || bad "profile not switched"

"$CLI" apply "$OUT/b.yaml" > "$OUT/b.out"; code=$?
cat "$OUT/b.out" | sed 's/^/    /'
[ $code -eq 0 ] && grep -q "1/1 window(s) in place" "$OUT/b.out" && ok "apply b updates same profile ($MODE)" || bad "apply b (exit $code)"
grep -q "~ HookProbe" "$OUT/b.out" && ok "diff shows change" || bad "diff shows change"
"$CLI" check "$OUT/b.yaml" > /dev/null && ok "check passes" || bad "check"

"$CLI" apply --undo > "$OUT/u1" && "$CLI" apply --undo > "$OUT/u2"
cat "$OUT/u1" "$OUT/u2" | sed 's/^/    /'
[ "$("$CLI" status --json | python3 -c "import json,sys; print(json.load(sys.stdin).get('profile'))")" == "$BEFORE_PROFILE" ] \
    && ok "undo returns to '$BEFORE_PROFILE'" || bad "undo"

sleep 1
python3 - "$OUT/rules.before" "$RULES" <<'PY' && ok "other profiles unchanged" || bad "other profiles changed"
import json, sys
a, b = (json.load(open(p)) for p in sys.argv[1:])
pa = {p["name"]: p["rules"] for p in a.get("profiles", [])}
pb = {p["name"]: p["rules"] for p in b.get("profiles", []) if p["name"] != "Deskmap Test"}
pa.pop("Deskmap Test", None)
sys.exit(0 if pa == pb and a["rules"] == b["rules"] and a.get("activeProfileID") == b.get("activeProfileID") else 1)
PY
[ $fail -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit $fail
