#!/bin/bash
# release.sh — build, sign, notarize, staple, and package Mygration.app into a
# distributable .dmg. Requires an Apple Developer Program membership.
#
# One-time setup:
#   1. Join the Apple Developer Program ($99/yr).
#   2. In Xcode → Settings → Accounts, download a "Developer ID Application" cert.
#   3. Store a notarization credential once:
#        xcrun notarytool store-credentials mygration-notary \
#          --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-pw"
#   4. export DEVID="Developer ID Application: Your Name (TEAMID)"
#   5. ./release.sh
set -euo pipefail
cd "$(dirname "$0")"

: "${DEVID:?set DEVID to your 'Developer ID Application: Name (TEAMID)' identity}"
NOTARY_PROFILE="${NOTARY_PROFILE:-mygration-notary}"
APP="build/Mygration.app"
DMG="build/Mygration.dmg"

echo "==> generating project"
xcodegen generate

echo "==> archiving (Release)"
xcodebuild -project Mygration.xcodeproj -scheme Mygration -configuration Release \
  -derivedDataPath build/dd \
  CODE_SIGN_IDENTITY="$DEVID" \
  CODE_SIGN_STYLE=Manual \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime" \
  build
rm -rf "$APP"; mkdir -p build
cp -R "build/dd/Build/Products/Release/Mygration.app" "$APP"

echo "==> signing (hardened runtime, secure timestamp)"
codesign --force --deep --timestamp --options runtime \
  --entitlements Mygration.entitlements --sign "$DEVID" "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "==> packaging .dmg"
rm -f "$DMG"
hdiutil create -volname "Mygration" -srcfolder "$APP" -ov -format UDZO "$DMG"

echo "==> notarizing (Apple scan; can take a few minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> stapling the ticket"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo "✅ $DMG — notarized & stapled. Users can download and open it normally."
echo "   Verify Gatekeeper acceptance:  spctl -a -t open --context context:primary-signature -v \"$DMG\""
