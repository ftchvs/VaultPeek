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
        # Returns true only when the *captured secret value* is itself a known
        # placeholder/synthetic literal. Matching on the captured value (not the
        # whole line) closes the bypass where a line merely *contained* a word
        # like "sample"/"fake"/"redacted" elsewhere and the whole line — real
        # secret and all — was waved through.
        function is_placeholder(val,   lc) {
            lc = tolower(val)
            return lc ~ /(00000000-0000-0000-0000-000000000000|example|placeholder|replace|synthetic|fixture|dummy|fake|sample|your[_-]|xxxx+|redacted|ci_smoke|test[_-]?secret|changeme)/
        }
        # Match keywords case-insensitively; Plaid tokens are lowercase hex.
        # Each rule captures the candidate secret value, then only the captured
        # value is checked against the placeholder allowlist.
        function offending(s,   lc, val) {
            lc = tolower(s)

            # Plaid item/access/public/link tokens: <env>-<uuid>.
            if (match(lc, /(access|public|link)-(sandbox|development|production)-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/)) {
                val = substr(lc, RSTART, RLENGTH)
                if (!is_placeholder(val)) return "plaid-token"
            }

            # Secret/client-id assignments, incl. snake_case and camelCase
            # (plaid_secret / plaidSecret / clientSecret / client_id) — the
            # camelCase spellings were previously missed.
            if (match(lc, /(plaid_?secret|plaid_?client_?id|client_?secret|client_?id)[ "'"'"']*[:=][ "'"'"']*[a-z0-9_-]{20,}/)) {
                # Isolate ONLY the captured value (the run after the separator),
                # not the rest of the line — otherwise a trailing comment like
                # "// not a sample" would smuggle a placeholder word into the
                # check and exempt a real secret. Re-match the value sub-pattern
                # within the captured region to slice it out precisely.
                val = substr(lc, RSTART, RLENGTH)
                sub(/^[^:=]*[:=][ "'"'"']*/, "", val)
                if (!is_placeholder(val)) return "secret-assignment"
            }

            # Bearer tokens in Authorization headers / literals.
            if (match(lc, /bearer[ ]+[a-z0-9._-]{32,}/)) {
                val = substr(lc, RSTART + 7, RLENGTH - 7)
                if (!is_placeholder(val)) return "bearer-token"
            }

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
    local positives negatives out rc=0 positive_count
    # Synthetic, fake-but-format-valid secrets — must be FLAGGED.
    # Includes the camelCase `plaidSecret` spelling and a real-shaped secret on a
    # line that ALSO contains a placeholder word ("sample") elsewhere — the old
    # whole-line allowlist waved both of those through.
    positives='+let token = "access-production-a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d"
+PLAID_SECRET=ab12cd34ef56ab78cd90ef12ab34
+Authorization: Bearer abcdef0123456789abcdef0123456789abcd
+let plaidSecret = "ab12cd34ef56ab78cd90ef12ab34"
+let clientSecret = "ab12cd34ef56ab78cd90ef12ab34" // not a sample'
    positive_count=5
    # Things that must NOT be flagged (placeholders / CI fakes / prose).
    negatives='+PLAID_SECRET: ci_smoke_secret
+let demo = "access-sandbox-00000000-0000-0000-0000-000000000000"
+// see your_plaid_secret in the dashboard
+let clientId = "REPLACE_ME"
+let plaidSecret = "your_plaid_secret_here"'

    echo "selftest: positives (expect a hit per line)..."
    out="$(printf '+++ b/Test.swift\n@@ -0,0 +1,%d @@\n%s\n' "$positive_count" "$positives" | scan_diff || true)"
    if [[ -z "$out" ]]; then
        echo "  FAIL: scanner did not flag known secrets"; rc=1
    else
        echo "$out"
        local hit_count
        hit_count="$(printf '%s\n' "$out" | grep -c '(rule:' || true)"
        if [[ "$hit_count" -lt "$positive_count" ]]; then
            echo "  FAIL: expected $positive_count hits, got $hit_count"; rc=1
        fi
    fi

    echo "selftest: negatives (expect no hits)..."
    out="$(printf '+++ b/Test.swift\n@@ -0,0 +1,5 @@\n%s\n' "$negatives" | scan_diff || true)"
    if [[ -z "$out" ]]; then
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

# Emit the per-commit patches for one push range on stdout. Scanning each
# outgoing commit (git log -p, first-parent, no merges) — rather than only the
# endpoint tree diff — closes the gap where a secret added in one commit and
# removed in a later commit of the same push is invisible to `git diff A..B`
# yet still travels to the remote inside the earlier commit object.
emit_range_patches() {
    local range="$1"
    git log -p --no-color -U0 --no-merges --first-parent "$range" 2>/dev/null
}

# Resolve the list of "<remote-oid> <local-oid>" ranges to scan.
#
# Preferred source: the refs Git feeds a pre-push hook on stdin, one per line as
#   <local ref> <local oid> <remote ref> <remote oid>
# This is authoritative for exactly what is being pushed — it covers pushing a
# non-current branch, multiple refs at once, or `git push origin other-branch`
# from a different checkout, none of which a HEAD-derived range gets right.
#
# Fallback (no stdin, e.g. the Claude Code PreToolUse hook or manual runs):
# derive a single range from @{push} → origin/main → all of HEAD.
ZERO_OID="0000000000000000000000000000000000000000"
ranges=()
stdin_refs=""
if [[ ! -t 0 ]]; then
    stdin_refs="$(cat 2>/dev/null || true)"
fi

if [[ -n "$stdin_refs" ]]; then
    while read -r local_ref local_oid _remote_ref remote_oid; do
        [[ -z "${local_ref:-}" ]] && continue
        if [[ "$local_oid" == "$ZERO_OID" ]]; then
            # Branch deletion — nothing to scan.
            continue
        fi
        if [[ "$remote_oid" == "$ZERO_OID" ]]; then
            # New remote ref: scan every commit reachable from local that is not
            # already on any other remote ref (avoids re-scanning all history).
            ranges+=("$(git rev-parse "$local_oid") --not --remotes")
        else
            ranges+=("${remote_oid}..${local_oid}")
        fi
    done <<< "$stdin_refs"
fi

if [[ ${#ranges[@]} -eq 0 ]]; then
    range="HEAD"
    if up="$(git rev-parse --abbrev-ref --symbolic-full-name '@{push}' 2>/dev/null)" \
        && git rev-parse --verify "$up" >/dev/null 2>&1; then
        range="${up}..HEAD"
    elif git rev-parse --verify origin/main >/dev/null 2>&1; then
        range="origin/main..HEAD"
    fi
    ranges+=("$range")
fi

echo "pre-push-gate: scanning ${#ranges[@]} push range(s) per-commit for secrets..." >&2
findings=""
for range in "${ranges[@]}"; do
    # $range may carry intentional rev-list flags (e.g. "<oid> --not --remotes"),
    # so word-splitting here is deliberate.
    # shellcheck disable=SC2086
    range_findings="$(emit_range_patches $range | scan_diff || true)"
    if [[ -n "$range_findings" ]]; then
        findings+="  [range: $range]"$'\n'"$range_findings"$'\n'
    fi
done

if [[ -z "$findings" ]]; then
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
