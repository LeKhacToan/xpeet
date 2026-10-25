#!/usr/bin/env bash
# Prints the UDID of the first paired, connected physical iPhone (cable or Wi-Fi), or nothing.
# Usage: DEVICE_ID=$(scripts/device-id.sh)
set -euo pipefail
devices_json=$(mktemp)
trap 'rm -f "$devices_json"' EXIT
xcrun devicectl list devices --json-output "$devices_json" >/dev/null 2>&1
python3 -I -c '
import json, sys
for d in json.load(open(sys.argv[1]))["result"]["devices"]:
    hw, conn = d["hardwareProperties"], d["connectionProperties"]
    if hw.get("reality") == "physical" and conn.get("pairingState") == "paired" and conn.get("tunnelState") != "unavailable":
        print(hw["udid"]); break
' "$devices_json"
