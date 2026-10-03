#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
MYPAD_TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$MYPAD_TEST_DIR"' EXIT
# PencilKit expects a main bundle identifier even in a command-line test.
MYPAD_BUNDLE="$MYPAD_TEST_DIR/MyPadNativeTests.app"
mkdir -p "$MYPAD_BUNDLE/Contents/MacOS"
cat > "$MYPAD_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>in.texoport.mypad.native-tests</string>
<key>CFBundleExecutable</key><string>MyPadNativeTests</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
MYPAD_SDK="$(xcrun --sdk macosx --show-sdk-path)"
MYPAD_ARCH="$(uname -m)"
xcrun swiftc -target "$MYPAD_ARCH-apple-ios17.0-macabi" -sdk "$MYPAD_SDK" \
  -F "$MYPAD_SDK/System/iOSSupport/System/Library/Frameworks" \
  MyPad/DrawingStore.swift MyPad/AgentBridge.swift tests/native/main.swift \
  -o "$MYPAD_BUNDLE/Contents/MacOS/MyPadNativeTests"
"$MYPAD_BUNDLE/Contents/MacOS/MyPadNativeTests" "$@"
