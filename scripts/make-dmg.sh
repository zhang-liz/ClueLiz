#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/bundle.sh release
STAGE=$(mktemp -d)
cp -R dist/Clueless.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f dist/Clueless.dmg
hdiutil create -volname "Clueless" -srcfolder "$STAGE" -ov -format UDZO dist/Clueless.dmg
rm -rf "$STAGE"
echo "Built dist/Clueless.dmg"
