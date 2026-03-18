#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

# Parse args
SANDBOX_FLAG=""
for arg in "$@"; do
    case $arg in
        --sandbox)
            SANDBOX_FLAG="--sandbox"
            ;;
    esac
done

echo "Building PlaidBar..."
swift build 2>&1

echo ""
echo "Starting PlaidBar server..."
swift run PlaidBarServer $SANDBOX_FLAG &
SERVER_PID=$!

# Wait for server to start
sleep 2

echo "Starting PlaidBar app..."
swift run PlaidBar &
APP_PID=$!

echo ""
echo "PlaidBar is running!"
echo "  Server PID: $SERVER_PID"
echo "  App PID: $APP_PID"
echo ""
echo "Press Ctrl+C to stop"

cleanup() {
    echo ""
    echo "Stopping PlaidBar..."
    kill $APP_PID 2>/dev/null || true
    kill $SERVER_PID 2>/dev/null || true
    exit 0
}

trap cleanup INT TERM
wait
