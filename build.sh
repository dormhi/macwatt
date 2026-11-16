#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP=build/MacWatt.app
BIN="$APP/Contents/MacOS/MacWatt"
ICONSET=build/AppIcon.iconset
ICNS=build/AppIcon.icns

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

xcrun --sdk macosx clang \
    -fobjc-arc -O2 -Wall \
    -mmacosx-version-min=13.0 \
    -framework AppKit -framework IOKit -framework Foundation \
    Sources/MacWatt/*.m \
    -o "$BIN"

if [[ ! -x build/makeicon || Tools/makeicon.m -nt build/makeicon ]]; then
    xcrun --sdk macosx clang -fobjc-arc -O2 -framework AppKit Tools/makeicon.m -o build/makeicon
fi

rm -rf "$ICONSET"
mkdir -p "$ICONSET"
build/makeicon build/AppIcon-1024.png
for size in 16 32 128 256 512; do
    sips -z $size $size build/AppIcon-1024.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double build/AppIcon-1024.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$ICNS"
cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>MacWatt</string>
<key>CFBundleDisplayName</key><string>MacWatt</string>
<key>CFBundleIdentifier</key><string>io.github.dormhi.macwatt</string>
<key>CFBundleExecutable</key><string>MacWatt</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleIconName</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Hazır: $APP"
