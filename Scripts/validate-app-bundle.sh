#!/usr/bin/env bash
# Validate that a local VaultPeek.app bundle can resolve its embedded frameworks.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

APP_DIR="${1:-$PROJECT_DIR/.build/VaultPeek.app}"
if [ ! -d "$APP_DIR" ]; then
    echo "Usage: $0 [path/to/VaultPeek.app]" >&2
    echo "No app bundle found at $APP_DIR — run ./Scripts/package-app.sh first." >&2
    exit 64
fi

APP_BINARY="$APP_DIR/Contents/MacOS/PlaidBar"
SERVER_BINARY="$APP_DIR/Contents/MacOS/PlaidBarServer"
SPARKLE_FRAMEWORK="$APP_DIR/Contents/Frameworks/Sparkle.framework"
INFO_PLIST="$APP_DIR/Contents/Info.plist"
APP_ICON="$APP_DIR/Contents/Resources/AppIcon.icns"
WIDGET_APPEX="$APP_DIR/Contents/PlugIns/PlaidBarWidgetExtension.appex"
WIDGET_INFO_PLIST="$WIDGET_APPEX/Contents/Info.plist"
WIDGET_BINARY="$WIDGET_APPEX/Contents/MacOS/PlaidBarWidgetExtension"

if [ ! -f "$INFO_PLIST" ]; then
    echo "Missing Info.plist at $INFO_PLIST" >&2
    exit 1
fi

if [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO_PLIST" 2>/dev/null || true)" != "PlaidBar" ]; then
    echo "VaultPeek.app Info.plist must keep CFBundleExecutable as PlaidBar until the binary rename slice lands" >&2
    exit 1
fi

if [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$INFO_PLIST" 2>/dev/null || true)" != "AppIcon" ]; then
    echo "VaultPeek.app Info.plist must set CFBundleIconFile to AppIcon" >&2
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
    echo "VaultPeek.app is missing @executable_path/../Frameworks rpath" >&2
    otool -l "$APP_BINARY" >&2
    exit 1
fi

# Widget extension (.appex) — embedded under Contents/PlugIns so the WidgetKit
# widgets, Control Center controls, and the Spotlight/Shortcuts App Intents
# install with the app (AND-586 distribution). The extension only loads when it
# is present with a valid WidgetKit extension point and a verifiable signature.
# Entitlements (App Group / sandbox) are intentionally NOT asserted here: the
# open-source ad-hoc build omits them so the local/DMG bundle stays launchable
# (see package-app.sh). The widget's App Group shared snapshot only works once a
# contributor supplies their own App Group entitlement and signing identity.
if [ ! -d "$WIDGET_APPEX" ]; then
    echo "Missing widget extension at $WIDGET_APPEX" >&2
    echo "package-app.sh must embed PlaidBarWidgetExtension.appex under Contents/PlugIns." >&2
    exit 1
fi

if [ ! -f "$WIDGET_INFO_PLIST" ]; then
    echo "Missing widget Info.plist at $WIDGET_INFO_PLIST" >&2
    exit 1
fi

if [ ! -x "$WIDGET_BINARY" ]; then
    echo "Missing executable widget binary at $WIDGET_BINARY" >&2
    exit 1
fi

WIDGET_EXTENSION_POINT="$(/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionPointIdentifier' "$WIDGET_INFO_PLIST" 2>/dev/null || true)"
if [ "$WIDGET_EXTENSION_POINT" != "com.apple.widgetkit-extension" ]; then
    echo "Widget Info.plist NSExtensionPointIdentifier must be com.apple.widgetkit-extension (got: ${WIDGET_EXTENSION_POINT:-<missing>})" >&2
    exit 1
fi

if [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$WIDGET_INFO_PLIST" 2>/dev/null || true)" != "com.ftchvs.PlaidBar.WidgetExtension" ]; then
    echo "Widget Info.plist CFBundleIdentifier must be com.ftchvs.PlaidBar.WidgetExtension" >&2
    exit 1
fi

if [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$WIDGET_INFO_PLIST" 2>/dev/null || true)" != "PlaidBarWidgetExtension" ]; then
    echo "Widget Info.plist CFBundleExecutable must be PlaidBarWidgetExtension" >&2
    exit 1
fi

if ! codesign --verify --strict "$WIDGET_APPEX" >/dev/null 2>&1; then
    echo "Widget extension signature failed to verify for $WIDGET_APPEX (ad-hoc or Developer ID)" >&2
    codesign --verify --strict --verbose=2 "$WIDGET_APPEX" >&2 || true
    exit 1
fi

if ! codesign --verify --deep --strict "$APP_DIR" >/dev/null 2>&1; then
    echo "Code signature failed to verify for $APP_DIR (ad-hoc or Developer ID)" >&2
    codesign --verify --deep --strict --verbose=2 "$APP_DIR" >&2 || true
    exit 1
fi

echo "Validated VaultPeek.app bundle (incl. widget extension) at $APP_DIR"
