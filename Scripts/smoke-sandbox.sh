#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PORT="${PLAIDBAR_SMOKE_PORT:-18484}"
SERVER_LOG="$(mktemp -t plaidbar-smoke-server.XXXXXX.log)"
SERVER_PID=""

cd "$PROJECT_DIR"

cleanup() {
    if [[ -n "$SERVER_PID" ]]; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

if [[ -z "${PLAID_CLIENT_ID:-}" || -z "${PLAID_SECRET:-}" ]]; then
    echo "Missing Plaid sandbox credentials."
    echo ""
    echo "Set sandbox credentials first:"
    echo "  export PLAID_CLIENT_ID=your_sandbox_client_id"
    echo "  export PLAID_SECRET=your_sandbox_secret"
    echo ""
    echo "Then run:"
    echo "  ./Scripts/smoke-sandbox.sh"
    exit 1
fi

echo "Building PlaidBarServer..."
swift build --target PlaidBarServer --skip-update --disable-keychain

echo "Starting sandbox server on http://127.0.0.1:$PORT..."
swift run PlaidBarServer --sandbox --port "$PORT" >"$SERVER_LOG" 2>&1 &
SERVER_PID=$!

for _ in {1..30}; do
    if curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
        break
    fi
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        echo "Server exited before health check passed."
        echo "Server log: $SERVER_LOG"
        cat "$SERVER_LOG"
        exit 1
    fi
    sleep 1
done

curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null
STATUS_JSON="$(curl -fsS "http://127.0.0.1:$PORT/api/status")"

python3 - "$STATUS_JSON" <<'PY'
import json
import sys

status = json.loads(sys.argv[1])
errors = []

if status.get("environment") != "sandbox":
    errors.append(f"expected sandbox environment, got {status.get('environment')!r}")
if status.get("credentialsConfigured") is not True:
    errors.append("expected credentialsConfigured=true")
if "itemCount" not in status:
    errors.append("status response missing itemCount")
if not status.get("storagePath"):
    errors.append("status response missing storagePath")

if errors:
    for error in errors:
        print(f"Smoke check failed: {error}", file=sys.stderr)
    sys.exit(1)

print("Sandbox smoke check passed.")
print(f"  Environment: {status['environment']}")
print(f"  Items: {status['itemCount']}")
print(f"  Storage: {status['storagePath']}")
PY

echo "Server log: $SERVER_LOG"
