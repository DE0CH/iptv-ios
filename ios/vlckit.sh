#!/bin/bash
# Fetches VLC's engine (MobileVLCKit 3.6.0, LGPL 2.1, VideoLAN's own build) into ios/Frameworks, checked by its
# SHA-256. Run from ios/ before `xcodegen generate`.
set -euo pipefail
URL=https://download.videolan.org/pub/cocoapods/prod/MobileVLCKit-3.6.0-c73b779f-dd8bfdba.tar.xz
SUM=1a5077beeb7bf943a3fbbb91523752e50a10d490a3046cb9808d906784ddbc36
[ -d Frameworks/MobileVLCKit.xcframework ] && { echo "MobileVLCKit already there"; exit 0; }
TMP=$(mktemp -d)
curl -fsSL --retry 3 -o "$TMP/vlc.tar.xz" "$URL"
echo "$SUM  $TMP/vlc.tar.xz" | shasum -a 256 -c -
tar -xJf "$TMP/vlc.tar.xz" -C "$TMP" MobileVLCKit-binary/MobileVLCKit.xcframework
mkdir -p Frameworks
mv "$TMP/MobileVLCKit-binary/MobileVLCKit.xcframework" Frameworks/
rm -rf "$TMP"
ls Frameworks/MobileVLCKit.xcframework
