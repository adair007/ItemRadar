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

echo ">> 写入 Info.plist ..."
cp Info.plist "$APP/Contents/Info.plist"

echo ">> ad-hoc 签名 ..."
codesign --force --deep --sign - "$APP"

echo ">> 完成：$APP"
