#!/bin/bash
# Full-size screenshots for the README and the guides, dark appearance:
#   docs/images/<lang>/<name>.png
# Drawn by the app's own `--shots` mode (demo data, no AX, no window moves),
# written at the mode's native size (2x). Needs build/Deskmap.app (make app).
# A shot window shows briefly on screen while it draws.
# Only names already present in docs/images are refreshed; images the shots
# mode cannot draw (07-menu, a real menu crop) or whose framing no longer
# holds (see source_name) are left untouched. The website's scaled copies
# come from scripts/site-shots.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/Deskmap.app/Contents/MacOS/Deskmap
[ -x "$APP" ] || { echo "docs-shots: $APP missing, run make app first" >&2; exit 1; }
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Docs name -> name the shots mode writes (crowded scenario names start with g).
# 08-open-closed is kept: the crowded map now lists the Extra monitor first and
# pushes the built-in display's Desktop 3 (Open 4 button, closed Preview group,
# what the README and the site describe) below the frame.
source_name() {
  case "$1" in
    08-open-closed) echo KEEP ;;
    *) echo "$1" ;;
  esac
}

for lang in en tr; do
  out="$TMP/$lang"
  mkdir -p "$out"
  "$APP" --shots "$out" -AppleLanguages "($lang)" -AppleInterfaceStyle Dark 2>/dev/null
  "$APP" --shots "$out" --scenario crowded -AppleLanguages "($lang)" -AppleInterfaceStyle Dark 2>/dev/null
  for f in docs/images/"$lang"/*.png; do
    name=$(basename "$f" .png)
    src=$(source_name "$name")
    if [ "$src" = KEEP ]; then
      echo "docs-shots: $lang/$name kept on purpose (see source_name)"
    elif [ -f "$out/$src.png" ]; then
      cp "$out/$src.png" "$f"
    else
      echo "docs-shots: $lang/$name has no shots-mode source; kept as is"
    fi
  done
done
echo "docs/images updated (dark, full size)."
