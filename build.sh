#!/bin/bash
# 编译 ItemRadar 菜单栏应用并组装 .app 包，ad-hoc 签名。
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="ItemRadar"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo ">> 编译 Swift 源码 ..."
swiftc -swift-version 5 -O \
    Sources/*.swift \
    -o "$APP/Contents/MacOS/$APP_NAME"

echo ">> 写入 Info.plist 与图标 ..."
cp Info.plist "$APP/Contents/Info.plist"
cp Sources/icon.icns "$APP/Contents/Resources/icon.icns"

echo ">> ad-hoc 签名 ..."
codesign --force --deep --sign - "$APP"

echo ">> 打包 zip ..."
VERSION=$(git describe --tags --abbrev=0 2>/dev/null || echo "dev")
ZIP_NAME="ItemRadar-${VERSION}.zip"
cd "$BUILD_DIR"
rm -f "$ZIP_NAME"
zip -r "$ZIP_NAME" "$APP_NAME.app"
cd - >/dev/null
echo ">> zip 完成：$BUILD_DIR/$ZIP_NAME"

echo ">> 完成：$APP"
