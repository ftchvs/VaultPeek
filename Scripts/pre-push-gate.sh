#!/usr/bin/env bash
#
# Pre-push safety gate for PlaidBar / VaultPeek.
#
# Runs two checks against the commits about to leave this machine and blocks
# the push (non-zero exit) on either failure:
#
#   1. Secret scan  — flags Plaid tokens / secrets / bearer tokens in the
#      outgoing diff. A real Plaid secret in a tracked file is unrecoverable
#      once pushed, so this errs toward blocking.
#   2. Strict build — the Swift 6 strict-concurrency build that is the CI gate
#      most likely to fail. Catches it locally, and acts as CI when GitHub
#      Actions is unavailable.
#
# Invoked from .git/hooks/pre-push and from the Claude Code PreToolUse hook
# (.claude/hooks/git-push-gate.sh). It is a heuristic backstop, NOT a
# replacement for a dedicated scanner such as gitleaks.
#
# Escape hatches (use sparingly):
#   PLAIDBAR_SKIP_GATE=1        git push ...   # skip the whole gate
#   PLAIDBAR_GATE_SKIP_BUILD=1  git push ...   # secret scan only, skip build
#
# Self-test (exercises the scanner on fixtures, runs no build, touches no git):
#   ./Scripts/pre-push-gate.sh --selftest

set -euo pipefail

# --- secret scanner ---------------------------------------------------------
# Reads a unified diff (-U0) on stdin, prints "file:line" for every added line
# that looks like a secret, and exits non-zero if any were found. Never prints
# the secret value itself (printing it would re-leak it into logs/terminal).
scan_diff() {
    awk '
        # Match keywords case-insensitively; Plaid tokens are lowercase hex.
        function offending(s,   lc) {
            lc = tolower(s)
            if (lc ~ /(00000000-0000-0000-0000-000000000000|example|placeholder|replace|synthetic|fixture|dummy|fake|sample|your_|your-|xxxx|redacted)/)
                return ""
            if (lc ~ /(access|public|link)-(sandbox|development|production)-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/)
                return "plaid-token"
            if (lc ~ /(plaid_secret|plaid_client_id|client_secret|clientsecret)[ "'"'"']*[:=][ "'"'"']*[a-z0-9]{24,}/)
                return "secret-assignment"
            if (lc ~ /bearer[ ]+[a-z0-9._-]{32,}/)
                return "bearer-token"
            return ""
        }
        /^\+\+\+ b\// { file = substr($0, 7); next }
        /^@@ / { match($0, /\+[0-9]+/); ln = substr($0, RSTART + 1, RLENGTH - 1) + 0; next }
        /^\+/ && !/^\+\+\+/ {
            rule = offending(substr($0, 2))
            if (rule != "") { printf "  %s:%d  (rule: %s)\n", file, ln, rule; hits++ }
            ln++; next
        }
        END { if (hits) exit 1 }
    '
}

run_selftest() {
    local positives negatives out rc=0
    # Synthetic, fake-but-format-valid secrets — must be FLAGGED.
    positives='+let token = "access-production-a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d"
+PLAID_SECRET=ab12cd34ef56ab78cd90ef12ab34
+Authorization: Bearer abcdef0123456789abcdef0123456789abcd'
    # Things that must NOT be flagged (placeholders / CI fakes / prose).
    negatives='+PLAID_SECRET: ci_smoke_secret
+let demo = "access-sandbox-00000000-0000-0000-0000-000000000000"
+// see your_plaid_secret in the dashboard
+let clientId = "REPLACE_ME"'

    echo "selftest: positives (expect a hit per line)..."
    if out="$(printf '+++ b/Test.swift\n@@ -0,0 +1,3 @@\n%s\n' "$positives" | scan_diff)"; then
        echo "  FAIL: scanner did not flag known secrets"; rc=1
    else
        echo "$out"
    fi

    echo "selftest: negatives (expect no hits)..."
    if out="$(printf '+++ b/Test.swift\n@@ -0,0 +1,4 @@\n%s\n' "$negatives" | scan_diff)"; then
        echo "  OK: no false positives"
    else
        echo "  FAIL: scanner flagged a placeholder/CI value:"; echo "$out"; rc=1
    fi

    if [[ $rc -eq 0 ]]; then echo "selftest: PASS"; else echo "selftest: FAIL"; fi
    return $rc
}

# --- entry point ------------------------------------------------------------
if [[ "${1:-}" == "--selftest" ]]; then
    run_selftest
    exit $?
fi

if [[ "${PLAIDBAR_SKIP_GATE:-0}" == "1" ]]; then
    echo "pre-push-gate: skipped (PLAIDBAR_SKIP_GATE=1)" >&2
    exit 0
fi

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

# Resolve the range of commits being pushed: prefer the push-upstream, then
# origin/main, else fall back to scanning all of HEAD.
range="HEAD"
if up="$(git rev-parse --abbrev-ref --symbolic-full-name '@{push}' 2>/dev/null)" \
    && git rev-parse --verify "$up" >/dev/null 2>&1; then
    range="${up}..HEAD"
elif git rev-parse --verify origin/main >/dev/null 2>&1; then
    range="origin/main..HEAD"
fi

echo "pre-push-gate: scanning '$range' for secrets..." >&2
if findings="$(git diff "$range" --no-color -U0 2>/dev/null | scan_diff)"; then
    echo "pre-push-gate: secret scan clean." >&2
else
    {
        echo ""
        echo "BLOCKED: possible secret(s) in the commits you are pushing:"
        echo "$findings"
        echo ""
        echo "Scrub the value (use sandbox/synthetic data), amend the commit, and retry."
        echo "If this is a false positive: PLAIDBAR_SKIP_GATE=1 git push ..."
    } >&2
    exit 1
fi

if [[ "${PLAIDBAR_GATE_SKIP_BUILD:-0}" == "1" ]]; then
    echo "pre-push-gate: build skipped (PLAIDBAR_GATE_SKIP_BUILD=1)" >&2
    exit 0
fi

echo "pre-push-gate: strict-concurrency build (incremental)..." >&2
if swift build -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors; then
    echo "pre-push-gate: strict build passed. Push allowed." >&2
else
    {
        echo ""
        echo "BLOCKED: strict-concurrency build failed (this is the CI gate)."
        echo "Fix the Sendable / concurrency errors above, or to push anyway:"
        echo "  PLAIDBAR_GATE_SKIP_BUILD=1 git push ...   (build only)"
        echo "  PLAIDBAR_SKIP_GATE=1 git push ...         (whole gate)"
    } >&2
    exit 1
fi
