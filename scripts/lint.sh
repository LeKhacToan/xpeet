#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v swiftlint >/dev/null; then
  echo "lint: SKIPPED (brew install swiftlint)"
  exit 0
fi
swiftlint lint --quiet --strict "$@" && echo "lint: OK"
