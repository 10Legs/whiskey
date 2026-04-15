#!/usr/bin/env bash
# Bundle the WhisKey SPM binary into a proper .app bundle so macOS
# Privacy & Security recognises it and shows it in permission lists.
#
# Usage:
#   bash Scripts/bundle-app.sh [--debug]
#
# Output: WhisKey.app in the project root

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

CONFIG="release"
if [[ "${1:-}" == "--debug" ]]; then
    CONFIG="debug"
fi

BUILD_DIR=".build/arm64-apple-macosx/$CONFIG"
BINARY="$BUILD_DIR/WhisKey"
INFO_PLIST="Sources/WhisKeyApp/Info.plist"
APP_BUNDLE="WhisKey.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES_SRC="Resources"
RESOURCES_DST="$CONTENTS/Resources"

echo "Building ($CONFIG)..."
swift build -c "$CONFIG"

echo "Assembling $APP_BUNDLE..."
# Create structure only if it doesn't exist yet.
# Updating in-place (not rm -rf) preserves TCC permission grants across rebuilds.
mkdir -p "$MACOS"
mkdir -p "$RESOURCES_DST"

cp "$BINARY" "$MACOS/WhisKey"
cp "$INFO_PLIST" "$CONTENTS/Info.plist"

# Copy model resources if present
if [ -d "$RESOURCES_SRC" ]; then
    cp -R "$RESOURCES_SRC/." "$RESOURCES_DST/"
fi

# Sign ad-hoc. The bundle ID in Info.plist (com.rdemeritt.whiskey) is used as
# the stable TCC identifier — updating the binary in-place keeps existing grants.
codesign --force --sign - "$APP_BUNDLE/Contents/MacOS/WhisKey"
codesign --force --sign - "$APP_BUNDLE"

echo ""
echo "Done: $PROJECT_DIR/$APP_BUNDLE"
echo ""
echo "Launch with:  open $PROJECT_DIR/$APP_BUNDLE"
