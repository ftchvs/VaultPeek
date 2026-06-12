#!/usr/bin/env bash
# Build a drag-install PlaidBar DMG around the self-contained VaultPeek.app.
#
# Usage: ./Scripts/package-dmg.sh
#
# Produces .build/PlaidBar-<version>.dmg containing VaultPeek.app and an
# /Applications symlink. The app bundle includes PlaidBarServer, which the
# app starts automatically on first launch, so non-developers only drag,
# drop, and open.
#
# The bundle is ad-hoc signed. Until Developer ID signing + notarization
# ship (see docs/release.md), downloaded DMGs require right-click > Open on
# first launch.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_DIR="${PLAIDBAR_PACKAGE_APP_DIR:-$PROJECT_DIR/.build/VaultPeek.app}"
# Keep package-app.sh writing to the exact bundle path this script stages.
export PLAIDBAR_PACKAGE_APP_DIR="$APP_DIR"
STAGING_DIR="$PROJECT_DIR/.build/dmg-staging"
VOLUME_NAME="PlaidBar"

cd "$PROJECT_DIR"

if [ ! -f version.env ]; then
    echo "Missing version.env" >&2
    exit 1
fi

# shellcheck disable=SC1091
source version.env

if [ -z "${VERSION:-}" ]; then
    echo "version.env must define VERSION" >&2
    exit 1
fi

DMG_PATH="$PROJECT_DIR/.build/PlaidBar-$VERSION.dmg"

"$SCRIPT_DIR/package-app.sh"

rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"
ditto "$APP_DIR" "$STAGING_DIR/VaultPeek.app"
ln -s /Applications "$STAGING_DIR/Applications"

echo "Creating $DMG_PATH..."
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null

rm -rf "$STAGING_DIR"

echo "Verifying DMG..."
hdiutil verify "$DMG_PATH" >/dev/null

echo ""
echo "Built $DMG_PATH"
echo "Install: open the DMG, drag VaultPeek.app to Applications, then"
echo "right-click VaultPeek.app > Open on first launch (ad-hoc signed build)."
