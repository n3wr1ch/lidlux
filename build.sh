#!/bin/zsh
# LidLux.app 번들을 빌드한다. 사용법: ./build.sh [install]
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=build/LidLux.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/LidLux "$APP/Contents/MacOS/LidLux"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>LidLux</string>
    <key>CFBundleIdentifier</key><string>com.ntoktok.lidlux</string>
    <key>CFBundleExecutable</key><string>LidLux</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
echo "빌드 완료: $APP"

if [[ "${1:-}" == "install" ]]; then
    pkill -x LidLux 2>/dev/null || true
    rm -rf /Applications/LidLux.app
    cp -R "$APP" /Applications/
    open /Applications/LidLux.app
    echo "설치 완료: /Applications/LidLux.app"
fi
