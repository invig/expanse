#!/bin/bash
# Builds Expanse Tests (Tests/Integration) and runs the end-to-end regression cases against the
# running development build of Expanse. It drives real windows: run it in a VM or a spare Mac,
# not on a desktop you're using.
#
# Needs: a development build of Expanse running (./scripts/build.sh; open build/Expanse.app),
# with `defaults write com.invignation.expanse debugURLCommands -bool true`; and, for cases that
# press keys or move the pointer, Accessibility for Expanse Tests.
#
#   scripts/integration.sh                 the cases that run on their own
#   scripts/integration.sh --all           every case (guided ones ask you in a panel)
#   scripts/integration.sh --area NAV      one area; --only NAV-03,URL-01 for single cases
#   scripts/integration.sh --build-only    just build it
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${CODESIGN_IDENTITY:-}" ]]; then
  if security find-identity -v -p codesigning 2>/dev/null | grep -q "Apple Development"; then
    CODESIGN_IDENTITY="Apple Development"
  else
    CODESIGN_IDENTITY="-"
  fi
fi

swift build -c release --package-path Tests/Integration
BIN="$(swift build -c release --package-path Tests/Integration --show-bin-path)/ExpanseIntegration"
APP="build/ExpanseTests.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/ExpanseIntegration"
cp Tests/Integration/Info.plist "$APP/Contents/Info.plist"
codesign --force --timestamp=none --sign "$CODESIGN_IDENTITY" "$APP"
[[ "${1:-}" == "--build-only" ]] && { echo "Built $APP"; exit 0; }

OUT="$PWD/build/integration"
rm -rf "$OUT"; mkdir -p "$OUT"
touch "$OUT/progress.log"
tail -f "$OUT/progress.log" &
TAIL=$!
trap 'kill $TAIL 2>/dev/null' EXIT
open -W -n "$APP" --args --out "$OUT" "$@"
sleep 0.5
echo "Report: $OUT/report.md"
! grep -q "| FAILED |" "$OUT/report.md" 2>/dev/null
