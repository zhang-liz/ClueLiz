#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/bundle.sh release
STAGE=$(mktemp -d)
cp -R dist/ClueLiz.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f dist/ClueLiz.dmg
hdiutil create -volname "ClueLiz" -srcfolder "$STAGE" -ov -format UDZO dist/ClueLiz.dmg
rm -rf "$STAGE"
echo "Built dist/ClueLiz.dmg"
