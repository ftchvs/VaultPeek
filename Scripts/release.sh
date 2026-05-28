#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

usage() {
    cat <<'EOF'
Usage: ./Scripts/release.sh [--publish]

Preflights the current PlaidBar release. With --publish, creates and pushes the
version tag, then creates a GitHub release for ftchvs/PlaidBar.

This script expects to run from a clean main branch after CI has passed.
EOF
}

PUBLISH=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --publish)
            PUBLISH=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ ! -f version.env ]]; then
    echo "Missing version.env" >&2
    exit 1
fi

# shellcheck disable=SC1091
source version.env

if [[ -z "${VERSION:-}" || -z "${BUILD:-}" ]]; then
    echo "version.env must define VERSION and BUILD" >&2
    exit 1
fi

TAG="v$VERSION"
BRANCH="$(git branch --show-current)"

if [[ "$BRANCH" != "main" ]]; then
    echo "Release must be run from main, currently on $BRANCH" >&2
    exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
    echo "Release must be run from a clean worktree" >&2
    git status --short >&2
    exit 1
fi

INFO_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Sources/PlaidBar/Resources/Info.plist)"
INFO_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Sources/PlaidBar/Resources/Info.plist)"
RUNTIME_VERSION="$(
    sed -n 's/.*appVersion: String = "\([^"]*\)".*/\1/p' \
        Sources/PlaidBarCore/Utilities/Constants.swift
)"

if [[ "$INFO_VERSION" != "$VERSION" ]]; then
    echo "Info.plist version $INFO_VERSION does not match version.env $VERSION" >&2
    exit 1
fi

if [[ "$INFO_BUILD" != "$BUILD" ]]; then
    echo "Info.plist build $INFO_BUILD does not match version.env $BUILD" >&2
    exit 1
fi

if [[ "$RUNTIME_VERSION" != "$VERSION" ]]; then
    echo "PlaidBarConstants.appVersion $RUNTIME_VERSION does not match version.env $VERSION" >&2
    exit 1
fi

if ! grep -Fq "tag: \"$TAG\"" Formula/plaidbar.rb; then
    echo "Formula/plaidbar.rb does not reference $TAG" >&2
    exit 1
fi

echo "Running release gates for $TAG..."
swift build -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
swift build -c release -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
bash -n Scripts/*.sh Scripts/plaidbar-run
ruby -c Formula/plaidbar.rb

if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "Tag $TAG already exists locally" >&2
    exit 1
fi

if git ls-remote --tags origin "$TAG" | grep -Fq "$TAG"; then
    echo "Tag $TAG already exists on origin" >&2
    exit 1
fi

if [[ "$PUBLISH" != "true" ]]; then
    echo ""
    echo "Dry run complete. Publish with:"
    echo "  ./Scripts/release.sh --publish"
    exit 0
fi

git tag -a "$TAG" -m "PlaidBar $TAG"
git push origin "$TAG"
gh release create "$TAG" \
    --repo ftchvs/PlaidBar \
    --title "PlaidBar $TAG" \
    --generate-notes

echo "Published $TAG."
