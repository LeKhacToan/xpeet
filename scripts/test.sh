#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh
xcodegen generate --quiet
set +e
xcodebuild test -project "$PROJECT" -scheme "$SCHEME" -destination "$DESTINATION" -quiet 2>&1 | grep -v -e 'IDESchemeActionSDKRecord' -e 'IDETestOperationsObserverDebug'
status=${PIPESTATUS[0]}
set -e
[ "$status" -eq 0 ] && echo "** TEST SUCCEEDED **" || echo "** TEST FAILED **"
exit "$status"
