#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
build="${BUILD_DIR:-$PWD/.build}"
if [[ ! -f "$build/webp/libwebp.a" ]]; then ./scripts/webp.sh; fi
xcrun swiftc -swift-version 5 -parse-as-library -target "$(uname -m)-apple-macos14.0" \
  -module-cache-path "$build/modules" -I BuildSupport/CWebP -Xcc "-I$build/libwebp-1.6.0/src" \
  Sources/{Records,MotionCamera,FirstInput,DeskModel,ArchiveIndex,ArchiveStyle,ArchiveBrowser,TimeRuler,WindowGlass,LibraryView}.swift Tests/Checks.swift \
  "$build/webp/libwebp.a" "$build/webp/libsharpyuv.a" -o "$build/Checks"
"$build/Checks" "$@"
