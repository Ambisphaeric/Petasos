#!/usr/bin/env bash
# Pack build/Petasos.app into a distributable DMG with an Applications symlink.
# Run after scripts/build-app.sh.
#
# Configuration via env:
#   VERSION   Version string baked into the DMG filename. Defaults to the
#             CFBundleShortVersionString read from Petasos.app/Contents/Info.plist.

set -euo pipefail

APP_NAME="Petasos"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"

if [[ ! -d "$APP_DIR" ]]; then
  echo "Error: $APP_DIR not found. Run scripts/build-app.sh first." >&2
  exit 1
fi

# Derive version from the built Info.plist unless explicitly overridden.
if [[ -z "${VERSION:-}" ]]; then
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")"
fi

DMG="$BUILD_DIR/$APP_NAME-$VERSION.dmg"
STAGING="$BUILD_DIR/dmg-staging"

echo "==> Staging $STAGING..."
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP_DIR" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo "==> Creating $DMG..."
hdiutil create \
  -volname "$APP_NAME $VERSION" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$DMG"

rm -rf "$STAGING"

echo ""
echo "Built: $DMG"
