#!/bin/bash
# Builds a signed, notarised, universal Expanse.app, publishes it as a GitHub release, and points
# the Homebrew cask at it (scripts/update-cask.sh).
#
# One-time setup:
#   1. A "Developer ID Application" certificate in your keychain
#      (Xcode › Settings › Accounts › Manage Certificates › + › Developer ID Application).
#   2. Notarisation credentials saved in the keychain under the profile "expanse-notary":
#        xcrun notarytool store-credentials expanse-notary --apple-id <you@example.com> --team-id <TEAMID>
#      (it asks for an app-specific password from account.apple.com).
#
# Usage: scripts/release.sh            # version from Resources/Info.plist
#        DRY_RUN=1 scripts/release.sh  # everything except notarising and publishing
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
IDENTITY="${CODESIGN_IDENTITY:-Developer ID Application}"
PROFILE="${NOTARY_PROFILE:-expanse-notary}"
OUT="build/release"
APP="$OUT/Expanse.app"
ZIP="$OUT/Expanse-$VERSION.zip"

echo "==> Expanse $VERSION"
if [[ -z "${DRY_RUN:-}" ]] && git tag --list | grep -qx "v$VERSION"; then
  echo "Tag v$VERSION already exists; bump CFBundleShortVersionString in Resources/Info.plist." >&2
  exit 1
fi

echo "==> Building universal binary (Apple Silicon + Intel)"
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Expanse"
lipo -info "$BIN"

rm -rf "$OUT"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Expanse"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "==> Signing with $IDENTITY (hardened runtime)"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

if [[ -n "${DRY_RUN:-}" ]]; then
  echo "==> Dry run: skipping notarisation and publishing. App at $APP"
  exit 0
fi

echo "==> Notarising (this takes a few minutes)"
ditto -c -k --keepParent "$APP" "$OUT/notarise.zip"
xcrun notarytool submit "$OUT/notarise.zip" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
spctl --assess --type execute --verbose=2 "$APP"

echo "==> Packaging"
ditto -c -k --keepParent "$APP" "$ZIP"
shasum -a 256 "$ZIP"

echo "==> Publishing GitHub release v$VERSION"
gh release create "v$VERSION" "$ZIP" --title "Expanse $VERSION" --notes-file - <<NOTES
**Your Mac, on an infinite canvas.**

Download \`Expanse-$VERSION.zip\`, unzip, and move **Expanse.app** to Applications. It's signed and
notarised by Apple, and runs on macOS 15 or later (Apple Silicon and Intel).

On first launch a short walkthrough sets up the two permissions Expanse needs (Accessibility and
Screen Recording) and shows the shortcuts. See the [README](https://github.com/invig/expanse#readme)
for everything else.
NOTES

echo "==> Updating the Homebrew cask (invig/homebrew-tap)"
scripts/update-cask.sh "$VERSION" "$ZIP" ||
  echo "The release is out, but the cask isn't updated: run scripts/update-cask.sh $VERSION $ZIP" >&2
echo "==> Done"
