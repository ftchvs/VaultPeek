#!/bin/bash
set -euo pipefail

echo "Building PlaidBar..."
swift build -c release 2>&1

echo ""
echo "Build complete!"
echo "  Server: .build/release/PlaidBarServer"
echo "  App:    .build/release/PlaidBar"
echo ""
echo "For a local app bundle with Sparkle embedded:"
echo "  ./Scripts/package-app.sh"
