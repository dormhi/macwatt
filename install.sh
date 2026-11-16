#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME=MacWatt
BUNDLE="$APP_NAME.app"
DEST="/Applications/$BUNDLE"
LABEL="io.github.dormhi.macwatt"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LEGACY_LABEL="com.macwatt.app"

stop_app() {
    pkill -f "$BUNDLE/Contents/MacOS/$APP_NAME" 2>/dev/null || true
    sleep 0.3
}

remove_autostart() {
    for label in "$LABEL" "$LEGACY_LABEL"; do
        launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
        rm -f "$HOME/Library/LaunchAgents/$label.plist"
    done
}

case "${1:-}" in
--uninstall)
    remove_autostart
    stop_app
    rm -rf "$DEST"
    echo "Kaldırıldı: $DEST ve otomatik başlatma"
    exit 0
    ;;
--autostart-off)
    remove_autostart
    echo "Otomatik başlatma kapatıldı"
    exit 0
    ;;
esac

./build.sh

stop_app
rm -rf "$DEST"
cp -R "build/$BUNDLE" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST" >/dev/null 2>&1 || true

if [[ "${1:-}" == "--autostart" ]]; then
    remove_autostart
    mkdir -p "$(dirname "$PLIST")"
    cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$LABEL</string>
<key>ProgramArguments</key><array><string>$DEST/Contents/MacOS/$APP_NAME</string></array>
<key>RunAtLoad</key><true/>
<key>ProcessType</key><string>Interactive</string>
</dict></plist>
PLIST
    launchctl bootstrap "gui/$(id -u)" "$PLIST"
    echo "Otomatik başlatma açık (girişte çalışır)"
else
    remove_autostart
    open "$DEST"
    echo "Otomatik başlatma kapalı, elle başlatıldı"
fi

echo "Kuruldu: $DEST"
echo "Açmak: open $DEST  •  Kapatmak: menü çubuğu simgesi > Çıkış"
