#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# The dot-free designmd shim avoids Windows/PowerShell .md command-resolution issues
# and resolves to the same @google/design.md entrypoint on macOS/Linux.
npx -y -p @google/design.md@0.3.0 designmd lint --format json DESIGN.md
