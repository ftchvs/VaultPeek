# Autonomous Loop Backlog

This backlog is the source of truth for 100+ autonomous PlaidBar
production-readiness iterations. Each task is intended to be independently
reviewable. A PR slice may contain one task or a small contiguous group from
the same section when the diff remains easy to review.

Use this backlog with `commands/goal.md`, `commands/plaidbar-prod-loop.md`,
and `docs/autonomous-roadmap.md`.

## Selection Rules

- Pick the first unfinished task that matches the requested focus.
- If no focus is provided, prefer the earliest unfinished task in the highest
  priority PR slice.
- Keep each iteration local-first, privacy-preserving, and honest about the
  current security model.
- Split broad refactors into separate PRs whenever they cross more than one
  module boundary, unless the boundary-crossing is a mechanical API move that
  cannot be reviewed independently.
- During loop-governance passes, audit this backlog for stale tasks, duplicate
  tasks, completed-but-unchecked items, and tasks that no longer match the
  product boundary; remove or consolidate them only with roadmap evidence.
- Do not add hosted backend, telemetry, cloud sync, multi-user accounts,
  budgeting workflows, or cloud AI over transaction data.
- Optional AI work must be local-only, off by default, explainable, reversible,
  and non-blocking when no local model runtime is configured.
- Merge only through the safe PR loop in `docs/autonomous-roadmap.md`.

## Review Gates For Every Task

- Local diff is scoped to the selected task or PR slice.
- UI changes preserve minimalist modern macOS density: no marketing chrome, no
  decorative gradients, no nested cards, no color without financial meaning.
- Security changes do not expose Plaid secrets, access tokens, public tokens,
  local bearer tokens, account IDs, item IDs, balances, or transactions through
  status, logs, screenshots, or public docs.
- Privacy docs remain true: PlaidBar has no hosted backend, analytics,
  telemetry, tracking, cloud sync, or cloud dashboard.
- Verification evidence is recorded in the commit, PR body, or final report.

## PR Slices And Tasks

### PR-001: Loop Governance And Backlog Hygiene

- [x] T001: Add a progress marker for completed backlog task IDs in the
  autonomous roadmap ledger.
- [x] T002: Add a PR-body template section for task IDs, local gates, GitHub
  checks, privacy impact, and merge safety.
- [x] T003: Add a reviewer checklist for local-first boundaries and secret
  exposure risks.
- [x] T004: Add a rule that broad refactors must be split when they touch more
  than one module boundary.
- [x] T005: Add a recurring audit that removes stale or duplicate backlog tasks.

### PR-002: Minimalist Modern Design Audit

- [x] T006: Inventory popover surfaces that still look tab-heavy or card-heavy.
- [x] T007: Replace decorative visual treatment with semantic spacing,
  separators, and status color in one surface.
- [x] T008: Normalize compact row spacing against the existing design tokens.
- [x] T009: Tighten one verbose label group without hiding financial meaning.
- [x] T010: Add or update screenshot evidence for the changed minimalist surface.

### PR-003: Dashboard Overview Structure

- [x] T011: Ensure the first popover view answers cash, credit, recent change,
  sync health, and action-needed status.
- [x] T012: Keep the heatmap, filter bar, account rows, and selected detail in
  one coherent overview.
- [x] T013: Preserve deeper account, transaction, credit, and status surfaces as
  drill-ins rather than competing first-level tabs.
- [x] T014: Add a fallback overview state when demo data is unavailable.
- [x] T015: Verify the overview fits a realistic menu-bar popover height.

### PR-004: Heatmap Readability

- [x] T016: Confirm spend and cashflow intensity use distinguishable semantics.
- [x] T017: Add accessible text for the strongest recent heatmap signals.
- [x] T018: Improve empty heatmap copy for no data vs filtered-zero states.
- [x] T019: Add a focused test for heatmap bucket or legend behavior.
- [ ] T020: Refresh screenshot evidence for the heatmap header.

### PR-005: Account And Card Rows

- [ ] T021: Audit row density for checking, savings, credit card, loan, and
  other account types.
- [ ] T022: Ensure every row has a primary amount, secondary detail, freshness,
  and status signal.
- [ ] T023: Make credit utilization, available credit, and due metadata readable
  without opening a budgeting workflow.
- [ ] T024: Add a selected/highlighted row state that remains subtle in dark and
  light appearances.
- [ ] T025: Add focused tests for one shared row-presentation helper.

### PR-006: Account Drill-In Surfaces

- [ ] T026: Ensure account drill-in opens from a row with a predictable keyboard
  and pointer path.
- [ ] T027: Show transactions, balances, limits, freshness, and sync state for
  the selected account.
- [ ] T028: Keep reconnect, remove, and settings actions explicit and
  confirmation-gated where destructive.
- [ ] T029: Add empty drill-in states for no synced transactions and server
  offline.
- [ ] T030: Add accessibility labels for drill-in status and action controls.

### PR-007: Empty, Loading, And Error States

- [ ] T031: Distinguish no server, no credentials, no linked item, no synced
  data, and filtered-zero states in one area.
- [ ] T032: Add one clear recovery action to each state in that area.
- [ ] T033: Preserve last-known local data during transient failures.
- [ ] T034: Truncate or sanitize server error text before display.
- [ ] T035: Add a focused test for one empty/error-state presenter.

### PR-008: Setup And Plaid Link Preflight

- [ ] T036: Verify demo, sandbox, and production setup choices explain their
  data boundaries before Plaid Link opens.
- [ ] T037: Fail fast when sandbox credentials are missing or wrong mode is
  selected.
- [ ] T038: Fail fast when production credentials or Plaid approval assumptions
  are missing.
- [ ] T039: Show the local storage path before linking accounts.
- [ ] T040: Add a smoke or unit check for preflight readiness output.

### PR-009: Reconnect And Degraded Items

- [ ] T041: Surface token-expired and item-error states in dashboard status.
- [ ] T042: Surface the same degraded item state in Settings or Status.
- [ ] T043: Add a clear reconnect path that does not expose raw Plaid payloads.
- [ ] T044: Handle browser-open failure with a copyable recovery path.
- [ ] T045: Add focused tests for degraded item presentation.

### PR-010: Status And Diagnostics

- [ ] T046: Keep `/api/status` limited to readiness metadata.
- [ ] T047: Add or verify UI treatment for server offline, syncing, stale data,
  credentials missing, and linked item counts.
- [ ] T048: Add a local-only diagnostic row for the active data directory.
- [ ] T049: Make status refresh and connect actions reachable from the dashboard.
- [ ] T050: Add tests that status presentation does not include sensitive IDs or
  raw balances.

### PR-011: Local Data Controls

- [ ] T051: Keep Settings visibly anchored on `~/.plaidbar/` or the configured
  `PLAIDBAR_DATA_DIR`.
- [ ] T052: Ensure copy and reveal actions avoid leaking secrets in labels or
  logs.
- [ ] T053: Confirm reset/delete copy explains local-vs-Plaid-vs-bank
  boundaries.
- [ ] T054: Ensure destructive local data actions require confirmation.
- [ ] T055: Add focused tests for reset-boundary wording or local data path
  presentation.

### PR-012: Token And Storage Safety

- [ ] T056: Verify new storage files use private permissions where supported.
- [ ] T057: Add a regression check for Keychain reference vs SQLite fallback
  language.
- [ ] T058: Ensure legacy database migration never mixes sandbox and production
  stores.
- [ ] T059: Verify local auth-token handling avoids public logs and screenshots.
- [ ] T060: Add tests around one storage or token-vault invariant.

### PR-013: API Auth And Status Security

- [ ] T061: Verify `/api/*` rejects missing and invalid local bearer tokens.
- [ ] T062: Add a negative test for status payload secret redaction.
- [ ] T063: Confirm public localhost endpoints remain limited to `/health` and
  OAuth callback behavior.
- [ ] T064: Document any endpoint contract changes before adding new status
  fields.
- [ ] T065: Add a secret-scan pattern only when it catches a real PlaidBar risk.

### PR-014: Logs, Fixtures, And Screenshot Safety

- [ ] T066: Audit screenshots for real credentials, balances, account IDs, and
  merchant histories.
- [ ] T067: Audit fixtures for synthetic-only financial data.
- [ ] T068: Ensure logs do not print raw transactions or token-like strings.
- [ ] T069: Update screenshot docs when a new safe capture path is needed.
- [ ] T070: Add a fixture or screenshot safety check that can run locally.

### PR-015: Demo Mode Polish

- [ ] T071: Keep demo data realistic, synthetic, and aligned with current UI
  screenshots.
- [ ] T072: Ensure demo mode never calls Plaid.
- [ ] T073: Make demo balances, transactions, recurring charges, and credit
  state tell a coherent product story.
- [ ] T074: Add one demo edge case for stale sync or degraded status.
- [ ] T075: Refresh README or screenshot references after demo UI changes.

### PR-016: Sandbox Reliability

- [ ] T076: Verify sandbox setup succeeds from a clean temporary data directory.
- [ ] T077: Add clearer failure handling for missing sandbox credentials.
- [ ] T078: Verify sandbox transaction sync preserves cursor state.
- [ ] T079: Add smoke-script coverage for one new sandbox readiness assertion.
- [ ] T080: Document any remaining sandbox limitation without implying
  production readiness.

### PR-017: Production Readiness Boundaries

- [ ] T081: Keep production setup copy explicit about Plaid approval and real
  financial data.
- [ ] T082: Verify production mode uses separate storage from sandbox.
- [ ] T083: Add a release checklist item for clean-profile production setup.
- [ ] T084: Avoid notarization, appcast, or distribution claims until verified.
- [ ] T085: Update troubleshooting for one production credential or mode failure.

### PR-018: Accessibility And Keyboard Flow

- [ ] T086: Add labels for one icon-only action group.
- [ ] T087: Ensure color-coded financial status has text, icon, or shape backup.
- [ ] T088: Verify tab order through overview, drill-in, refresh, reconnect, and
  settings actions.
- [ ] T089: Add VoiceOver summaries for one chart or status surface.
- [ ] T090: Add focused tests or manual QA notes for the changed accessibility
  behavior.

### PR-019: Performance And Responsiveness

- [ ] T091: Identify one slow or duplicate data calculation in the popover path.
- [ ] T092: Move one reusable pure calculation into `PlaidBarCore`.
- [ ] T093: Preserve cached last-known data during refresh.
- [ ] T094: Avoid blocking the popover on optional diagnostics or AI output.
- [ ] T095: Add a focused performance or reducer test for the moved calculation.

### PR-020: Optional Local AI Boundaries

- [ ] T096: Define the local AI runtime contract without naming a cloud model as
  a dependency.
- [ ] T097: Add copy that local AI is optional, off by default, and never
  required for dashboard use.
- [ ] T098: Ensure local AI prompts never include secrets, raw account IDs, or
  tokens.
- [ ] T099: Add an unavailable state when no local model runtime is configured.
- [ ] T100: Add tests for local AI availability and disabled-state presentation.

### PR-021: Local AI Insight Quality

- [ ] T101: Summarize 7-day spending changes using local transaction data only.
- [ ] T102: Summarize monthly income, expenses, recurring charges, and credit
  utilization with source evidence.
- [ ] T103: Add year-over-year wording only when enough local history exists.
- [ ] T104: Show why an insight was generated using source transaction or
  category evidence.
- [ ] T105: Add a deterministic non-AI fallback summary for unsupported runtimes.

### PR-022: Local AI Categorization Safety

- [ ] T106: Treat Plaid category data as the auditable source-of-record fallback.
- [ ] T107: Keep AI category suggestions separate from raw Plaid transaction
  records.
- [ ] T108: Allow a user correction path for suggested categories.
- [ ] T109: Add reversible local-only storage for category corrections when
  implemented.
- [ ] T110: Add tests that AI suggestions do not mutate raw Plaid data.

### PR-023: QA, CI, And Release Gates

- [ ] T111: Keep `docs/qa-matrix.md` aligned with the current minimum PR gates.
- [ ] T112: Add or update a local command for formula or package validation.
- [ ] T113: Record known Swift toolchain baseline limitations accurately.
- [ ] T114: Keep release notes honest about shipped behavior and deferred work.
- [ ] T115: Add a final release-candidate checklist for privacy, security,
  screenshots, and local setup.

### PR-024: PR, Review, And Merge Hygiene

- [ ] T116: Ensure every autonomous PR includes task IDs, changed files, local
  checks, and secret-scan evidence.
- [ ] T117: Require GitHub checks to be green before any merge attempt.
- [ ] T118: Require a manual safety read of the diff before merging under scoped
  approval.
- [ ] T119: Block merge when app code, docs, screenshots, or generated files
  include real private financial data.
- [ ] T120: After a safe merge, update the progress ledger and choose the next
  unfinished task.
