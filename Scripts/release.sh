#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

usage() {
    cat <<'EOF'
Usage: ./Scripts/release.sh [--publish] [--allow-current-branch]

Preflights the current VaultPeek release. With --publish, creates and pushes the
version tag, then creates a GitHub release for ftchvs/PlaidBar.

This script expects to run from a clean main branch after CI has passed.
Use --allow-current-branch only for release-prep PR validation; publishing still
requires clean main.

Set PLAIDBAR_RELEASE_SKIP_TESTS=1 only for the documented local Swift Testing
toolchain mismatch; CI must still pass tests before publishing.
EOF
}

PUBLISH=false
ALLOW_CURRENT_BRANCH=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --publish)
            PUBLISH=true
            shift
            ;;
        --allow-current-branch)
            ALLOW_CURRENT_BRANCH=true
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

if [[ "$PUBLISH" == "true" && "$BRANCH" != "main" ]]; then
    echo "Publishing must be run from main, currently on $BRANCH" >&2
    exit 1
fi

if [[ "$ALLOW_CURRENT_BRANCH" != "true" && "$BRANCH" != "main" ]]; then
    echo "Release must be run from main, currently on $BRANCH" >&2
    echo "For release-prep PR validation, rerun with --allow-current-branch." >&2
    exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
    echo "Release must be run from a clean worktree" >&2
    git status --short >&2
    exit 1
fi

"$SCRIPT_DIR/verify-version-alignment.sh"

echo "Running release gates for $TAG..."
swift build -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors --disable-keychain
swift build -c release -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors --disable-keychain
if [[ "${PLAIDBAR_RELEASE_SKIP_TESTS:-0}" == "1" ]]; then
    echo "Skipping swift test because PLAIDBAR_RELEASE_SKIP_TESTS=1."
    echo "Only use this for the documented local Swift Testing toolchain mismatch; CI must pass tests before publishing."
else
    swift test --skip-update --disable-keychain
fi
bash -n Scripts/*.sh Scripts/vaultpeek-run Scripts/plaidbar-run

echo "Running release-diff secret scan (release-checklist.md Privacy And Security)..."
PLAIDBAR_GATE_SKIP_BUILD=1 bash "$SCRIPT_DIR/pre-push-gate.sh"

echo "Validating packaged VaultPeek.app bundle..."
"$SCRIPT_DIR/package-app.sh"
"$SCRIPT_DIR/validate-app-bundle.sh"

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

git tag -a "$TAG" -m "VaultPeek $TAG"
git push origin "$TAG"
gh release create "$TAG" \
    --repo ftchvs/PlaidBar \
    --title "VaultPeek $TAG" \
    --generate-notes

echo "Published $TAG."
