#!/usr/bin/env bash
# Build script: compile universal binary, assemble .app, sign, notarize, staple, DMG.
#
# Usage:
#   ./build.sh             # build + sign + notarize + DMG
#   ./build.sh --no-notarize   # skip notarization (faster local iteration)
#   ./build.sh --dev       # unsigned dev build for local testing only

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PKG_DIR="$SCRIPT_DIR"

if [[ -f "$APP_ROOT/.env" ]]; then
  set -a; source "$APP_ROOT/.env"; set +a
fi

VERSION="${VERSION:-1.0.0}"
APP_NAME="Digital Pat"
EXECUTABLE="DigitalPat"
BUNDLE_ID="ai.bulia.tinytools.digitalpat"
IDENTITY="${APPLE_IDENTITY:-Developer ID Application: Mili Software Inc. (PGZ497J325)}"

MODE="release"
DO_NOTARIZE=1
DEV_BUILD=0
for arg in "$@"; do
  case "$arg" in
    --no-notarize) DO_NOTARIZE=0 ;;
    --dev) DEV_BUILD=1; DO_NOTARIZE=0 ;;
  esac
done

BUILD_DIR="$APP_ROOT/build-swift"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "==> Cleaning build dir"
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES"

echo "==> Compiling universal binary (arm64 + x86_64)"
cd "$PKG_DIR"
ARM_BIN="$PKG_DIR/.build/arm64-apple-macosx/release/$EXECUTABLE"
X64_BIN="$PKG_DIR/.build/x86_64-apple-macosx/release/$EXECUTABLE"

swift build -c release --arch arm64
swift build -c release --arch x86_64

if [[ -f "$ARM_BIN" && -f "$X64_BIN" ]]; then
  echo "==> Creating universal binary with lipo"
  lipo -create -output "$MACOS_DIR/$EXECUTABLE" "$ARM_BIN" "$X64_BIN"
else
  echo "==> Universal slices not both present; copying available arch"
  cp "$ARM_BIN" "$MACOS_DIR/$EXECUTABLE" 2>/dev/null || cp "$X64_BIN" "$MACOS_DIR/$EXECUTABLE"
fi
chmod +x "$MACOS_DIR/$EXECUTABLE"

echo "==> Generating Info.plist (version $VERSION)"
sed "s/__VERSION__/$VERSION/g" "$PKG_DIR/Info.plist.template" > "$CONTENTS/Info.plist"

echo "==> Copying icon"
cp "$APP_ROOT/build/icon.icns" "$RESOURCES/icon.icns"

echo "==> Copying characters"
mkdir -p "$RESOURCES/Characters"
cp -R "$APP_ROOT"/characters/* "$RESOURCES/Characters/"
find "$RESOURCES/Characters" -name '.DS_Store' -delete   # keep junk out of the signed bundle

echo "==> Embedding Sparkle.framework (auto-updater)"
FRAMEWORKS="$CONTENTS/Frameworks"
mkdir -p "$FRAMEWORKS"
SPARKLE_FW="$PKG_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
ditto "$SPARKLE_FW" "$FRAMEWORKS/Sparkle.framework"
# make the executable find the framework on any machine
install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/$EXECUTABLE" 2>/dev/null || true

ENTITLEMENTS="$BUILD_DIR/entitlements.plist"
cat > "$ENTITLEMENTS" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.allow-jit</key>
    <true/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
    <key>com.apple.security.automation.apple-events</key>
    <true/>
</dict>
</plist>
EOF

if [[ "$DEV_BUILD" -eq 1 ]]; then
  echo "==> Dev build: skipping signing/notarization"
  echo "==> App: $APP_BUNDLE"
  exit 0
fi

echo "==> Signing Sparkle components (inner-out, Developer ID + hardened runtime)"
SPV="$FRAMEWORKS/Sparkle.framework/Versions/Current"
for xpc in "$SPV"/XPCServices/*.xpc; do
  [ -e "$xpc" ] && codesign -f -o runtime --timestamp --preserve-metadata=entitlements --sign "$IDENTITY" "$xpc"
done
[ -e "$SPV/Autoupdate" ] && codesign -f -o runtime --timestamp --sign "$IDENTITY" "$SPV/Autoupdate"
[ -e "$SPV/Updater.app" ] && codesign -f -o runtime --timestamp --preserve-metadata=entitlements --sign "$IDENTITY" "$SPV/Updater.app"
codesign -f -o runtime --timestamp --sign "$IDENTITY" "$FRAMEWORKS/Sparkle.framework"

echo "==> Codesigning with hardened runtime"
codesign --force --options runtime --timestamp \
  --entitlements "$ENTITLEMENTS" \
  --sign "$IDENTITY" \
  "$APP_BUNDLE"

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

if [[ "$DO_NOTARIZE" -eq 1 ]]; then
  if [[ -z "${APPLE_ID:-}" || -z "${APPLE_PASSWORD:-}" || -z "${APPLE_TEAM_ID:-}" ]]; then
    echo "WARNING: APPLE_ID / APPLE_PASSWORD / APPLE_TEAM_ID not in env — skipping notarization."
  else
    echo "==> Zipping for notarization"
    ZIP_PATH="$BUILD_DIR/$EXECUTABLE-notarize.zip"
    ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

    echo "==> Submitting to Apple notary service…"
    xcrun notarytool submit "$ZIP_PATH" \
      --apple-id "$APPLE_ID" \
      --password "$APPLE_PASSWORD" \
      --team-id "$APPLE_TEAM_ID" \
      --wait

    echo "==> Stapling notarization ticket"
    xcrun stapler staple "$APP_BUNDLE"
    rm -f "$ZIP_PATH"
  fi
fi

echo "==> Building DMG"
DMG_STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

DMG_PATH="$BUILD_DIR/$EXECUTABLE-$VERSION.dmg"
rm -f "$DMG_PATH"

hdiutil create -volname "$APP_NAME $VERSION" \
  -srcfolder "$DMG_STAGING" \
  -ov -format UDZO \
  "$DMG_PATH"

echo "==> Signing DMG"
codesign --force --sign "$IDENTITY" "$DMG_PATH"

if [[ "$DO_NOTARIZE" -eq 1 && -n "${APPLE_ID:-}" ]]; then
  echo "==> Notarizing DMG"
  xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_PASSWORD" \
    --team-id "$APPLE_TEAM_ID" \
    --wait
  xcrun stapler staple "$DMG_PATH"
fi

echo ""
echo "==================================================="
echo "Build complete:"
echo "  App:  $APP_BUNDLE"
echo "  DMG:  $DMG_PATH"
ls -lh "$DMG_PATH" | awk '{print "  Size:", $5}'
echo "==================================================="
