#!/usr/bin/env bash
# Build a signed Petasos.app from the SwiftPM package via xcodebuild.
#
# Why xcodebuild and not `swift build`: SwiftPM cannot compile Metal shaders,
# so mlx-swift's default.metallib is never produced and the app crashes at
# first MLX call ("Failed to load the default metallib"). xcodebuild runs the
# Metal compiler and emits mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib
# which we copy into Petasos.app/Contents/Resources/.
#
# Configuration via env:
#   PETASOS_SIGN_IDENTITY  Codesign identity. Default "-" (ad-hoc) — works
#                          locally but keychain ACLs won't persist across
#                          rebuilds. Set to the CN of a self-signed code
#                          signing cert (see docs/SIGNING.md) to make
#                          "Always Allow" stick.
#   CONFIG                 Release | Debug. Default Release.

set -euo pipefail

CONFIG="${CONFIG:-Release}"
SIGN_IDENTITY="${PETASOS_SIGN_IDENTITY:--}"
APP_NAME="Petasos"
BUNDLE_ID="com.petasos"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build"
DERIVED="$BUILD_DIR/derived"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
INFO_PLIST="$ROOT/Sources/PetasosApp/Info.plist"
ENTITLEMENTS="$ROOT/Sources/PetasosApp/Petasos.entitlements"

cd "$ROOT"

echo "==> xcodebuild $CONFIG (this compiles the Metal shaders)..."
xcodebuild \
  -scheme "$APP_NAME" \
  -configuration "$CONFIG" \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" \
  build

PRODUCTS="$DERIVED/Build/Products/$CONFIG"
EXEC="$PRODUCTS/$APP_NAME"

if [[ ! -f "$EXEC" ]]; then
  echo "Error: executable not found at $EXEC" >&2
  exit 1
fi
if [[ ! -d "$PRODUCTS/mlx-swift_Cmlx.bundle" ]]; then
  echo "Error: mlx-swift_Cmlx.bundle not found — MLX would fail at runtime." >&2
  exit 1
fi

echo "==> Assembling $APP_DIR..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$EXEC" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$INFO_PLIST" "$APP_DIR/Contents/Info.plist"

# Copy every SwiftPM resource bundle next to the binary. mlx-swift's loader
# searches Bundle.allBundles for mlx-swift_Cmlx.bundle so location inside
# Contents/Resources/ is correct.
for bundle in "$PRODUCTS"/*.bundle; do
  [[ -d "$bundle" ]] && cp -R "$bundle" "$APP_DIR/Contents/Resources/"
done

# Strip Apple's quarantine xattr that xcodebuild sometimes leaves on outputs;
# it causes Gatekeeper to refuse to launch even a properly signed app on the
# same machine.
xattr -cr "$APP_DIR" || true

echo "==> Codesigning ($SIGN_IDENTITY)..."
# --options runtime: enable hardened runtime (required for notarization later).
# --entitlements: declare TCC resource keys (mic, network). Without these,
# under hardened runtime macOS silently denies the corresponding requests
# and the app never appears in Privacy & Security.
codesign --force --deep \
  --options runtime \
  --entitlements "$ENTITLEMENTS" \
  --sign "$SIGN_IDENTITY" \
  --identifier "$BUNDLE_ID" \
  "$APP_DIR"

echo "==> Verifying..."
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

echo ""
echo "Built: $APP_DIR"
