#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh
xcodegen generate --quiet
set +e
xcodebuild build -project "$PROJECT" -scheme "$SCHEME" -destination "$DESTINATION" -quiet 2>&1 | grep -v 'IDESchemeActionSDKRecord'
status=${PIPESTATUS[0]}
set -e
[ "$status" -eq 0 ] && echo "** BUILD SUCCEEDED **" || echo "** BUILD FAILED **"
exit "$status"
