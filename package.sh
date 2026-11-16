#!/bin/bash
# Dağıtım için DMG üretir: dist/MacWatt-<sürüm>.dmg
# İçinde MacWatt.app ve Applications kısayolu vardır; kullanıcı sürükleyip bırakarak kurar.
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

APP=build/MacWatt.app
VERSION=$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")
DMG="dist/MacWatt-$VERSION.dmg"
STAGING=build/dmg

rm -rf "$STAGING"
mkdir -p "$STAGING" dist
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
hdiutil create -volname "MacWatt $VERSION" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGING"

echo "Hazır: $DMG ($(du -h "$DMG" | cut -f1))"
