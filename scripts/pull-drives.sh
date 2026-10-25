#!/usr/bin/env bash
# Copies recorded drives (specs/speed-accuracy R24) off the connected iPhone into build/drives/ (gitignored).
# Files are copied one by one: whole-directory copies are known to time out.
# Usage: scripts/pull-drives.sh            then: scripts/test.sh (AccuracyReportTests writes build/drives/report.txt)
# Overrides: DEVICE_ID=<udid> scripts/pull-drives.sh
set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID="app.plouton.xpeet"
DEST="build/drives"
DEVICE_ID="${DEVICE_ID:-$(scripts/device-id.sh)}"
if [ -z "$DEVICE_ID" ]; then
    echo "error: no iPhone found. Plug it in with a cable, unlock it and tap Trust, then run again." >&2
    exit 1
fi
mkdir -p "$DEST"

listing=$(mktemp)
trap 'rm -f "$listing"' EXIT
xcrun devicectl device info files --device "$DEVICE_ID" \
    --domain-type appDataContainer --domain-identifier "$BUNDLE_ID" --username mobile \
    --subdirectory Documents/Drives --json-output "$listing" >/dev/null
# The listing's JSON shape is not documented: collect every string that names a .jsonl file.
names=$(python3 -I -c '
import json, os, sys
found = set()
def walk(node):
    if isinstance(node, dict):
        for value in node.values(): walk(value)
    elif isinstance(node, list):
        for value in node: walk(value)
    elif isinstance(node, str) and node.endswith(".jsonl"):
        found.add(os.path.basename(node))
walk(json.load(open(sys.argv[1])))
print("\n".join(sorted(found)))
' "$listing")

if [ -z "$names" ]; then
    echo "pull: no drives on the phone (launch with RECORD=1 scripts/install-device.sh, then drive)."
    exit 0
fi
count=0
while IFS= read -r name; do
    if [ -f "$DEST/$name" ]; then
        echo "pull: $name (already here)"
        continue
    fi
    xcrun devicectl device copy from --device "$DEVICE_ID" \
        --domain-type appDataContainer --domain-identifier "$BUNDLE_ID" --user mobile \
        --source "Documents/Drives/$name" --destination "$DEST/$name" >/dev/null
    echo "pull: $name"
    count=$((count + 1))
done <<< "$names"
echo "** PULLED $count DRIVE(S) INTO $DEST **"
