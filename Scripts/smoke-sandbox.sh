#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PORT="${PLAIDBAR_SMOKE_PORT:-18484}"
SETUP_PORT="${PLAIDBAR_SMOKE_SETUP_PORT:-$((PORT + 1))}"
SERVER_LOG="$(mktemp -t plaidbar-smoke-server.XXXXXX.log)"
CREATED_DATA_DIR=""
SETUP_DATA_DIR=""
SERVER_PID=""
SETUP_SERVER_PID=""

cd "$PROJECT_DIR"

cleanup() {
    for pid in "$SERVER_PID" "$SETUP_SERVER_PID"; do
        if [[ -n "$pid" ]]; then
            kill "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
        fi
    done
    if [[ -n "$CREATED_DATA_DIR" ]]; then
        rm -rf "$CREATED_DATA_DIR"
    fi
    if [[ -n "$SETUP_DATA_DIR" ]]; then
        rm -rf "$SETUP_DATA_DIR"
    fi
    rm -f "$SERVER_LOG"
}
trap cleanup EXIT INT TERM

fail_with_log() {
    echo "$1" >&2
    echo "Server log: $SERVER_LOG" >&2
    cat "$SERVER_LOG" >&2
    exit 1
}

# Waits until /health answers on the given port, or fails if the given
# server process exits first.
wait_for_health() {
    local port="$1"
    local pid="$2"
    for _ in {1..30}; do
        if curl -fsS "http://127.0.0.1:$port/health" >/dev/null 2>&1; then
            return 0
        fi
        if ! kill -0 "$pid" 2>/dev/null; then
            fail_with_log "Server exited before health check passed."
        fi
        sleep 1
    done
    if ! curl -fsS "http://127.0.0.1:$port/health" >/dev/null; then
        fail_with_log "Server did not become healthy before timeout."
    fi
}

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

wait_for_health "$PORT" "$SERVER_PID"
AUTH_TOKEN_PATH="$PLAIDBAR_DATA_DIR/auth-token"
if [[ ! -r "$AUTH_TOKEN_PATH" ]]; then
    fail_with_log "Smoke check failed: auth token is not readable at $AUTH_TOKEN_PATH"
fi

AUTH_TOKEN="$(tr -d '\r\n' < "$AUTH_TOKEN_PATH")"

if curl -fsS "http://127.0.0.1:$PORT/api/status" >/dev/null 2>&1; then
    echo "Smoke check failed: unauthenticated API status request succeeded" >&2
    exit 1
fi

if curl -fsS "http://127.0.0.1:$PORT/api/items" >/dev/null 2>&1; then
    echo "Smoke check failed: unauthenticated API items request succeeded" >&2
    exit 1
fi

if curl -fsS -H "Authorization: Bearer definitely-wrong-token" "http://127.0.0.1:$PORT/api/status" >/dev/null 2>&1; then
    echo "Smoke check failed: bad bearer token API status request succeeded" >&2
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
required_status_keys = {
    "version",
    "environment",
    "itemCount",
    "credentialsConfigured",
    "storagePath",
    "syncReady",
    "syncedItemCount",
}
optional_status_keys = {"lastSync"}
allowed_status_keys = required_status_keys | optional_status_keys
forbidden_status_fragments = [
    "account",
    "access",
    "balance",
    "client",
    "institution",
    "itemId",
    "public",
    "secret",
    "token",
    "transaction",
]

status_keys = set(status)
missing_status_keys = required_status_keys - status_keys
unexpected_status_keys = status_keys - allowed_status_keys
if missing_status_keys or unexpected_status_keys:
    errors.append(
        "status response keys changed: "
        f"missing {sorted(missing_status_keys)}, unexpected {sorted(unexpected_status_keys)}"
    )
for key in status_keys:
    lowered = key.lower()
    if any(fragment.lower() in lowered for fragment in forbidden_status_fragments):
        errors.append(f"status response exposes forbidden key-shaped field: {key}")

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
    if storage_path != data_dir:
        errors.append(f"expected storage path to be {data_dir}, got {storage_path}")
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

sqlite_path = os.path.join(data_dir, "plaidbar-sandbox.sqlite")
if not os.path.exists(sqlite_path):
    errors.append(f"SQLite store was not created at {sqlite_path}")
else:
    for path in [sqlite_path, f"{sqlite_path}-wal", f"{sqlite_path}-shm"]:
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

# Restart recovery: a second server boot against the same data directory must
# reuse the same auth token (the app holds it across server restarts) and
# report the same sandbox readiness state.
echo "Restarting server to verify restart recovery..."
kill "$SERVER_PID" 2>/dev/null || true
wait "$SERVER_PID" 2>/dev/null || true
SERVER_PID=""

swift run PlaidBarServer --sandbox --port "$PORT" >>"$SERVER_LOG" 2>&1 &
SERVER_PID=$!
wait_for_health "$PORT" "$SERVER_PID"

RESTART_AUTH_TOKEN="$(tr -d '\r\n' < "$AUTH_TOKEN_PATH")"
if [[ "$RESTART_AUTH_TOKEN" != "$AUTH_TOKEN" ]]; then
    fail_with_log "Smoke check failed: auth token changed across a server restart"
fi

RESTART_STATUS_JSON="$(curl -fsS -H "Authorization: Bearer $AUTH_TOKEN" "http://127.0.0.1:$PORT/api/status")"

python3 - "$STATUS_JSON" "$RESTART_STATUS_JSON" <<'PY'
import json
import sys

first = json.loads(sys.argv[1])
restarted = json.loads(sys.argv[2])
errors = []

if restarted.get("environment") != "sandbox":
    errors.append(f"expected sandbox environment after restart, got {restarted.get('environment')!r}")
if restarted.get("credentialsConfigured") is not True:
    errors.append("expected credentialsConfigured=true after restart")
for key in ["storagePath", "itemCount", "syncedItemCount"]:
    if restarted.get(key) != first.get(key):
        errors.append(
            f"expected {key} to be preserved across restart: "
            f"{first.get(key)!r} became {restarted.get(key)!r}"
        )

if errors:
    for error in errors:
        print(f"Smoke check failed: {error}", file=sys.stderr)
    sys.exit(1)

print("Restart recovery check passed.")
PY

# Setup-state readiness: a credential-less boot in a clean data directory
# must stay reachable (/health, /api/status), report
# credentialsConfigured=false, and answer Plaid-backed routes with a 503
# whose body names the missing credential variables.
echo "Verifying credential-less boot reports setup state on http://127.0.0.1:$SETUP_PORT..."
SETUP_DATA_DIR="$(mktemp -d -t plaidbar-smoke-setup.XXXXXX)"
PLAID_CLIENT_ID="" PLAID_SECRET="" PLAIDBAR_DATA_DIR="$SETUP_DATA_DIR" \
    swift run PlaidBarServer --sandbox --port "$SETUP_PORT" >>"$SERVER_LOG" 2>&1 &
SETUP_SERVER_PID=$!
wait_for_health "$SETUP_PORT" "$SETUP_SERVER_PID"

SETUP_AUTH_TOKEN_PATH="$SETUP_DATA_DIR/auth-token"
if [[ ! -r "$SETUP_AUTH_TOKEN_PATH" ]]; then
    fail_with_log "Smoke check failed: setup-state auth token is not readable at $SETUP_AUTH_TOKEN_PATH"
fi
SETUP_AUTH_TOKEN="$(tr -d '\r\n' < "$SETUP_AUTH_TOKEN_PATH")"

SETUP_STATUS_JSON="$(curl -fsS -H "Authorization: Bearer $SETUP_AUTH_TOKEN" "http://127.0.0.1:$SETUP_PORT/api/status")"
ACCOUNTS_HTTP_CODE="$(curl -sS -o /tmp/plaidbar-smoke-setup-body.$$ -w '%{http_code}' \
    -H "Authorization: Bearer $SETUP_AUTH_TOKEN" "http://127.0.0.1:$SETUP_PORT/api/accounts")"
ACCOUNTS_BODY="$(cat /tmp/plaidbar-smoke-setup-body.$$)"
rm -f /tmp/plaidbar-smoke-setup-body.$$

python3 - "$SETUP_STATUS_JSON" "$ACCOUNTS_HTTP_CODE" "$ACCOUNTS_BODY" <<'PY'
import json
import sys

status = json.loads(sys.argv[1])
accounts_http_code = sys.argv[2]
accounts_body = sys.argv[3]
errors = []

if status.get("environment") != "sandbox":
    errors.append(f"expected sandbox environment in setup state, got {status.get('environment')!r}")
if status.get("credentialsConfigured") is not False:
    errors.append("expected credentialsConfigured=false in setup state")
if accounts_http_code != "503":
    errors.append(f"expected Plaid-backed route to return 503 in setup state, got {accounts_http_code}")
for variable in ["PLAID_CLIENT_ID", "PLAID_SECRET"]:
    if variable not in accounts_body:
        errors.append(f"expected setup-state 503 body to name {variable}")

if errors:
    for error in errors:
        print(f"Smoke check failed: {error}", file=sys.stderr)
    sys.exit(1)

print("Setup-state readiness check passed.")
PY

kill "$SETUP_SERVER_PID" 2>/dev/null || true
wait "$SETUP_SERVER_PID" 2>/dev/null || true
SETUP_SERVER_PID=""

echo "Server log: $SERVER_LOG"
