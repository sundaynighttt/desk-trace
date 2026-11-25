#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export BUILD_DIR="${BUILD_DIR:-$PWD/.build}"
./scripts/webp.sh
stage=$(mktemp -d "${TMPDIR:-/tmp}/desktrace-app.XXXXXX")
trap 'rm -rf "$stage"' EXIT
bundle="$stage/자리기록.app"
app="$bundle/Contents"
mkdir -p "$app/MacOS" "$app/Resources/Notices" "$BUILD_DIR/modules"
for arch in arm64 x86_64; do
  xcrun swiftc -swift-version 5 -parse-as-library -O -target "$arch-apple-macos14.0" \
    -module-cache-path "$BUILD_DIR/modules" -I BuildSupport/CWebP \
    -Xcc "-I$BUILD_DIR/libwebp-1.6.0/src" Sources/*.swift \
    "$BUILD_DIR/webp/libwebp.a" "$BUILD_DIR/webp/libsharpyuv.a" -o "$BUILD_DIR/DeskTrace-$arch"
done
lipo -create "$BUILD_DIR/DeskTrace-arm64" "$BUILD_DIR/DeskTrace-x86_64" -output "$app/MacOS/DeskTrace"
cp BuildSupport/Info.plist "$app/"
cp Notices/* "$app/Resources/Notices/"
xcrun swift -module-cache-path "$BUILD_DIR/modules" BuildSupport/Icon.swift BuildSupport/AppIcon.png "$BUILD_DIR/AppIcon.iconset"
iconutil -c icns "$BUILD_DIR/AppIcon.iconset" -o "$app/Resources/AppIcon.icns"
codesign --force --sign - "$bundle"
codesign --verify --strict "$bundle"
ditto --noextattr --norsrc "$bundle" "$BUILD_DIR/자리기록.app"
# Synced folders sometimes assign FinderInfo to newly copied application bundles.
if xattr -p com.apple.FinderInfo "$BUILD_DIR/자리기록.app" >/dev/null 2>&1; then
  xattr -d com.apple.FinderInfo "$BUILD_DIR/자리기록.app"
fi
codesign --verify --strict "$BUILD_DIR/자리기록.app"
