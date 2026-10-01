#!/bin/bash
# Build Anti-slop.app for local use with the LiTiL Labs certificate.
# No notarization, upload or distribution is performed.
#   ./scripts/build-app.sh                 # release build, LiTiL Labs signature
#   SIGN_IDENTITY="Apple Development: …" ./scripts/build-app.sh
#   SIGN_IDENTITY=- ./scripts/build-app.sh  # explicit ad-hoc fixture build
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: LiTiL Labs, Inc. (5N876P35QC)}"
swift build -c "$CONFIG" --product AntiSlop
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
APP="build/Anti-slop.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/AntiSlop" "$APP/Contents/MacOS/AntiSlop"
mkdir -p "$APP/Contents/Resources/Licenses"
cp ../third_party/no-ai-slop/LICENSE "$APP/Contents/Resources/Licenses/No-AI-Slop.txt"
cp ../third_party/humanizer/LICENSE "$APP/Contents/Resources/Licenses/Humanizer.txt"

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
    <key>NSHumanReadableCopyright</key><string>Local development build. Writing styles adapted from MIT-licensed sources; license notices bundled in Contents/Resources/Licenses.</string>
</dict>
</plist>
PLIST

codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP"
echo "Run:  open $APP        (developer fixture mode: open $APP --args --fixture-provider)"
