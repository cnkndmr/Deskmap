#!/bin/bash
# deskmap komut satırı aracının uçtan uca testi. Yalnız kendi test penceresine
# (HookProbe) dokunur; eklediği kuralı siler, sonunda rules.json'un ilk hâline
# döndüğünü denetler. Deskmap çalışıyor olmalı.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
CLI="$DIR/../deskmap"
RULES="$HOME/Library/Application Support/Deskmap/rules.json"
OUT="$(mktemp -d)"
cp "$RULES" "$OUT/rules.before"
[ -x "$DIR/HookProbe" ] || swiftc -O "$DIR/HookProbe.swift" -o "$DIR/HookProbe"
fail=0
ok()   { echo "PASS $1"; }
bad()  { echo "FAIL $1"; fail=1; }
# probe penceresinin alanı: q <python ifadesi, w = pencere sözlüğü>
q() { "$CLI" windows --app HookProbe --json | python3 -c "import json,sys; ws=json.load(sys.stdin); w=ws[0] if ws else None; print($1)"; }
place() { q '"%s/%s" % (w.get("screen"), w.get("desktop")) if w else "none"'; }
wait_place() {  # beklenen yer, saniye
    for _ in $(seq 1 $(( ${2:-4} * 4 ))); do [ "$(place)" == "$1" ] && return 0; sleep 0.25; done; return 1; }

"$DIR/HookProbe" idle 60 > /dev/null & PROBE=$!
trap 'kill $PROBE 2>/dev/null' EXIT
sleep 5

"$CLI" status > "$OUT/s" && grep -q "routing" "$OUT/s" && ok "status" || bad "status"
WIN=$(q 'w["id"] if w else ""')
[ -n "$WIN" ] && ok "windows finds probe ($WIN)" || { bad "windows finds probe"; exit 1; }
"$CLI" screens | grep -q "^builtin" && ok "screens" || bad "screens"

"$CLI" move HookProbe external 1 > /dev/null; wait_place external/1 && ok "move → external/1" || bad "move → external/1 (at $(place))"
"$CLI" move "$WIN" retina 1 > /dev/null;      wait_place builtin/1  && ok "move by id + screen name → builtin/1" || bad "move → builtin/1 (at $(place))"

"$CLI" pin HookProbe external 1
[ "$(q 'w.get("pinned",{}).get("screen")')" == "external" ] && ok "pin recorded" || bad "pin recorded"
wait_place external/1 && ok "pin moves window" || bad "pin moves window (at $(place))"
"$CLI" unpin HookProbe
[ "$(q '"pinned" in w')" == "False" ] && ok "unpin" || bad "unpin"

"$CLI" pause;  "$CLI" status --json | python3 -c "import json,sys; sys.exit(json.load(sys.stdin)['enabled'])" && ok "pause" || bad "pause"
"$CLI" resume; "$CLI" status --json | python3 -c "import json,sys; sys.exit(not json.load(sys.stdin)['enabled'])" && ok "resume" || bad "resume"

"$CLI" move HookProbe builtin 1 > /dev/null; wait_place builtin/1
RID=$("$CLI" rule add --app HookProbe --title HookProbe --screen external --undocked-screen external --layout 0,0,0.5,1)
[ -n "$RID" ] && "$CLI" rules | grep -q "^$RID" && ok "rule add ($RID)" || bad "rule add"
wait_place external/1 6 && ok "rule moves window" || bad "rule moves window (at $(place))"
"$CLI" rule rm "$RID" && ! "$CLI" rules | grep -q "^$RID" && ok "rule rm" || bad "rule rm"

"$CLI" reload && ok "reload" || bad "reload"
"$CLI" profile NoSuchProfile 2>/dev/null && bad "unknown profile fails" || ok "unknown profile fails"
"$CLI" move 999999 builtin 2>/dev/null && bad "unknown window fails" || ok "unknown window fails"
"$CLI" rule rm NOPE 2>/dev/null && bad "unknown rule fails" || ok "unknown rule fails"
"$CLI" status > /dev/null 2>&1 && ok "error does not stick to next command" || bad "error sticks"

sleep 1
python3 - "$OUT/rules.before" "$RULES" <<'PY' && ok "rules.json rules unchanged" || bad "rules.json changed"
import json, sys
a, b = (json.load(open(p)) for p in sys.argv[1:])
sys.exit(0 if a["rules"] == b["rules"] and a.get("profiles") == b.get("profiles") else 1)
PY
[ $fail -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit $fail
