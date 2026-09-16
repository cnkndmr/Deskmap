#!/usr/bin/env bash
#
# Deskmap'i gönderilebilir tek bir paket hâline getirir:
#   evrensel (arm64 + x86_64) release derleme → .app → imza → (isteğe bağlı
#   noter) → build/dist/Deskmap-<sürüm>.zip (+ isteğe bağlı .dmg)
#
#   make dist                                    # ad-hoc imza, zip
#   FORMAT=dmg make dist                         # zip yerine dmg
#   FORMAT=both make dist                        # ikisi de
#   VERSION=0.3.1 make dist                      # sürüm numarası (varsayılan: kökteki VERSION dosyası)
#   SIGN_IDENTITY="Developer ID Application: Ad (TEAMID)" \
#   NOTARY_PROFILE=notary make dist              # Developer ID + noter + staple
#
# NOTARY_PROFILE için bir kez:
#   xcrun notarytool store-credentials notary --apple-id ... --team-id ... --password <app-specific>
#
# Ad-hoc imzalı paket başka Mac'te Gatekeeper uyarısı verir; alıcı sağ tık ›
# Open ile açar ya da: xattr -dr com.apple.quarantine /Applications/Deskmap.app
#
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Deskmap"
VERSION="${VERSION:-$(cat "$PROJECT_DIR/VERSION")}"
FORMAT="${FORMAT:-zip}"                 # zip | dmg | both
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

BUILD_ROOT="$PROJECT_DIR/build"
APP_BUNDLE="$BUILD_ROOT/$APP_NAME.app"
DIST_DIR="$BUILD_ROOT/dist"
ZIP="$DIST_DIR/$APP_NAME-$VERSION.zip"
DMG="$DIST_DIR/$APP_NAME-$VERSION.dmg"

info() { printf '\033[0;34m==>\033[0m %s\n' "$1"; }
ok()   { printf '\033[0;32m  ✓\033[0m %s\n' "$1"; }

case "$FORMAT" in zip|dmg|both) ;; *) echo "FORMAT must be zip, dmg or both." >&2; exit 1;; esac

if [[ -n "$NOTARY_PROFILE" && "$SIGN_IDENTITY" == "-" ]]; then
  echo "Notarization requires SIGN_IDENTITY (a Developer ID Application identity)." >&2
  exit 1
fi

# 1. Evrensel release derleme + .app (build-app.sh imzayı da yapar).
VERSION="$VERSION" UNIVERSAL=1 SIGN_IDENTITY="$SIGN_IDENTITY" \
  "$PROJECT_DIR/scripts/build-app.sh" release

info "Verifying signature"
codesign --verify --deep --strict "$APP_BUNDLE"
ok "codesign OK ($(codesign -dv "$APP_BUNDLE" 2>&1 | sed -n 's/^Authority=//p' | head -1 || true))"

# 2. Noter (yalnızca Developer ID ile).
if [[ -n "$NOTARY_PROFILE" ]]; then
  info "Submitting for notarization ($NOTARY_PROFILE)"
  NOTARY_ZIP="$(mktemp -d)/$APP_NAME.zip"
  ditto -c -k --keepParent "$APP_BUNDLE" "$NOTARY_ZIP"
  xcrun notarytool submit "$NOTARY_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP_BUNDLE"
  rm -f "$NOTARY_ZIP"
  ok "Notarization ticket stapled"
fi

# 3. Paketle.
mkdir -p "$DIST_DIR"
rm -f "$ZIP" "$DMG"

if [[ "$FORMAT" == "zip" || "$FORMAT" == "both" ]]; then
  info "Creating ZIP"
  ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP"
  ok "$ZIP"
fi

if [[ "$FORMAT" == "dmg" || "$FORMAT" == "both" ]]; then
  info "Creating DMG"
  STAGE="$(mktemp -d)"
  cp -R "$APP_BUNDLE" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname "Deskmap" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"
  rm -rf "$STAGE"
  if [[ "$SIGN_IDENTITY" != "-" ]]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
    [[ -n "$NOTARY_PROFILE" ]] && {
      xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
      xcrun stapler staple "$DMG"
    }
  fi
  ok "$DMG"
fi

cat <<NEXT

Distribution package ready (build/dist):
$(ls -lh "$DIST_DIR" | awk 'NR>1 {print "  " $5 "\t" $9}')

Architectures: $(lipo -archs "$APP_BUNDLE/Contents/MacOS/$APP_NAME")
Signature:     $([[ "$SIGN_IDENTITY" == "-" ]] && echo "ad-hoc (recipients must right-click › Open the first time)" || echo "$SIGN_IDENTITY")
NEXT
