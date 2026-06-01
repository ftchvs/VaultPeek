# PlaidBar Autonomous Roadmap

This roadmap guides the recurring local agent loop that keeps PlaidBar moving
toward a trustworthy 1.0 release. It complements `GOAL.md`,
`commands/goal.md`, and `docs/v1.0-roadmap.md`.

## Operating Contract

- Work locally for implementation and verification.
- Felipe granted scoped PlaidBar approval on 2026-05-30 to push branches, open
  PRs, and merge to remote `main` after green local and GitHub checks.
- Do not publish releases or post externally outside normal GitHub PR/merge
  workflow without Felipe's explicit approval.
- Keep each loop to one reviewable production-readiness slice.
- Prefer fixes that make the 1.0 promise more true: local-first trust,
  reliable onboarding, clear recovery, and dense native finance UX.
- Commit only when local verification passes or baseline limitations are
  documented.
- Leave the branch reviewable after every run.

## Loop Cadence

The OpenClaw cron job `d6eb6833-969a-4436-af06-0fd0f1bd94e2` runs an isolated
PlaidBar production-readiness loop every four hours. Each run should:

1. Inspect `git status --short --branch` and recent commits.
2. Read `GOAL.md`, `docs/v1.0-roadmap.md`, this file, and the touched area.
3. Pick the highest-leverage unfinished slice from the backlog below.
4. Implement the smallest coherent change.
5. Run the relevant gates.
6. Use Clawpatch or manual review for changed surfaces.
7. Commit locally with a focused conventional commit when safe.
8. Report branch, commits, checks, known limitations, and next slice.

## Always-Run Gates

- `git diff --check`
- `swift build --target PlaidBar --skip-update --disable-keychain`
- `swift build --target PlaidBarServer --skip-update --disable-keychain` when
  server, shared DTO, or package code changes
- Secret scan from `commands/plaidbar-prod-loop.md`

Use `swift test --skip-update --disable-keychain` when the local Swift toolchain
supports the `Testing` module. On this machine, the current baseline is
`no such module 'Testing'`; record that limitation instead of treating it as a
new regression.

## Backlog

### Progress Ledger

Completed production-readiness slices:

- 2026-05-30: moved notification trigger selection into `PlaidBarCore`.
- 2026-05-30: moved transaction filtering into `PlaidBarCore`.
- 2026-05-30: recorded scoped approval to push branches, open PRs, and merge
  green PlaidBar PRs to remote `main`.
- 2026-05-30: moved spending period summaries, category rollups, and recurring
  monthly totals into `PlaidBarCore`.
- 2026-05-30: clarified recurring empty states for server offline, no linked
  bank, no synced transactions, and no recurring charges found.
- 2026-05-30: reused the shared credit utilization summary in the credit tab.
- 2026-05-30: routed spending trend and income/expense charts through the
  shared expense filter.
- 2026-05-31: clarified dashboard status and recovery context, including
  spending empty states and server config preservation during local reset.
- 2026-05-31: moved account-detail title, subtitle, and available-balance
  presentation rules into `PlaidBarCore`.
- 2026-05-31: reused shared credit balance and utilization presentation in
  credit rows.
- 2026-05-31: expanded transaction detail source context with merchant, raw
  name, and category/source rows.
- 2026-05-31: improved transaction filter/search VoiceOver labels.
- 2026-05-31: added recurring charge next-date, match-count, and confidence
  context.
- 2026-05-31: hardened local data reset so preserved config files keep private
  permissions.
- 2026-05-31: surfaced invalid URL and browser-open failures for item reconnect
  flows.
- 2026-05-31: refreshed the roadmap progress ledger for the autonomous loop.
- 2026-05-31: improved VoiceOver summaries for dashboard error dismissal,
  status diagnostics, Plaid item status rows, and Settings account rows.
- 2026-05-31: added VoiceOver labels for dashboard account filter chips,
  drill-down rows, selected account signal pills, and mini activity rows.
- 2026-05-31: added VoiceOver summaries for spending trend, income/expense,
  and standalone heatmap chart signals.
- 2026-06-01: clarified first-run partial-sync and uncommitted-sync recovery
  states.
- 2026-06-01: added VoiceOver labels and recovery hints for setup preflight
  rows.
- 2026-06-01: made onboarding missing-credential failures explicit before
  opening Plaid Link.
- 2026-06-01: labeled credit utilization status in summary and account
  accessibility surfaces.
- 2026-06-01: labeled dashboard credit utilization status in account rows and
  selected details.
- 2026-06-01: aligned credit utilization status icons and dashboard tinting
  with the configured warning threshold.

### Reliability And Trust

1. Continue moving duplicated UI/service formulas into `PlaidBarCore` helpers
   where they still exist, especially chart totals, credit/debt presentation,
   and account detail summary logic.
2. Harden local storage and token handling:
   pre-open SQLite permissions, Keychain fallback copy, reset behavior, and
   private-file invariants.
3. Make sandbox and production setup failures explicit:
   wrong mode, missing credentials, browser-open failure, and first-sync
   partial completion.
4. Keep status/reconnect paths available from dashboard, settings, and account
   detail surfaces.

### Product Polish

1. Improve empty and filtered-zero states for transactions, recurring charges,
   credit, and account drill-down.
2. Keep the dashboard compact and RepoBar-like:
   heatmap first, dense rows, status-rich selected detail, no marketing chrome.
3. Refresh demo fixtures and screenshots when UI behavior changes.
4. Improve accessibility labels for icon-only controls and chart/status signals.

### Distribution And Open Source

1. Keep README, troubleshooting, privacy, security, release notes, and QA matrix
   aligned with actual behavior.
2. Verify Homebrew formula syntax and source-build path after packaging changes.
3. Maintain a release checklist that is honest about notarization, Plaid
   production approval, and local data boundaries.

## Stop Conditions

Stop the current loop and report when:

- Verification fails on a likely regression.
- A required decision would change product/security scope.
- A clean local commit is made and the next slice is independent.
- The branch contains user changes that conflict with the planned edit.

Do not stop merely because more roadmap work remains.
