#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

SERVER_PID=""
APP_PID=""

cleanup() {
    local exit_code=$?
    if [[ -n "$APP_PID" ]]; then
        kill "$APP_PID" 2>/dev/null || true
    fi
    if [[ -n "$SERVER_PID" ]]; then
        kill "$SERVER_PID" 2>/dev/null || true
    fi
    exit "$exit_code"
}

trap cleanup EXIT INT TERM

# Parse args
SANDBOX_FLAG=""
SERVER_PORT="${PLAIDBAR_SERVER_PORT:-8484}"
for arg in "$@"; do
    case $arg in
        --sandbox)
            SANDBOX_FLAG="--sandbox"
            ;;
    esac
done

if [[ -z "${PLAID_CLIENT_ID:-}" || -z "${PLAID_SECRET:-}" ]]; then
    echo "Missing Plaid credentials."
    echo ""
    if [[ "$SANDBOX_FLAG" == "--sandbox" ]]; then
        echo "Set sandbox credentials first:"
        echo "  export PLAID_CLIENT_ID=your_sandbox_client_id"
        echo "  export PLAID_SECRET=your_sandbox_secret"
    else
        echo "Set production credentials first:"
        echo "  export PLAID_CLIENT_ID=your_client_id"
        echo "  export PLAID_SECRET=your_secret"
    fi
    echo ""
    echo "For screenshot/demo data without Plaid, run: swift run PlaidBar --demo"
    exit 1
fi

echo "Building PlaidBar..."
swift build 2>&1

echo ""
echo "Starting PlaidBar server..."
swift run PlaidBarServer $SANDBOX_FLAG --port "$SERVER_PORT" &
SERVER_PID=$!

echo "Waiting for server health..."
for _ in {1..30}; do
    if curl -fsS "http://127.0.0.1:$SERVER_PORT/health" >/dev/null 2>&1; then
        break
    fi
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        echo "PlaidBar server exited before becoming healthy."
        exit 1
    fi
    sleep 1
done

curl -fsS "http://127.0.0.1:$SERVER_PORT/health" >/dev/null
DATA_DIR="${PLAIDBAR_DATA_DIR:-$HOME/.plaidbar}"
case "$DATA_DIR" in
    "~")
        DATA_DIR="$HOME"
        ;;
    "~/"*)
        DATA_DIR="$HOME/${DATA_DIR#"~/"}"
        ;;
esac
AUTH_TOKEN_PATH="$DATA_DIR/auth-token"
AUTH_TOKEN="$(tr -d '\r\n' < "$AUTH_TOKEN_PATH")"
STATUS_JSON="$(curl -fsS -H "Authorization: Bearer $AUTH_TOKEN" "http://127.0.0.1:$SERVER_PORT/api/status")"
python3 - "$STATUS_JSON" <<'PY'
import json
import sys

status = json.loads(sys.argv[1])
print(
    "Server ready: "
    f"{status.get('environment', 'unknown')} | "
    f"{status.get('itemCount', 0)} item(s) | "
    f"credentials {'ready' if status.get('credentialsConfigured') else 'missing'}"
)
PY

echo "Starting PlaidBar app..."
swift run PlaidBar &
APP_PID=$!

echo ""
echo "PlaidBar is running!"
echo "  Server PID: $SERVER_PID"
echo "  App PID: $APP_PID"
echo ""
echo "Press Ctrl+C to stop"
wait
