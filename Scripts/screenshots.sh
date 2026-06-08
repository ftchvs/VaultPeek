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

run_osascript() {
    local script="$1"
    local timeout_seconds="${PLAIDBAR_SCREENSHOT_OSASCRIPT_TIMEOUT:-5}"
    local output_file=""
    local pid=""
    local elapsed=0
    local status=0

    output_file="$(mktemp -t plaidbar-osascript.XXXXXX.out)"
    osascript -e "$script" >"$output_file" 2>&1 &
    pid=$!

    while kill -0 "$pid" 2>/dev/null; do
        if [ "$elapsed" -ge "$timeout_seconds" ]; then
            kill "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
            rm -f "$output_file"
            return 124
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    wait "$pid" || status=$?
    cat "$output_file"
    rm -f "$output_file"
    return "$status"
}


require_screen_capture() {
    local probe_file=""

    probe_file="$(mktemp -t plaidbar-screencapture.XXXXXX.png)"
    if ! screencapture -x -R0,0,1,1 "$probe_file" >/dev/null 2>&1; then
        rm -f "$probe_file"
        echo "Error: Screen Recording permission is required for screenshot capture."
        echo "Grant it to the terminal app running this script in System Settings > Privacy & Security > Screen Recording."
        exit 1
    fi
    rm -f "$probe_file"
}

plaidbar_window_id() {
    local name_hint="${1:-}"
    local swift_file=""
    local status=0

    swift_file="$(mktemp -t plaidbar-window-id.XXXXXX.swift)"
    cat >"$swift_file" <<'SWIFT'
import CoreGraphics
import Foundation

let hint = ProcessInfo.processInfo.environment["PLAIDBAR_WINDOW_NAME_HINT", default: ""]
    .trimmingCharacters(in: .whitespacesAndNewlines)
    .lowercased()

guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
    exit(1)
}

struct Candidate {
    let id: Int
    let name: String
    let area: Double
    let hinted: Bool
}

let candidates: [Candidate] = windows.compactMap { window in
    guard (window[kCGWindowOwnerName as String] as? String) == "PlaidBar",
          let id = window[kCGWindowNumber as String] as? Int,
          let bounds = window[kCGWindowBounds as String] as? [String: Any],
          let width = bounds["Width"] as? Double,
          let height = bounds["Height"] as? Double,
          width > 0,
          height > 0
    else { return nil }

    let name = window[kCGWindowName as String] as? String ?? ""
    let hinted = hint.isEmpty ? true : name.lowercased().contains(hint)
    return Candidate(id: id, name: name, area: width * height, hinted: hinted)
}

let sorted = candidates.sorted { lhs, rhs in
    if lhs.hinted != rhs.hinted { return lhs.hinted && !rhs.hinted }
    return lhs.area > rhs.area
}

guard let match = sorted.first else { exit(1) }
print(match.id)
SWIFT

    PLAIDBAR_WINDOW_NAME_HINT="$name_hint" swift "$swift_file" || status=$?
    rm -f "$swift_file"
    return "$status"
}

wait_for_plaidbar_window_id() {
    local name_hint="${1:-}"
    local window_id=""

    for _ in {1..40}; do
        window_id=$(plaidbar_window_id "$name_hint" 2>/dev/null || true)
        if [ -n "$window_id" ]; then
            echo "$window_id"
            return 0
        fi
        sleep 0.5
    done

    return 1
}

capture_plaidbar_window() {
    local output="$1"
    local name_hint="${2:-}"
    local window_id=""

    window_id=$(wait_for_plaidbar_window_id "$name_hint") || {
        echo "Error: Could not find a PlaidBar window to capture."
        echo "App log:"
        cat "$APP_LOG" 2>/dev/null || true
        exit 1
    }

    echo "Capturing ${output}..."
    screencapture -x -o -l"$window_id" "$ASSETS_DIR/$output"
    chmod 644 "$ASSETS_DIR/$output"
}

capture_dashboard() {
    local filter="$1"
    local output="$2"
    local account="${3:-}"
    local extra_args="${4:-}"
    local window_rect=""

    APP_LOG="$(mktemp -t plaidbar-screenshots.XXXXXX.log)"
    APP_PID=""

    echo "Opening dashboard popover (${filter})..."
    if [ -n "$account" ]; then
        "$BINARY" --demo --show-popover --screenshot-filter "$filter" --screenshot-account "$account" $extra_args >"$APP_LOG" 2>&1 &
    else
        "$BINARY" --demo --show-popover --screenshot-filter "$filter" $extra_args >"$APP_LOG" 2>&1 &
    fi
    APP_PID=$!

    for _ in {1..20}; do
        window_rect=$(run_osascript '
            tell application "System Events"
                if exists process "PlaidBar" then
                    tell process "PlaidBar"
                        if (count of windows) > 0 then
                            set position of window 1 to {40, 80}
                            set windowPosition to position of window 1
                            set windowSize to size of window 1
                            return (item 1 of windowPosition as text) & "," & (item 2 of windowPosition as text) & "," & (item 1 of windowSize as text) & "," & (item 2 of windowSize as text)
                        end if
                    end tell
                end if
            end tell
        ' || true)

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

    capture_plaidbar_window "$output"

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
        window_rect=$(run_osascript '
            tell application "System Events"
                if exists process "PlaidBar" then
                    tell process "PlaidBar"
                        set frontmost to true
                        if (count of windows) > 0 then
                            set position of window 1 to {40, 80}
                            set windowPosition to position of window 1
                            set windowSize to size of window 1
                            return (item 1 of windowPosition as text) & "," & (item 2 of windowPosition as text) & "," & (item 1 of windowSize as text) & "," & (item 2 of windowSize as text)
                        end if
                    end tell
                end if
            end tell
        ' || true)

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

    run_osascript '
        tell application "System Events"
            tell process "PlaidBar"
                set frontmost to true
                click button 5 of group 1 of window 1
            end tell
        end tell
    ' >/dev/null || true
    sleep 1

    window_rect=$(run_osascript '
        tell application "System Events"
            tell process "PlaidBar"
                set position of window 1 to {40, 80}
                set windowPosition to position of window 1
                set windowSize to size of window 1
                return (item 1 of windowPosition as text) & "," & (item 2 of windowPosition as text) & "," & (item 1 of windowSize as text) & "," & (item 2 of windowSize as text)
            end tell
        end tell
    ' || true)

    capture_plaidbar_window "$output"

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
        window_rect=$(run_osascript '
            tell application "System Events"
                if exists process "PlaidBar" then
                    tell process "PlaidBar"
                        set frontmost to true
                        if (count of windows) > 0 then return "ready"
                    end tell
                end if
            end tell
        ' || true)

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

    run_osascript '
        tell application "System Events"
            tell process "PlaidBar"
                set frontmost to true
                click button 3 of group 1 of window 1
            end tell
        end tell
    ' >/dev/null || true

    for _ in {1..24}; do
        window_rect=$(run_osascript '
            tell application "System Events"
                if exists process "PlaidBar" then
                    tell process "PlaidBar"
                        set frontmost to true
                        repeat with candidateWindow in windows
                            if name of candidateWindow contains "Settings" or name of candidateWindow contains "General" or name of candidateWindow contains "Accounts" or name of candidateWindow contains "Notifications" or name of candidateWindow contains "About" then
                                set position of candidateWindow to {40, 80}
                                set windowPosition to position of candidateWindow
                                set windowSize to size of candidateWindow
                                return (item 1 of windowPosition as text) & "," & (item 2 of windowPosition as text) & "," & (item 1 of windowSize as text) & "," & (item 2 of windowSize as text)
                            end if
                        end repeat
                    end tell
                end if
            end tell
        ' || true)

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

    capture_plaidbar_window "$output" "$tab"

    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
    APP_PID=""
    rm -f "$APP_LOG"
    APP_LOG=""
}

require_screen_capture

capture_sandbox_preflight "setup-sandbox-preflight.png"
capture_dashboard "All" "dashboard.png"
capture_dashboard "Cash" "dashboard-cash.png" "demo_checking"
capture_dashboard "Credit" "dashboard-credit.png" "demo_visa"
capture_dashboard "Savings" "dashboard-savings.png" "demo_savings"
capture_dashboard "Debt" "dashboard-debt.png" "demo_visa"
capture_dashboard "Status" "dashboard-status.png" "" "--screenshot-status-recovery"
capture_settings "general" "settings-local-data.png"
capture_settings "accounts" "settings-accounts.png"
capture_settings "notifications" "settings-notifications.png"
capture_settings "about" "settings-about.png"

echo "Done! Screenshots saved to $ASSETS_DIR"
