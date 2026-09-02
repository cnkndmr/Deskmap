#!/usr/bin/env bash
#
# Space Router — kurulum.
#
#   ./scripts/install.sh
#
# Yaptıkları:
#   1. ~/.hammerspoon/spacerouter  ->  engine/spacerouter  sembolik bağı
#   2. ~/Library/Application Support/SpaceRouter/rules.json oluşturur
#   3. ~/.hammerspoon/init.lua içine yükleyici bloğu ekler
#
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HAMMERSPOON_DIR="$HOME/.hammerspoon"
CONFIG_DIR="$HOME/Library/Application Support/SpaceRouter"
INIT_FILE="$HAMMERSPOON_DIR/init.lua"
MARKER=">>> space-router >>>"

info()  { printf '\033[0;34m==>\033[0m %s\n' "$1"; }
ok()    { printf '\033[0;32m  ✓\033[0m %s\n' "$1"; }
warn()  { printf '\033[0;33m  !\033[0m %s\n' "$1"; }

# --- 0. Ön koşullar ------------------------------------------------------
info "Ön koşullar kontrol ediliyor"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Bu script yalnızca macOS üzerinde çalışır." >&2
  exit 1
fi

if [[ ! -d "/Applications/Hammerspoon.app" ]]; then
  warn "Hammerspoon bulunamadı."
  warn "Kurmak için:  brew install --cask hammerspoon"
  warn "veya https://www.hammerspoon.org adresinden indirin."
else
  ok "Hammerspoon kurulu"
fi

# --- 1. Motoru bağla -----------------------------------------------------
info "Hammerspoon modülü bağlanıyor"
mkdir -p "$HAMMERSPOON_DIR"

LINK_TARGET="$HAMMERSPOON_DIR/spacerouter"
if [[ -L "$LINK_TARGET" ]]; then
  rm "$LINK_TARGET"
elif [[ -e "$LINK_TARGET" ]]; then
  warn "$LINK_TARGET zaten var ve sembolik bağ değil. Yedekleniyor."
  mv "$LINK_TARGET" "$LINK_TARGET.backup.$(date +%s)"
fi

ln -s "$PROJECT_DIR/engine/spacerouter" "$LINK_TARGET"
ok "$LINK_TARGET -> engine/spacerouter"

# --- 2. Yapılandırma -----------------------------------------------------
info "Yapılandırma hazırlanıyor"
mkdir -p "$CONFIG_DIR"

if [[ -f "$CONFIG_DIR/rules.json" ]]; then
  ok "rules.json zaten var, korunuyor"
else
  cp "$PROJECT_DIR/config/rules.example.json" "$CONFIG_DIR/rules.json"
  ok "rules.json örnek dosyadan oluşturuldu"
  warn "Ekran UUID'lerini gerçek değerlerle değiştirmeyi unutmayın."
fi

# --- 3. init.lua yükleyicisi --------------------------------------------
info "Hammerspoon yükleyicisi ekleniyor"
touch "$INIT_FILE"

if grep -qF "$MARKER" "$INIT_FILE"; then
  ok "init.lua zaten yapılandırılmış"
else
  cp "$INIT_FILE" "$INIT_FILE.backup.$(date +%s)" 2>/dev/null || true
  printf '\n' >> "$INIT_FILE"
  cat "$PROJECT_DIR/engine/hammerspoon-init-snippet.lua" >> "$INIT_FILE"
  ok "init.lua güncellendi (eski dosya yedeklendi)"
fi

# --- 4. Sonraki adımlar --------------------------------------------------
cat <<'NEXT'

Kurulum tamam. Sırasıyla:

  1. Hammerspoon'u açın.
  2. Accessibility izni verin:
     System Settings > Privacy & Security > Accessibility > Hammerspoon
     İzinden sonra Hammerspoon'u kapatıp yeniden açın.
  3. Menü çubuğundaki "SSR" menüsünden
     "Ekran UUID'lerini konsola yaz" seçeneğini çalıştırın.
  4. UUID'leri rules.json içine yazın.
  5. Safari'de Tab Group'a geçip
     "Safari başlıklarını konsola yaz" ile eşleşmeyi doğrulayın.

Ayrıntılı adımlar: docs/SETUP.md

NEXT
