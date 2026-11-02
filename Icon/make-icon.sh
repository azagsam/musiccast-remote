#!/bin/sh
# Regenerates AppIcon.icns. Only needed when make-icon.swift changes.
set -e
cd "$(dirname "$0")"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
SET="$WORK/AppIcon.iconset"
mkdir "$SET"

swift make-icon.swift "$WORK/icon.png"

for SIZE in 16 32 128 256 512; do
    DOUBLE=$((SIZE * 2))
    sips -z "$SIZE" "$SIZE" "$WORK/icon.png" --out "$SET/icon_${SIZE}x${SIZE}.png" >/dev/null
    sips -z "$DOUBLE" "$DOUBLE" "$WORK/icon.png" --out "$SET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done

iconutil -c icns "$SET" -o AppIcon.icns
echo "Built AppIcon.icns"
