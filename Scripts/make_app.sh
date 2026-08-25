#!/bin/bash
# Wraps the SwiftPM executable into a double-clickable, agent-style .app bundle.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
APP="$ROOT/DesktopCasino.app"
VERSION="$(tr -d "[:space:]" < "$ROOT/VERSION")"

swift build -c release --product DesktopCasino

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/release/DesktopCasino" "$APP/Contents/MacOS/DesktopCasino"

# Produced by `swift run IconDesigner`. Absent is fine — the app just gets the system default.
if [ -f "$ROOT/Icon/AppIcon.icns" ]; then
  cp "$ROOT/Icon/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
  echo "Using Icon/AppIcon.icns"
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>DesktopCasino</string>
    <key>CFBundleDisplayName</key>     <string>Desktop Casino</string>
    <key>CFBundleExecutable</key>      <string>DesktopCasino</string>
    <key>CFBundleIdentifier</key>      <string>dev.timfedo.DesktopCasino</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>__VERSION__</string>
    <key>CFBundleVersion</key>         <string>__VERSION__</string>
    <key>LSMinimumSystemVersion</key>  <string>14.0</string>
    <key>NSHighResolutionCapable</key> <true/>
    <!-- Agent app: no Dock tile, no menu bar. -->
    <key>CFBundleIconFile</key>        <string>AppIcon</string>
    <key>LSUIElement</key>             <true/>
</dict>
</plist>
PLIST

sed -i "" "s/__VERSION__/$VERSION/g" "$APP/Contents/Info.plist"

# Ad-hoc signature so Gatekeeper does not complain about an unsigned local build.
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "Built $APP"
echo "Launch:  open '$APP'"
echo "Quit:    hover the panel and click ✕, or  pkill DesktopCasino"
