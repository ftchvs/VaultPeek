#!/usr/bin/env bash
# PlaidBar screenshot pipeline
# Captures dashboard-first MenuBarExtra popover states in demo mode for README.md.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ASSETS_DIR="$PROJECT_DIR/Assets"

mkdir -p "$ASSETS_DIR"

echo "Building PlaidBar in release mode..."
cd "$PROJECT_DIR"
swift build -c release --disable-keychain

BINARY=".build/release/PlaidBar"

cleanup() {
    if [ -n "${APP_PID:-}" ]; then
        kill "$APP_PID" 2>/dev/null || true
        wait "$APP_PID" 2>/dev/null || true
    fi
    rm -f "${APP_LOG:-}"
}
trap cleanup EXIT

capture_dashboard() {
    local filter="$1"
    local output="$2"
    local account="${3:-}"
    local window_rect=""

    APP_LOG="$(mktemp -t plaidbar-screenshots.XXXXXX.log)"
    APP_PID=""

    echo "Opening dashboard popover (${filter})..."
    if [ -n "$account" ]; then
        "$BINARY" --demo --show-popover --screenshot-filter "$filter" --screenshot-account "$account" >"$APP_LOG" 2>&1 &
    else
        "$BINARY" --demo --show-popover --screenshot-filter "$filter" >"$APP_LOG" 2>&1 &
    fi
    APP_PID=$!

    for _ in {1..20}; do
        window_rect=$(osascript -e '
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

        if [ -n "$window_rect" ] && [ "$window_rect" != "missing value" ]; then
            break
        fi
        sleep 0.5
    done

    if [ -z "$window_rect" ] || [ "$window_rect" = "missing value" ]; then
        echo "Error: Could not find the PlaidBar popover window."
        echo "App log:"
        cat "$APP_LOG" 2>/dev/null || true
        exit 1
    fi

    echo "Capturing ${output}..."
    screencapture -R"$window_rect" "$ASSETS_DIR/$output"
    chmod 644 "$ASSETS_DIR/$output"

    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
    APP_PID=""
    rm -f "$APP_LOG"
    APP_LOG=""
}

capture_dashboard "All" "dashboard.png"
capture_dashboard "Cash" "dashboard-cash.png" "demo_checking"
capture_dashboard "Credit" "dashboard-credit.png" "demo_visa"
capture_dashboard "Savings" "dashboard-savings.png" "demo_savings"
capture_dashboard "Debt" "dashboard-debt.png" "demo_visa"
capture_dashboard "Status" "dashboard-status.png"

echo "Done! Screenshots saved to $ASSETS_DIR"
