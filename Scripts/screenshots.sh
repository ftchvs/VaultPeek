#!/usr/bin/env bash
# VaultPeek screenshot pipeline
# Renders the window-first workspace surfaces used in README.md via the built-in
# headless render harness (`--demo --render-window-first`, AND-624). No UI
# automation, no Screen Recording permission, and no Plaid credentials needed —
# the harness rasterizes the routed content off-screen from demo fixtures.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ASSETS_DIR="$PROJECT_DIR/Assets"
RENDER_DIR="$(mktemp -d -t vaultpeek-shots.XXXXXX)"

cleanup() {
    rm -rf "$RENDER_DIR"
}
trap cleanup EXIT

mkdir -p "$ASSETS_DIR"
cd "$PROJECT_DIR"

echo "Rendering window-first surfaces to $RENDER_DIR ..."
swift run PlaidBar --demo --render-window-first "$RENDER_DIR"

# The window-first surfaces published in README.md. The harness writes one
# `window-<destination>.png` per in-shell destination (plus `window-shell.png`);
# we copy only the committed README set so Assets/ stays focused.
ASSETS=(
    window-dashboard.png
    window-transactions.png
    window-budgets.png
    window-insights.png
    window-accounts.png
)

for asset in "${ASSETS[@]}"; do
    if [ ! -f "$RENDER_DIR/$asset" ]; then
        echo "Error: expected render '$asset' not found in $RENDER_DIR" >&2
        echo "Renderer produced:" >&2
        ls -1 "$RENDER_DIR" >&2 || true
        exit 1
    fi
    cp "$RENDER_DIR/$asset" "$ASSETS_DIR/$asset"
    chmod 644 "$ASSETS_DIR/$asset"
    echo "Updated Assets/$asset"
done

echo "Done! Window-first screenshots saved to $ASSETS_DIR"
