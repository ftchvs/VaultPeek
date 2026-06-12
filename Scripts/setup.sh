#!/bin/bash
set -euo pipefail

echo "VaultPeek Setup"
echo "==============="
echo ""

DATA_DIR="$HOME/.vaultpeek"

# Create data directory
mkdir -p "$DATA_DIR"
chmod 700 "$DATA_DIR"
echo "Created data directory: $DATA_DIR"

# Check for Plaid credentials
if [ -z "${PLAID_CLIENT_ID:-}" ] || [ -z "${PLAID_SECRET:-}" ]; then
    echo ""
    echo "No Plaid credentials found in environment."
    echo ""
    echo "To use sandbox mode, set sandbox credentials first:"
    echo "  export PLAID_CLIENT_ID=your_sandbox_client_id"
    echo "  export PLAID_SECRET=your_sandbox_secret"
    echo "  ./Scripts/run.sh --sandbox"
    echo ""
    echo "For screenshot/demo data without Plaid:"
    echo "  swift run PlaidBar --demo"
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
echo "Building VaultPeek..."
swift build 2>&1

echo ""
echo "Setup complete! Run VaultPeek with:"
echo "  swift run PlaidBar --demo    # Local fixture demo"
echo "  ./Scripts/run.sh --sandbox   # Plaid sandbox"
echo "  ./Scripts/run.sh             # Production mode"
