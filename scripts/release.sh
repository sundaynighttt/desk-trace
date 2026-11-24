#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

: "${DESKTRACE_SIGN_IDENTITY:?Set the Developer ID Application signing identity}"
: "${DESKTRACE_NOTARY_PROFILE:?Set the notarytool keychain profile}"
build="${BUILD_DIR:-$PWD/.build}"
source_app="$build/자리기록.app"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$source_app/Contents/Info.plist")
release="$build/release"
mkdir -p "$release"
stage=$(mktemp -d "${TMPDIR:-/tmp}/desktrace-release.XXXXXX")
trap 'rm -rf "$stage"' EXIT

mkdir "$stage/volume"
app="$stage/volume/자리기록.app"
image="$stage/DeskTrace-$version.dmg"
ditto --noextattr --norsrc "$source_app" "$app"
codesign --force --options runtime --timestamp --sign "$DESKTRACE_SIGN_IDENTITY" \
  --entitlements BuildSupport/Release.entitlements "$app"
codesign --verify --deep --strict "$app"
ln -s /Applications "$stage/volume/Applications"
hdiutil create -volname '자리기록' -fs HFS+ -format UDZO -srcfolder "$stage/volume" "$image"
codesign --timestamp --sign "$DESKTRACE_SIGN_IDENTITY" "$image"

xcrun notarytool submit "$image" --keychain-profile "$DESKTRACE_NOTARY_PROFILE" \
  --wait --output-format json > "$stage/notary.json"
status=$(/usr/bin/plutil -extract status raw "$stage/notary.json")
submission=$(/usr/bin/plutil -extract id raw "$stage/notary.json")
echo "Apple notarization $submission $status"
[[ "$status" == Accepted ]]
xcrun stapler staple "$image"
xcrun stapler validate "$image"
hdiutil verify "$image"
spctl --assess --type open --context context:primary-signature --verbose=2 "$image"
mv "$image" "$release/"
