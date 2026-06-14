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
# Invoked from .git/hooks/pre-push (Git feeds the to-be-pushed refs on stdin)
# and runnable by hand. A real Plaid secret in a tracked file is unrecoverable
# once pushed. It is a heuristic backstop, NOT a replacement for a dedicated
# scanner such as gitleaks.
#
# Blocking failures exit 2: git aborts the push on any non-zero hook exit, and
# Claude Code hooks treat exit 2 (not 1) as "block the action" — so a single
# exit 2 blocks both the native pre-push hook and a Claude PreToolUse wrapper,
# with no exit-code translation needed.
#
# Escape hatches (use sparingly):
#   PLAIDBAR_SKIP_GATE=1        git push ...   # skip the whole gate
#   PLAIDBAR_GATE_SKIP_BUILD=1  git push ...   # secret scan only, skip build
#
# Self-test (exercises the scanner on fixtures, runs no build, touches no git):
#   ./Scripts/pre-push-gate.sh --selftest

set -euo pipefail

# Exit code for blocking failures. git aborts the push on ANY non-zero hook
# exit, and Claude Code hooks treat exit 2 (not 1) as "block the action" — so 2
# blocks both the native pre-push hook and a Claude PreToolUse wrapper.
readonly BLOCK_EXIT=2

# --- secret scanner ---------------------------------------------------------
# Reads a unified diff (-U0) on stdin, prints "file:line" for every added line
# that looks like a secret, and exits non-zero if any were found. Never prints
# the secret value itself (printing it would re-leak it into logs/terminal).
scan_diff() {
    awk '
        # Returns true only when the *captured secret value* is itself a known
        # placeholder/synthetic literal. The match is ANCHORED to the whole value
        # — not a substring — so a real high-entropy secret that merely *contains*
        # a placeholder word (e.g. a 28-char value with "fake" buried inside) is
        # NOT exempted. A value is a placeholder only when it is exactly a known
        # placeholder token, or is composed solely of a placeholder word plus
        # surrounding marker chars (underscores, dashes, "here", digits) — i.e.
        # it carries no real entropy.
        function is_placeholder(val,   lc) {
            lc = tolower(val)
            # The canonical all-zero UUID (Plaid demo token) as a whole value.
            if (lc ~ /^(access|public|link)-(sandbox|development|production)-0+(-0+)*$/)
                return 1
            # The entire value is a placeholder word, optionally wrapped in
            # marker affixes like your_, _here, dashes, or trailing digits.
            return lc ~ /^[_-]*(example|placeholder|replace(_?me)?|synthetic|fixture|dummy|fake|sample|xxxx+|redacted|ci_smoke(_?secret)?|test_?secret|changeme|your_[a-z0-9_]*|[a-z0-9_]*_here)[_-]*[0-9]*$/
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

            # Secret/client-id assignments: snake_case, camelCase, AND the
            # official Plaid hyphenated header / bare body-field spellings — so
            # plaid_secret / plaidSecret / PLAID-SECRET: / client_secret /
            # bare "secret": / "client_secret": are all caught. The key is
            # word-bounded so "mysecret" / "secretsManager" do not trip the bare
            # "secret" form, and the value must be 20+ unbroken chars.
            if (match(lc, /(^|[^a-z0-9_])(plaid[_-]?secret|plaid[_-]?client[_-]?id|client[_-]?secret|client[_-]?id|secret)[ "'"'"']*[:=][ "'"'"']*[a-z0-9_-]{20,}/)) {
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
    # Fixtures are ASSEMBLED AT RUNTIME from fragments so this script's own
    # tracked source contains no literal secret-shaped token — otherwise the gate
    # would flag its own outgoing patch and force developers to bypass the very
    # gate being introduced. `hex` is a fake-but-format-valid 28-char value; the
    # token/bearer fixtures are likewise concatenated, never written whole.
    local hex="ab12cd34ef56ab78cd90ef12ab34"
    local uuid="a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d"
    local plaid_token="access-production-${uuid}"
    local bearer; bearer="abcdef0123456789$(printf '%s' abcdef0123456789abcd)"
    # A high-entropy value that *contains* a placeholder word ("fake") — also
    # assembled from fragments so this source carries no literal secret token.
    local word_bearing; word_bearing="abcdef$(printf '%s' fake)abcdeffakeabcdeffake"
    # Synthetic, fake-but-format-valid secrets — must be FLAGGED. Covers the
    # camelCase plaidSecret spelling, a comment-decoy line ("// not a sample"),
    # and a secret that *contains* the word "fake" (the substring-bypass case).
    positives="+let token = \"${plaid_token}\"
+PLAID_SECRET=${hex}
+Authorization: Bearer ${bearer}
+let plaidSecret = \"${hex}\"
+let clientSecret = \"${hex}\" // not a sample
+PLAID_SECRET=${word_bearing}
+PLAID-SECRET: ${hex}
+\"secret\": \"${hex}\""
    positive_count=8
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

# Emit the per-commit patches for one push range on stdout. Scans EVERY commit
# in the range — including merge side-branch commits — by NOT passing
# --first-parent/--no-merges (those skip exactly the side-branch commits that a
# post-merge push still sends). `git log -p -U0` per-commit also closes the gap
# where a secret added then removed across the range is invisible to the
# endpoint `git diff A..B` yet still rides along in the earlier commit object.
#
# Exit status is the git status: a failure here (e.g. a remote object absent
# from a stale clone) must propagate so the caller can FAIL CLOSED rather than
# read it as an empty/clean finding set.
emit_range_patches() {
    # -m shows each merge commit's diff against its parents, so a secret added
    # ONLY during conflict resolution (present in the merge commit but in
    # neither parent) is still scanned. Non-merge commits are unaffected. The
    # 2-way per-parent diffs stay in the standard format scan_diff parses.
    git log -p -m --no-color -U0 "$@"
}

# Resolve the list of ranges (each an array of git-rev args) to scan.
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
# Each element is a NUL-free, space-joined git-rev argument list. We re-split on
# spaces at scan time (the only tokens are oids and `--not --remotes` flags).
ranges=()
range_tips=()   # local OID for ranges[i] — used for the local-only fail-closed retry
pushed_tips=()
stdin_had_refs=0
stdin_refs=""
if [[ ! -t 0 ]]; then
    stdin_refs="$(cat 2>/dev/null || true)"
fi

if [[ -n "$stdin_refs" ]]; then
    while read -r local_ref local_oid _remote_ref remote_oid; do
        [[ -z "${local_ref:-}" ]] && continue
        stdin_had_refs=1
        if [[ "$local_oid" == "$ZERO_OID" ]]; then
            # Branch deletion — no commits travel, nothing to scan.
            continue
        fi
        pushed_tips+=("$local_oid")
        range_tips+=("$local_oid")
        if [[ "$remote_oid" == "$ZERO_OID" ]]; then
            # New remote ref: scan every commit reachable from local that is not
            # already on any other remote ref (avoids re-scanning all history).
            ranges+=("${local_oid} --not --remotes")
        else
            ranges+=("${remote_oid}..${local_oid}")
        fi
    done <<< "$stdin_refs"
fi

# Only fall back to a HEAD-derived range when stdin supplied NO refs at all. If
# stdin DID supply refs but they were all deletions (ranges empty), there is
# genuinely nothing to scan — do not fall back to scanning the current HEAD,
# which would block `git push origin :old-branch` on unrelated history.
if [[ ${#ranges[@]} -eq 0 && "$stdin_had_refs" -eq 0 ]]; then
    range="HEAD"
    if up="$(git rev-parse --abbrev-ref --symbolic-full-name '@{push}' 2>/dev/null)" \
        && git rev-parse --verify "$up" >/dev/null 2>&1; then
        range="${up}..HEAD"
    elif git rev-parse --verify origin/main >/dev/null 2>&1; then
        range="origin/main..HEAD"
    fi
    ranges+=("$range")
    range_tips+=("HEAD")
fi

if [[ ${#ranges[@]} -eq 0 ]]; then
    # Delete-only push (or nothing being added): no commits travel, so there is
    # nothing to scan AND nothing to build. Exit clean here rather than fall
    # through to the strict build, which would block `git push origin :branch`
    # on the current checkout's unrelated build state.
    echo "pre-push-gate: no commits in this push to scan or build (deletion only). Push allowed." >&2
    exit 0
fi

echo "pre-push-gate: scanning ${#ranges[@]} push range(s) per-commit for secrets..." >&2
findings=""
# Guard the expansion: under `set -u`, "${ranges[@]}" on an empty array is an
# unbound-variable error in older bash (e.g. macOS's bash 3.2). A delete-only
# push legitimately leaves `ranges` empty.
for i in "${!ranges[@]}"; do
    range="${ranges[$i]}"
    range_tip="${range_tips[$i]}"   # the pushed (local) OID for this range
    # $range carries oids and possibly `--not --remotes`; deliberate splitting.
    # shellcheck disable=SC2086
    set -- $range
    # Capture patches and the git exit status separately. A git failure (e.g. a
    # remote object missing from a stale clone on a force-push) must FAIL CLOSED:
    # we retry with a LOCAL-ONLY range built from the pushed tip, else block the
    # push rather than treat an unreadable range as clean.
    if ! patches="$(emit_range_patches "$@" 2>/dev/null)"; then
        # Retry the pushed tip alone, excluding everything already on a remote we
        # DO have — depends only on local objects. NOTE: use $range_tip, not $1:
        # for an existing-ref "remote..local" range, $1 is the whole unreadable
        # range string, so retrying with it would just fail again.
        if ! patches="$(emit_range_patches "$range_tip" --not --remotes 2>/dev/null)"; then
            findings+="  [range: $range]"$'\n'"  UNREADABLE: could not compute the push range (failing closed)."$'\n'
            continue
        fi
    fi
    range_findings="$(printf '%s' "$patches" | scan_diff || true)"
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
    exit "$BLOCK_EXIT"
fi

if [[ "${PLAIDBAR_GATE_SKIP_BUILD:-0}" == "1" ]]; then
    echo "pre-push-gate: build skipped (PLAIDBAR_GATE_SKIP_BUILD=1)" >&2
    exit 0
fi

# The build can only validate the WORKING TREE that is checked out — it cannot
# build an arbitrary pushed ref. If the push targets a ref whose tip is not the
# current HEAD (e.g. `git push origin other-branch`), building the current
# checkout would give a misleading pass for code that is not what is shipping.
# In that case skip the build with a clear warning so CI remains the source of
# truth for the pushed ref, rather than asserting a false green.
if [[ "${#pushed_tips[@]}" -gt 0 ]]; then
    head_oid="$(git rev-parse HEAD 2>/dev/null || echo)"
    # Require EVERY pushed tip to be the current HEAD. A mixed push such as
    # `git push origin HEAD other-branch` must NOT be validated by building only
    # the current checkout: other-branch points at a different tree the build
    # never sees. If any tip differs, skip and let CI validate the pushed refs.
    all_tips_are_head=1
    for tip in "${pushed_tips[@]}"; do
        if [[ "$tip" != "$head_oid" ]]; then
            all_tips_are_head=0
            break
        fi
    done
    if [[ "$all_tips_are_head" -eq 0 ]]; then
        echo "pre-push-gate: a pushed ref is not the current checkout — skipping the" >&2
        echo "  strict build (it would only validate the current tree). CI must" >&2
        echo "  validate the pushed ref(s). Secret scan above covered all pushed commits." >&2
        exit 0
    fi
fi

# The build validates the WORKING TREE on disk, not the exact pushed commit. In
# a hook run, if tracked files differ from HEAD an uncommitted local fix could
# mask a strict-concurrency failure in the commit actually being pushed and yield
# a false "passed". Skip in that case (untracked files don't affect the build);
# a manual run still builds whatever is checked out, which is the intent.
if [[ "$stdin_had_refs" -eq 1 ]] && ! git diff --quiet HEAD -- 2>/dev/null; then
    echo "pre-push-gate: working tree has uncommitted changes vs HEAD — skipping the" >&2
    echo "  strict build (it would not reflect the exact pushed commit). Commit or" >&2
    echo "  stash to run it locally; CI validates the pushed commit either way." >&2
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
    exit "$BLOCK_EXIT"
fi
