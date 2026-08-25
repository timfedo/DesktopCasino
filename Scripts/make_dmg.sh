#!/bin/bash
# Builds DesktopCasino.app and packages it as a compressed DMG for a GitHub release.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
VERSION="$(tr -d "[:space:]" < "$ROOT/VERSION")"
APP="$ROOT/DesktopCasino.app"
DIST="$ROOT/dist"
DMG="$DIST/DesktopCasino-$VERSION.dmg"

"$ROOT/Scripts/make_app.sh"

rm -rf "$DIST"
mkdir -p "$DIST"

# Stage the app beside a symlink to /Applications, so the mounted volume is a drag-to-install.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create \
  -volname "DesktopCasino $VERSION" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DMG" >/dev/null

shasum -a 256 "$DMG" | tee "$DMG.sha256"
echo
echo "Built $DMG"
echo
echo "Ad-hoc signed, not notarised. It installs fine, but macOS blocks the FIRST LAUNCH on"
echo "any other Mac. Recover via System Settings > Privacy & Security > Open Anyway."
echo "Control-click > Open no longer works: Apple removed that override in macOS 15."
echo "To skip the prompt entirely, clear the quarantine flag before launching:"
echo "  xattr -dr com.apple.quarantine /Applications/DesktopCasino.app"
echo
echo "Publish with:"
echo "  git tag v$VERSION && git push origin v$VERSION      # workflow builds and releases"
echo "  gh release create v$VERSION '$DMG' --generate-notes  # or do it by hand"
