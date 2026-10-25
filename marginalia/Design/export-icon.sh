#!/bin/sh
# Renders AppIcon.svg into every size of the macOS app icon set.
# Requires Inkscape (brew install --cask inkscape).
set -e
cd "$(dirname "$0")"
out=../marginalia/Assets.xcassets/AppIcon.appiconset
for px in 16 32 64 128 256 512 1024; do
    inkscape AppIcon.svg --export-type=png --export-width=$px --export-filename="$out/icon_$px.png" >/dev/null 2>&1
done
