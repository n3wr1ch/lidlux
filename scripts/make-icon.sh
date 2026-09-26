#!/bin/zsh
# Command Line Tools only; no Xcode project or asset catalog required.
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p Resources build
ICON_WORK=$(mktemp -d "$PWD/build/make-icon.XXXXXX")
trap 'rm -rf "$ICON_WORK"' EXIT
ICONSET="$ICON_WORK/AppIcon.iconset"
mkdir -p "$ICONSET"

swift scripts/make-icon.swift "$ICON_WORK/AppIcon.png"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ICON_WORK/AppIcon.png" \
        --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$ICON_WORK/AppIcon.png" \
        --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
echo "아이콘 생성 완료: Resources/AppIcon.icns"
