#!/bin/zsh
# PadMac을 빌드해서 ~/Applications/PadMac.app 으로 설치한다.
#
#   ./build.sh         빌드 + 설치
#   ./build.sh --zip   빌드 + 설치 + 배포용 zip 생성 (GitHub Release 업로드용)
#
# Apple Silicon과 Intel 맥 모두에서 실행되는 Universal 앱으로 만든다.
# (iCloud 폴더 안에서 codesign 하면 확장 속성 때문에 실패하는 경우가 있어 빌드/번들은 밖에서 만든다)
set -euo pipefail
cd "$(dirname "$0")"

VERSION="0.1.0"
BUILD_DIR="$HOME/Library/Caches/PadMac-build"
APP="$HOME/Applications/PadMac.app"

mkdir -p "$BUILD_DIR"
for ARCH in arm64 x86_64; do
    echo "빌드 중: $ARCH"
    swiftc -O -swift-version 5 -target "$ARCH-apple-macosx13.0" \
        -framework AppKit -framework GameController -framework SwiftUI \
        Sources/PadMac/*.swift -o "$BUILD_DIR/PadMac-$ARCH"
done
lipo -create "$BUILD_DIR/PadMac-arm64" "$BUILD_DIR/PadMac-x86_64" -output "$BUILD_DIR/PadMac"

pkill -x PadMac 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD_DIR/PadMac" "$APP/Contents/MacOS/PadMac"
# 아이콘 (assets/ 는 tools/make_icons.swift 로 만든다)
cp assets/AppIcon.icns assets/MenuBarIcon.png "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.sonbumsu.padmac</string>
    <key>CFBundleName</key><string>PadMac</string>
    <key>CFBundleExecutable</key><string>PadMac</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 sonbumsu. MIT License.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "설치 완료: $APP"

if [[ "${1:-}" == "--zip" ]]; then
    ZIP="$BUILD_DIR/PadMac-$VERSION.zip"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP" # .app 번들 구조와 서명을 유지한 채 압축
    echo "배포용 zip: $ZIP"
fi

echo "실행: open \"$APP\""
