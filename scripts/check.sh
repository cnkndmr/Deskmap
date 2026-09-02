#!/usr/bin/env bash
#
# Sözdizimi ve şema doğrulaması. CI ve commit öncesi için.
#
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILED=0

echo "==> Lua sözdizimi"
if command -v luac >/dev/null 2>&1; then
  LUAC=luac
elif command -v luac5.4 >/dev/null 2>&1; then
  LUAC=luac5.4
else
  LUAC=""
  echo "  ! luac bulunamadı, atlanıyor (brew install lua)"
fi

if [[ -n "$LUAC" ]]; then
  while IFS= read -r file; do
    if $LUAC -p "$file" 2>/dev/null; then
      echo "  ✓ $(basename "$file")"
    else
      echo "  ✗ $(basename "$file")"
      $LUAC -p "$file" || true
      FAILED=1
    fi
  done < <(find "$PROJECT_DIR/engine" -name '*.lua')
fi

echo "==> JSON şeması"
while IFS= read -r file; do
  if python3 -c "import json,sys;json.load(open(sys.argv[1]))" "$file"; then
    echo "  ✓ $(basename "$file")"
  else
    echo "  ✗ $(basename "$file")"
    FAILED=1
  fi
done < <(find "$PROJECT_DIR/config" -name '*.json')

echo "==> Swift derlemesi"
if command -v swift >/dev/null 2>&1 && [[ "$(uname -s)" == "Darwin" ]]; then
  if swift build --package-path "$PROJECT_DIR/app" -c debug; then
    echo "  ✓ Swift paketi derlendi"
  else
    echo "  ✗ Swift derlemesi başarısız"
    FAILED=1
  fi
else
  echo "  ! swift/macOS yok, atlanıyor"
fi

exit $FAILED
