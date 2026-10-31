#!/bin/bash
# UPDATE-02: is this a proper release? Universal (Apple Silicon and Intel), signed with a Developer
# ID with the hardened runtime, accepted by Gatekeeper as notarised, and the notarisation stapled.
# Run it on the app from the latest release's zip (spctl may ask Apple about the notarisation):
#   Tests/scripts/UPDATE-02-release-check.sh ~/Downloads/Expanse.app
# Prints each check; exits 1 if any fails. (UPDATETests runs it with stand-ins for the tools.)
set -uo pipefail
APP="${1:?usage: $0 path/to/Expanse.app}"
failed=0
pass() { echo "ok    $1"; }
fail() { echo "FAIL  $1"; printf '%s\n' "$2" | sed 's/^/      /'; failed=1; }

archs=$(lipo -archs "$APP/Contents/MacOS/Expanse" 2>&1)
if [[ " $archs " == *" x86_64 "* && " $archs " == *" arm64 "* ]]; then pass "universal: $archs"
else fail "universal (x86_64 and arm64)" "$archs"; fi

signature=$(codesign -dv --verbose=2 "$APP" 2>&1)
if grep -q '^Authority=Developer ID Application: ' <<<"$signature"; then pass "signed with a Developer ID"
else fail "signed with a Developer ID" "$signature"; fi
if grep -Eq '^CodeDirectory .*flags=0x[0-9a-f]+\([^)]*runtime' <<<"$signature"; then pass "hardened runtime"
else fail "hardened runtime" "$signature"; fi

gatekeeper=$(spctl -a -vv "$APP" 2>&1)
if grep -q ': accepted$' <<<"$gatekeeper" && grep -qx 'source=Notarized Developer ID' <<<"$gatekeeper"; then pass "Gatekeeper: accepted, notarised"
else fail "Gatekeeper accepts it as notarised" "$gatekeeper"; fi

if stapled=$(xcrun stapler validate "$APP" 2>&1); then pass "notarisation stapled"
else fail "notarisation stapled" "$stapled"; fi

exit $failed
