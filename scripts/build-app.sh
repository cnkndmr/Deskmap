#!/usr/bin/env bash
#
# SwiftUI menü çubuğu uygulamasını derler ve .app paketi hâline getirir.
# Xcode gerekmez; Xcode Command Line Tools yeterlidir.
#
#   ./scripts/build-app.sh            # release
#   ./scripts/build-app.sh debug      # debug
#
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${1:-release}"
APP_NAME="SpaceRouter"
BUNDLE_ID="com.spacerouter.app"
VERSION="0.1.0"

BUILD_ROOT="$PROJECT_DIR/build"
APP_BUNDLE="$BUILD_ROOT/$APP_NAME.app"

info() { printf '\033[0;34m==>\033[0m %s\n' "$1"; }
ok()   { printf '\033[0;32m  ✓\033[0m %s\n' "$1"; }

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Bu script yalnızca macOS üzerinde çalışır." >&2
  exit 1
fi

if ! command -v swift >/dev/null 2>&1; then
  echo "swift bulunamadı. Xcode Command Line Tools kurun:" >&2
  echo "  xcode-select --install" >&2
  exit 1
fi

info "Swift paketi derleniyor ($CONFIGURATION)"
swift build --package-path "$PROJECT_DIR/app" -c "$CONFIGURATION"

BINARY="$PROJECT_DIR/app/.build/$CONFIGURATION/$APP_NAME"
if [[ ! -f "$BINARY" ]]; then
  echo "Derleme çıktısı bulunamadı: $BINARY" >&2
  exit 1
fi
ok "İkili dosya hazır"

info ".app paketi oluşturuluyor"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>       <string>Space Router</string>
    <key>CFBundleIdentifier</key>        <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>        <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key>           <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>    <string>13.0</string>
    <!-- Menü çubuğu uygulaması: Dock'ta simge gösterme. -->
    <key>LSUIElement</key>               <true/>
    <key>NSHighResolutionCapable</key>   <true/>
</dict>
</plist>
PLIST
ok "Info.plist yazıldı"

info "Ad-hoc imzalanıyor"
codesign --force --sign - "$APP_BUNDLE" >/dev/null 2>&1 \
  && ok "İmzalandı" \
  || echo "  ! İmzalama atlandı (zorunlu değil)"

cat <<NEXT

Hazır:  $APP_BUNDLE

Çalıştırmak için:
  open "$APP_BUNDLE"

Kalıcı kurulum için:
  cp -R "$APP_BUNDLE" /Applications/

İlk açılışta Erişilebilirlik izni isteyecektir:
  System Settings > Privacy & Security > Accessibility

NEXT
