#!/usr/bin/env bash
# PlaidBar screenshot pipeline
# Captures the dashboard-first MenuBarExtra popover in demo mode for README.md.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ASSETS_DIR="$PROJECT_DIR/Assets"
APP_LOG="$(mktemp -t plaidbar-screenshots.XXXXXX.log)"

mkdir -p "$ASSETS_DIR"

echo "Building PlaidBar in release mode..."
cd "$PROJECT_DIR"
swift build -c release --disable-keychain

BINARY=".build/release/PlaidBar"
APP_PID=""

cleanup() {
    if [ -n "${APP_PID:-}" ]; then
        kill "$APP_PID" 2>/dev/null || true
        wait "$APP_PID" 2>/dev/null || true
    fi
    rm -f "$APP_LOG"
}
trap cleanup EXIT

echo "Opening dashboard popover..."
"$BINARY" --demo --show-popover >"$APP_LOG" 2>&1 &
APP_PID=$!

WINDOW_RECT=""
for _ in {1..20}; do
    WINDOW_RECT=$(osascript -e '
        tell application "System Events"
            if exists process "PlaidBar" then
                tell process "PlaidBar"
                    if (count of windows) > 0 then
                        set windowPosition to position of window 1
                        set windowSize to size of window 1
                        return (item 1 of windowPosition as text) & "," & (item 2 of windowPosition as text) & "," & (item 1 of windowSize as text) & "," & (item 2 of windowSize as text)
                    end if
                end tell
            end if
        end tell
    ' 2>/dev/null || true)

    if [ -n "$WINDOW_RECT" ] && [ "$WINDOW_RECT" != "missing value" ]; then
        break
    fi
    sleep 0.5
done

if [ -z "$WINDOW_RECT" ] || [ "$WINDOW_RECT" = "missing value" ]; then
    echo "Error: Could not find the PlaidBar popover window."
    echo "App log:"
    cat "$APP_LOG" 2>/dev/null || true
    exit 1
fi

echo "Capturing dashboard popover..."
screencapture -R"$WINDOW_RECT" "$ASSETS_DIR/dashboard.png"
chmod 644 "$ASSETS_DIR/dashboard.png"

echo "Done! Screenshot saved to $ASSETS_DIR/dashboard.png"
