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

# Compile Metal shaders and place default.metallib next to the binary.
# ggml-metal-device.m looks for it in bin_dir (Contents/MacOS/), not Resources.
# SPM excludes the .metal file from compilation, so we compile it here.
METAL_SRC="CGGML/ggml-metal/ggml-metal.metal"
METALLIB_DST="$MACOS/default.metallib"
if [ -f "$METAL_SRC" ]; then
    echo "Compiling Metal shaders..."
    AIR_FILE="$BUILD_DIR/ggml-metal.air"
    xcrun -sdk macosx metal -c "$METAL_SRC" -o "$AIR_FILE" \
        -I "CGGML/ggml-metal" \
        -I "CGGML/include" \
        2>&1
    xcrun -sdk macosx metallib "$AIR_FILE" -o "$METALLIB_DST" 2>&1
    echo "Compiled default.metallib → $METALLIB_DST"
else
    echo "Warning: $METAL_SRC not found — Metal acceleration will not work."
fi

# Also copy the .metal source to Resources as runtime-compile fallback
# (ggml falls back to bundle resource path if metallib not found next to binary)
if [ -f "$METAL_SRC" ]; then
    cp "$METAL_SRC" "$RESOURCES_DST/ggml-metal.metal"
fi

# Sign with a stable local identity so TCC keeps microphone/accessibility grants
# across rebuilds. Requires a self-signed "WhiskeyDev" cert in your login keychain:
#   Keychain Access → Certificate Assistant → Create a Certificate
#   Name: WhiskeyDev, Identity Type: Self Signed Root, Cert Type: Code Signing
#
# Falls back to ad-hoc if the cert is not found (TCC will re-prompt after each build).
SIGN_IDENTITY="WhiskeyDev"
if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
    echo "Warning: '$SIGN_IDENTITY' cert not found in login keychain — falling back to ad-hoc signing."
    echo "         TCC permissions will reset on every rebuild until you create the cert."
    SIGN_IDENTITY="-"
fi

ENTITLEMENTS="WhisKey/WhisKey.entitlements"
codesign --force --sign "$SIGN_IDENTITY" --entitlements "$ENTITLEMENTS" "$APP_BUNDLE/Contents/MacOS/WhisKey"
codesign --force --sign "$SIGN_IDENTITY" --entitlements "$ENTITLEMENTS" "$APP_BUNDLE"

echo ""
echo "Done: $PROJECT_DIR/$APP_BUNDLE"
echo ""
echo "Launch with:  open $PROJECT_DIR/$APP_BUNDLE"
