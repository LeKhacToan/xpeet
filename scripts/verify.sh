#!/usr/bin/env bash
# Single entry point for "is this task done?". Used by Claude, the verifier agent, and CI.
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/lint.sh
scripts/test.sh   # test builds the app target too
