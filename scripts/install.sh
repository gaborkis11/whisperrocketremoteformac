#!/bin/bash
# WhisperRocket Remote telepítése az /Applications mappába.
# A stabil útvonal kell a TCC-engedélyeknek és az SMAppService login itemnek.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="WhisperRocket Remote.app"
SOURCE="$PROJECT_ROOT/dist/$APP_NAME"
TARGET="/Applications/$APP_NAME"

[ -d "$SOURCE" ] || { echo "Nincs build: $SOURCE — futtasd előbb a scripts/build-app.sh-t" >&2; exit 1; }

# Futó példány leállítása, hogy a csere ne futó binárist írjon felül
pkill -x WhisperRocketRemote 2>/dev/null && sleep 1 || true

# ditto őrzi a metaadatokat és az aláírást; a cél előbb törlődik, hogy ne
# maradjon árva fájl egy régebbi bundle-ből
rm -rf "$TARGET"
ditto "$SOURCE" "$TARGET"

codesign --verify --strict "$TARGET"
echo "==> telepítve: $TARGET"
