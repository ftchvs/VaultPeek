---
description: Run the PlaidBar autonomous production-readiness loop with focused implementation, verification, PR review, and safe handoff.
argument-hint: "[focus area] [--hours=2-4] [--no-commit]"
---

# /plaidbar-prod-loop

Use this command to keep improving PlaidBar toward a production-ready,
local-first macOS finance utility through the 100+ task backlog in
`docs/autonomous-loop-backlog.md`.

When another local agent is active, also follow
`docs/agent-collaboration.md` for worktree ownership, PR handoff, and
autonomous merge gates.

The default goal is:

> Make PlaidBar feel like RepoBar for personal finance: a native macOS menu-bar
> instrument with a GitHub-style heatmap header, dense account/card rows,
> financial scope filters, and drill-in details for each account.

## Usage

```bash
/plaidbar-prod-loop
/plaidbar-prod-loop "local data controls" --hours=2
/plaidbar-prod-loop "empty states and error recovery" --hours=3 --no-commit
/plaidbar-prod-loop "RepoBar-style finance dashboard" --hours=4
```

For Codex CLI non-interactive runs:

```bash
codex exec --cd /Users/otto/.openclaw/workspace/repos/PlaidBar \
  "$(cat commands/plaidbar-prod-loop.md)"
```

For a focused autonomous iteration:

```bash
codex exec --cd /Users/otto/.openclaw/workspace/repos/PlaidBar \
  "Read commands/plaidbar-prod-loop.md and complete the next unfinished task from docs/autonomous-loop-backlog.md for: <focus>"
```

For parallel review support, keep one primary editor agent and use optional
read-only parallel agents for design, security/privacy, and QA. Parallel agents
may inspect files and propose findings; the primary agent owns edits, commits,
PR creation, and merge-safety decisions.

## Operating Boundaries

- Work locally by default. Use the scoped PlaidBar approval in
  `docs/autonomous-roadmap.md` for push, PR, and merge only when the current
  run is clearly inside that scope and the safe PR loop below passes.
- When using repo-local `.codex/skills/`, follow their safe PR/check/review
  gate; do not merge if any approval scope or safety condition is unclear.
- Do not add telemetry, cloud sync, hosted backend, multi-user features, or
  cloud AI over private transaction data.
- Preserve local-first boundaries: app, localhost server, Plaid API, local
  storage, and no PlaidBar-owned cloud service.
- Optional AI must be local-only, off by default, explainable, reversible, and
  non-blocking when no local model runtime is configured.
- Do not claim token encryption, notarization, or production security properties
  unless the implementation actually provides them.
- Do not commit screenshots, logs, build products, local databases, or secrets.
- Keep every slice reviewable: one coherent product improvement at a time.

## Long-Run Loop

Run for the requested timebox, defaulting to 2 hours and stopping at 4 hours.
Repeat these phases until the timebox ends or a blocker appears:

1. Sync and inspect:
   - `git status --short --branch`
   - `git fetch origin main`
   - If on `main`, create a feature branch named
     `feature/<short-production-readiness-topic>`.
   - Read `GOAL.md`, `README.md`, `DESIGN.md`, `docs/architecture.md`, and
     recent changed files before editing.

2. Pick the highest-leverage next task:
   - Prefer the explicit focus area in `$ARGUMENTS`.
   - Otherwise use `docs/autonomous-loop-backlog.md`.
   - When the current slice is loop governance, first audit the backlog for
     stale tasks, duplicate tasks, completed-but-unchecked items, and tasks that
     no longer match PlaidBar's local-first product boundary.
   - Treat one backlog task as one autonomous iteration.
   - Combine adjacent tasks from the same PR slice only when the diff remains
     small enough to finish with verification evidence.
   - If the focus mentions RepoBar, heatmap-first design, account rows, or the
     attached screenshot, use the RepoBar-style finance dashboard slice first.

3. Implement:
   - Follow the app's existing SwiftUI, theme, and local-server patterns.
   - Put finance calculations in `PlaidBarCore` when they are testable logic.
   - Keep UI minimalist, dense, native, status-rich, and non-marketing.
   - For the main popover, prefer a single overview surface with drill-in
     details over adding another tab.
   - Keep risky actions explicit and confirmation-gated.
   - Keep local AI optional and local-only; never send private financial data to
     cloud AI services.
   - Update docs only when behavior or setup changes.

4. Verify:
   - Always run `git diff --check`.
   - Run the smallest meaningful Swift gate:
     `swift build --target PlaidBar --skip-update --disable-keychain`.
   - Run focused tests when core/server logic changes.
   - Run the secret scan in this command before reporting success.
   - Note known baseline warnings instead of hiding them.

5. Commit or stage:
   - If `--no-commit` is absent and verification passes, create one focused
     conventional commit.
   - If verification fails from a pre-existing baseline issue, document it and
     keep the branch reviewable.

6. Run the PR/check/review/merge loop when scoped approval applies:
   - Push only the focused branch for the completed task or PR slice.
   - Open or update a PR with task ID(s), changed files, local checks,
     secret-scan result, privacy/security impact, and known limitations.
   - Wait for GitHub checks; do not merge with failing, pending, skipped, or
     ambiguous required checks.
   - Review the final diff before merge for secrets, real financial data,
     scope creep, generated artifacts, destructive behavior, and local-first
     boundary violations.
   - Merge only when local gates passed, GitHub checks are green, the diff is
     safe under the existing scoped approval, and no user decision is needed.
   - After merge, verify remote `main` moved as expected, then record the
     completed task ID in the roadmap ledger.

7. Report progress:
   - Every 30-45 minutes, summarize changed files, validation, and next slice.
   - End with branch name, commit SHA(s), checks, and whether it is ready for
     push, PR, review, or merge.

## Production-Readiness Backlog

Use `docs/autonomous-loop-backlog.md` as the concrete backlog. It contains 120
reviewable tasks grouped into PR slices covering:

- minimalist modern design and RepoBar-style dashboard polish,
- account rows, heatmaps, drill-in surfaces, empty states, and reconnect flows,
- local data controls, token/storage safety, auth, status redaction, logs,
  screenshots, and fixture safety,
- demo, sandbox, production setup, accessibility, performance, and QA gates,
- optional local AI boundaries, local-only insights, and reversible
  categorization suggestions,
- PR, review, check, and merge hygiene.

If a task appears stale, first inspect the current implementation. Complete it
only if there is still a real gap; otherwise mark the task as already satisfied
in the roadmap ledger with evidence.

During loop-governance passes, remove or consolidate stale and duplicate backlog
tasks only after recording evidence in `docs/autonomous-roadmap.md`; otherwise
leave questionable tasks in place and report the uncertainty instead of hiding
scope.

## Design Standard

PlaidBar should feel like a compact financial instrument:

- At-a-glance status first.
- Dense but calm layout.
- Finance colors carry meaning, not decoration.
- Every risky action has explicit copy and confirmation.
- Every error state says what happened and what to do next.
- Keyboard and accessibility behavior must not regress.

## Verification Commands

Run from the repository root:

```bash
git diff --check
swift build --target PlaidBar --skip-update --disable-keychain
rg -n "(PLAID_SECRET|client_secret|access_token|sk-|ghp_|github_pat_|BEGIN (RSA|OPENSSH|EC) PRIVATE KEY|api[_-]?key)" \
  README.md GOAL.md CHANGELOG.md SECURITY.md DESIGN.md PRD.md docs Sources Tests commands .codex
```

For core logic changes, also run focused tests where the local Swift toolchain
supports them. If `swift test --enable-swift-testing` fails with the known
`no such module 'Testing'` baseline issue, record that explicitly.

## Done Criteria

A run is complete only when it leaves the repo in one of these states:

- clean branch with one or more focused commits and passing local gates, or
- documented blocker with no half-finished edits.

Final report must include:

- branch name
- commit SHA(s), if any
- changed files
- validation commands and results
- known warnings or blockers
- recommended next slice
- push/PR/review/merge status
