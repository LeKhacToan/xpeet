#!/usr/bin/env bash
# Usage: evals/check.sh <case.json> <workdir>  -> runs the case's acceptance checks inside workdir.
set -uo pipefail
case_file=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
cd "$2"
fail=0
while IFS= read -r check; do
  if bash -c "$check" </dev/null >/dev/null 2>&1; then echo "  ✅ $check"; else echo "  ❌ $check"; fail=1; fi
done < <(jq -r '.checks[]' "$case_file")
exit $fail
