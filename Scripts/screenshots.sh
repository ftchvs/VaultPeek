#!/usr/bin/env bash
# PlaidBar screenshot pipeline
# Captures onboarding, dashboard, and settings states for README.md.
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

capture_sandbox_preflight() {
    local output="$1"
    local window_rect=""

    APP_LOG="$(mktemp -t plaidbar-screenshots.XXXXXX.log)"
    APP_PID=""

    echo "Opening sandbox preflight popover..."
    PLAIDBAR_SERVER_PORT="${PLAIDBAR_SCREENSHOT_PREFLIGHT_PORT:-18999}" "$BINARY" --show-popover >"$APP_LOG" 2>&1 &
    APP_PID=$!

    for _ in {1..20}; do
        window_rect=$(osascript -e '
            tell application "System Events"
                if exists process "PlaidBar" then
                    tell process "PlaidBar"
                        set frontmost to true
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
        echo "Error: Could not find the PlaidBar setup window."
        echo "App log:"
        cat "$APP_LOG" 2>/dev/null || true
        exit 1
    fi

    osascript -e '
        tell application "System Events"
            tell process "PlaidBar"
                set frontmost to true
                click button 5 of group 1 of window 1
            end tell
        end tell
    ' 2>/dev/null || true
    sleep 1

    window_rect=$(osascript -e '
        tell application "System Events"
            tell process "PlaidBar"
                set windowPosition to position of window 1
                set windowSize to size of window 1
                return (item 1 of windowPosition as text) & "," & (item 2 of windowPosition as text) & "," & (item 1 of windowSize as text) & "," & (item 2 of windowSize as text)
            end tell
        end tell
    ' 2>/dev/null || true)

    echo "Capturing ${output}..."
    screencapture -R"$window_rect" "$ASSETS_DIR/$output"
    chmod 644 "$ASSETS_DIR/$output"

    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
    APP_PID=""
    rm -f "$APP_LOG"
    APP_LOG=""
}

capture_settings() {
    local tab="$1"
    local output="$2"
    local window_rect=""

    APP_LOG="$(mktemp -t plaidbar-screenshots.XXXXXX.log)"
    APP_PID=""

    echo "Opening settings (${tab})..."
    "$BINARY" --demo --show-popover --settings-tab "$tab" >"$APP_LOG" 2>&1 &
    APP_PID=$!

    sleep 1
    for _ in {1..40}; do
        window_rect=$(osascript -e '
            tell application "System Events"
                if exists process "PlaidBar" then
                    tell process "PlaidBar"
                        set frontmost to true
                        if (count of windows) > 0 then return "ready"
                    end tell
                end if
            end tell
        ' 2>/dev/null || true)

        if [ "$window_rect" = "ready" ]; then
            break
        fi
        sleep 0.5
    done

    if [ "$window_rect" != "ready" ]; then
        echo "Error: Could not find the PlaidBar popover before opening settings."
        echo "App log:"
        cat "$APP_LOG" 2>/dev/null || true
        exit 1
    fi

    osascript -e '
        tell application "System Events"
            tell process "PlaidBar"
                set frontmost to true
                click button 3 of group 1 of window 1
            end tell
        end tell
    ' 2>/dev/null || true

    for _ in {1..24}; do
        window_rect=$(osascript -e '
            tell application "System Events"
                if exists process "PlaidBar" then
                    tell process "PlaidBar"
                        set frontmost to true
                        repeat with candidateWindow in windows
                            if name of candidateWindow contains "Settings" or name of candidateWindow contains "General" or name of candidateWindow contains "Accounts" or name of candidateWindow contains "Notifications" or name of candidateWindow contains "About" then
                                set windowPosition to position of candidateWindow
                                set windowSize to size of candidateWindow
                                return (item 1 of windowPosition as text) & "," & (item 2 of windowPosition as text) & "," & (item 1 of windowSize as text) & "," & (item 2 of windowSize as text)
                            end if
                        end repeat
                    end tell
                end if
            end tell
        ' 2>/dev/null || true)

        if [ -n "$window_rect" ] && [ "$window_rect" != "missing value" ] && [ "$window_rect" != "ready" ]; then
            break
        fi
        sleep 0.5
    done

    if [ -z "$window_rect" ] || [ "$window_rect" = "missing value" ] || [ "$window_rect" = "ready" ]; then
        echo "Error: Could not find the PlaidBar settings window."
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

capture_sandbox_preflight "setup-sandbox-preflight.png"
capture_dashboard "All" "dashboard.png"
capture_dashboard "Cash" "dashboard-cash.png" "demo_checking"
capture_dashboard "Credit" "dashboard-credit.png" "demo_visa"
capture_dashboard "Savings" "dashboard-savings.png" "demo_savings"
capture_dashboard "Debt" "dashboard-debt.png" "demo_visa"
capture_dashboard "Status" "dashboard-status.png"
capture_settings "general" "settings-local-data.png"
capture_settings "accounts" "settings-accounts.png"
capture_settings "notifications" "settings-notifications.png"

echo "Done! Screenshots saved to $ASSETS_DIR"
