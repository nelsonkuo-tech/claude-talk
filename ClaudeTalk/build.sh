#!/bin/bash
set -e

# Regenerate project from xcodegen
xcodegen generate

# Build release
xcodebuild -project ClaudeTalk.xcodeproj \
  -scheme ClaudeTalk \
  -configuration Release \
  -derivedDataPath build \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  build

# Copy app bundle
APP_PATH="build/Build/Products/Release/Claude Talk.app"
if [ ! -d "$APP_PATH" ]; then
  APP_PATH="build/Build/Products/Release/ClaudeTalk.app"
fi

mkdir -p build/release
cp -R "$APP_PATH" "build/release/"

echo "Build complete: build/release/"
