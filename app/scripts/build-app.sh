#!/bin/bash
# Build Anti-slop.app for local use (no distribution signing or notarization).
#   ./scripts/build-app.sh                 # release build, ad-hoc signature
#   SIGN_IDENTITY="Apple Development: …" ./scripts/build-app.sh
# Accessibility permission is tied to the code signature: with the default
# ad-hoc signature, macOS may ask again after each rebuild.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
swift build -c "$CONFIG" --product AntiSlop
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
APP="build/Anti-slop.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/AntiSlop" "$APP/Contents/MacOS/AntiSlop"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>AntiSlop</string>
    <key>CFBundleIdentifier</key><string>local.antislop.app</string>
    <key>CFBundleName</key><string>Anti-slop</string>
    <key>CFBundleDisplayName</key><string>Anti-slop</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>Local development build. Writing styles adapted from MIT-licensed sources; see Acknowledgements.</string>
</dict>
</plist>
PLIST

codesign --force --sign "${SIGN_IDENTITY:--}" --timestamp=none "$APP"
echo "Built $APP"
echo "Run:  open $APP        (developer fixture mode: open $APP --args --fixture-provider)"
