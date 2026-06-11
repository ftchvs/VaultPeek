#!/usr/bin/env bash
# Build a local PlaidBar.app bundle that includes SwiftPM dynamic frameworks.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIGURATION="${PLAIDBAR_PACKAGE_CONFIGURATION:-release}"
BUILD_DIR="$PROJECT_DIR/.build/$CONFIGURATION"
APP_DIR="${PLAIDBAR_PACKAGE_APP_DIR:-$PROJECT_DIR/.build/PlaidBar.app}"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
RESOURCES_DIR="$PROJECT_DIR/Sources/PlaidBar/Resources"
APP_BINARY="$MACOS_DIR/PlaidBar"

if [ "$CONFIGURATION" = "release" ]; then
    BUILD_FLAGS=(-c release)
else
    BUILD_FLAGS=()
fi

echo "Building PlaidBar ($CONFIGURATION)..."
cd "$PROJECT_DIR"
swift build "${BUILD_FLAGS[@]}" --disable-keychain

if [ ! -x "$BUILD_DIR/PlaidBar" ]; then
    echo "PlaidBar binary not found at $BUILD_DIR/PlaidBar" >&2
    exit 1
fi

if [ ! -x "$BUILD_DIR/PlaidBarServer" ]; then
    echo "PlaidBarServer binary not found at $BUILD_DIR/PlaidBarServer" >&2
    exit 1
fi

if [ ! -d "$BUILD_DIR/Sparkle.framework" ]; then
    echo "Sparkle.framework not found at $BUILD_DIR/Sparkle.framework" >&2
    exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$FRAMEWORKS_DIR"

cp "$BUILD_DIR/PlaidBar" "$APP_BINARY"
cp "$BUILD_DIR/PlaidBarServer" "$MACOS_DIR/PlaidBarServer"
cp "$RESOURCES_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable PlaidBar" "$CONTENTS_DIR/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string PlaidBar" "$CONTENTS_DIR/Info.plist"
ditto "$BUILD_DIR/Sparkle.framework" "$FRAMEWORKS_DIR/Sparkle.framework"
chmod +x "$APP_BINARY" "$MACOS_DIR/PlaidBarServer"

if ! otool -l "$APP_BINARY" | grep -q "@executable_path/../Frameworks"; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BINARY"
fi

codesign --force --deep --sign - "$APP_DIR" >/dev/null

"$SCRIPT_DIR/validate-app-bundle.sh" "$APP_DIR"

if [ "${PLAIDBAR_PACKAGE_SMOKE_LAUNCH:-0}" = "1" ]; then
    "$APP_BINARY" --demo >/tmp/plaidbar-package-smoke.log 2>&1 &
    app_pid=$!
    sleep 2
    if ! kill -0 "$app_pid" 2>/dev/null; then
        echo "Packaged PlaidBar.app exited during smoke launch" >&2
        cat /tmp/plaidbar-package-smoke.log >&2 || true
        exit 1
    fi
    kill "$app_pid" 2>/dev/null || true
    wait "$app_pid" 2>/dev/null || true
fi

echo "Packaged PlaidBar.app at $APP_DIR"
