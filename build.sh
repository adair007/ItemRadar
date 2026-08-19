#!/bin/bash
# 编译 ItemRadar 菜单栏应用并组装 .app 包，生成 Apple Silicon + Intel Universal Binary。
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="ItemRadar"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"
VERSION="$(sed -n 's/.*currentVersion = "\([^"]*\)".*/\1/p' Sources/Constants.swift | head -1)"
VERSION="${VERSION:-dev}"
ARM_BINARY="$BUILD_DIR/$APP_NAME-arm64"
INTEL_BINARY="$BUILD_DIR/$APP_NAME-x86_64"
ZIP_NAME="ItemRadar-v${VERSION}.zip"

rm -rf "$APP" "$ARM_BINARY" "$INTEL_BINARY" "$BUILD_DIR/$ZIP_NAME"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

SOURCES=(Sources/*.swift)

echo ">> 编译 Apple Silicon (arm64) ..."
swiftc -swift-version 5 -O \
    -target arm64-apple-macos13.0 \
    "${SOURCES[@]}" \
    -o "$ARM_BINARY"

echo ">> 编译 Intel (x86_64) ..."
swiftc -swift-version 5 -O \
    -target x86_64-apple-macos13.0 \
    "${SOURCES[@]}" \
    -o "$INTEL_BINARY"

echo ">> 合并 Universal Binary ..."
lipo -create "$ARM_BINARY" "$INTEL_BINARY" -output "$APP/Contents/MacOS/$APP_NAME"
rm -f "$ARM_BINARY" "$INTEL_BINARY"

echo ">> 写入 Info.plist 与图标 ..."
cp Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
cp Sources/icon.icns "$APP/Contents/Resources/icon.icns"

echo ">> ad-hoc 签名 ..."
codesign --force --deep --sign - "$APP"

echo ">> 打包 zip ..."
(cd "$BUILD_DIR" && zip -r "$ZIP_NAME" "$APP_NAME.app")

echo ">> 架构检查 ..."
lipo -info "$APP/Contents/MacOS/$APP_NAME"
echo ">> zip 完成：$BUILD_DIR/$ZIP_NAME"
echo ">> 完成：$APP (v$VERSION)"