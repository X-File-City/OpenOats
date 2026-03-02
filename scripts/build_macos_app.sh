#!/usr/bin/env bash
set -euo pipefail

# Build signed macOS .app for On The Spot
# Usage:
#   ./scripts/build_macos_app.sh
#
# For local builds (auto-detects your signing identity):
#   ./scripts/build_macos_app.sh
#
# For CI / explicit identity:
#   CODESIGN_IDENTITY="Developer ID Application: ..." ./scripts/build_macos_app.sh
#
# For notarization (requires Developer ID cert):
#   APPLE_ID="name@example.com"
#   APPLE_TEAM_ID="TEAMID123"
#   APPLE_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"

cd "$(dirname "$0")/.."
SCRIPT_DIR="$(pwd)"

python3 -m pip install --break-system-packages -q pyinstaller

rm -rf build dist

pyinstaller \
  --noconfirm \
  --windowed \
  --name "On The Spot" \
  --collect-all faster_whisper \
  --collect-all sklearn \
  --hidden-import sounddevice \
  --hidden-import soundfile \
  desktop_app.py

APP_PATH="dist/On The Spot.app"
ENTITLEMENTS="$SCRIPT_DIR/entitlements.plist"

# Auto-detect signing identity if not explicitly set
if [[ -z "${CODESIGN_IDENTITY:-}" ]]; then
  # Prefer Developer ID Application, fall back to Apple Development
  CODESIGN_IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)"/\1/' || true)
  if [[ -z "$CODESIGN_IDENTITY" ]]; then
    CODESIGN_IDENTITY=$(security find-identity -v -p codesigning | grep "Apple Development" | head -1 | sed 's/.*"\(.*\)"/\1/' || true)
  fi
fi

if [[ -n "$CODESIGN_IDENTITY" ]]; then
  echo "Signing with: $CODESIGN_IDENTITY"

  # Sign all nested binaries and dylibs first (inside-out signing)
  find "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Frameworks" "$APP_PATH/Contents/Resources" \
    \( -name "*.dylib" -o -name "*.so" -o -perm +111 -type f \) 2>/dev/null | while read -r binary; do
    codesign --force --verify --verbose \
      --options runtime \
      --entitlements "$ENTITLEMENTS" \
      --sign "$CODESIGN_IDENTITY" \
      "$binary" 2>/dev/null || true
  done

  # Sign any embedded .app bundles
  find "$APP_PATH" -name "*.app" -depth -mindepth 1 2>/dev/null | while read -r nested; do
    codesign --force --verify --verbose \
      --options runtime \
      --entitlements "$ENTITLEMENTS" \
      --sign "$CODESIGN_IDENTITY" \
      "$nested" 2>/dev/null || true
  done

  # Sign any frameworks
  find "$APP_PATH/Contents/Frameworks" -name "*.framework" -depth 2>/dev/null | while read -r fw; do
    codesign --force --verify --verbose \
      --options runtime \
      --entitlements "$ENTITLEMENTS" \
      --sign "$CODESIGN_IDENTITY" \
      "$fw" 2>/dev/null || true
  done

  # Sign the main app bundle last
  codesign --force --verify --verbose \
    --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign "$CODESIGN_IDENTITY" \
    "$APP_PATH"

  echo "Verifying signature..."
  codesign --verify --deep --strict --verbose=2 "$APP_PATH"
  echo "Signature verified OK"
else
  echo "WARNING: No signing identity found. App will be unsigned."
  echo "Install a Developer ID Application certificate for distribution signing."
fi

# Notarize if credentials are available (requires Developer ID cert)
if [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
  echo "Submitting for notarization..."
  ZIP_PATH="dist/OnTheSpot-mac.zip"
  ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
  xcrun notarytool submit "$ZIP_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --wait
  xcrun stapler staple "$APP_PATH"
  rm -f "$ZIP_PATH"
  echo "Notarization complete and stapled"
fi

echo "Build complete: $APP_PATH"
