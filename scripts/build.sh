#!/bin/bash
# Builds Expanse.app into ./build.
#
# Signing: uses your "Apple Development" certificate if you have one, so macOS keeps the
# Accessibility / Screen Recording grants across rebuilds. Without one it signs ad hoc, which
# works too, but macOS will ask you to grant the permissions again after each rebuild.
# Override with CODESIGN_IDENTITY="Your Identity" (or "-" for ad hoc).
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
APP="build/Expanse.app"

if [[ -z "${CODESIGN_IDENTITY:-}" ]]; then
  if security find-identity -v -p codesigning 2>/dev/null | grep -q "Apple Development"; then
    CODESIGN_IDENTITY="Apple Development"
  else
    CODESIGN_IDENTITY="-"
  fi
fi

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Expanse"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Expanse"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --timestamp=none --sign "$CODESIGN_IDENTITY" "$APP"

echo "Built $APP (signed with: $CODESIGN_IDENTITY)"
