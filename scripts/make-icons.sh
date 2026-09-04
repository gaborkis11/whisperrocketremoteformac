#!/bin/bash
# Builds AssetsSource/AppIcon.icns from the 1024×1024 WhisperRocket artwork.
#
# No asset catalog anywhere in this project (the CLT-only build path has no
# actool), so the app icon is made the old way: sips down to the ten sizes an
# .iconset needs, then iconutil. Committing the .icns rather than generating it
# at build time keeps build-app.sh free of image tooling — run this only when
# the artwork changes.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="${1:-$ROOT/AssetsSource/whisperrocket_ico.png}"
ICONSET="$(mktemp -d)/AppIcon.iconset"
OUTPUT="$ROOT/AssetsSource/AppIcon.icns"

if [ ! -f "$SOURCE" ]; then
	echo "!! no source artwork at $SOURCE" >&2
	exit 1
fi

# macOS wants each size at 1× and 2×; the 2× of one size is the 1× pixel count
# of the next, but both names have to exist or iconutil rejects the set.
SIZES=(16 32 128 256 512)

echo "==> source: $SOURCE"
sips -g pixelWidth -g pixelHeight "$SOURCE" | tail -n 2

mkdir -p "$ICONSET"
for size in "${SIZES[@]}"; do
	retina=$((size * 2))
	sips -z "$size" "$size" "$SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
	sips -z "$retina" "$retina" "$SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

echo "==> $(ls "$ICONSET" | wc -l | tr -d ' ') images in the iconset"
iconutil --convert icns --output "$OUTPUT" "$ICONSET"
rm -rf "$(dirname "$ICONSET")"

echo "==> wrote $OUTPUT ($(stat -f%z "$OUTPUT") bytes)"
# Proof it is a real icns and not just a renamed PNG.
sips -g format -g pixelWidth -g pixelHeight "$OUTPUT" | tail -n 3
