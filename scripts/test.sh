#!/bin/bash
# Runs the regression unit tests (docs/regression). One at a time: some share settings and
# folders. Extra arguments go to swift test, e.g. scripts/test.sh --filter NAV
set -euo pipefail
cd "$(dirname "$0")/.."
swift test --no-parallel "$@"
