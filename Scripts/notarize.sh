#!/usr/bin/env bash
# Developer ID signing + notarization scaffold for VaultPeek.app and its DMG.
#
# STATUS: SCAFFOLD ONLY. This script has never produced a signed or notarized
# build. It exists so the runbook in docs/distribution.md has an executable
# shape ready for the day Felipe configures Apple Developer credentials.
# Do not claim notarized distribution until the verification checklist in
# docs/distribution.md passes on a clean machine.
#
# Required environment (no defaults on purpose — missing values fail fast):
#
#   PLAIDBAR_SIGNING_IDENTITY  Developer ID Application identity, e.g.
#                              "Developer ID Application: Felipe Chaves (TEAMID)"
#   PLAIDBAR_NOTARY_PROFILE    notarytool keychain profile name, created once with:
#                              xcrun notarytool store-credentials <profile> \
#                                --apple-id <apple-id> --team-id <team-id> \
#                                --password <app-specific-password>
#
# TODO before first real run (see docs/distribution.md):
#   - Replace the SUPublicEDKey placeholder in Sources/PlaidBar/Resources/Info.plist
#     with a real Sparkle EdDSA public key (or remove Sparkle from the bundle).
#   - Re-review Sources/PlaidBar/Resources/PlaidBar.entitlements before each
#     signing run; the bundled PlaidBarServer requires
#     com.apple.security.network.server when the app sandbox is enforced.
#   - Verify Gatekeeper acceptance on a clean machine (spctl + first launch).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_DIR="$PROJECT_DIR/.build/VaultPeek.app"
ENTITLEMENTS="$PROJECT_DIR/Sources/PlaidBar/Resources/PlaidBar.entitlements"
WIDGET_APPEX="$APP_DIR/Contents/PlugIns/PlaidBarWidgetExtension.appex"
WIDGET_ENTITLEMENTS="$PROJECT_DIR/Sources/PlaidBarWidgetExtension/Resources/PlaidBarWidgetExtension.entitlements"
STAGING_DIR="$PROJECT_DIR/.build/notarize-staging"

cd "$PROJECT_DIR"

missing=()
if [ -z "${PLAIDBAR_SIGNING_IDENTITY:-}" ]; then
    missing+=("PLAIDBAR_SIGNING_IDENTITY")
fi
if [ -z "${PLAIDBAR_NOTARY_PROFILE:-}" ]; then
    missing+=("PLAIDBAR_NOTARY_PROFILE")
fi

if [ "${#missing[@]}" -gt 0 ]; then
    {
        echo "notarize.sh is a scaffold and cannot run yet."
        echo ""
        echo "Missing required environment: ${missing[*]}"
        echo ""
        echo "Signing and notarization need Felipe's Apple Developer credentials."
        echo "Setup steps, entitlements review, and the Gatekeeper verification"
        echo "checklist live in docs/distribution.md."
    } >&2
    exit 64
fi

if ! xcrun --find notarytool >/dev/null 2>&1; then
    echo "xcrun notarytool not found — install full Xcode (not just CLT)." >&2
    exit 69
fi

if [ ! -f version.env ]; then
    echo "Missing version.env" >&2
    exit 1
fi

# shellcheck disable=SC1091
source version.env

DMG_PATH="$PROJECT_DIR/.build/VaultPeek-$VERSION.dmg"
ZIP_PATH="$PROJECT_DIR/.build/VaultPeek-$VERSION-notarize.zip"

if ! /usr/libexec/PlistBuddy \
    -c 'Print :com.apple.security.network.server' \
    "$ENTITLEMENTS" 2>/dev/null | grep -qx 'true'; then
    {
        echo "Missing com.apple.security.network.server in $ENTITLEMENTS."
        echo "The bundled PlaidBarServer binds localhost, so notarization must"
        echo "not proceed until the signed app carries the server entitlement."
    } >&2
    exit 65
fi

echo "==> Building unsigned-for-distribution app bundle..."
"$SCRIPT_DIR/package-app.sh"

echo "==> Signing inside-out with hardened runtime..."
# Sparkle's embedded helpers must be signed before the framework, and the
# framework before the executables that link it (Sparkle sandboxing docs).
SPARKLE="$APP_DIR/Contents/Frameworks/Sparkle.framework"
for helper in \
    "$SPARKLE/Versions/B/XPCServices/Installer.xpc" \
    "$SPARKLE/Versions/B/XPCServices/Downloader.xpc" \
    "$SPARKLE/Versions/B/Autoupdate" \
    "$SPARKLE/Versions/B/Updater.app"; do
    if [ -e "$helper" ]; then
        codesign --force --options runtime --timestamp \
            --sign "$PLAIDBAR_SIGNING_IDENTITY" "$helper"
    fi
done
codesign --force --options runtime --timestamp \
    --sign "$PLAIDBAR_SIGNING_IDENTITY" "$SPARKLE"
codesign --force --options runtime --timestamp \
    --sign "$PLAIDBAR_SIGNING_IDENTITY" \
    "$APP_DIR/Contents/MacOS/PlaidBarServer"
# The widget extension is a nested code bundle that package-app.sh only ad-hoc
# signs. Re-sign it with the Developer ID identity, hardened runtime, and its
# own entitlements BEFORE the outer app — otherwise the notarized bundle ships
# a nested .appex with only the ad-hoc signature, which fails notarization /
# Gatekeeper and leaves the widget undiscoverable (AND-385 Codex review).
if [ -e "$WIDGET_APPEX" ]; then
    codesign --force --options runtime --timestamp \
        --entitlements "$WIDGET_ENTITLEMENTS" \
        --sign "$PLAIDBAR_SIGNING_IDENTITY" "$WIDGET_APPEX"
fi
codesign --force --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$PLAIDBAR_SIGNING_IDENTITY" "$APP_DIR"

echo "==> Verifying signature before submission..."
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

# The widget extension only appears in the widget gallery and only reads the
# shared App Group snapshot when the signed .appex actually carries the
# group.com.ftchvs.PlaidBar entitlement. codesign silently drops --entitlements
# if the file path is wrong, so confirm the entitlement survived the signing
# pass before spending a notarization round-trip (AND-586 distribution).
if [ -e "$WIDGET_APPEX" ]; then
    echo "==> Verifying widget extension carries the App Group entitlement..."
    if ! codesign -d --entitlements :- "$WIDGET_APPEX" 2>/dev/null \
        | grep -q "group.com.ftchvs.PlaidBar"; then
        {
            echo "Signed widget extension is missing the App Group entitlement."
            echo "Expected group.com.ftchvs.PlaidBar from $WIDGET_ENTITLEMENTS."
            echo "Without it the widget cannot read the shared snapshot and shows"
            echo "the setup state, and Control Center controls cannot toggle state."
        } >&2
        exit 1
    fi
fi

echo "==> Notarizing the app bundle..."
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"
xcrun notarytool submit "$ZIP_PATH" \
    --keychain-profile "$PLAIDBAR_NOTARY_PROFILE" --wait
xcrun stapler staple "$APP_DIR"

echo "==> Building, signing, and notarizing the DMG..."
rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"
ditto "$APP_DIR" "$STAGING_DIR/VaultPeek.app"
ln -s /Applications "$STAGING_DIR/Applications"
hdiutil create -volname "VaultPeek" -srcfolder "$STAGING_DIR" \
    -ov -format UDZO "$DMG_PATH" >/dev/null
rm -rf "$STAGING_DIR"
codesign --force --timestamp --sign "$PLAIDBAR_SIGNING_IDENTITY" "$DMG_PATH"
xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$PLAIDBAR_NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG_PATH"

echo "==> Gatekeeper assessment..."
spctl --assess --type exec --verbose=2 "$APP_DIR"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH"

echo "==> Release artifact checksum..."
shasum -a 256 "$DMG_PATH"

echo ""
echo "Local signing flow finished for $DMG_PATH."
echo "This is NOT a verified distribution until the clean-machine Gatekeeper"
echo "checklist in docs/distribution.md passes end to end."
