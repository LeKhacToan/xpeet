#!/usr/bin/env bash
# Copies recorded drives (specs/speed-accuracy R24) off the connected iPhone into build/drives/ (gitignored).
# Files are copied one by one: whole-directory copies are known to time out.
# Usage: scripts/pull-drives.sh            then: scripts/test.sh (AccuracyReportTests writes build/drives/report.txt)
# Overrides: DEVICE_ID=<udid> scripts/pull-drives.sh
#            DEST=build/drives-precise-off scripts/pull-drives.sh   keeps a drive out of the accuracy report
#            (specs/precise-location R15). A later default pull skips any drive already in a build/drives-*/ folder.
set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID="app.plouton.xpeet"
DEST="${DEST:-build/drives}"
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
newest=$(printf '%s\n' "$names" | tail -1)
count=0
while IFS= read -r name; do
    # A drive set aside in another build/drives-*/ folder stays out of the accuracy report (precise-location R15).
    if [ "$DEST" = "build/drives" ]; then
        for kept in build/drives-*/; do
            if [ -f "$kept$name" ]; then
                echo "pull: $name (kept out, in $kept)"
                continue 2
            fi
        done
    fi
    # The newest drive may still be recording, so it is always fetched again; finished ones are fetched once.
    if [ -f "$DEST/$name" ] && [ "$name" != "$newest" ]; then
        echo "pull: $name (already here)"
        continue
    fi
    # Copy to a temporary name first, so a failed copy never looks like a finished drive.
    part="$DEST/.$name.part"
    rm -f "$part"
    xcrun devicectl device copy from --device "$DEVICE_ID" \
        --domain-type appDataContainer --domain-identifier "$BUNDLE_ID" --user mobile \
        --source "Documents/Drives/$name" --destination "$part" >/dev/null
    mv "$part" "$DEST/$name"
    echo "pull: $name"
    count=$((count + 1))
done <<< "$names"
echo "** PULLED $count DRIVE(S) INTO $DEST **"
