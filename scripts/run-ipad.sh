#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Pass another paired iPad's UDID as the first argument if needed.
IPAD_DEVICE_ID="${1:-00008120-001C554628214032}"
xcodebuild \
  -project MyPad.xcodeproj \
  -scheme MyPad \
  -configuration Debug \
  -destination "id=$IPAD_DEVICE_ID" \
  -derivedDataPath build \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  build
xcrun devicectl device install app \
  --device "$IPAD_DEVICE_ID" \
  build/Build/Products/Debug-iphoneos/MyPad.app
xcrun devicectl device process launch \
  --device "$IPAD_DEVICE_ID" \
  --terminate-existing \
  in.texoport.mypad
