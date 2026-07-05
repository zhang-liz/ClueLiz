#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
swift build -c "$CONFIG"
APP=dist/Clueless.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/Clueless" "$APP/Contents/MacOS/Clueless"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --deep -s "${SIGN_ID:--}" "$APP"
echo "Built $APP"
