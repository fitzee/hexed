#!/bin/bash
# Convert a 1024x1024 PNG to macOS .icns
# Usage: bash make_icon.sh icon.png

set -e

INPUT="${1:-icon.png}"
if [ ! -f "$INPUT" ]; then
    echo "Usage: bash make_icon.sh <1024x1024.png>"
    exit 1
fi

ICONSET="hexed.iconset"
mkdir -p "$ICONSET"

sips -z 16 16       "$INPUT" --out "$ICONSET/icon_16x16.png"      >/dev/null
sips -z 32 32       "$INPUT" --out "$ICONSET/icon_16x16@2x.png"   >/dev/null
sips -z 32 32       "$INPUT" --out "$ICONSET/icon_32x32.png"      >/dev/null
sips -z 64 64       "$INPUT" --out "$ICONSET/icon_32x32@2x.png"   >/dev/null
sips -z 128 128     "$INPUT" --out "$ICONSET/icon_128x128.png"    >/dev/null
sips -z 256 256     "$INPUT" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256     "$INPUT" --out "$ICONSET/icon_256x256.png"    >/dev/null
sips -z 512 512     "$INPUT" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512     "$INPUT" --out "$ICONSET/icon_512x512.png"    >/dev/null
sips -z 1024 1024   "$INPUT" --out "$ICONSET/icon_512x512@2x.png" >/dev/null

iconutil -c icns "$ICONSET" -o hexed.icns
rm -rf "$ICONSET"
echo "Created hexed.icns"
