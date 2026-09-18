#!/usr/bin/env bash
# Builds the executable and assembles a signed TapSwitch.app in build/.
# Prints the bundle path on stdout; everything else goes to stderr.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${CONFIG:-debug}"
APP="$ROOT/build/TapSwitch.app"

swift build --package-path "$ROOT" -c "$CONFIG" --product tapswitch >&2
BIN_DIR="$(swift build --package-path "$ROOT" -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/tapswitch" "$APP/Contents/MacOS/TapSwitch"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/"

# A stable identity keeps the bundle's designated requirement the same across
# rebuilds, so Login Items keeps pointing at it. Ad-hoc works too.
IDENTITY="$(security find-identity -v -p codesigning \
  | awk -F'"' '$2 == "TapSwitch Dev" { split($1, f, " "); print f[2]; exit }')"
if [ -z "$IDENTITY" ]; then
    echo "warning: no 'TapSwitch Dev' identity found — signing ad-hoc." >&2
    echo "warning: run Scripts/make-dev-cert.sh for a stable signature." >&2
    IDENTITY="-"
fi

codesign --force --sign "$IDENTITY" "$APP" >&2

echo "$APP"
