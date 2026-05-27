---
description: Run a multi-hour PlaidBar production-readiness loop with focused implementation, verification, and handoff.
argument-hint: "[focus area] [--hours=2-4] [--no-commit]"
---

# /plaidbar-prod-loop

Use this command to keep improving PlaidBar toward a production-ready,
local-first macOS finance utility.

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

## Operating Boundaries

- Work locally unless Felipe explicitly approves pushing or opening a PR.
- Do not merge PRs from this command.
- Do not add telemetry, cloud sync, hosted backend, or multi-user features.
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
   - Read `GOAL.md`, `README.md`, `DESIGN.md`, `ARCHITECTURE.md`, and recent
     changed files before editing.

2. Pick the highest-leverage next slice:
   - Prefer the explicit focus area in `$ARGUMENTS`.
   - Otherwise use the production-readiness backlog below.
   - Keep the slice small enough to finish with verification evidence.
   - If the focus mentions RepoBar, heatmap-first design, account rows, or the
     attached screenshot, use the RepoBar-style finance dashboard slice first.

3. Implement:
   - Follow the app's existing SwiftUI, theme, and local-server patterns.
   - Put finance calculations in `PlaidBarCore` when they are testable logic.
   - Keep UI dense, native, status-rich, and non-marketing.
   - For the main popover, prefer a single overview surface with drill-in
     details over adding another tab.
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

6. Report progress:
   - Every 30-45 minutes, summarize changed files, validation, and next slice.
   - End with branch name, commit SHA(s), checks, and whether it is ready for
     Felipe to approve push/PR.

## Production-Readiness Backlog

Work in this order unless Felipe gives a better focus:

1. **RepoBar-style finance dashboard**
   - Study RepoBar's live app/site and source before editing:
     - `https://repobar.app`
     - `https://github.com/steipete/RepoBar`
     - local clone if available: `/Users/otto/.openclaw/workspace/repos/RepoBar`
   - Target the attached reference screenshot:
     - translucent macOS popover,
     - heatmap header,
     - segmented filter bar,
     - dense rows with selected/highlighted state,
     - chevron/drill-in affordance.
   - Translate RepoBar concepts into finance:
     - contribution heatmap -> daily spend/cashflow heatmap,
     - repo rows -> checking, savings, credit card, loan, and other account rows,
     - repo stats -> balance, available credit, utilization, pending count, sync freshness,
     - repo submenu -> account/card detail view or sheet,
     - All/Pinned/Local/Work -> All/Cash/Credit/Savings/Debt/Status.
   - Build the first slice as an overview UI, not a full budgeting product:
     - top heatmap from existing transaction/demo data,
     - filterable account/card rows,
     - one selected row detail surface for a specific credit card/account,
     - preserve Status/Settings recovery actions.

2. **Trust-first local data controls**
   - Show the local storage path (`~/.plaidbar/`) in Settings.
   - Add copy/reveal actions for the storage directory when practical.
   - Add confirmation-gated reset/delete local data flow.
   - Keep language explicit about what is removed and what remains in Plaid.

3. **Sharper empty and error states**
   - Accounts: no server, no linked institution, no synced account data.
   - Transactions: no synced history vs filters returning zero results.
   - Credit: no linked credit accounts vs data unavailable.
   - Include one clear recovery action per state.

4. **Server/config preflight**
   - Add a server endpoint or client helper that reports environment,
     credential readiness, storage path, item count, and sync readiness.
   - Use it before Plaid Link and in the Status tab.
   - Avoid exposing secrets or raw tokens.

5. **Reconnect and degraded-item handling**
   - Surface item errors and token-expired states in the Status tab.
   - Provide a clear reconnect/add-account path.

6. **Demo and screenshot polish**
   - Keep demo data realistic but synthetic.
   - Ensure screenshots show the current product story:
     menu summary, status, spending heatmap, onboarding, and settings.

7. **Distribution readiness, later**
   - Only after sandbox and production setup are reliable.
   - Focus on packaging docs, signing assumptions, and release checklist.
   - Do not implement notarization prematurely.

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
  README.md GOAL.md CHANGELOG.md SECURITY.md ARCHITECTURE.md DESIGN.md PRD.md Sources Tests commands .codex
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
- whether push/PR approval is needed
