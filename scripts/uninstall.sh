#!/usr/bin/env bash
#
# Space Router — kaldırma.
# Yapılandırma dosyanız (rules.json) silinmez.
#
set -euo pipefail

HAMMERSPOON_DIR="$HOME/.hammerspoon"
INIT_FILE="$HAMMERSPOON_DIR/init.lua"

if [[ -L "$HAMMERSPOON_DIR/spacerouter" ]]; then
  rm "$HAMMERSPOON_DIR/spacerouter"
  echo "  ✓ sembolik bağ kaldırıldı"
fi

if [[ -f "$INIT_FILE" ]] && grep -qF ">>> space-router >>>" "$INIT_FILE"; then
  cp "$INIT_FILE" "$INIT_FILE.backup.$(date +%s)"
  /usr/bin/sed -i '' '/>>> space-router >>>/,/<<< space-router <<</d' "$INIT_FILE"
  echo "  ✓ init.lua temizlendi"
fi

echo
echo "Kaldırma tamam. Hammerspoon menüsünden Reload Config yapın."
echo "Kurallarınız hâlâ burada:"
echo "  ~/Library/Application Support/SpaceRouter/rules.json"
