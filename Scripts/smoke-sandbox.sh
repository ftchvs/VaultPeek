#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PORT="${PLAIDBAR_SMOKE_PORT:-18484}"
SERVER_LOG="$(mktemp -t plaidbar-smoke-server.XXXXXX.log)"
CREATED_DATA_DIR=""
SERVER_PID=""

cd "$PROJECT_DIR"

cleanup() {
    if [[ -n "$SERVER_PID" ]]; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    if [[ -n "$CREATED_DATA_DIR" ]]; then
        rm -rf "$CREATED_DATA_DIR"
    fi
    rm -f "$SERVER_LOG"
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
swift build --target PlaidBarServer --disable-keychain

if [[ -z "${PLAIDBAR_DATA_DIR:-}" ]]; then
    CREATED_DATA_DIR="$(mktemp -d -t plaidbar-smoke-data.XXXXXX)"
    export PLAIDBAR_DATA_DIR="$CREATED_DATA_DIR"
fi

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

if ! curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null; then
    echo "Server did not become healthy before timeout."
    echo "Server log: $SERVER_LOG"
    cat "$SERVER_LOG"
    exit 1
fi
AUTH_TOKEN_PATH="$PLAIDBAR_DATA_DIR/auth-token"
if [[ ! -r "$AUTH_TOKEN_PATH" ]]; then
    echo "Smoke check failed: auth token is not readable at $AUTH_TOKEN_PATH" >&2
    echo "Server log: $SERVER_LOG" >&2
    cat "$SERVER_LOG" >&2
    exit 1
fi

AUTH_TOKEN="$(tr -d '\r\n' < "$AUTH_TOKEN_PATH")"

if curl -fsS "http://127.0.0.1:$PORT/api/status" >/dev/null 2>&1; then
    echo "Smoke check failed: unauthenticated API status request succeeded" >&2
    exit 1
fi

STATUS_JSON="$(curl -fsS -H "Authorization: Bearer $AUTH_TOKEN" "http://127.0.0.1:$PORT/api/status")"
ITEMS_JSON="$(curl -fsS -H "Authorization: Bearer $AUTH_TOKEN" "http://127.0.0.1:$PORT/api/items")"

python3 - "$STATUS_JSON" "$ITEMS_JSON" "$PLAIDBAR_DATA_DIR" <<'PY'
import json
import os
import sys

status = json.loads(sys.argv[1])
items = json.loads(sys.argv[2])
data_dir = os.path.realpath(sys.argv[3])
errors = []

if status.get("environment") != "sandbox":
    errors.append(f"expected sandbox environment, got {status.get('environment')!r}")
if status.get("credentialsConfigured") is not True:
    errors.append("expected credentialsConfigured=true")
if "itemCount" not in status:
    errors.append("status response missing itemCount")
if "syncedItemCount" not in status:
    errors.append("status response missing syncedItemCount")
elif not isinstance(status["syncedItemCount"], int):
    errors.append("status response syncedItemCount is not an integer")
storage_path = None
if not status.get("storagePath"):
    errors.append("status response missing storagePath")
else:
    storage_path = os.path.realpath(status["storagePath"])
    if not storage_path.startswith(data_dir + os.sep):
        errors.append(f"expected storage path under {data_dir}, got {storage_path}")
if not isinstance(items, list):
    errors.append("items response is not a JSON array")

auth_token_path = os.path.join(data_dir, "auth-token")
if not os.path.exists(auth_token_path):
    errors.append(f"auth token was not created at {auth_token_path}")
elif os.path.getsize(auth_token_path) == 0:
    errors.append(f"auth token is empty at {auth_token_path}")
else:
    token_mode = os.stat(auth_token_path).st_mode & 0o777
    if token_mode != 0o600:
        errors.append(f"expected auth token permissions 0600, got {token_mode:04o}")

data_dir_mode = os.stat(data_dir).st_mode & 0o777
if data_dir_mode != 0o700:
    errors.append(f"expected data directory permissions 0700, got {data_dir_mode:04o}")

if storage_path:
    if not os.path.exists(storage_path):
        errors.append(f"SQLite store was not created at {storage_path}")
    else:
        for path in [storage_path, f"{storage_path}-wal", f"{storage_path}-shm"]:
            if os.path.exists(path):
                store_mode = os.stat(path).st_mode & 0o777
                if store_mode != 0o600:
                    errors.append(f"expected SQLite store permissions 0600 for {path}, got {store_mode:04o}")

if errors:
    for error in errors:
        print(f"Smoke check failed: {error}", file=sys.stderr)
    sys.exit(1)

print("Sandbox smoke check passed.")
print(f"  Environment: {status['environment']}")
print(f"  Items: {status['itemCount']}")
print(f"  Storage: {status['storagePath']}")
print(f"  Isolated data dir: {data_dir}")
PY

echo "Server log: $SERVER_LOG"
