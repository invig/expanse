#!/bin/bash
# Builds Canvas.app into ./build and signs it with the local Apple Development
# identity, so macOS keeps the Accessibility / Screen Recording grants across rebuilds.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
IDENTITY="${CODESIGN_IDENTITY:-Apple Development}"
APP="build/Canvas.app"

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Canvas"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Canvas"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --timestamp=none --sign "$IDENTITY" "$APP"

echo "Built $APP"
