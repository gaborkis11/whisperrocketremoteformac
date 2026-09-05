#!/bin/bash
# Builds AssetsSource/AppIcon.icns from scripts/make-appicon.swift.
#
# The icon is drawn, not photographed: make-appicon.swift renders each size from
# the same vector description, so the 16-pixel icon is composed for 16 pixels
# instead of being a 1024 master crushed by sips. That is also why the old
# whisperrocket_ico.png path is gone — there is no master bitmap any more.
#
# No asset catalog anywhere in this project (the CLT-only build path has no
# actool), so the result is an .icns, made with iconutil and committed.
# build-app.sh only copies it — run this when the artwork changes.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRAWING="$ROOT/scripts/make-appicon.swift"
WORK="$(mktemp -d)"
ICONSET="$WORK/AppIcon.iconset"
OUTPUT="$ROOT/AssetsSource/AppIcon.icns"
# Optional: keep the rendered PNGs somewhere for a look (make-icons.sh <dir>).
KEEP="${1:-}"

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

if [ ! -f "$DRAWING" ]; then
	echo "!! no drawing at $DRAWING" >&2
	exit 1
fi

echo "==> rendering $DRAWING"
swift "$DRAWING" "$ICONSET"

echo "==> $(ls "$ICONSET" | wc -l | tr -d ' ') images in the iconset"
mkdir -p "$(dirname "$OUTPUT")"
iconutil --convert icns --output "$OUTPUT" "$ICONSET"

if [ -n "$KEEP" ]; then
	mkdir -p "$KEEP"
	cp "$ICONSET"/*.png "$KEEP/"
	echo "==> kept the rendered PNGs in $KEEP"
fi

echo "==> wrote $OUTPUT ($(stat -f%z "$OUTPUT") bytes)"
# Proof it is a real icns and not just a renamed PNG.
sips -g format -g pixelWidth -g pixelHeight "$OUTPUT" | tail -n 3
