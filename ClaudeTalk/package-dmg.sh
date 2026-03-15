#!/bin/bash
set -e

APP_DIR="build/release"
APP_NAME=$(ls "$APP_DIR" | grep ".app$" | head -1)

if [ -z "$APP_NAME" ]; then
  echo "No .app found in $APP_DIR. Run build.sh first."
  exit 1
fi

VERSION=$(defaults read "$APP_DIR/$APP_NAME/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "1.0.0")
DMG_NAME="ClaudeTalk-${VERSION}.dmg"

hdiutil create -volname "Claude Talk" \
  -srcfolder "$APP_DIR/$APP_NAME" \
  -ov -format UDZO \
  "build/$DMG_NAME"

echo "DMG created: build/$DMG_NAME"
