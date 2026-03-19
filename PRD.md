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

### v0.2 (current)

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

### v0.3 (planned)

#### Recurring Transaction Detection

| # | Requirement | Acceptance Criteria |
|---|-------------|-------------------|
| 3.1 | Identify recurring transactions | **Given** a user has 3+ transactions with the same merchant and similar amount (±10%) within 90 days, **When** the transaction list loads, **Then** those transactions are tagged with a "recurring" badge |
| 3.2 | Recurring summary view | **Given** the user navigates to the recurring tab, **When** recurring transactions exist, **Then** a list shows: merchant name, frequency (weekly/monthly/yearly), average amount, and next expected date |
| 3.3 | Recurring with no matches | **Given** the user has no recurring patterns detected, **When** they view the recurring tab, **Then** an empty state explains "No recurring transactions detected yet — we need at least 3 months of data" |

#### Transaction Filtering

| # | Requirement | Acceptance Criteria |
|---|-------------|-------------------|
| 3.4 | Filter by date range | **Given** the user is on the transaction list, **When** they select a date range (7d, 30d, 90d, custom), **Then** only transactions within that range appear and the count updates |
| 3.5 | Filter by category | **Given** the user is on the transaction list, **When** they select one or more Plaid categories, **Then** only matching transactions appear |
| 3.6 | Filter persistence | **Given** the user applies filters and closes the menu bar panel, **When** they reopen it, **Then** the filters remain applied until explicitly cleared |

#### Notifications

| # | Requirement | Acceptance Criteria |
|---|-------------|-------------------|
| 3.7 | Large transaction alert | **Given** the user has enabled notifications in settings and set a threshold (default: $100), **When** a new transaction exceeds that threshold during sync, **Then** a macOS notification shows: merchant, amount, and account name |
| 3.8 | Notification settings | **Given** the user opens Settings > Notifications, **When** they toggle notifications on/off and set a threshold amount, **Then** the preference persists across app restarts via UserDefaults |
| 3.9 | Notification when app is backgrounded | **Given** the app is running in the menu bar (not focused), **When** a qualifying transaction is detected, **Then** the notification still fires via UNUserNotificationCenter |

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
| Custom date filter: end date before start date | Prevent selection; if typed manually, swap dates and show corrected range |
| Filter results in zero transactions | Show "No transactions match your filters" with a "Clear filters" button |
| Recurring detection: merchant name varies slightly ("NETFLIX.COM" vs "Netflix") | Normalize merchant names using Plaid's `merchant_name` field (not `name`); group by normalized value |
| Notification threshold set to $0 | Treat as "notify for every transaction"; show warning in settings: "You'll be notified for every transaction" |
| 1000+ transactions in a single sync | Process in batches of 100; show progress indicator; do not block UI during sync |

### Permission & System Edge Cases

| Scenario | Expected Behavior |
|----------|------------------|
| User denies notification permission (macOS) | Notification toggle in settings shows "Disabled — enable in System Settings > Notifications" with deep link |
| App launched but companion server not running | Show connection error with "Start Server" button; auto-retry every 3 seconds for 30 seconds |
| Multiple PlaidBar instances launched | Second instance detects existing process via port 8484 check; shows alert and exits |

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

| Metric | Target | How to Measure |
|--------|--------|----------------|
| Recurring detection accuracy | > 90% of known subscriptions detected in sandbox | Manual QA with 10 known recurring merchants |
| Filter usage rate | > 30% of sessions use at least one filter | Analytics event (local-only counter in UserDefaults) |
| Notification opt-in rate | > 50% of users who reach Settings | Local-only counter: settings_opened / notifications_enabled |
