#!/bin/bash
# Fetches VLC's engine (VLCKit 4.0.0a19, LGPL 2.1, VideoLAN's own build; 4.0 is the line with picture in picture)
# into ios/Frameworks, checked by its SHA-256. Run from ios/ before `xcodegen generate`.
set -euo pipefail
URL=https://download.videolan.org/pub/cocoapods/unstable/VLCKit-4.0.0a19-d7597c1706-85a537d69.tar.xz
SUM=1172078a43150af202c31feb62db3d6687f242d3aa048cce1b899f51c4f14142
[ -d Frameworks/VLCKit.xcframework ] && { echo "VLCKit already there"; exit 0; }
TMP=$(mktemp -d)
curl -fsSL --retry 3 -o "$TMP/vlc.tar.xz" "$URL"
echo "$SUM  $TMP/vlc.tar.xz" | shasum -a 256 -c -
tar -xJf "$TMP/vlc.tar.xz" -C "$TMP" VLCKit-binary/VLCKit.xcframework
mkdir -p Frameworks
mv "$TMP/VLCKit-binary/VLCKit.xcframework" Frameworks/
rm -rf "$TMP"
ls Frameworks/VLCKit.xcframework
