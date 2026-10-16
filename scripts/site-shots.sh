#!/bin/bash
# Web-sized screenshots for the website, in both appearances:
#   website/shots/<lang>/<name>.png        dark (as docs/images)
#   website/shots/<lang>/light/<name>.png  light
# Drawn by the app's own `--shots` mode (demo data, no AX, no window moves),
# then scaled to at most 1600 px wide with sips. Needs build/Deskmap.app
# (make app). A shot window shows briefly on screen while it draws.
# Images the shots mode cannot draw (07-menu, a real menu crop) keep their
# docs/images copy and have no light variant.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/Deskmap.app/Contents/MacOS/Deskmap
[ -x "$APP" ] || { echo "site-shots: $APP missing, run make app first" >&2; exit 1; }
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Website name -> name the shots mode writes (crowded scenario names start with g).
source_name() {
  case "$1" in
    08-open-closed) echo g01c-grid-closed-pins ;;
    *) echo "$1" ;;
  esac
}

fit() { # src dest
  local w
  w=$(sips -g pixelWidth "$1" | awk '/pixelWidth/{print $2}')
  if [ "$w" -gt 1600 ]; then sips --resampleWidth 1600 "$1" --out "$2" >/dev/null; else cp "$1" "$2"; fi
}

for lang in en tr; do
  for theme in dark light; do
    out="$TMP/$lang-$theme"
    # Light: force the Aqua appearance whatever the Mac uses; dark: force Dark.
    if [ "$theme" = light ]; then look=(-NSRequiresAquaSystemAppearance YES); else look=(-AppleInterfaceStyle Dark); fi
    "$APP" --shots "$out" -AppleLanguages "($lang)" "${look[@]}" 2>/dev/null
    "$APP" --shots "$out" --scenario crowded -AppleLanguages "($lang)" "${look[@]}" 2>/dev/null
  done
  mkdir -p "website/shots/$lang/light"
  for f in docs/images/"$lang"/*.png; do
    name=$(basename "$f" .png)
    src=$(source_name "$name")
    if [ -f "$TMP/$lang-dark/$src.png" ]; then
      fit "$TMP/$lang-dark/$src.png" "website/shots/$lang/$name.png"
      fit "$TMP/$lang-light/$src.png" "website/shots/$lang/light/$name.png"
    else
      fit "$f" "website/shots/$lang/$name.png"
      echo "site-shots: $lang/$name has no shots-mode source; dark copy only"
    fi
  done
done
echo "website/shots updated (dark + light)."
