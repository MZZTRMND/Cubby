#!/bin/bash
# Records the scripted demo of the test build for the promo video.
#
#   Scripts/record-demo.sh            → promo/footage/demo.mov and demo-markers.json
#   Scripts/record-demo.sh --dark     → promo/footage/demo-dark.mov, in dark mode on a night stage
#   Scripts/record-demo.sh --no-build → reuses build.noindex/Cubby-Test.app (combines with --dark)
#
# The demo runs in Cubby Test only, on its own wiped store, and only Cubby Test's windows
# are recorded. Leave the mouse alone while it plays (about a minute). Needs Screen
# Recording permission for the app running this script.
set -euo pipefail

cd "$(dirname "$0")/.."

APP="build.noindex/Cubby-Test.app"
BUNDLE_ID="com.cubby.app.test"
OUT="promo/footage"
mkdir -p "$OUT"

BUILD=true
NAME="demo"
THEME="light"
DARK="NO"
for arg in "$@"; do
    case "$arg" in
        --no-build) BUILD=false ;;
        --dark) NAME="demo-dark"; THEME="dark"; DARK="YES" ;;
    esac
done

if $BUILD; then
    Scripts/make-app.sh --test
fi

quit_test_app() {
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
    for _ in {1..10}; do
        pgrep -f "Cubby-Test.app/Contents/MacOS/Cubby" >/dev/null || return 0
        sleep 0.5
    done
}

quit_test_app

echo "==> Starting the recorder"
swift Scripts/record-demo.swift "$OUT/$NAME.mov" &
RECORDER=$!
sleep 4

echo "==> Launching the demo"
# Settings for the demo only: launch arguments, which are never saved.
open -n "$APP" --args --demo \
    -folderScale 1.5 -itemScale 1 -theme $THEME -demoDark $DARK -panelShown YES -pinnedOnTop NO \
    -catchScreenshots NO -showInDock NO -sortOrder dateAdded

STATUS=0
wait $RECORDER || STATUS=$?
if [[ $STATUS -ne 0 ]]; then
    quit_test_app
    echo "Recording failed (status $STATUS)." >&2
    exit $STATUS
fi
cp "$HOME/Library/Application Support/$BUNDLE_ID/Demo/markers.json" "$OUT/$NAME-markers.json" 2>/dev/null || true
quit_test_app
# Remotion only serves what's really in public/, not links to it.
cp "$OUT/$NAME.mov" "promo/public/$NAME.mov"
echo "Recorded $OUT/$NAME.mov"
