#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
build="${BUILD_DIR:-$PWD/.build}"
app="$build/자리기록.app"
stage=$(mktemp -d "${TMPDIR:-/tmp}/desktrace-dmg.XXXXXX")
trap 'rm -rf "$stage"' EXIT
ditto --noextattr --norsrc "$app" "$stage/자리기록.app"
codesign --verify --strict "$stage/자리기록.app"
ln -s /Applications "$stage/Applications"
image="$build/DeskTrace-0.1.0.dmg"
hdiutil create -ov -volname '자리기록' -fs HFS+ -format UDZO -srcfolder "$stage" "$image"
hdiutil verify "$image"
