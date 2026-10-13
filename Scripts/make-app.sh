#!/bin/bash
# Builds Cubby.app from the SwiftPM executable.
#
#   make-app.sh          → Cubby.app       (com.cubby.app)
#   make-app.sh --test   → Cubby-Test.app  (com.cubby.app.test, "Cubby Test")
#
# Each bundle id gets its own store and files under
# ~/Library/Application Support/<bundle id>, so the test build never touches real data.
set -euo pipefail

cd "$(dirname "$0")/.."

APP="Cubby.app"
BUNDLE_ID="com.cubby.app"
NAME="Cubby"
VERSION="0.2"
if [[ "${1:-}" == "--test" ]]; then
    APP="Cubby-Test.app"
    BUNDLE_ID="com.cubby.app.test"
    NAME="Cubby Test"
fi

echo "==> Building release binary"
swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH/Cubby" "$APP/Contents/MacOS/Cubby"
# The icon is an Icon Composer file; actool turns it into Assets.car (which macOS uses)
# plus a fallback AppIcon.icns.
xcrun actool Resources/AppIcon.icon --compile "$APP/Contents/Resources" \
    --platform macosx --minimum-deployment-target 26.0 --app-icon AppIcon \
    --output-partial-info-plist /dev/null >/dev/null

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Cubby</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>$NAME</string>
    <key>CFBundleDisplayName</key><string>$NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAppleEventsUsageDescription</key><string>Cubby asks Finder to show Get Info for files on your cubby.</string>
</dict>
</plist>
PLIST

echo "==> Signing"
codesign --force --deep -s - "$APP" 2>/dev/null
codesign --verify --strict "$APP"

echo
echo "Built $APP — launch with: open $APP"
