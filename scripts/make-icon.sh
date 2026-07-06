#!/bin/bash
# Regenerates Resources/AppIcon.icns from Resources/logo.png.
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="${1:-Resources/logo.png}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

swift scripts/MakeIcon.swift "$SRC" "$TMP/master.png"

ICONSET="$TMP/AppIcon.iconset"
mkdir "$ICONSET"
for s in 16 32 128 256 512; do
    sips -z "$s" "$s" "$TMP/master.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    sips -z "$d" "$d" "$TMP/master.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
echo "Built Resources/AppIcon.icns"
