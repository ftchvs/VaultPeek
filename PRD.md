# PlaidBar — Product Requirements

## Vision

A menu bar app that makes personal finance data glanceable. One click to see all accounts, recent transactions, spending patterns, and credit utilization — no browser login required.

## Persona

**Solo developer / tech-forward professional** who:
- Has 2-5 bank accounts and credit cards
- Wants a quick glance at finances without logging into bank websites
- Values privacy (no cloud sync, no telemetry)
- Runs macOS as primary OS
- Comfortable with terminal for initial setup

## Jobs to Be Done

1. **Glance at net worth** — See total balance in menu bar without clicking
2. **Check recent charges** — "What was that $142 charge?" answered in 2 clicks
3. **Monitor credit utilization** — Keep utilization under 30% for credit score
4. **Understand spending patterns** — Category breakdown over time
5. **Stay updated** — Background refresh keeps data fresh without manual action
6. **Track recurring charges** — "How much am I locked into per month?" answered with one tap to Recurring view
7. **Get alerted to anomalies** — Large charges, low balances, and high utilization flagged via macOS notifications without opening the app

## Feature Matrix

### v0.1 (shipped)

- [x] Menu bar net balance display
- [x] Account list grouped by type (depository, credit)
- [x] Transaction list grouped by date, searchable
- [x] Spending donut chart by category
- [x] Credit utilization progress bars
- [x] Sandbox demo mode
- [x] Local companion server (Hummingbird)
- [x] Hover states, avatars, animations
- [x] Setup/onboarding flow

### v0.2 (shipped)

- [x] Design system (semantic colors, typography, spacing)
- [x] Settings persistence (UserDefaults)
- [x] Launch at login (SMAppService)
- [x] Sparkle auto-update integration
- [x] Keyboard shortcuts (Cmd+1-4, Cmd+R, Cmd+N)
- [x] Spending trend line chart
- [x] Income vs expense bar chart
- [x] Credit utilization gauge
- [x] Balance history sparkline
- [x] Enhanced empty states
- [x] Accessibility improvements (secondary cues for color-only info)
- [x] Fix: nonisolated(unsafe) formatter (Issue #5)

### v0.3 (shipped)

#### Recurring Transaction Detection

| # | Requirement | Acceptance Criteria |
|---|-------------|-------------------|
| 3.1 | Identify recurring transactions | **Given** a user has 2+ transactions with the same merchant name, **When** RecurringDetector runs, **Then** transactions meeting confidence ≥ 0.3 are classified into one of 5 frequency bands (weekly, biweekly, monthly, quarterly, annual) based on median interval |
| 3.2 | Recurring summary view | **Given** the user navigates to the recurring tab, **When** recurring transactions exist, **Then** a list shows: merchant name, frequency (weekly/monthly/yearly), average amount, and next expected date |
| 3.3 | Recurring with no matches | **Given** the user has no recurring patterns detected, **When** they view the recurring tab, **Then** an empty state explains "Recurring charges will be detected automatically after syncing 2+ months of transactions." |

#### Transaction Filtering

| # | Requirement | Acceptance Criteria |
|---|-------------|-------------------|
| 3.4 | Filter by date range | **Given** the user is on the transaction list, **When** they select a date range from the DateRangeFilter enum — `.week` ("This Week"), `.month` ("This Month"), `.thirtyDays` ("30 Days"), `.all` ("All") — **Then** only transactions within that range appear and the count updates |
| 3.5 | Filter by category | **Given** the user is on the transaction list, **When** they select one or more Plaid categories, **Then** only matching transactions appear |
| 3.6 | Filter state lifecycle | **Given** the user applies filters (stored as @State on TransactionsView), **When** the menu bar popover closes and reopens, **Then** all filters reset to defaults (no category, no account, date = All) — by design, filters are ephemeral |

#### Notifications

| # | Requirement | Acceptance Criteria |
|---|-------------|-------------------|
| 3.7 | Transaction & balance notifications | **Given** the user has enabled notifications in settings, **When** a sync completes, **Then** three trigger types fire: (1) large transaction above threshold (default: $500 via `largeTransactionThreshold`), (2) low balance below threshold (default: $100 via `lowBalanceThreshold`), (3) high credit utilization. Each macOS notification shows contextual details (merchant+amount, account+balance, or account+utilization) |
| 3.8 | Settings window | **Given** the user opens Settings (⌘,), **When** the 480×380 window presents, **Then** it contains 4 tabs: General, Accounts, Notifications, and About. Notification tab allows toggling notifications on/off and setting thresholds; all preferences persist via UserDefaults |
| 3.9 | Notification deduplication | **Given** a notification has already been sent for a transaction/condition, **When** subsequent syncs encounter the same item, **Then** the LRU dedup cache (500 entry cap, oldest evicted first) prevents duplicate alerts. Resolved conditions (e.g., balance rises above threshold) clear their dedup entries via `clearResolvedDedup()` |

#### Transaction Detail & Navigation

| # | Requirement | Acceptance Criteria |
|---|-------------|-------------------|
| 3.10 | Transaction detail sheet | **Given** user taps a transaction row, **When** the detail sheet presents, **Then** it shows: merchant name, raw transaction name, amount (color-coded), category with icon, date, account name, and status (posted/pending with colored dot). Dismiss via "Done" toolbar button |
| 3.11 | Accessibility on new components | **Given** VoiceOver is enabled, **When** navigating recurring/filter/detail views, **Then** each component provides meaningful labels: FilterChipsView announces active filter count, RecurringRow announces merchant+frequency+amount, TransactionDetailView contains combined accessible elements |
| 3.12 | Recent/Recurring toggle | **Given** user is on the Transactions tab, **When** they use the segmented picker, **Then** they can switch between "Recent" (filtered transaction list) and "Recurring" (recurring detection view) with animated transition |

#### Spending Enhancements

| # | Requirement | Acceptance Criteria |
|---|-------------|-------------------|
| 3.13 | Period-over-period comparison | **Given** spending data exists for current and previous period, **When** the user views the Spending tab, **Then** a comparison shows absolute delta, percentage change, and directional arrow (up = red/negative, down = green/positive). Color semantics: spending increase = negative (red), decrease = positive (green). Section hidden when previous period spending is zero |
| 3.14 | Spending category color palette | **Given** chart data is rendered, **When** any SpendingCategory is displayed, **Then** it uses the fixed hex color from `SpendingCategory.colorHex` (17 categories). Full palette documented in DESIGN.md |

#### Design System

| # | Requirement | Acceptance Criteria |
|---|-------------|-------------------|
| 3.15 | Design token completeness | **Given** any v0.3 component is rendered, **When** spacing or color is needed, **Then** it uses tokens from DesignTokens.swift: `Spacing.xxs` (2pt), `Spacing.rowVertical` (6pt), `SemanticColors.sparkline` (.blue), `SemanticColors.brand` (.blue), `SemanticColors.brandSecondary` (.orange), `SemanticColors.recurring` (.indigo) |

### v0.4 (planned)

| # | Issue | Title | Category |
|---|-------|-------|----------|
| 4.1 | #7 | SetupView credentials collected but never sent | Enhancement |
| 4.2 | #8 | SemanticColors has redundant color aliases | Tech debt |
| 4.3 | #9 | IncomeExpenseChart recomputes monthlyData on every render | Performance |
| 4.4 | #10 | Formatters.currency copies NumberFormatter on every call | Performance |
| 4.5 | #12 | NotificationService singleton not testable (needs DI) | Tech debt |
| 4.6 | #13 | Settings window activation uses fragile window title matching | Fix |
| 4.7 | #14 | UserDefaults notification settings lack didSet guard | Chore |
| 4.8 | #15 | SpendingView periodInterval may recompute on every access | Performance |
| 4.9 | #17 | Activation policy switch may leave dock icon visible | Fix |

### Future (not committed)

- [ ] Budget alerts per category
- [ ] Multi-currency support
- [ ] Investment account tracking
- [ ] CSV/JSON export
- [ ] Webhook support for real-time updates
- [ ] Homebrew cask distribution
- [ ] Teller.io as alternative provider
- [ ] Widget for macOS desktop
- [ ] iOS companion app

## Edge Cases & Error Handling

### Plaid API Failures

| Scenario | Expected Behavior |
|----------|------------------|
| Plaid API returns 5xx during sync | Show last-known data with "Last updated: {timestamp}" badge; retry after 5 minutes; do not clear existing local data |
| Plaid access token expires (ITEM_LOGIN_REQUIRED) | Show inline banner "Re-authentication needed for {institution}" with button to launch Plaid Link re-auth flow |
| Plaid rate limit hit (429) | Queue the request; retry with exponential backoff (1s, 2s, 4s, max 60s); show subtle "Syncing..." indicator |
| Network unreachable (no internet) | Display cached data normally; hide refresh button; show "Offline" badge in menu bar icon |

### Data Edge Cases

| Scenario | Expected Behavior |
|----------|------------------|
| Account with zero transactions | Show account in list with balance; transaction tab shows empty state: "No transactions yet" |
| Date range filter with no data in range | Show "No transactions match your filters" empty state; filter chips remain visible for adjustment |
| Filter results in zero transactions | Show "No transactions match your filters" with a "Clear filters" button |
| Recurring detection: merchant name varies slightly ("NETFLIX.COM" vs "Netflix") | Normalize merchant names using Plaid's `merchant_name` field (not `name`); group by normalized value |
| Notification threshold set to $0 | Treat as "notify for every transaction"; show warning in settings: "You'll be notified for every transaction" |
| 1000+ transactions in a single sync | Process in batches of 100; show progress indicator; do not block UI during sync |
| Recurring with <2 months history | Show empty state; don't classify until at least 2 occurrences with valid interval |
| Nil merchant name | Excluded from recurring detection (only non-nil `merchantName` grouped) |
| Zero previous period spending | Comparison section hidden (`guard previousPeriodSpending > 0`) |
| All transactions filtered out | Show "No transactions match your filters" empty state with clear button |

### Permission & System Edge Cases

| Scenario | Expected Behavior |
|----------|------------------|
| User denies notification permission (macOS) | Notification toggle in settings shows "Disabled — enable in System Settings > Notifications" with deep link |
| App launched but companion server not running | Show connection error with "Start Server" button; auto-retry every 3 seconds for 30 seconds |
| Multiple PlaidBar instances launched | Second instance detects existing process via port 8484 check; shows alert and exits |
| Notification permission revoked in System Settings | On app startup, `loadInitialData()` rechecks permission status; if denied, sets `notificationsEnabled = false` automatically |
| Duplicate sync (same transaction re-added) | Transaction sync uses id-based upsert (modified replaces by index, removed by id set) |
| LRU overflow (500+ notified transactions) | Oldest entries evicted first; set kept in sync with ordered array |

## Non-Goals

- **Not a budgeting app** — No envelope budgeting, no goal tracking, no bill reminders
- **No cloud sync** — All data stays local. Period.
- **No multi-user** — Single-user, single-machine
- **No transaction editing** — Read-only view of bank data
- **No AI/ML features** — Simple categorization from Plaid, no smart insights

## Success Metrics

### Adoption (lagging)

| Metric | Baseline | Target | Timeframe | How to Measure |
|--------|----------|--------|-----------|----------------|
| GitHub stars | 0 | 100 | 3 months post-launch | GitHub API |
| Homebrew installs | 0 | 50 | 3 months post-launch | Homebrew analytics (opt-in) |
| Plaid Link completion rate | — | > 80% | Per cohort | Server logs: link_started / link_completed |

### Quality (leading)

| Metric | Baseline | Target | Timeframe | How to Measure |
|--------|----------|--------|-----------|----------------|
| Build success rate | 100% | 100% | Continuous | GitHub Actions CI |
| Open issues (bugs) | 0 | < 5 | Rolling 30-day | GitHub Issues (label: bug) |
| Crash-free sessions | — | > 99.5% | Rolling 7-day | MetricKit (macOS 13+) or crash log count |

### UX Performance (leading)

| Metric | Baseline | Target | Timeframe | How to Measure |
|--------|----------|--------|-----------|----------------|
| Time to first data (sandbox) | — | < 3 minutes | Per release | Manual QA: launch → first balance visible |
| Menu bar click to data | 1 click | 1 click | Continuous | Design constraint (not measured) |
| Sync latency (background refresh) | — | < 5 seconds p95 | Per release | Server-side timing: sync start → response |
| Notification delivery latency | — | < 10 seconds after sync | v0.3 | Timestamp delta: sync_complete → notification_shown |

### v0.3 Feature-Specific

| Metric | Baseline (v0.3.0) | Target | Timeframe | How to Measure |
|--------|--------------------|--------|-----------|----------------|
| Recurring detection accuracy | 7/7 demo merchants detected (100% sandbox) | >90% user-reported subscriptions in first 5 bug reports | v0.3.1 | Manual QA + user feedback issues |
| Filter usage rate | 0% (new feature) | >30% of sessions use ≥1 filter | 90 days post-v0.3 | Local UserDefaults counter (planned) |
| Notification opt-in rate | 0% (new feature) | >50% of users who open Settings | 90 days post-v0.3 | Local counter: settings_opened / notifications_enabled |
| Notification delivery latency | N/A | <10s after sync completes | Continuous | Timestamp delta: sync_complete → notification_shown |
| Test suite size | 86 tests, 100% pass | Maintain 100% pass rate | Continuous | `swift test` in CI |
| Build time (clean) | ~45s M1 | <60s | Per release | GitHub Actions CI timing |
