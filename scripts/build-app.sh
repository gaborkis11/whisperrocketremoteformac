#!/bin/bash
# Builds dist/WhisperRocket Remote.app without Xcode: SPM build + hand-assembled
# bundle + codesign. No actool, so no asset catalogs anywhere in this project.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="release"
BUILD_DIR="$ROOT/.build/$CONFIG"
APP="$ROOT/dist/WhisperRocket Remote.app"
CONTENTS="$APP/Contents"
BUNDLE_ID="com.gaborkis.WhisperRocketRemote"

# The TCC database keys permissions to (signing identity, bundle id). Signing with
# the real Apple Development cert keeps the designated requirement stable across
# rebuilds; ad-hoc (SIGN_IDENTITY=-) makes macOS re-prompt after every build.
SIGN_IDENTITY="${SIGN_IDENTITY:-Apple Development: developer@example.com (TEAMID0000)}"

# The CommandLineTools toolchain ships no libPreviewsMacros.dylib, so every
# dependency that uses #Preview (KeyboardShortcuts does) fails to compile.
# DEVELOPER_DIR redirects to the full Xcode toolchain without needing sudo.
if [ -z "${DEVELOPER_DIR:-}" ] \
	&& [ "$(xcode-select -p)" = "/Library/Developer/CommandLineTools" ] \
	&& [ -d /Applications/Xcode.app ]; then
	export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi
echo "==> developer dir: ${DEVELOPER_DIR:-$(xcode-select -p)}"

cd "$ROOT"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BUILD_DIR/WhisperRocketRemote" "$CONTENTS/MacOS/WhisperRocketRemote"
cp "$ROOT/Support/Info.plist" "$CONTENTS/Info.plist"
printf 'APPL????' > "$CONTENTS/PkgInfo"

# The app icon, named by CFBundleIconFile in Info.plist. Regenerate it with
# scripts/make-icons.sh when the artwork changes; a missing icns is not fatal
# (the app runs with the generic one), so this only warns.
if [ -f "$ROOT/AssetsSource/AppIcon.icns" ]; then
	cp "$ROOT/AssetsSource/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
	echo "    app icon: AppIcon.icns"
else
	echo "!! no AssetsSource/AppIcon.icns — run scripts/make-icons.sh" >&2
fi

shopt -s nullglob
bundles=("$BUILD_DIR"/*.bundle)
shopt -u nullglob
if [ ${#bundles[@]} -eq 0 ]; then
	echo "!! no SPM resource bundle found in $BUILD_DIR" >&2
	exit 1
fi
for bundle in "${bundles[@]}"; do
	echo "    resource bundle: $(basename "$bundle")"
	cp -R "$bundle" "$CONTENTS/Resources/"
done

if [ "$SIGN_IDENTITY" != "-" ]; then
	if ! security find-identity -v -p codesigning | grep -qF "$SIGN_IDENTITY"; then
		echo "!! codesigning identity not in keychain: $SIGN_IDENTITY" >&2
		exit 1
	fi
fi

echo "==> codesign ($SIGN_IDENTITY)"
# No hardened runtime, no entitlements: local-only build, never notarized.
codesign --force --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_ID" "$APP"
codesign --verify --verbose=2 "$APP"

echo "==> done: $APP"
