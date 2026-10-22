#!/bin/bash
# build.sh - compile LinkBlend and package it as LinkBlend.app.
#
# Set STAGE_ONLY=1 to build into ./build/LinkBlend.app without installing,
# which is what update.sh uses to stage a build before swapping it in.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME=LinkBlend
BUNDLE_ID=local.linkblend
VERSION=2.11
BUILD_NUMBER=22
STAGE=${STAGE_ONLY:+build}
OUT="${STAGE:+$STAGE/}$APP_NAME.app"
BINARY="${STAGE:+$STAGE/}$APP_NAME"

# Keep the target in one place: the UI uses Liquid Glass (glassEffect) and the
# Window scene, both of which need the macOS 26 SDK.
TARGET=arm64-apple-macos26.0

SOURCES=$(find Sources -name '*.swift' | sort)
if [ -z "$SOURCES" ]; then
  echo "no Swift sources found under Sources/" >&2
  exit 1
fi

echo "== Compiling $(echo "$SOURCES" | wc -l | tr -d ' ') Swift files"
mkdir -p "$(dirname "$BINARY")"
# shellcheck disable=SC2086
xcrun swiftc -O -parse-as-library -target "$TARGET" $SOURCES -o "$BINARY"

echo "== Packaging $OUT"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp "$BINARY" "$OUT/Contents/MacOS/$APP_NAME"
cp Resources/AppIcon.icns "$OUT/Contents/Resources/AppIcon.icns"

cat > "$OUT/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
EOF

codesign -f -s - "$OUT" >/dev/null

if [ "${STAGE_ONLY:-0}" = "1" ]; then
  echo "Staged $(pwd)/$OUT"
  exit 0
fi

rm -rf /Applications/$APP_NAME.app
cp -R "$OUT" /Applications/$APP_NAME.app
echo "Installed /Applications/$APP_NAME.app"
