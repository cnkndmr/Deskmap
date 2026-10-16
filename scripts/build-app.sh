#!/usr/bin/env bash
#
# SwiftUI menü çubuğu uygulamasını derler ve .app paketi hâline getirir.
# Xcode gerekmez; Xcode Command Line Tools yeterlidir.
#
#   ./scripts/build-app.sh            # release
#   ./scripts/build-app.sh debug      # debug
#
# Ortam değişkenleri:
#   VERSION=0.3.1          Info.plist sürümü (varsayılan: depo kökündeki VERSION dosyası)
#   UNIVERSAL=1            arm64 + x86_64 evrensel ikili (dağıtım için)
#   SIGN_IDENTITY="..."    codesign kimliği (varsayılan "-" = ad-hoc)
#
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${1:-release}"
APP_NAME="Deskmap"
# The name people see: menu bar, Login Items, the Accessibility list.
# Overridable for a one-off rebrand build without touching the identity below
# (see docs/naming.md).
DISPLAY_NAME="${DISPLAY_NAME:-Deskmap}"
BUNDLE_ID="com.deskmap.app"
COPYRIGHT="${COPYRIGHT:-© 2026 Can Kandemir. MIT licensed.}"
VERSION="${VERSION:-$(cat "$PROJECT_DIR/VERSION")}"
UNIVERSAL="${UNIVERSAL:-0}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

# Where the .app is assembled. Overridable so a verification build can be made
# without touching a copy that is currently running from build/.
BUILD_ROOT="${BUILD_ROOT:-$PROJECT_DIR/build}"
APP_BUNDLE="$BUILD_ROOT/$APP_NAME.app"

info() { printf '\033[0;34m==>\033[0m %s\n' "$1"; }
ok()   { printf '\033[0;32m  ✓\033[0m %s\n' "$1"; }

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script only runs on macOS." >&2
  exit 1
fi

if ! command -v swift >/dev/null 2>&1; then
  echo "swift not found. Install the Xcode Command Line Tools:" >&2
  echo "  xcode-select --install" >&2
  exit 1
fi

if [[ "$UNIVERSAL" == "1" ]]; then
  info "Building Swift package ($CONFIGURATION, universal arm64+x86_64)"
  swift build --package-path "$PROJECT_DIR/app" -c "$CONFIGURATION" \
    --arch arm64 --arch x86_64
  BINARY="$(swift build --package-path "$PROJECT_DIR/app" -c "$CONFIGURATION" \
    --arch arm64 --arch x86_64 --show-bin-path)/$APP_NAME"
else
  info "Building Swift package ($CONFIGURATION)"
  swift build --package-path "$PROJECT_DIR/app" -c "$CONFIGURATION"
  BINARY="$PROJECT_DIR/app/.build/$CONFIGURATION/$APP_NAME"
fi
if [[ ! -f "$BINARY" ]]; then
  echo "Build output not found: $BINARY" >&2
  exit 1
fi
ok "Binary ready ($(lipo -archs "$BINARY" 2>/dev/null || echo '?'))"

info "Creating .app bundle"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Simgeler: uygulama simgesi (.icns) ve menü çubuğu şablon simgesi (PNG @1x/@2x).
RESOURCES_DIR="$PROJECT_DIR/app/Resources"
cp "$RESOURCES_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
cp "$RESOURCES_DIR/MenuBarIcon.png" "$RESOURCES_DIR/MenuBarIcon@2x.png" "$APP_BUNDLE/Contents/Resources/"
ok "Icons copied"

# Yerelleştirmeler: anahtarlar kaynakta İngilizce; tr.lproj Türkçe çeviriyi taşır,
# en.lproj boştur ama paketin İngilizce yerelleştirmeyi bildirmesi için gerekir.
for lproj in "$RESOURCES_DIR"/*.lproj; do
  plutil -lint -s "$lproj"/*.strings
  cp -R "$lproj" "$APP_BUNDLE/Contents/Resources/"
done
ok "Localizations copied ($(cd "$RESOURCES_DIR" && ls -d *.lproj | sed 's/\.lproj//' | tr '\n' ' '))"

# Privacy manifest: required for App Store submission, harmless otherwise.
plutil -lint -s "$RESOURCES_DIR/PrivacyInfo.xcprivacy"
cp "$RESOURCES_DIR/PrivacyInfo.xcprivacy" "$APP_BUNDLE/Contents/Resources/"
ok "Privacy manifest copied"

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>       <string>$DISPLAY_NAME</string>
    <key>CFBundleIdentifier</key>        <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>        <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleIconFile</key>          <string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key>           <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>    <string>13.0</string>
    <key>LSApplicationCategoryType</key> <string>public.app-category.productivity</string>
    <key>NSHumanReadableCopyright</key>  <string>$COPYRIGHT</string>
    <!-- Dil: İngilizce varsayılan; Türkçe tercih edenlere tr.lproj. -->
    <key>CFBundleDevelopmentRegion</key> <string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>tr</string>
    </array>
    <!-- Menü çubuğu uygulaması: Dock'ta simge gösterme. -->
    <key>LSUIElement</key>               <true/>
    <key>NSHighResolutionCapable</key>   <true/>
    <!-- Kapalı pinli Safari penceresini ayrı pencerede yeniden açmak için. -->
    <key>NSAppleEventsUsageDescription</key>
    <string>Deskmap opens a closed pinned browser window again in a new window on its desktop.</string>
    <!-- Otomasyon: deskmap://reapply, pause, resume, toggle, profile/<ad>, next-profile. -->
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>    <string>$DISPLAY_NAME</string>
            <key>CFBundleTypeRole</key>   <string>Viewer</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>deskmap</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST
ok "Info.plist written"

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  info "Signing ad-hoc"
  codesign --force --sign - "$APP_BUNDLE" >/dev/null 2>&1 \
    && ok "Signed (ad-hoc)" \
    || echo "  ! Signing skipped (optional)"
else
  info "Signing: $SIGN_IDENTITY"
  codesign --force --options runtime --timestamp \
    --entitlements "$(dirname "$0")/Deskmap.entitlements" --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
  ok "Signed"
fi

cat <<NEXT

Ready:  $APP_BUNDLE

To run it:
  open "$APP_BUNDLE"

For a permanent install:
  cp -R "$APP_BUNDLE" /Applications/

On first launch it asks for Accessibility permission:
  System Settings > Privacy & Security > Accessibility

NEXT
