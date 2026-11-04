#!/bin/bash
# Runs the end-to-end regression cases (scripts/integration.sh) inside a tart VM, so they drive the
# VM's windows instead of yours. Builds Expanse and Expanse Tests here, copies them in, and copies
# the report back to build/integration-vm/. It starts the VM if it's stopped but never stops it:
# run `tart stop expanse-demo` when you've finished with it.
#
# One-time setup in the VM (see docs/regression/README.md, Using the VM):
#   - this Mac's SSH key in the VM's ~/.ssh/authorized_keys (ssh-copy-id admin@<VM address>);
#   - Accessibility and Screen Recording for Expanse, and Accessibility for Expanse Tests, in the
#     VM's System Settings (they're kept across rebuilds signed with the same certificate).
#
#   scripts/vm-integration.sh [arguments for the runner: --all, --area NAV, --only NAV-03 …]
# VM defaults to expanse-demo (VM=name to change), user admin (VM_USER=name).
set -euo pipefail
cd "$(dirname "$0")/.."
VM="${VM:-expanse-demo}"
VM_USER="${VM_USER:-admin}"

./scripts/build.sh > /dev/null
./scripts/integration.sh --build-only > /dev/null

if ! tart list | grep -q "^local *$VM .*running"; then
  echo "Starting $VM…"
  tart run "$VM" > /dev/null 2>&1 &
fi
# The DHCP lease file sometimes loses track of the VM; the ARP table still has it.
IP="$(tart ip "$VM" --wait 120 2>/dev/null || tart ip "$VM" --resolver arp)"
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new "$VM_USER@$IP")
until "${SSH[@]}" true 2>/dev/null; do sleep 3; done

# The apps live in ~/Applications in the VM, so their paths (and permissions) stay the same.
"${SSH[@]}" 'mkdir -p ~/Applications; osascript -e "tell application id \"com.invignation.expanse\" to quit" 2>/dev/null; sleep 1; rm -rf ~/Applications/Expanse.app ~/Applications/ExpanseTests.app'
tar -C build -czf - Expanse.app ExpanseTests.app | "${SSH[@]}" 'tar -C ~/Applications -xzf -'
# Animations at their real speed for the run (the demo videos slow them down), put back after.
# A VM's capture service runs out of room for streams sooner than a Mac's (see streamBudget in
# CanvasController): 8 for the run, as docs/how-it-works.md suggests. Both put back after.
SLOWDOWN="$("${SSH[@]}" 'defaults read com.invignation.expanse animationSlowdown 2>/dev/null' || true)"
BUDGET="$("${SSH[@]}" 'defaults read com.invignation.expanse streamBudget 2>/dev/null' || true)"
# Expanse Tests' closed windows from earlier runs out of Expanse's saved layout (see
# forgetOwnWindowsInExpanseLayout in Harness.swift), with Expanse not running yet.
"${SSH[@]}" '~/Applications/ExpanseTests.app/Contents/MacOS/ExpanseIntegration --forget-own-windows'
"${SSH[@]}" 'defaults write com.invignation.expanse debugURLCommands -bool true; defaults delete com.invignation.expanse animationSlowdown 2>/dev/null; defaults write com.invignation.expanse streamBudget -int 8; open ~/Applications/Expanse.app; sleep 3'
restore_slowdown() {
  [[ -n "$SLOWDOWN" ]] && "${SSH[@]}" "defaults write com.invignation.expanse animationSlowdown -float $SLOWDOWN" || true
  if [[ -n "$BUDGET" ]]; then "${SSH[@]}" "defaults write com.invignation.expanse streamBudget -int $BUDGET" || true
  else "${SSH[@]}" "defaults delete com.invignation.expanse streamBudget 2>/dev/null" || true; fi
}
trap restore_slowdown EXIT

ARGS=$(printf ' %q' "$@")
"${SSH[@]}" "rm -rf ~/ExpanseTestsReport; mkdir -p ~/ExpanseTestsReport; touch ~/ExpanseTestsReport/progress.log; \
  (tail -f ~/ExpanseTestsReport/progress.log & echo \$! > /tmp/tail.pid); \
  open -W -n ~/Applications/ExpanseTests.app --args --out ~/ExpanseTestsReport --expanse ~/Applications/Expanse.app$ARGS; \
  sleep 0.5; kill \$(cat /tmp/tail.pid)"
rm -rf build/integration-vm; mkdir -p build/integration-vm
scp -q -o BatchMode=yes "$VM_USER@$IP:ExpanseTestsReport/*" build/integration-vm/
echo "Report: build/integration-vm/report.md"
echo "$VM is still running. When you've finished with it: tart stop $VM"
! grep -q "| FAILED |" build/integration-vm/report.md
