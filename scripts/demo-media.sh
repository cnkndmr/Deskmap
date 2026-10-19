#!/bin/bash
# Demo GIF and MP4 for docs/media, in English and Turkish:
#   docs/media/<lang>/demo.gif    ≤ 8 s, ≤ 3 MB, 960 px wide
#   docs/media/<lang>/demo.mp4    same frames, H.264
# Drawn by the app's own `--shots --scenario demo` mode (demo data: no AX,
# no window moves; a shot window shows briefly on screen while it draws),
# then assembled with ffmpeg. Needs build/Deskmap.app (make app) and ffmpeg.
#   FRAMES=<dir>   keep the PNG frames there too (default: temp dir only)
#   HOLD=1.7       seconds per frame (4 frames; the last one holds 0.6 s longer)
#   WIDTH=960      output width in px
#   CROP=0         keep the inspector column (default: cropped away so the map is larger)
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/Deskmap.app/Contents/MacOS/Deskmap
[ -x "$APP" ] || { echo "demo-media: $APP missing, run make app first" >&2; exit 1; }
command -v ffmpeg >/dev/null || { echo "demo-media: ffmpeg missing" >&2; exit 1; }
HOLD="${HOLD:-1.7}"
WIDTH="${WIDTH:-960}"
CROP="${CROP:-1}"
# The window is 906 pt of map + 361 pt of inspector (RootView.inspectorWidth + divider).
if [ "$CROP" = 1 ]; then crop="crop=iw*906/1267.5:ih:0:0,"; else crop=""; fi
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

for lang in en tr; do
  out="$TMP/$lang"
  "$APP" --shots "$out" --scenario demo -AppleLanguages "($lang)" -AppleInterfaceStyle Dark 2>/dev/null
  if [ -n "${FRAMES:-}" ]; then mkdir -p "$FRAMES/$lang"; cp "$out"/*.png "$FRAMES/$lang/"; fi

  # concat list: each frame held HOLD seconds, the last one 0.6 s longer.
  list="$TMP/$lang.txt"; : > "$list"
  frames=("$out"/d*.png); n=${#frames[@]}
  for i in "${!frames[@]}"; do
    d=$HOLD; [ "$i" -eq $((n - 1)) ] && d=$(awk "BEGIN{print $HOLD+0.6}")
    printf "file '%s'\nduration %s\n" "${frames[$i]}" "$d" >> "$list"
  done
  # The concat demuxer needs the last file once more; the clip is then cut
  # to the intended length (otherwise the last frame is held twice).
  printf "file '%s'\n" "${frames[$((n - 1))]}" >> "$list"
  total=$(awk "BEGIN{print $HOLD*($n-1)+$HOLD+0.6}")

  mkdir -p "docs/media/$lang"
  # GIF: palette from all frames, Bayer dither keeps file size low.
  ffmpeg -y -loglevel error -f concat -safe 0 -i "$list" -t "$total" \
    -vf "${crop}fps=10,scale=$WIDTH:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=128:stats_mode=diff[p];[s1][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" \
    -loop 0 "docs/media/$lang/demo.gif"
  # MP4: even dimensions required by yuv420p.
  ffmpeg -y -loglevel error -f concat -safe 0 -i "$list" -t "$total" \
    -vf "${crop}fps=30,scale=$((WIDTH * 2)):-2:flags=lanczos,format=yuv420p" \
    -c:v libx264 -crf 23 -preset slow -movflags +faststart "docs/media/$lang/demo.mp4"
  ls -l "docs/media/$lang/demo.gif" "docs/media/$lang/demo.mp4"
done
echo "docs/media updated (en + tr)."
