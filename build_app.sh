#!/bin/bash
# Build hexed.app bundle for macOS
# Usage: bash build_app.sh [--dmg]
set -e

m2c build

APP=".m2c/Hexed.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .m2c/bin/hexed "$APP/Contents/MacOS/hexed-bin"
cp platform/macos/Info.plist "$APP/Contents/"

# Shell wrapper: handles "open file.bin" drag-and-drop and Open With
cat > "$APP/Contents/MacOS/hexed" << 'WRAPPER'
#!/bin/bash
DIR="$(dirname "$0")"
if [ $# -ge 1 ]; then
    exec "$DIR/hexed-bin" "$1"
else
    # macOS passes opened files via "open" events; for CLI use show usage
    FILE=$(osascript -e 'POSIX path of (choose file with prompt "Open file in hexed:")' 2>/dev/null)
    if [ -n "$FILE" ]; then
        exec "$DIR/hexed-bin" "$FILE"
    fi
fi
WRAPPER
chmod +x "$APP/Contents/MacOS/hexed"

# Copy icon if it exists
if [ -f platform/macos/hexed.icns ]; then
    cp platform/macos/hexed.icns "$APP/Contents/Resources/"
fi

# Ad-hoc codesign so macOS doesn't block the app
codesign --force --deep -s - "$APP"

echo "Built: $APP"

# --- DMG packaging ---
if [ "$1" = "--dmg" ]; then
    VERSION=$(grep '^version=' m2.toml | cut -d= -f2)
    DMG_NAME="Hexed-${VERSION}.dmg"
    DMG_PATH=".m2c/$DMG_NAME"
    STAGING=".m2c/dmg_staging"

    rm -rf "$STAGING" "$DMG_PATH"
    mkdir -p "$STAGING"

    # Copy app into staging
    cp -R "$APP" "$STAGING/"

    # Symlink to /Applications for drag-to-install
    ln -s /Applications "$STAGING/Applications"

    # Create DMG
    hdiutil create -volname "Hexed" \
        -srcfolder "$STAGING" \
        -ov -format UDZO \
        "$DMG_PATH" >/dev/null

    rm -rf "$STAGING"
    echo "Created: $DMG_PATH"
else
    echo "Run:   open $APP file.bin"
    echo "  or:  bash build_app.sh --dmg"
fi
