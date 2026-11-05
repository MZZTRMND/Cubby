#!/bin/bash
# Builds Cubby.app from the SwiftPM executable.
#
#   make-app.sh            → build.noindex/Cubby.app       (com.cubby.app)
#   make-app.sh --test     → build.noindex/Cubby-Test.app  (com.cubby.app.test, "Cubby Test")
#   make-app.sh --install  → builds Cubby.app, quits the running copy, replaces
#                            /Applications/Cubby.app with it and opens it
#
# Builds go in build.noindex, a folder Spotlight skips, so searching for Cubby only
# finds the installed app.
#
# Each bundle id gets its own store and files under
# ~/Library/Application Support/<bundle id>, so the test build never touches real data.
set -euo pipefail

cd "$(dirname "$0")/.."

OUT="build.noindex"
APP="$OUT/Cubby.app"
BUNDLE_ID="com.cubby.app"
NAME="Cubby"
VERSION="0.4"
INSTALL=false
if [[ "${1:-}" == "--install" ]]; then
    INSTALL=true
elif [[ "${1:-}" == "--test" ]]; then
    APP="$OUT/Cubby-Test.app"
    BUNDLE_ID="com.cubby.app.test"
    NAME="Cubby Test"
fi

echo "==> Building release binary"
swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)"

echo "==> Assembling $APP"
mkdir -p "$OUT"
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

if $INSTALL; then
    INSTALLED="/Applications/Cubby.app"
    echo "==> Installing to $INSTALLED"
    # Quit only the installed copy, by its own executable, never anything else.
    osascript -e 'tell application id "com.cubby.app" to quit' >/dev/null 2>&1 || true
    for _ in {1..10}; do
        pgrep -f "^$INSTALLED/Contents/MacOS/Cubby" >/dev/null || break
        sleep 0.5
    done
    if pgrep -f "^$INSTALLED/Contents/MacOS/Cubby" >/dev/null; then
        echo "Cubby is still running; quit it and run this again." >&2
        exit 1
    fi
    ditto "$APP" "$INSTALLED"
    open "$INSTALLED"
    echo
    echo "Installed $INSTALLED (version $VERSION) and opened it."
    exit 0
fi

echo
echo "Built $APP — launch with: open $APP"
