# PlaidBar Autonomous Roadmap

This roadmap guides the recurring local agent loop that keeps PlaidBar aligned
with its local-first menu bar finance vision. It complements `GOAL.md`,
`commands/goal.md`, `commands/plaidbar-prod-loop.md`, the concrete backlog in
`docs/autonomous-loop-backlog.md`, and the long-term product brief in
`docs/v1.0-roadmap.md`.

## Operating Contract

- Work locally for implementation and verification.
- Felipe granted scoped PlaidBar approval on 2026-05-30 to push branches, open
  PRs, and merge to remote `main` after green local and GitHub checks. Use that
  approval only for focused PlaidBar work with a safe final diff review.
- Do not publish releases or post externally outside normal GitHub PR/merge
  workflow without Felipe's explicit approval.
- Keep each loop to one reviewable production-readiness slice.
- Split broad refactors when they cross more than one module boundary; one PR
  should be reviewable as a single boundary move, presenter extraction, UI
  surface change, server/API change, storage change, or docs/governance change.
- Prefer fixes that make the 1.0 promise more true: local-first trust,
  reliable onboarding, clear recovery, and dense native finance UX.
- Preserve the privacy boundary: no PlaidBar-hosted backend, telemetry, cloud
  sync, multi-user accounts, or cloud AI over private transaction data.
- Keep optional local AI local-only, off by default, explainable, reversible,
  and non-blocking when no local model runtime is configured.
- Commit only when local verification passes or baseline limitations are
  documented.
- Leave the branch reviewable after every run.

## Loop Cadence

The OpenClaw cron job `d6eb6833-969a-4436-af06-0fd0f1bd94e2` runs an isolated
PlaidBar production-readiness loop every four hours. Each run should:

1. Inspect `git status --short --branch` and recent commits.
2. Read `GOAL.md`, `commands/plaidbar-prod-loop.md`,
   `docs/autonomous-loop-backlog.md`, this file, and the touched area.
3. Pick the highest-leverage unfinished task ID from the backlog.
4. Implement the smallest coherent change; combine adjacent task IDs only when
   the PR remains easy to review.
5. Run the relevant local gates.
6. Use Clawpatch, manual review, or read-only parallel agents for changed
   surfaces.
7. Commit locally with a focused conventional commit when safe.
8. If scoped approval applies, run the PR/check/review/merge loop below.
9. Report branch, commits, checks, known limitations, completed task IDs, and
   next task ID.

## Codex CLI And Parallel Agents

- `commands/plaidbar-prod-loop.md` is the canonical Codex CLI prompt.
- Use one primary editor agent for all writes, commits, PR updates, and merge
  decisions.
- Use optional read-only parallel agents for design, security/privacy, QA, or
  docs review. They should return findings and suggested tests, not edit the
  same files in parallel.
- Prefer focused search and file reads over speculative repo-wide rewrites.
- Do not run parallel push or merge attempts.

## PR, Check, Review, And Merge Loop

Use this loop only when the current run is inside the 2026-05-30 scoped
PlaidBar approval. If approval scope, product safety, or security impact is
unclear, stop and ask Felipe.

1. Push only the focused branch for the completed task or PR slice.
2. Open or update a PR with task ID(s), changed files, local verification,
   secret-scan result, privacy/security impact, screenshots when relevant, and
   known limitations.
3. Wait for required GitHub checks. Do not merge with failing, pending,
   skipped, cancelled, missing, or ambiguous required checks.
4. Read the final diff before merge. Block merge for secrets, real financial
   data, raw Plaid identifiers, scope creep, generated artifacts, unsafe
   destructive behavior, or local-first boundary violations.
5. Merge only when local gates passed, GitHub checks are green, the diff is
   safe under the scoped approval, and no user decision is needed.
6. After merge, verify remote `main` moved as expected and record completed
   task ID(s) in the progress ledger.

## Always-Run Gates

- `git diff --check`
- `swift build --target PlaidBar --skip-update --disable-keychain`
- `swift build --target PlaidBarServer --skip-update --disable-keychain` when
  server, shared DTO, or package code changes
- Secret scan from `commands/plaidbar-prod-loop.md`

Use `swift test --skip-update --disable-keychain` when the local Swift toolchain
supports the `Testing` module. As of 2026-06-10 the local toolchain builds and
runs the full Swift Testing suite (`swift test` passes, 276+ tests), so test
runs are expected locally; if a machine hits `no such module 'Testing'`, record
that limitation instead of treating it as a new regression.

## Progress Ledger

Completed production-readiness slices:

Use `[T###]` after the date for completed backlog task IDs, for example
`2026-06-07 [T001]: ...`. Legacy entries without a mapped backlog task ID may
remain unmarked.

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
- 2026-06-01: reported the local storage directory, not the SQLite file, in
  status preflight and sandbox smoke checks.
- 2026-06-01: aligned Settings local-data copy with the server storage
  directory contract.
- 2026-06-01: covered server-reported storage directory path resolution in
  `PlaidBarCore`.
- 2026-06-01: shared balance composition totals through `PlaidBarCore`.
- 2026-06-01: moved account row amounts, subtitles, and accessibility summary
  composition into `PlaidBarCore`.
- 2026-06-07 [T001]: documented the completed-task marker convention for
  autonomous roadmap ledger entries; evidence: docs-only roadmap update.
- 2026-06-07 [T002]: expanded the pull request template with task IDs,
  local gates, GitHub checks, privacy impact, and merge safety sections;
  evidence: `.github/pull_request_template.md` checklist update.
- 2026-06-07 [T007]: replaced decorative balance-mix gradients with semantic
  flat account-type color, a lighter panel fill, and a separator in the main
  dashboard surface; evidence: `Sources/PlaidBar/Views/MainPopover.swift` UI
  update.
- 2026-06-07 [T003]: added an explicit reviewer checklist for local-first
  boundaries, secret exposure, readiness metadata, optional local AI behavior,
  and synthetic-only public artifacts; evidence:
  `.github/pull_request_template.md` checklist update.
- 2026-06-07 [T004]: added a module-boundary split rule for broad refactors in
  the autonomous loop selection rules and operating contract; evidence:
  `docs/autonomous-loop-backlog.md` and `docs/autonomous-roadmap.md` updates.
- 2026-06-07 [T005]: added a recurring loop-governance audit for stale,
  duplicate, completed-but-unchecked, and product-boundary-mismatched backlog
  tasks; evidence: `docs/autonomous-loop-backlog.md` and
  `commands/plaidbar-prod-loop.md` updates.
- 2026-06-07 [T008]: normalized dashboard account-row and selected-detail
  spacing through compact row design tokens; evidence:
  `Sources/PlaidBar/Theme/DesignTokens.swift` and
  `Sources/PlaidBar/Views/MainPopover.swift` updates.
- 2026-06-07 [T006]: inventoried popover surfaces that still risk feeling
  tab-heavy or card-heavy; evidence: `DESIGN.md` popover surface inventory.
- 2026-06-07 [T009]: tightened the dashboard heatmap label group while
  preserving the 365-day spending and cashflow meaning; evidence:
  `Sources/PlaidBar/Views/MainPopover.swift` UI copy update.
- 2026-06-07 [T010]: refreshed the public-safe screenshot evidence for the
  minimalist dashboard, setup preflight, and Settings surfaces, and made the
  screenshot script capture PlaidBar windows by window ID instead of stale
  display rectangles; evidence: `Assets/*.png` screenshot refresh and
  `Scripts/screenshots.sh` capture update.
- 2026-06-07 [T014]: added a first-overview fallback banner for the no demo/no
  synced data path so setup recovery does not render an empty heatmap as the
  primary state; evidence: `DashboardOverviewFallbackState` and app tests.
- 2026-06-07 [T013]: preserved account, activity, credit, and status surfaces
  as selected-row drill-in affordances instead of competing first-level tabs;
  evidence: `DashboardDrillInSurface` and selected-account rail tests.
- 2026-06-07 [T012]: grouped the 365-day activity heatmap, account filter bar,
  account rows, and selected-account detail into a single dashboard overview
  flow; evidence: `Sources/PlaidBar/Views/MainPopover.swift` overview stack
  update.
- 2026-06-07 [T011]: expanded the first popover overview cards so the dashboard
  answers cash, credit, recent spend, sync health, and action-needed status
  before deeper account drill-ins; evidence:
  `Sources/PlaidBar/Views/MainPopover.swift`.
- 2026-06-07 [T015]: verified the dashboard overview against a 660-point
  realistic menu-bar popover height budget with selected-row drill-in tests;
  evidence: `DashboardOverviewHeightBudget` and app tests.
- 2026-06-07 [T016]: confirmed heatmap spend and net-cashflow semantics stay
  distinguishable through shared mode labels, descriptions, and a focused core
  test; evidence: `SpendingHeatmapMode` labels and
  `heatmapModeLabelsDistinguishSemantics`.
- 2026-06-07 [T017]: added strongest recent heatmap signal summaries for
  VoiceOver so high-spend, income, and outflow days are exposed without cell-by-cell
  scanning; evidence: `SpendingHeatmapSignal` and core tests.
- 2026-06-07 [T018]: split heatmap empty copy between missing synced data and
  filtered-zero spend/cashflow states so empty tiles do not incorrectly imply
  sync is missing; evidence: `SpendingHeatmapEmptyPresentation` and core tests.
- 2026-06-07 [T019]: moved heatmap cell intensity into a focused core helper
  with clamp/empty-day tests, keeping the SwiftUI cell on the same presentation
  rule; evidence: `SpendingHeatmap.cellIntensity` and core tests.
- 2026-06-08 [T116]: made cross-agent PR handoff operational by adding agent
  coordination fields to the PR template, explicit GitHub/Linear/repo-doc/local
  state channels, and head-SHA collision checks for autonomous review/merge;
  evidence: `docs/agent-collaboration.md`,
  `docs/agent-coordination-state.example.json`,
  `.github/pull_request_template.md`, `.gitignore`, and
  `commands/plaidbar-prod-loop.md`.
- 2026-06-08 [T021]: audited account-row density across checking, savings,
  credit card, loan, investment, and other rows; evidence: `DESIGN.md`
  documents the shared two-line dashboard row rhythm and follow-up constraints.
- 2026-06-08 [T022]: ensured account rows expose a primary amount, secondary
  account detail, freshness text, and connection status signal outside the
  dashboard drill-in; evidence: `Sources/PlaidBar/Views/AccountsView.swift`.
- 2026-06-08 [T023]: made dashboard credit rows and accessibility summaries
  include utilization, available credit, and an explicit due-metadata state
  without adding a budgeting workflow; evidence:
  `Sources/PlaidBarCore/Utilities/AccountPresentation.swift` and core tests.
- 2026-06-08 [T024]: added a subtle account-row selected state with a low-opacity
  accent fill, narrow leading rail, border, and selected accessibility state;
  evidence: `Sources/PlaidBar/Views/AccountsView.swift`.
- 2026-06-08 [T025]: added focused coverage for the shared account-row
  accessibility presentation helper, including display-safe field boundaries;
  evidence: `Tests/PlaidBarCoreTests/PlaidBarCoreTests.swift`.
- 2026-06-08 [T026]: made account drill-in rows explicitly focusable and gave
  pointer, keyboard, and assistive-technology activation paths shared open/collapse
  copy; evidence: `DashboardAccountDrillInPath`, dashboard row modifiers, and
  core tests.
- 2026-06-08 [T027]: extracted a selected-account drill-in summary that keeps
  transactions, balances, credit limits, freshness, and sync state in one
  display-safe presentation model; evidence: `DashboardAccountDrillInSummary`,
  `MainPopover` selected-account panel wiring, and core tests.
- 2026-06-08 [T028]: added explicit selected-account drill-in actions for
  reconnect, remove, and settings, with destructive remove gated by a
  confirmation dialog; evidence: `DashboardDrillInAction` and selected account
  action bar tests.
- 2026-06-08 [T029]: confirmed selected-account recent-activity empty states
  distinguish no synced transactions, server offline, demo-only empty activity,
  and item recovery states; evidence: `AccountActivityEmptyState` and core
  tests.
- 2026-06-08 [T030]: added display-safe accessibility labels for selected
  account drill-in summaries, status badges, recovery buttons, action controls,
  and empty activity panels; evidence: `DashboardAccountDrillInSummary`,
  `DashboardDrillInAction`, `MainPopover`, and core tests.
- 2026-06-08 [T031]: distinguished the dashboard account empty panel's no-server,
  missing-credentials, no-linked-bank, no-account-data, healthy-status, and
  filtered-zero states; evidence: `DashboardAccountEmptyState`, `MainPopover`,
  and core tests.
- 2026-06-08 [T032]: verified each dashboard account empty panel state has one
  explicit recovery action, including Check Server, Check Credentials, Check
  Status, Reconnect Item, Sync Balances, Refresh, and Refresh Data; evidence:
  `DashboardAccountEmptyState` action titles and core tests.
- 2026-06-08 [T033]: preserved last-known account rows alongside transactions
  in the local cache so transient refresh/balance failures keep usable dashboard
  data scoped by environment and storage path; evidence: `LocalDataStore`
  account cache, `AppState` cache load/save wiring, and server tests.
- 2026-06-08 [T034]: centralized display-safe error sanitization for dashboard,
  setup, secondary empty states, and popover banners so raw server/Plaid
  payloads, token-like values, Plaid identifiers, and stack trace tails are not
  rendered directly; evidence: `UserFacingError`, app error-state wiring, and
  core tests.
- 2026-06-10 [T035]: added focused coverage for the heatmap empty-state
  presenter distinguishing no-synced-data from filtered-zero spend and cashflow
  states; evidence: `heatmapEmptyPresentationDistinguishesStates` core test.
- 2026-06-10 [T036]: verified demo, sandbox, and production setup choices
  explain their data boundaries before Plaid Link opens; evidence: onboarding
  choice subtitles ("Local sample data. No Plaid credentials.", "Plaid test
  institutions.", "Approved Plaid access for real accounts.") and the
  link-prep storage disclosure rows in `Sources/PlaidBar/Views/SetupView.swift`.
- 2026-06-10 [T037] [T038]: moved setup preflight readiness into a display-safe
  `OnboardingPreflight` core presenter so sandbox and production Plaid Link
  stay blocked (button disabled, fail-fast hint shown) while the server is
  offline, in the wrong mode, or missing credentials; the action path keeps the
  same guards in `AppState.connectForOnboarding`; evidence:
  `Sources/PlaidBarCore/Models/OnboardingPreflight.swift` and core tests.
- 2026-06-10 [T039]: confirmed the local storage path is shown before linking
  accounts in both the link-prep disclosure rows and the preflight Storage row,
  now covered by `onboardingPreflightReadyShowsStoragePath`; evidence:
  `SetupView` storage disclosure and `OnboardingPreflight` core test.
- 2026-06-10 [T040]: added unit checks for preflight readiness output covering
  offline, mode-mismatch, missing-credentials, and ready states for sandbox and
  production; evidence: Onboarding Preflight test section in
  `Tests/PlaidBarCoreTests/PlaidBarCoreTests.swift`.

## Backlog Source

Use `docs/autonomous-loop-backlog.md` for new work. It currently defines 120
reviewable tasks across 24 PR slices:

- loop governance, PR hygiene, checks, review, and merge safety
- minimalist modern design, heatmap overview, dense rows, and drill-in surfaces
- empty states, setup preflight, reconnect, status diagnostics, and local data
  controls
- token/storage safety, API auth, status redaction, logs, fixtures, and
  screenshot safety
- demo, sandbox, production setup, accessibility, performance, QA, and release
  readiness
- optional local AI boundaries, local-only insights, and reversible
  categorization suggestions

When a task is completed or found already satisfied, add one dated ledger entry
with the task ID, evidence, and PR or commit reference when available.

## Stop Conditions

Stop the current loop and report when:

- Verification fails on a likely regression.
- A required decision would change product/security scope.
- A clean local commit is made and the next slice is independent.
- The branch contains user changes that conflict with the planned edit.
- GitHub checks are not green or the final diff is not safe to merge under the
  existing scoped approval.

Do not stop merely because more roadmap work remains.
