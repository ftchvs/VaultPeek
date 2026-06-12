#!/usr/bin/env bash
# Validate that a local PlaidBar.app bundle can resolve its embedded frameworks.
set -euo pipefail

APP_DIR="${1:-}"
if [ -z "$APP_DIR" ]; then
    echo "Usage: $0 path/to/PlaidBar.app" >&2
    exit 64
fi

APP_BINARY="$APP_DIR/Contents/MacOS/PlaidBar"
SERVER_BINARY="$APP_DIR/Contents/MacOS/PlaidBarServer"
SPARKLE_FRAMEWORK="$APP_DIR/Contents/Frameworks/Sparkle.framework"
INFO_PLIST="$APP_DIR/Contents/Info.plist"
APP_ICON="$APP_DIR/Contents/Resources/AppIcon.icns"

if [ ! -f "$INFO_PLIST" ]; then
    echo "Missing Info.plist at $INFO_PLIST" >&2
    exit 1
fi

if [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO_PLIST" 2>/dev/null || true)" != "PlaidBar" ]; then
    echo "PlaidBar.app Info.plist must set CFBundleExecutable to PlaidBar" >&2
    exit 1
fi

if [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$INFO_PLIST" 2>/dev/null || true)" != "AppIcon" ]; then
    echo "PlaidBar.app Info.plist must set CFBundleIconFile to AppIcon" >&2
    exit 1
fi

if [ ! -f "$APP_ICON" ]; then
    echo "Missing app icon at $APP_ICON" >&2
    exit 1
fi

if [ ! -x "$APP_BINARY" ]; then
    echo "Missing executable PlaidBar binary at $APP_BINARY" >&2
    exit 1
fi

if [ ! -x "$SERVER_BINARY" ]; then
    echo "Missing executable PlaidBarServer binary at $SERVER_BINARY" >&2
    exit 1
fi

if [ ! -d "$SPARKLE_FRAMEWORK" ]; then
    echo "Missing embedded Sparkle.framework at $SPARKLE_FRAMEWORK" >&2
    exit 1
fi

if ! otool -L "$APP_BINARY" | grep -q "@rpath/Sparkle.framework"; then
    echo "PlaidBar binary does not link Sparkle via @rpath" >&2
    otool -L "$APP_BINARY" >&2
    exit 1
fi

if ! otool -l "$APP_BINARY" | grep -q "@executable_path/../Frameworks"; then
    echo "PlaidBar.app is missing @executable_path/../Frameworks rpath" >&2
    otool -l "$APP_BINARY" >&2
    exit 1
fi

echo "Validated PlaidBar.app bundle at $APP_DIR"
