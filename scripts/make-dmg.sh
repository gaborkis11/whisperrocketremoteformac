#!/bin/bash
# Packages the built app into a distributable DMG: the app plus an /Applications
# symlink, compressed. Expects a fresh dist/ from build-app.sh (runs it if missing).
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="WhisperRocket Remote.app"
APP="$PROJECT_ROOT/dist/$APP_NAME"

[ -d "$APP" ] || "$PROJECT_ROOT/scripts/build-app.sh"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
# The release tag is date-shaped (2026-09-05); the plist stores it dot-separated.
TAG="${VERSION//./-}"
DMG="$PROJECT_ROOT/dist/WhisperRocket-Remote-$TAG.dmg"

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/$APP_NAME"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
hdiutil create -volname "WhisperRocket Remote" -srcfolder "$STAGING" -ov -format UDZO -quiet "$DMG"
hdiutil verify -quiet "$DMG"
echo "==> kész: $DMG"
