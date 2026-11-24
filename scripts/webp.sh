#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
build="${BUILD_DIR:-$PWD/.build}"
version=1.6.0
archive="$build/libwebp-$version.tar.gz"
mkdir -p "$build"
if [[ ! -f "$archive" ]]; then
  curl -fL --retry 2 "https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-$version.tar.gz" -o "$archive.part"
  mv "$archive.part" "$archive"
fi
echo "e4ab7009bf0629fd11982d4c2aa83964cf244cffba7347ecd39019a9e38c4564  $archive" | shasum -a 256 -c -
if [[ ! -f "$build/libwebp-$version/src/webp/encode.h" ]]; then
  tar -xzf "$archive" -C "$build"
fi
for arch in arm64 x86_64; do
cmake -S "$build/libwebp-$version" -B "$build/webp-$arch" \
  -DCMAKE_BUILD_TYPE=Release "-DCMAKE_OSX_ARCHITECTURES=$arch" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 -DBUILD_SHARED_LIBS=OFF -DWEBP_ENABLE_SIMD=ON \
  -DWEBP_BUILD_CWEBP=OFF -DWEBP_BUILD_DWEBP=OFF -DWEBP_BUILD_GIF2WEBP=OFF \
  -DWEBP_BUILD_IMG2WEBP=OFF -DWEBP_BUILD_VWEBP=OFF -DWEBP_BUILD_ANIM_UTILS=OFF \
  -DWEBP_BUILD_WEBPINFO=OFF -DWEBP_BUILD_WEBPMUX=OFF -DWEBP_BUILD_LIBWEBPMUX=OFF -DWEBP_BUILD_EXTRAS=OFF
cmake --build "$build/webp-$arch" --target webp --parallel 4
done
mkdir -p "$build/webp"
for lib in libwebp.a libsharpyuv.a; do
  lipo -create "$build/webp-arm64/$lib" "$build/webp-x86_64/$lib" -output "$build/webp/$lib"
done
