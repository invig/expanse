#!/bin/bash
# Retakes the README's screenshots (docs/screenshots) in the VM. Expanse Tests lays out stock apps
# and drives each feature (Tests/Integration/.../Screenshots.swift); this takes the pictures over
# SSH when it asks, since SSH can record the VM's screen and Expanse Tests needn't be allowed to.
# Run it like scripts/vm-integration.sh (docs/regression/README.md, Using the VM): with the Mac
# kept awake, and `tart stop expanse-demo` when you've finished.
#
#   scripts/screenshots.sh                 all of them
#   scripts/screenshots.sh overview,tidy   only those
set -euo pipefail
cd "$(dirname "$0")/.."
VM="${VM:-expanse-demo}"
VM_USER="${VM_USER:-admin}"

WATCH='rm -f /tmp/expanse-shot; while :; do
  if [ -s /tmp/expanse-shot ]; then
    sudo launchctl asuser 501 sudo -u admin screencapture -x -C "$(cat /tmp/expanse-shot)"
    rm -f /tmp/expanse-shot
  fi
  sleep 0.1
done'
# Waits for the VM to come up (the run below starts it). -tt so the loop ends when SSH does.
(until IP="$(tart ip "$VM" 2>/dev/null)" && ssh -tt -o BatchMode=yes -o ConnectTimeout=10 "$VM_USER@$IP" "$WATCH" > /dev/null 2>&1; do sleep 3; done) &
WATCHER=$!
disown
trap 'kill $WATCHER 2>/dev/null; pkill -f "ssh -tt .*expanse-shot" 2>/dev/null || true' EXIT

./scripts/vm-integration.sh --shots ${1:-}

mkdir -p docs/screenshots
for f in build/integration-vm/*.png; do
  sips -Z 1400 "$f" --out "docs/screenshots/$(basename "${f%.png}").jpg" -s format jpeg -s formatOptions 72 > /dev/null
done
echo "Pictures: docs/screenshots/"
