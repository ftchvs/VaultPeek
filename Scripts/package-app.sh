#!/usr/bin/env bash
# Build a local VaultPeek.app bundle that includes SwiftPM dynamic frameworks.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIGURATION="${PLAIDBAR_PACKAGE_CONFIGURATION:-release}"
BUILD_DIR="$PROJECT_DIR/.build/$CONFIGURATION"
APP_DIR="${PLAIDBAR_PACKAGE_APP_DIR:-$PROJECT_DIR/.build/VaultPeek.app}"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
PLUGINS_DIR="$CONTENTS_DIR/PlugIns"
RESOURCES_DIR="$PROJECT_DIR/Sources/PlaidBar/Resources"
WIDGET_RESOURCES_DIR="$PROJECT_DIR/Sources/PlaidBarWidgetExtension/Resources"
APP_BINARY="$MACOS_DIR/PlaidBar"
WIDGET_EXTENSION_DIR="$PLUGINS_DIR/PlaidBarWidgetExtension.appex"
WIDGET_EXTENSION_CONTENTS_DIR="$WIDGET_EXTENSION_DIR/Contents"
WIDGET_EXTENSION_MACOS_DIR="$WIDGET_EXTENSION_CONTENTS_DIR/MacOS"
WIDGET_EXTENSION_BINARY="$WIDGET_EXTENSION_MACOS_DIR/PlaidBarWidgetExtension"

if [ "$CONFIGURATION" = "release" ]; then
    BUILD_FLAGS=(-c release)
else
    BUILD_FLAGS=("--configuration" "$CONFIGURATION")
fi

echo "Building VaultPeek ($CONFIGURATION)..."
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

if [ ! -x "$BUILD_DIR/PlaidBarWidgetExtension" ]; then
    echo "PlaidBarWidgetExtension binary not found at $BUILD_DIR/PlaidBarWidgetExtension" >&2
    exit 1
fi

if [ ! -d "$BUILD_DIR/Sparkle.framework" ]; then
    echo "Sparkle.framework not found at $BUILD_DIR/Sparkle.framework" >&2
    exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$FRAMEWORKS_DIR" "$CONTENTS_DIR/Resources" "$WIDGET_EXTENSION_MACOS_DIR"

cp "$BUILD_DIR/PlaidBar" "$APP_BINARY"
cp "$BUILD_DIR/PlaidBarServer" "$MACOS_DIR/PlaidBarServer"
cp "$BUILD_DIR/PlaidBarWidgetExtension" "$WIDGET_EXTENSION_BINARY"
cp "$RESOURCES_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$RESOURCES_DIR/AppIcon.icns" "$CONTENTS_DIR/Resources/AppIcon.icns"
cp "$WIDGET_RESOURCES_DIR/Info.plist" "$WIDGET_EXTENSION_CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable PlaidBar" "$CONTENTS_DIR/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string PlaidBar" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable PlaidBarWidgetExtension" "$WIDGET_EXTENSION_CONTENTS_DIR/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string PlaidBarWidgetExtension" "$WIDGET_EXTENSION_CONTENTS_DIR/Info.plist"
ditto "$BUILD_DIR/Sparkle.framework" "$FRAMEWORKS_DIR/Sparkle.framework"
chmod +x "$APP_BINARY" "$MACOS_DIR/PlaidBarServer" "$WIDGET_EXTENSION_BINARY"

if ! otool -l "$APP_BINARY" | grep -q "@executable_path/../Frameworks"; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BINARY"
fi

codesign --force --deep --sign - "$APP_DIR" >/dev/null
codesign --force --sign - \
    --entitlements "$WIDGET_RESOURCES_DIR/PlaidBarWidgetExtension.entitlements" \
    "$WIDGET_EXTENSION_DIR" >/dev/null
codesign --force --sign - \
    --entitlements "$RESOURCES_DIR/PlaidBar.entitlements" \
    "$APP_DIR" >/dev/null

"$SCRIPT_DIR/validate-app-bundle.sh" "$APP_DIR"

if [ "${PLAIDBAR_PACKAGE_SMOKE_LAUNCH:-0}" = "1" ]; then
    "$APP_BINARY" --demo >/tmp/vaultpeek-package-smoke.log 2>&1 &
    app_pid=$!
    sleep 2
    if ! kill -0 "$app_pid" 2>/dev/null; then
        echo "Packaged VaultPeek.app exited during smoke launch" >&2
        cat /tmp/vaultpeek-package-smoke.log >&2 || true
        exit 1
    fi
    kill "$app_pid" 2>/dev/null || true
    wait "$app_pid" 2>/dev/null || true
fi

echo "Packaged VaultPeek.app at $APP_DIR"
