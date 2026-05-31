#!/usr/bin/env bash
# Validate that a local PlaidBar.app bundle can resolve its embedded frameworks.
set -euo pipefail

APP_DIR="${1:-}"
if [ -z "$APP_DIR" ]; then
    echo "Usage: $0 path/to/PlaidBar.app" >&2
    exit 64
fi

APP_BINARY="$APP_DIR/Contents/MacOS/PlaidBar"
SPARKLE_FRAMEWORK="$APP_DIR/Contents/Frameworks/Sparkle.framework"

if [ ! -x "$APP_BINARY" ]; then
    echo "Missing executable PlaidBar binary at $APP_BINARY" >&2
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
