#!/usr/bin/env bash
# Headless light/dark appearance matrix renders for visual QA.
#
# Renders the demo dashboard and account fly-out under forced light AND dark
# appearance via "--demo --render-snapshot" (window rasterization — no Screen
# Recording permission, no on-screen capture) and writes PNGs under docs/qa/.
#
# Reduce Transparency cannot be forced per-process: it is a system-wide
# accessibility setting (System Settings > Accessibility > Display). To capture
# that half of the matrix, toggle the setting manually and re-run with:
#   PLAIDBAR_QA_MATRIX_SUFFIX="-reduce-transparency" ./Scripts/qa-appearance-matrix.sh
# Results and open human-eyes checks are tracked in docs/qa-matrix.md.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_ROOT="${1:-$PROJECT_DIR/docs/qa}"
SUFFIX="${PLAIDBAR_QA_MATRIX_SUFFIX:-}"

cd "$PROJECT_DIR"
echo "Building PlaidBar in release mode..."
swift build -c release --disable-keychain

BINARY=".build/release/PlaidBar"

for appearance in light dark; do
    out="$OUTPUT_ROOT/appearance-${appearance}${SUFFIX}"
    echo "Rendering ${appearance} appearance to ${out}..."
    # --show-popover is required alongside --render-snapshot: its delayed
    # presentation path reliably opens the popover even when the status item
    # starts in menu bar overflow.
    "$BINARY" --demo --show-popover --render-snapshot "$out" --appearance "$appearance"
done

echo "Done. Review PNGs under $OUTPUT_ROOT (demo data only) before committing."
