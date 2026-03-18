#!/bin/bash
set -euo pipefail

echo "PlaidBar Setup"
echo "=============="
echo ""

DATA_DIR="$HOME/.plaidbar"

# Create data directory
mkdir -p "$DATA_DIR"
echo "Created data directory: $DATA_DIR"

# Check for Plaid credentials
if [ -z "${PLAID_CLIENT_ID:-}" ] || [ -z "${PLAID_SECRET:-}" ]; then
    echo ""
    echo "No Plaid credentials found in environment."
    echo ""
    echo "To use sandbox mode (demo data):"
    echo "  ./Scripts/run.sh --sandbox"
    echo ""
    echo "To use production mode, set these environment variables:"
    echo "  export PLAID_CLIENT_ID=your_client_id"
    echo "  export PLAID_SECRET=your_secret"
    echo ""
    echo "Get credentials at: https://dashboard.plaid.com"
else
    echo "Plaid credentials found in environment."
fi

# Build
echo ""
echo "Building PlaidBar..."
swift build 2>&1

echo ""
echo "Setup complete! Run PlaidBar with:"
echo "  ./Scripts/run.sh --sandbox   # Demo mode"
echo "  ./Scripts/run.sh             # Production mode"
