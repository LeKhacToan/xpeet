#!/usr/bin/env bash
# Builds Xpeet, signs it with your Apple Development certificate and installs it on a connected iPhone.
# Re-run whenever the app stops opening: free Apple ID profiles expire after 7 days.
# Usage: scripts/install-device.sh
# Overrides: DEVICE_ID=<udid> TEAM_ID=<team> scripts/install-device.sh
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh

BUNDLE_ID="app.plouton.xpeet"
DERIVED_DATA="build/DerivedData-device"

# Team ID: the OU field of the first "Apple Development" certificate in the keychain.
if [ -z "${TEAM_ID:-}" ]; then
    TEAM_ID=$(security find-certificate -c "Apple Development" -p 2>/dev/null \
        | openssl x509 -noout -subject 2>/dev/null \
        | sed -n 's/.*OU=\([A-Z0-9]*\).*/\1/p')
fi
if [ -z "$TEAM_ID" ]; then
    echo "error: no Apple Development certificate found. Sign in to Xcode > Settings > Accounts once." >&2
    exit 1
fi

# Device: the first paired physical iPhone that is connected (cable or Wi-Fi).
if [ -z "${DEVICE_ID:-}" ]; then
    devices_json=$(mktemp)
    trap 'rm -f "$devices_json"' EXIT
    xcrun devicectl list devices --json-output "$devices_json" >/dev/null 2>&1
    DEVICE_ID=$(python3 -I -c '
import json, sys
for d in json.load(open(sys.argv[1]))["result"]["devices"]:
    hw, conn = d["hardwareProperties"], d["connectionProperties"]
    if hw.get("reality") == "physical" and conn.get("pairingState") == "paired" and conn.get("tunnelState") != "unavailable":
        print(hw["udid"]); break
' "$devices_json")
fi
if [ -z "$DEVICE_ID" ]; then
    echo "error: no iPhone found. Plug it in with a cable, unlock it and tap Trust, then run again." >&2
    exit 1
fi

echo "install: team $TEAM_ID, device $DEVICE_ID"
xcodegen generate --quiet

set +e
xcodebuild build -project "$PROJECT" -scheme "$SCHEME" -configuration Debug \
    -destination "id=$DEVICE_ID" -derivedDataPath "$DERIVED_DATA" \
    DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates -quiet 2>&1 \
    | grep -v 'IDESchemeActionSDKRecord'
status=${PIPESTATUS[0]}
set -e
if [ "$status" -ne 0 ]; then
    echo "** INSTALL FAILED ** (build)" >&2
    exit "$status"
fi

xcrun devicectl device install app --device "$DEVICE_ID" "$DERIVED_DATA/Build/Products/Debug-iphoneos/Xpeet.app" >/dev/null
xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID" >/dev/null 2>&1 \
    || echo "note: installed, but could not launch it (unlock the iPhone and open Xpeet)."
echo "** INSTALL SUCCEEDED **"
