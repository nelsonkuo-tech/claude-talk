#!/bin/bash
set -e

cd "$(dirname "$0")"

APP_NAME="ClaudeTalk"
VERSION="1.3.1"
BUILD_DIR="build/release"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
DMG_NAME="$APP_NAME-$VERSION.dmg"

echo "=== Claude Talk $VERSION Release Build ==="

# Clean
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Step 1: Build PyInstaller binary (if not already built)
PYINSTALLER_DIR="build/pyinstaller/transcribe_server"
if [ ! -d "$PYINSTALLER_DIR" ]; then
    echo ">>> Building transcribe_server binary..."
    python3 -m PyInstaller \
        --onedir \
        --name transcribe_server \
        --distpath build/pyinstaller \
        --workpath build/pyinstaller-work \
        --specpath build \
        --hidden-import faster_whisper \
        --hidden-import ctranslate2 \
        --hidden-import numpy \
        --hidden-import numpy.fft._pocketfft_umath \
        --collect-all ctranslate2 \
        --collect-all faster_whisper \
        --collect-all numpy \
        --target-arch arm64 \
        --noconfirm \
        ClaudeTalk/Transcription/transcribe_server.py
else
    echo ">>> PyInstaller binary already built, skipping..."
fi

# Step 2: Build Swift app (Release)
echo ">>> Building Swift app..."
xcodebuild \
    -scheme ClaudeTalk \
    -configuration Release \
    -arch arm64 \
    -derivedDataPath build/derived \
    CONFIGURATION_BUILD_DIR="$(pwd)/$BUILD_DIR" \
    build 2>&1 | tail -5

# Step 3: Bundle transcribe_server directory into app Resources
echo ">>> Bundling transcribe_server..."
RESOURCES="$APP_BUNDLE/Contents/Resources"
cp -R "$PYINSTALLER_DIR" "$RESOURCES/transcribe_server_dist"
chmod +x "$RESOURCES/transcribe_server_dist/transcribe_server"

# Step 4: Remove development files from Resources
rm -f "$RESOURCES/transcribe_server.py" 2>/dev/null || true

# Step 6: Code sign with Developer ID
SIGN_IDENTITY="Developer ID Application: CHENG HAO KUO (YWM35G3G8G)"
echo ">>> Code signing with: $SIGN_IDENTITY"
codesign --force --deep --sign "$SIGN_IDENTITY" --options runtime "$APP_BUNDLE"

# Step 7: Create DMG
echo ">>> Creating DMG..."
DMG_TMP="$BUILD_DIR/tmp.dmg"
DMG_FINAL="$BUILD_DIR/$DMG_NAME"

hdiutil create -size 800m -fs HFS+ -volname "$APP_NAME" "$DMG_TMP" -quiet
hdiutil attach "$DMG_TMP" -quiet -mountpoint /tmp/claudetalk-dmg-mount
cp -R "$APP_BUNDLE" /tmp/claudetalk-dmg-mount/
ln -s /Applications /tmp/claudetalk-dmg-mount/Applications
hdiutil detach /tmp/claudetalk-dmg-mount -quiet
hdiutil convert "$DMG_TMP" -format UDZO -o "$DMG_FINAL" -quiet
rm -f "$DMG_TMP"

# Summary
APP_SIZE=$(du -sh "$APP_BUNDLE" | awk '{print $1}')
DMG_SIZE=$(du -sh "$DMG_FINAL" | awk '{print $1}')

echo ""
echo "=== Build Complete ==="
echo "  App: $APP_BUNDLE ($APP_SIZE)"
echo "  DMG: $DMG_FINAL ($DMG_SIZE)"
echo "  Version: $VERSION"
