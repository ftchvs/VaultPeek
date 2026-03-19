#!/usr/bin/env bash
# PlaidBar screenshot pipeline
# Captures each tab in demo mode for README.md
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ASSETS_DIR="$PROJECT_DIR/Assets"

mkdir -p "$ASSETS_DIR"

echo "Building PlaidBar in release mode..."
cd "$PROJECT_DIR"
swift build -c release 2>/dev/null

BINARY=".build/release/PlaidBar"

for tab in accounts transactions spending credit; do
    echo "Capturing $tab tab..."
    $BINARY --demo --tab "$tab" &
    APP_PID=$!
    sleep 3

    # Find the PlaidBar window and capture it
    WINDOW_ID=$(osascript -e '
        tell application "System Events"
            set plaidWindows to every window of every process whose name contains "PlaidBar"
            if (count of plaidWindows) > 0 then
                return id of item 1 of item 1 of plaidWindows
            end if
        end tell
    ' 2>/dev/null || echo "")

    if [ -n "$WINDOW_ID" ]; then
        screencapture -l"$WINDOW_ID" "$ASSETS_DIR/$tab.png"
        echo "  Saved $ASSETS_DIR/$tab.png"
    else
        echo "  Warning: Could not find PlaidBar window for $tab"
    fi

    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
    sleep 1
done

echo "Done! Screenshots saved to $ASSETS_DIR/"
