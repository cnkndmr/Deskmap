#!/usr/bin/env bash
# Builds the probe twice into /tmp/deskmap-probe: sandboxed and plain.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT=/tmp/deskmap-probe
rm -rf "$OUT" && mkdir -p "$OUT"
swiftc -O "$HERE/Probe.swift" -o "$OUT/Probe"

make_bundle() { # name bundle-id display-name
  local app="$OUT/$1.app"
  mkdir -p "$app/Contents/MacOS"
  cp "$OUT/Probe" "$app/Contents/MacOS/Probe"
  cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$2</string>
  <key>CFBundleName</key><string>$3</string>
  <key>CFBundleExecutable</key><string>Probe</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
}

make_bundle ProbePlain   com.deskmap.probe.plain   "Deskmap Probe (plain)"
make_bundle ProbeSandbox com.deskmap.probe.sandbox "Deskmap Probe (sandbox)"

cat > "$OUT/sandbox.entitlements" <<ENT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.app-sandbox</key><true/>
</dict></plist>
ENT

codesign --force --sign - "$OUT/ProbePlain.app"
codesign --force --sign - --entitlements "$OUT/sandbox.entitlements" "$OUT/ProbeSandbox.app"
codesign -d --entitlements - "$OUT/ProbeSandbox.app" 2>/dev/null | grep -c app-sandbox
echo "built: $OUT"
