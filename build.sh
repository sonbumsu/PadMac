#!/bin/zsh
# PadMac을 빌드해서 ~/Applications/PadMac.app 으로 설치한다.
# (iCloud 폴더 안에서 codesign 하면 확장 속성 때문에 실패하는 경우가 있어 빌드/번들은 밖에서 만든다)
set -euo pipefail
cd "$(dirname "$0")"

BUILD_DIR="$HOME/Library/Caches/PadMac-build"
APP="$HOME/Applications/PadMac.app"

mkdir -p "$BUILD_DIR"
swiftc -O -swift-version 5 -target arm64-apple-macosx13.0 \
    -framework AppKit -framework GameController -framework SwiftUI \
    Sources/PadMac/*.swift -o "$BUILD_DIR/PadMac"

pkill -x PadMac 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD_DIR/PadMac" "$APP/Contents/MacOS/PadMac"
# 아이콘 (assets/ 는 tools/make_icons.swift 로 만든다)
cp assets/AppIcon.icns assets/MenuBarIcon.png "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.sonbumsu.padmac</string>
    <key>CFBundleName</key><string>PadMac</string>
    <key>CFBundleExecutable</key><string>PadMac</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "설치 완료: $APP"
echo "실행: open \"$APP\""
