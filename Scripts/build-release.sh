#!/usr/bin/env bash
# build-release.sh — Archive, export, and notarize WhisKey
# Usage: ./scripts/build-release.sh [version]
# Requires: Xcode CLI tools, Developer ID Application cert in Keychain
# Notarization requires: xcrun notarytool with App Store Connect API key

set -euo pipefail

SCHEME="WhisKey"
BUNDLE_ID="com.rdemeritt.whiskey"
TEAM_ID="VMYU8579BG"
VERSION="${1:-$(defaults read "$(pwd)/Sources/WhisKeyApp/Info" CFBundleShortVersionString 2>/dev/null || echo "dev")}"
BUILD_DIR="$(pwd)/build"
ARCHIVE_PATH="$BUILD_DIR/WhisKey-${VERSION}.xcarchive"
EXPORT_PATH="$BUILD_DIR/WhisKey-${VERSION}-export"
DMG_PATH="$BUILD_DIR/WhisKey-${VERSION}.dmg"

echo "==> Building WhisKey v${VERSION}"
mkdir -p "$BUILD_DIR"

# 1. Regenerate Xcode project from project.yml
if command -v xcodegen &>/dev/null; then
  echo "==> Regenerating Xcode project"
  xcodegen generate
fi

# 2. Archive
echo "==> Archiving (Release)"
xcodebuild archive \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  | xcpretty || cat

# 3. Export
echo "==> Exporting archive"
cat > "$BUILD_DIR/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
  | xcpretty || cat

APP_PATH="$EXPORT_PATH/WhisKey.app"

# 4. Create DMG (requires create-dmg: brew install create-dmg)
if command -v create-dmg &>/dev/null; then
  echo "==> Creating DMG"
  create-dmg \
    --volname "WhisKey" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --app-drop-link 450 185 \
    "$DMG_PATH" \
    "$APP_PATH"
else
  echo "  [skip] create-dmg not found — skipping DMG creation (brew install create-dmg)"
fi

# 5. Notarization (requires Apple Developer Program enrollment)
echo ""
echo "==> Notarization (manual step — requires Developer ID cert + App Store Connect API key)"
echo "    Run when enrolled:"
echo ""
echo "    xcrun notarytool submit \"$DMG_PATH\" \\"
echo "      --apple-id YOUR_APPLE_ID \\"
echo "      --team-id $TEAM_ID \\"
echo "      --password APP_SPECIFIC_PASSWORD \\"
echo "      --wait"
echo ""
echo "    xcrun stapler staple \"$DMG_PATH\""
echo ""
echo "==> Archive: $ARCHIVE_PATH"
echo "==> Export:  $EXPORT_PATH"
[ -f "$DMG_PATH" ] && echo "==> DMG:     $DMG_PATH"
echo "==> Done."
