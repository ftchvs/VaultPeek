#!/usr/bin/env bash
# Verify that version.env, Info.plist, and the runtime constant agree on the
# release version and build number. Used by Scripts/release.sh and CI so a
# release candidate cannot ship with drifting version metadata.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

if [ ! -f version.env ]; then
    echo "Missing version.env" >&2
    exit 1
fi

# shellcheck disable=SC1091
source version.env

if [ -z "${VERSION:-}" ] || [ -z "${BUILD:-}" ]; then
    echo "version.env must define VERSION and BUILD" >&2
    exit 1
fi

INFO_PLIST="Sources/PlaidBar/Resources/Info.plist"
INFO_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
INFO_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
RUNTIME_VERSION="$(
    sed -n 's/.*appVersion: String = "\([^"]*\)".*/\1/p' \
        Sources/PlaidBarCore/Utilities/Constants.swift
)"

FAILED=0

if [ "$INFO_VERSION" != "$VERSION" ]; then
    echo "Info.plist CFBundleShortVersionString '$INFO_VERSION' does not match version.env VERSION '$VERSION'" >&2
    FAILED=1
fi

if [ "$INFO_BUILD" != "$BUILD" ]; then
    echo "Info.plist CFBundleVersion '$INFO_BUILD' does not match version.env BUILD '$BUILD'" >&2
    FAILED=1
fi

if [ "$RUNTIME_VERSION" != "$VERSION" ]; then
    echo "PlaidBarConstants.appVersion '$RUNTIME_VERSION' does not match version.env VERSION '$VERSION'" >&2
    FAILED=1
fi

if [ "$FAILED" -ne 0 ]; then
    exit 1
fi

echo "Version metadata aligned: VERSION=$VERSION BUILD=$BUILD"
