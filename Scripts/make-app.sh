#!/bin/bash
# Builds Shelf.app from the SwiftPM executable.
#
#   make-app.sh          → Shelf.app       (com.shelf.app)
#   make-app.sh --test   → Shelf-Test.app  (com.shelf.app.test, "Shelf Test")
#
# Each bundle id gets its own store and files under
# ~/Library/Application Support/<bundle id>, so the test build never touches real data.
set -euo pipefail

cd "$(dirname "$0")/.."

APP="Shelf.app"
BUNDLE_ID="com.shelf.app"
NAME="Shelf"
if [[ "${1:-}" == "--test" ]]; then
    APP="Shelf-Test.app"
    BUNDLE_ID="com.shelf.app.test"
    NAME="Shelf Test"
fi

echo "==> Building release binary"
swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH/Shelf" "$APP/Contents/MacOS/Shelf"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Shelf</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>$NAME</string>
    <key>CFBundleDisplayName</key><string>$NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSUIElement</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "==> Signing"
codesign --force --deep -s - "$APP" 2>/dev/null
codesign --verify --strict "$APP"

echo
echo "Built $APP — launch with: open $APP"
