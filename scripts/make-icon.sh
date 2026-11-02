#!/bin/bash
# Regenerate Resources/AppIcon.icns and docs/icon.png from Resources/AppIcon.svg.
# Maintainers only (needs `brew install librsvg`); the generated files are committed.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v rsvg-convert >/dev/null || { echo "brew install librsvg" >&2; exit 1; }
tmp="$(mktemp -d)"; set="$tmp/AppIcon.iconset"; mkdir -p "$set"
for base in 16 32 128 256 512; do
  rsvg-convert -w $base -h $base Resources/AppIcon.svg -o "$set/icon_${base}x${base}.png"
  rsvg-convert -w $((base*2)) -h $((base*2)) Resources/AppIcon.svg -o "$set/icon_${base}x${base}@2x.png"
done
iconutil -c icns "$set" -o Resources/AppIcon.icns
rsvg-convert -w 256 -h 256 Resources/AppIcon.svg -o docs/icon.png
rm -rf "$tmp"
echo "✅ Resources/AppIcon.icns, docs/icon.png"
