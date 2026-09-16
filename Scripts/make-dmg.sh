#!/usr/bin/env bash
# Builds a release TapSwitch.app and wraps it in a compressed disk image.
#
# The image is not notarized: notarization needs a paid Developer ID, and the
# app's whole technique is a private framework, so the App Store was never a
# destination. A first launch needs clearing Gatekeeper by hand; the README
# says how.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGING="$ROOT/build/dmg"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
DMG="$ROOT/build/TapSwitch-$VERSION.dmg"

APP="$(CONFIG=release "$ROOT/Scripts/bundle.sh")"

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
    -volname "TapSwitch $VERSION" \
    -srcfolder "$STAGING" \
    -ov -format UDZO \
    "$DMG" >&2

rm -rf "$STAGING"
echo "$DMG"
