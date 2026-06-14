---
title: VaultPeek Consumer Experience Roadmap — Feature Design Specs
status: proposed
linear: [AND-351, AND-352, AND-353, AND-354, AND-355, AND-392]
date: 2026-06-12
---

# VaultPeek Consumer Experience Roadmap

**Design specs only — nothing in this document is an implementation commitment.** Each section below is a buildable design anchored to real code in this repo (file paths verified against `Sources/` in this worktree on 2026-06-12), with acceptance criteria written to be pasted directly into the corresponding Linear issue.

All pricing figures are labeled with retrieval date. Plaid per-product costs are **estimates** unless stated otherwise — the managed-linking unit-economics doc owns the authoritative numbers.

---

## 0. Shared ground rules

### 0.1 Local-first compliance baseline

Every feature in this doc must satisfy the existing promise (README/SECURITY): no cloud backend, no telemetry, financial data stays on the machine. The current architecture already enforces this — the SwiftUI app (`Sources/PlaidBar/`) talks only to the localhost Hummingbird server (`Sources/PlaidBarServer/`), which holds Plaid tokens in Keychain (`Sources/PlaidBarServer/Storage/PlaidTokenVault.swift`) and item records in local SQLite. All five features below compute from **locally cached accounts + transactions**; none require a new network surface.

### 0.2 The hosted-component tension (called out once, referenced per-feature)

Two things in this roadmap cannot be fully local:

1. **Plus-tier entitlement** (AND-353 advanced alert rules, AND-355 monthly review). Stripe billing requires a hosted entitlement check. **Minimal footprint proposal:** a hosted endpoint that exchanges a license id + install id for a signed, time-boxed entitlement receipt (Ed25519-signed; 30-day TTL + 14-day grace — wire format and protocol owned by the Stripe entitlements design doc), cached locally and verified offline by signature. The hosted service sees: an email/license id and a tier. It **never** sees accounts, balances, transactions, Plaid tokens, or any derived financial metric. Degradation rule: if the entitlement service is unreachable, previously-validated Plus features keep working until receipt expiry + grace period — the app never phones home on a hot path.
2. **Managed Plaid linking** (separate doc; referenced by data requirements below). If a user is on the managed tier, a hosted **link-token broker** creates Plaid link tokens so the user doesn't bring their own keys. Financial data is never *stored* on the hosted service; per the managed-link architecture doc, managed-mode sync traffic does *transit* a stateless, memory-only blind proxy (Plaid forbids shipping the org `secret` in clients, so direct device→Plaid data calls are impossible in managed mode — BYO mode stays fully direct). The broker's control plane sees institution-link events, never transactions or balances. Precedent that users accept honestly-priced aggregator pass-through: Actual Budget + SimpleFIN at $15/yr user-paid (retrieved 2026-06-12).

Every feature section below has a **Local-first compliance** subsection stating whether it touches either hosted component.

### 0.3 Tier mapping

AND-392 owns the canonical Free / Plus / Managed matrix:
`entitlement-matrix.md`. Feature specs below use that matrix for limits and
pricing. Free includes demo fixtures and BYO-keys mode; Plus is $15/month or
$129/year early-access with up to 8 managed institutions; Managed is a custom
written quote starting from Plus. BYO-keys mode stays free and ungated.

| Feature | Free | Plus / Managed |
|---|---|---|
| AND-351 first-run snapshot | Demo/BYO | Managed live data |
| AND-352 menu bar cockpit | Demo/BYO | Managed live data |
| AND-353 alerts | Core local triggers | Advanced rules when built |
| AND-354 recurring view | Basic local view | Review controls when built |
| AND-355 monthly review | Not promised | Plus/Managed when built |

---

## 1. AND-351 — First-run money snapshot after account connection

### User story

> As a new user who just connected my first bank account, I want to see a complete picture of my money within two minutes — cash, credit, net worth, recent big charges, this month's spend — so that VaultPeek proves its value before I close the popover.

This is the "two-minute aha." Copilot and Monarch deliver it as a full-app dashboard; VaultPeek's differentiation is delivering it **inside a 480pt menu bar popover**, computed entirely on-device.

### UI sketch (anchored to code)

The first-run flow already has the scaffolding:

- `Sources/PlaidBarCore/Models/FirstRunCompletion.swift` models the pipeline: `openPlaidLink → loadAccounts → syncTransactions → ready` (or `blocked`). The snapshot mounts at the `ready` transition.
- `Sources/PlaidBar/Views/MainPopover.swift` — `dashboardColumn` currently swaps `SetupView` for the full dashboard the moment `appState.isSetupComplete` flips (`shouldShowSetupScreen`, line ~241). The snapshot is a **one-time interstitial state of the dashboard column**, not a new window.

Proposed structure — a new `FirstRunSnapshotView` rendered in `dashboardColumn` when `FirstRunCompletionState.isReady` first becomes true and a `hasSeenFirstRunSnapshot` flag (UserDefaults/`@AppStorage`, like `dashboard.accountFilter` in `MainPopover.swift`) is unset:

1. **Hero**: "Here's your money." + net worth figure, reusing the exact `DashboardHeader` pattern (`Text(Formatters.currency(appState.netBalance, format: .full)).displayBalance()`) — one hero number per surface, per the existing comment in `DashboardHeader`.
2. **Three metric cards** reusing the private `MetricCard` component from `MainPopover.swift` (`DashboardSummaryCards` row): **Cash available** (`MenuBarSummary.totalCash`), **Credit owed + utilization** (`MenuBarSummary.totalDebt` / `MenuBarSummary.creditUtilization` from `Sources/PlaidBarCore/Utilities/MenuBarSummary.swift`), **Spend this month** (new `MenuBarSummary` calendar-month variant of `recentSpend(from:days:)` — the existing function is window-based, month-to-date needs a calendar-anchored start date; put it in `PlaidBarCore` per convention).
3. **Debt/liabilities line** when loan accounts exist: reuse `BalanceCompositionStrip` segments (`AccountPresentation.debtBalanceTotal(from:type:)` for `.credit` and `.loan`).
4. **Recent large transactions** (up to 3): reuse `NotificationTriggerSelection.largeTransactions(from:threshold:)` (`Sources/PlaidBarCore/Utilities/NotificationTriggerSelection.swift`, default threshold $500) rendered with the compact row idiom of `DashboardAccountRow`.
5. **Footer**: "Computed and stored on this Mac. VaultPeek does not store this snapshot on its servers." + a single prominent "Go to dashboard" button (`.borderedProminent`, `.controlSize(.small)` like `DashboardOverviewFallbackBanner`). Dismissal sets the flag; the snapshot never auto-reappears. Avoid claiming that no data left the machine for managed accounts: the underlying bank data still comes from Plaid, and managed-tier sync traffic may transit the VaultPeek broker.

Height stays inside the existing `dashboardScrollHeight` budget (`Layout.dashboardMinHeight = 460` up to screen cap) — the snapshot is a single non-scrolling screen at minimum height.

### Data requirements

- Accounts + balances from `GET /api/accounts` (already cached in `AppState.accounts`).
- ≥1 page of transaction sync (`PlaidBarConstants.initialSyncDays = 90` in `Sources/PlaidBarCore/Utilities/Constants.swift`) for spend-so-far and large transactions.
- **No new Plaid products required.** Liabilities/investments enrich the snapshot when present but are optional (see partial states). Pulling Plaid Liabilities adds per-account cost on a managed tier — estimate only, flagged to the pricing doc.
- New pure logic in `PlaidBarCore` (testable, per CLAUDE.md convention): `FirstRunSnapshot.evaluate(accounts:transactions:)` returning a presentation struct, mirroring how `DashboardOverviewFallbackState.evaluate` and `FirstRunCompletionState.evaluate` work today.

### Partial/empty states

Mirror the tone system of `DashboardAccountEmptyState` / `SecondaryContentUnavailableState`:

- No credit accounts → credit card shows "No credit linked" (string already exists in `DashboardSummaryCards.creditDetail`).
- No transactions yet (sync still paging) → spend card shows "Syncing transactions…" with the `FirstRunCompletionState.syncTransactions` step detail; the snapshot renders with balances only and live-updates when sync lands.
- No liabilities/investments → omit rows entirely rather than rendering zeros (the `BalanceCompositionStrip.activeSegments` filter already establishes this pattern).

### Caching & failure behavior

Snapshot inputs are whatever `AppState` last loaded; persist the computed snapshot struct via the existing local store (`Sources/PlaidBarCore/Utilities/LocalDataStore.swift`) so a server restart or transient Plaid failure during minute two does not blank the screen. Stale data is labeled with `Formatters.relativeDate` ("as of 2m ago"), consistent with `lastSyncRelative` usage in `StatusMetricGrid`.

### Accessibility (no color-only meaning)

- The snapshot is one `accessibilityElement(children: .contain)` region with a summary label, like `DashboardOverviewStack` does today.
- Utilization risk is conveyed by icon + text via the existing `SemanticColors.utilizationIcon(for:threshold:)` pairing (see `DashboardAccountRow` — "tint the icon, never the text").
- Large-transaction amounts use `.primary` text ("amounts are data, not verdicts" — comment in `DashboardAccountRow`).
- VoiceOver announcement on mount via `AccessibilityNotification.Announcement`, same mechanism as `ErrorBanner`.

### Local-first compliance

Fully local. No hosted component. Snapshot math runs in `PlaidBarCore`; nothing transits any service. (On the managed tier the *link* that precedes it touches the broker — out of scope here.)

### Effort estimate

**M — ~4–6 engineer-days** (estimate). New Core presentation struct + month-to-date spend helper (~1d incl. tests), `FirstRunSnapshotView` reusing `MetricCard`/strip components (~2d), partial-state matrix + fixtures for `--demo` (~1d), accessibility + screenshot pass (~1d).

### Acceptance criteria (paste into AND-351)

- [ ] After the first successful sync (`FirstRunCompletionState.step == .ready`), a one-time snapshot view replaces the dashboard column showing: cash available, credit balances, credit utilization %, net worth estimate, debt/liabilities total when ≥1 credit/loan account exists, up to 3 recent large transactions, and month-to-date spend.
- [ ] Snapshot logic lives in `PlaidBarCore` as a pure `evaluate` function with unit tests covering: full data, no credit, no liabilities, zero transactions, sync-in-progress.
- [ ] Missing liabilities/investments/transaction history render as omitted rows or labeled placeholders — never $0.00 or layout collapse (verified against demo fixtures with each category removed).
- [ ] Snapshot persists via the local data store and remains visible (with "as of …" staleness label) when the server or provider becomes unreachable after first sync.
- [ ] Snapshot fits the 480pt popover at `dashboardMinHeight` without scrolling; verified in `Scripts/screenshots.sh` output.
- [ ] No color-only meaning: utilization and large-charge emphasis carry icon + text; whole view exposes a combined VoiceOver summary and posts a mount announcement.
- [ ] Dismissal is explicit ("Go to dashboard"), recorded in `@AppStorage`, and the snapshot never reappears unless the user resets it in Settings.
- [ ] Zero new network calls; works identically in `--demo` mode.

---

## 2. AND-352 — Menu bar cockpit refinement for consumer positioning

### User story

> As a Mac user who checks money the way I check the clock, I want the menu bar item and its first dropdown to answer "am I okay?" in under three seconds — so that VaultPeek feels like a private cockpit, not another budgeting app I have to *go to*.

This is the moat feature: the competitive brief (2026-06-12) shows no maintained US multi-account personal-finance menu bar app (Balance is defunct, simplebanking is EU-only, Runtab is single-metric).

### UI sketch (anchored to code)

**Menu bar label** — `Sources/PlaidBar/Views/MenuBarLabel.swift` already carries state by **glyph, not color** (`exclamationmark.octagon` for errors, `network.slash` for offline, `exclamationmark.triangle` for needs-login/stale, `dollarsign.circle` healthy), plus optional `menuBarAttentionText` and a `monospacedDigit` summary value. Changes:

1. **Add `.netWorth` to `MenuBarSummaryMode`** (`Sources/PlaidBarCore/Utilities/MenuBarSummary.swift`). The enum today has `netCash, totalCash, creditUtilization, recentSpend, iconOnly` — the Linear AC asks for net worth, which `AppState.netBalance` already computes for `DashboardHeader`; move/share that reduction in `MenuBarSummary` so both surfaces use one function.
2. **Rename fallback strings**: `MenuBarSummary.text` returns `"PlaidBar"` when accounts are empty (3 occurrences) — must become the VaultPeek wordmark as part of the rename.
3. **Attention states**: extend the glyph ladder with consumer-financial conditions (today it only reflects plumbing): low cash (`NotificationTriggerSelection.lowBalanceAccounts`), high utilization (`MenuBarSummary.creditUtilization` vs `appState.creditUtilizationThreshold`, default `PlaidBarConstants.creditUtilizationWarningThreshold = 30`), unusual spending (7d spend vs trailing baseline — new Core helper next to `MenuBarSummary.recentSpend`). Severity mapping reuses `AttentionQueueSeverity` (`healthy/warning/blocked`) from `Sources/PlaidBarCore/Models/AttentionQueue.swift`: blocked → octagon, warning → triangle, with `menuBarAttentionText` carrying a short token ("Low cash") so the state is never glyph-only either.

**Popover dropdown** — `MainPopover.swift` is already dashboard-first. Cockpit refinements, in existing components:

- `DashboardHeader` (net worth hero + `BalanceTrendChart` sparkline) stays the single hero.
- `AttentionQueueView` (max 3 rows, `AttentionQueue.maximumRowCount`) is the "key warnings" surface — extend `AttentionQueue.evaluate` with the three financial conditions above so warnings cover: low cash, high utilization, unusual spending, stale sync (`isSyncStale` exists), broken connection (`needsLoginItemCount`/`erroredItemCount` exist). Each row keeps an action (`DashboardStatusReadinessAction`) — click-through is the recovery path.
- `DashboardSummaryCards` (Cash / Credit / 7D Spend) + `BalanceCompositionStrip` summarize posture; `StatusMetricGrid` already summarizes sync state. **Anti-budgeting-suite rule:** the popover gets *no* new tabs, budgets, or category editors; depth goes into the `AccountDetailFlyout` (320pt leading fly-out, already built) — "click-through opens the fuller dashboard/details" is satisfied by the existing row → fly-out drill-in (`AccountRowWithDrilldown`).
- **Positioning copy**: the trust footer line ("Computed on this Mac…") joins `DashboardFooter`'s status line (`statusLineText`, e.g. "Sandbox · Synced 2m ago · 2 linked"), and `LocalInsightsCard` already shows the `lock.shield.fill` + "Local" pill — reuse that vocabulary, don't invent a second privacy idiom.

### Data requirements

All inputs already exist in `AppState`: `accounts`, `transactions`, `itemStatuses`, `balanceHistory`, `isSyncStale`, `serverConnected`. New pure helpers in `PlaidBarCore`: `netWorth(from:)`, `unusualSpend(transactions:now:)` (baseline = trailing 4-week median of weekly spend; flag when current week > k× median, k configurable, default 2.0 — estimate, tune on fixtures). No new server endpoints, no new Plaid products, no extra refresh cadence (stays on `backgroundRefreshInterval = 15 min`).

### Accessibility (no color-only meaning)

- Menu bar state is glyph + text by design (existing comment in `MenuBarLabel.swift`); keep `accessibilityLabel(appState.menuBarAccessibilityLabel)` exhaustive: mode, value, and any attention condition in words.
- New attention rows inherit `AttentionQueueRow`'s built-in `accessibilityLabel`/`accessibilityHint` construction.
- Red/yellow severities must each pair with distinct icon + title text (octagon vs triangle), matching `DashboardStatusReadinessPanel`'s icon ladder.

### Local-first compliance

Fully local. No hosted component. This feature is the *argument* for local-first positioning — copy should claim what no cloud competitor can, in the precise form the pricing doc's copy rule requires: "your transactions are never stored on our servers" (BYO mode: "never touch our servers" holds verbatim).

### Effort estimate

**M — ~5–7 engineer-days** (estimate). `MenuBarSummaryMode.netWorth` + shared net-worth reduction (~1d), unusual-spend heuristic + tests (~1.5d), `AttentionQueue` financial rows + glyph ladder (~1.5d), copy/positioning pass incl. VaultPeek wordmark strings (~1d), QA across the five degraded states (~1d).

### Acceptance criteria (paste into AND-352)

- [ ] Menu bar summary mode supports net cash, net worth, credit utilization, and icon-only; net worth uses the same `PlaidBarCore` reduction as the popover hero (single source of truth, unit-tested).
- [ ] Popover summarizes account posture (hero + metric cards + balance mix), sync state (footer status line), and key warnings (attention queue) without adding tabs, budget editors, or category management to the popover surface.
- [ ] Red/yellow status states cover all five conditions — low cash, high credit utilization, unusual spending, stale sync, broken connection — each expressed as glyph + text in the menu bar and as an attention-queue row with a recovery action in the popover.
- [ ] Clicking an account row opens the existing detail fly-out; every attention row's action deep-links to its fix (reconnect, refresh, settings).
- [ ] All user-visible "PlaidBar" fallback strings in `MenuBarSummary.text` and popover copy are replaced with VaultPeek positioning copy; at least one surface carries the "computed on this Mac" trust line.
- [ ] No state is conveyed by color alone: each severity has a distinct SF Symbol and text label; VoiceOver reads mode, value, and attention condition from the menu bar item.
- [ ] Thresholds (low cash, utilization, unusual-spend multiplier) read from the same configuration as alerts (AND-353) — one settings surface, no duplicated constants.

---

## 3. AND-353 — Money-saving alert system for retention

### User story

> As a returning user, I want VaultPeek to tap me on the shoulder only when money needs attention — a big charge, a balance about to go negative, a new subscription, a card running hot — so that the app earns its subscription on the days I *don't* open it.

Retention logic: glanceable apps die when there's no reason to glance. Alerts are the re-engagement loop that cloud competitors run server-side; VaultPeek must run it entirely on-device.

### UI sketch / system design (anchored to code)

The skeleton exists and should be extended, not replaced:

- `Sources/PlaidBar/Services/NotificationService.swift` — `evaluateTriggers(transactions:accounts:config:)` with LRU dedup (`notifiedTransactionIds` persisted to UserDefaults) already prevents repeat alerts.
- `Sources/PlaidBarCore/Utilities/NotificationTriggerSelection.swift` — pure, tested selection helpers with defaults: large transaction ≥ $500, low balance < $100, utilization > 30%.
- Evaluation runs on the existing sync cadence (`PlaidBarConstants.transactionSyncInterval = 30 min`, `backgroundRefreshInterval = 15 min`) — alerts compute from cached/synced data, **never** from extra live `/balance/get` polling (which would also cost per-call on a managed tier; estimate, pricing doc owns numbers).

**New trigger set** (all new selection logic in `PlaidBarCore`, mirroring the existing helpers):

| Trigger | Source | Tier |
|---|---|---|
| Large transaction | `largeTransactions(from:threshold:)` — exists | Personal |
| Low balance | `lowBalanceAccounts(from:threshold:)` — exists | Personal |
| High credit utilization | `highUtilizationAccounts(from:threshold:)` — exists | Personal |
| Recurring charge detected (new stream) | diff of `RecurringDetector.detect(from:)` results vs persisted prior set, keyed by `RecurringTransaction.id` (`"merchant-frequency"`) | Personal |
| Bill/charge due soon | `RecurringTransaction.nextExpectedDate` within N days (default 3) and `confidence ≥ 0.6` (estimate, tune) | Personal |
| Account connection broken | `itemStatuses` needs-login/errored — same inputs as `AttentionQueue.evaluate` | Personal |
| Advanced rules (per-account thresholds, quiet hours, amount-vs-merchant-average deviation, utilization forecast at statement close) | composition of the above | **Plus** |

**Settings UI**: extend the notifications section of `Sources/PlaidBar/Settings/SettingsView.swift` with per-trigger toggles + threshold steppers bound to `NotificationTriggers` (which already models the three thresholds; add the new ones there so defaults stay in one `Sendable` struct).

**Notification copy & lock-screen privacy**: title states category, body stays coarse. "Large charge detected — open VaultPeek for details" rather than "$1,240.00 at Delta". A "show amounts in notifications" toggle (default **off**) gates merchant/amount detail, consistent with `/api/status`'s readiness-only philosophy. Each notification's click action opens the popover at the relevant surface (attention queue or recurring view).

### Data requirements

- Cached transactions/accounts in `AppState` (already synced via `SyncService`).
- Persisted set of known recurring stream ids + last-alerted state — extend the `LocalDataStore` pattern; dedup keys follow `NotificationService`'s existing UserDefaults LRU approach.
- No new Plaid products. (Plaid's Recurring Transactions add-on could replace local detection on a managed tier — cost implication flagged as estimate to the pricing doc; local `RecurringDetector` remains the default and the BYO-keys path.)
- Plus gating: requires the **entitlement receipt** (§0.2). Trigger evaluation itself stays local; the receipt check is a local signature verification.

### Accessibility (no color-only meaning)

- macOS notifications are inherently text-first; ensure every alert title names the condition in words ("Credit utilization high"), never relying on an emoji/colored icon alone.
- In-app mirrors of alerts land in `AttentionQueueView` rows (icon + title + detail + action), inheriting its accessibility construction.
- Settings toggles get `.accessibilityHint` describing the trigger and its threshold.

### Local-first compliance

Trigger evaluation, dedup, scheduling: fully local (`UNUserNotificationCenter`, on-device). **Hosted tension:** only the Plus entitlement receipt (§0.2). Explicitly: no alert content, threshold, or trigger metadata ever leaves the machine; the entitlement service cannot learn which alerts a user has enabled. If the entitlement check fails closed, Plus rules degrade to Personal rules — core alerts never break.

### Effort estimate

**L — ~8–10 engineer-days** (estimate). Three new triggers + persistence + tests (~3d), settings UI for trigger matrix (~2d), notification copy/privacy modes + deep-link routing (~2d), Plus gating against entitlement receipt stub (~1d), QA incl. dedup across restarts (~1.5d).

### Acceptance criteria (paste into AND-353)

- [ ] Alerts ship for all six core triggers: large transaction, low balance, high credit utilization, recurring charge detected (new stream), bill/charge due soon (from `nextExpectedDate` with confidence floor), and account connection broken.
- [ ] All trigger selection logic is pure, lives in `PlaidBarCore`, and has unit tests per trigger including dedup behavior (no re-alert for the same transaction id, stream id, or item state across app restarts).
- [ ] Thresholds (amount, balance, utilization, due-soon window, confidence floor) are user-configurable in Settings with the documented sane defaults ($500 / $100 / 30% / 3 days / 0.6) pre-filled from one `NotificationTriggers` struct.
- [ ] Alert evaluation runs only on the existing sync/refresh cadence from cached data; zero additional live Plaid Balance calls are introduced (verifiable in `PlaidClient` call sites).
- [ ] Default notification copy contains no merchant names or amounts; a default-off setting enables detailed copy, with lock-screen exposure documented in SECURITY.md.
- [ ] Clicking a notification opens the popover focused on the relevant surface (attention queue or recurring view).
- [ ] Plus-only advanced rules are documented in this spec's table, gated by a locally-verifiable entitlement receipt, and degrade gracefully to Personal behavior when no valid receipt exists.
- [ ] No alert, threshold, or trigger metadata is transmitted off-device; the doc's hosted-footprint statement (entitlement check only) is reflected in SECURITY.md.

---

## 4. AND-354 — Recurring payments / subscriptions view

### User story

> As a subscriber-fatigued user, I want one screen that shows every recurring charge — what it costs monthly, when it hits next, and which ones changed or went quiet — so that VaultPeek visibly pays for itself by surfacing a subscription I forgot.

This is the classic "the app found me $14/mo" retention moment, and the easiest value to demo in marketing.

### UI sketch (anchored to code)

Substantial machinery already exists — this issue is mostly **promotion + enrichment** of an existing surface:

- `Sources/PlaidBarCore/Utilities/RecurringDetector.swift` — groups by `merchantName`, median-interval classification (weekly 5–9d, biweekly 12–16d, monthly 26–35d, quarterly 80–100d, annual 350–380d), confidence = 1 − coefficient of variation with a 0.3 floor, min 3 occurrences for weekly/biweekly.
- `Sources/PlaidBarCore/Models/RecurringTransaction.swift` — already carries `averageAmount`, `frequency`, `lastDate`, `nextExpectedDate`, `transactionCount`, `confidence`.
- `Sources/PlaidBarCore/Utilities/RecurringSummary.swift` — `estimatedMonthlyTotal` via `monthlyMultiplier`.
- `Sources/PlaidBar/Views/RecurringView.swift` — renders "EST. MONTHLY COST" hero + `RecurringRow` list with a proper empty state (`SecondaryContentUnavailableState.recurring`).

Design deltas:

1. **Surface promotion.** `RecurringView` must be reachable from the consumer popover (per the design-direction memory, legacy tabs were audited as dead). Proposal: a compact "Recurring" summary card in `MainPopover.dashboardColumn` after `DashboardSummaryCards` — monthly total + next 2 upcoming charges — that drills into the full `RecurringView` inside the existing `AccountDetailFlyout`-style leading fly-out (320pt), reusing the drill-in idiom of `AccountRowWithDrilldown`.
2. **Row spec** (extend `RecurringRow`): merchant, `frequency.displayName` + `frequency.iconName` (already defined), average amount (`.dataText()`, `.primary`), "Last `lastDate` · Next `nextExpectedDate`" via `Formatters.displayTransactionDate`, and an explainability affordance.
3. **Price-increase flag**: latest charge amount > trailing average by both ≥10% and ≥$1 (estimate, tune on fixtures), only when `confidence ≥ 0.6`. Badge: `arrow.up.circle` icon + "Up $3.00 vs avg" text.
4. **Stale-stream flag**: today − `lastDate` > 2× `frequency.estimatedDays` → "May have ended" badge (`zzz` or `pause.circle` icon + text). Stale streams drop out of `estimatedMonthlyTotal` (change to `RecurringSummary` + tests).
5. **Explainability & reversibility**: each row's detail discloses *why* — "Detected from 7 charges, ~30 days apart, 92% consistent" (all fields exist on `RecurringTransaction`). Each row has "Not recurring" which adds the stream id to a local ignore list (persisted via `LocalDataStore` pattern); Settings shows ignored streams with one-tap restore. Detection re-runs are idempotent over the ignore list.
6. **Tier note**: Personal = full view + flags. Plus (later, separate issue) = review workflows (bulk review queue, cancellation tracking). This issue ships nothing Plus-gated.

### Data requirements

- Cached transactions only; ≥60–90 days of history for monthly detection (initial sync already pulls `initialSyncDays = 90`).
- Persisted ignore list + prior detection snapshot (shared with AND-353's "new stream" trigger — build once).
- Optional future: Plaid Recurring Transactions product on managed tier (per-item cost — estimate, pricing doc). Local detector remains canonical so BYO-keys users lose nothing.

### Accessibility (no color-only meaning)

- Price-increase and stale badges are icon + text, never a bare colored chip; amount deltas are spelled out ("Up $3.00 from $12.99 average").
- The monthly-total header already has a combined accessibility label in `RecurringView` — keep that pattern for the new dashboard card.
- Rows expose a single VoiceOver label: merchant, frequency, amount, next expected date, any flag, plus an accessibility action for "Not recurring" (mirroring `accessibilityAction(named:)` in `AccountRowWithDrilldown`).
- Confidence is communicated as text ("92% consistent"), not as an opacity/color ramp.

### Local-first compliance

Fully local. Detection, flags, ignore list, and totals all compute in `PlaidBarCore` from cached data. No hosted component. (Managed-tier Plaid recurring product is an explicit *option*, not a dependency.)

### Effort estimate

**M — ~5–7 engineer-days** (estimate). Price-increase + stale flags with detector tests (~2d), ignore list + persistence + settings restore (~1.5d), dashboard card + fly-out promotion (~1.5d), accessibility + demo fixtures with recurring streams (~1d). Detection core already exists — that's most of the savings.

### Acceptance criteria (paste into AND-354)

- [ ] Recurring streams are detected from local transactions via `RecurringDetector` (provider recurring data optional/absent), and the view is reachable from the main popover dashboard — not a dead tab.
- [ ] Each stream shows amount (average), frequency, last charge date, next expected charge date, and the list header shows the estimated monthly recurring total.
- [ ] Price-increase flag appears only when the latest charge exceeds the trailing average by ≥10% and ≥$1 with confidence ≥ 0.6; stale flag appears when the last charge is older than 2× the expected interval; both thresholds are constants in `PlaidBarCore` with unit tests.
- [ ] Stale streams are excluded from the estimated monthly total (tested).
- [ ] Every row explains its detection in plain language (occurrence count, typical interval, consistency %) — no unexplained "subscription" claims.
- [ ] "Not recurring" removes a stream reversibly: ignored streams persist locally, are restorable from Settings, and survive detector re-runs.
- [ ] Flags and confidence are conveyed with icon + text; rows have combined VoiceOver labels and a named accessibility action for ignore.
- [ ] Feature is fully functional on Personal tier with no entitlement check; all computation is on-device with no new network calls.

---

## 5. AND-355 — Plus-tier monthly financial review

### User story

> As a Plus subscriber, I want a once-a-month, plain-English review — what changed in my spending, which merchants grew, where my cash and debt are trending, what subscriptions appeared or got pricier — so that Plus feels like a financial check-up I'd otherwise pay a human for, not just "more accounts."

This is the Plus differentiator beyond link count (the Linear AC demands differentiation "beyond just more institution links"). Monarch's $199/yr Plus tier (retrieved 2026-06-12) shows premium headroom for planner-style features; VaultPeek's version is the **private** review — generated on-device.

### UI sketch (anchored to code)

The presentation DNA already exists in `LocalInsightsCard` (`MainPopover.swift`) + `Sources/PlaidBarCore/Utilities/LocalAIInsightBuilder.swift` / `Sources/PlaidBar/Services/LocalAIInsightsService.swift`: headline, evidence chips, confidence/limitations receipt lines, `lock.shield.fill` "Local" pill, and the `LocalAIStatusPill` availability states. The monthly review is that idiom, scaled to a full surface:

1. **Entry point**: in the first week of a new month, a "Your May review is ready" card appears under `LocalInsightsCard` (Plus only; Personal sees a one-line teaser with an upgrade affordance — no fake data).
2. **Review surface**: opens in the leading fly-out (320pt, `AccountDetailFlyout` idiom) or a dedicated window if depth demands it; sections in order:
   - **Headline summary** — 2–3 plain-English sentences. Template-first generation in `PlaidBarCore` (deterministic, testable); the on-device model (`LocalAIInsightsService`, Apple Foundation Models) may *rephrase* templated facts but is never the source of numbers — same receipts discipline (`confidence`, `limitations`) the `LocalAIInsightReceipt` already enforces.
   - **Month-over-month spend** — total + per-category deltas from `Sources/PlaidBarCore/Utilities/SpendingSummary.swift` aggregations, rendered with the existing `IncomeExpenseChart`/`SpendingTrendChart` components (`Views/Charts/`).
   - **Top merchants** — top 5 by spend with deltas vs prior month.
   - **Cash trend** — month-end cash from `balanceHistory` (`BalanceSnapshot.swift`), sparkline via `BalanceTrendChart`.
   - **Debt trend** — credit + loan totals (`AccountPresentation.debtBalanceTotal`) month over month, with utilization context.
   - **Subscription changes** — diff of `RecurringDetector` results vs prior month's persisted snapshot: new, ended (stale), price-increased (shared logic with AND-353/354).
3. **Export/share**: a single explicit "Export PDF…" button. Export is **redacted by default** — account names generalized ("Checking ••42"), merchant names kept, no account ids; a pre-export preview shows exactly what leaves. No share sheet auto-population, no background export, ever.

### Data requirements

- ≥2 full calendar months of cached transactions (else the review renders a labeled partial state: "First full review available July 1").
- Persisted month-end snapshots: extend `LocalDataStore` with a monthly rollup record (spend by category, merchant totals, cash/debt totals, recurring set) written at month close — this also makes year views cheap later.
- **No raw transaction data to any cloud model.** Generation order: deterministic templates (always) → optional on-device model rephrasing when `LocalAIAvailability.state == .available`. A future cloud-model option is explicitly out of scope and would require its own product decision + doc, per the Linear AC.
- **Entitlement**: Plus receipt (§0.2), verified locally.
- **Provider cost implications** (managed tier, all estimates retrieved 2026-06-12 — pricing doc owns final numbers): review quality improves with Plaid Liabilities (true APRs/dues) and Investments products, each adding per-account monthly cost (commonly cited estimates: ~$0.20 and ~$0.18 per account/month, unverified); Plaid's Recurring Transactions add-on similarly. The review must therefore be designed to be *complete without them* — transactions-only is the baseline; liabilities/investments sections appear only when the data exists (BYO keys with those products enabled, or a managed-tier decision to pay for them).

### Accessibility (no color-only meaning)

- Every chart pairs with a text summary (the `BalanceTrendChart` + `accessibilitySummary` pattern in `DashboardHeader`); deltas are signed text ("Dining up $84, +18%"), with direction also carried by `arrow.up`/`arrow.down` SF Symbols, not tint alone — matching the `deltaTint` + text convention.
- Section order is a logical VoiceOver reading order; each section is an `accessibilityElement(children: .contain)` with a one-line label.
- The review is fully consumable with VoiceOver and with charts hidden (text carries 100% of the conclusions).

### Local-first compliance

Computation, generation, and storage: fully local. **Hosted tensions (two, explicit):** (1) Plus entitlement receipt (§0.2) — the entitlement service learns only that a customer is Plus, never that a review was generated, opened, or exported; no review telemetry exists. (2) If a future decision adds cloud-model summarization, that is a **boundary change requiring explicit opt-in UI and a revision of SECURITY.md** — this spec deliberately does not depend on it. Export shares data only via explicit user action with visible redaction preview.

### Effort estimate

**L — ~10–14 engineer-days** (estimate). Monthly rollup persistence + MoM/merchant/debt aggregations with tests (~4d), review surface + charts reuse (~3d), template generation + optional local-model rephrase plumbing (~2d), redacted PDF export + preview (~2d), entitlement gating + Personal teaser (~1d), accessibility pass (~1d).

### Acceptance criteria (paste into AND-355)

- [ ] Review covers: month-over-month total and per-category spend, top 5 merchants with deltas, cash trend, debt trend, subscription changes (new/ended/price-increased), and a plain-English summary of 2–3 sentences.
- [ ] All numbers come from deterministic `PlaidBarCore` aggregations with unit tests; the on-device model may only rephrase templated facts and the review renders fully (template text) when local AI is disabled or unavailable.
- [ ] No raw transaction data is sent to any cloud model; the only network dependency is the locally-verified Plus entitlement receipt, and the review keeps working through entitlement-service outages until receipt expiry + grace (30-day token TTL + 14-day grace per the entitlements design doc).
- [ ] Plus differentiation is the review itself plus advanced alert rules (AND-353) — institution-link count is not the gate; Personal users see a non-functional teaser, never degraded fake data.
- [ ] Export exists only as an explicit user action producing a redacted PDF (account numbers masked, no account ids), preceded by a preview of exactly what will be included; no automatic or background sharing paths exist.
- [ ] Baseline review is complete with transactions-only data; liabilities/investments/recurring-product sections render only when that data is present, and their managed-tier provider costs are documented (as estimates) in the managed-linking pricing doc.
- [ ] Partial-history state ("first full review available <date>") renders when fewer than two complete months are cached.
- [ ] Every chart has a text equivalent carrying the same conclusion; deltas use sign + symbol + text, never color alone; sections expose combined VoiceOver labels.

---

## 6. Sequencing & dependency summary

| Order | Issue | Depends on | Effort (est.) | Why this order |
|---|---|---|---|---|
| 1 | AND-352 cockpit | — | M (5–7d) | Sharpens the daily surface everything else lands on; pure refactor of existing components |
| 2 | AND-351 snapshot | AND-352 attention/threshold config | M (4–6d) | First-run aha; reuses cockpit cards |
| 3 | AND-354 recurring | — (shares stream persistence with AND-353) | M (5–7d) | Highest "found me money" value per day of work; detector already built |
| 4 | AND-353 alerts | AND-354 stream persistence; entitlement stub for Plus rules | L (8–10d) | Retention loop; consumes recurring streams |
| 5 | AND-355 monthly review | AND-353/354 shared logic; entitlement receipt; monthly rollup store | L (10–14d) | Plus anchor; needs 2 months of rollups accruing — ship the rollup writer earlier if possible |

Cross-cutting prerequisites (separate issues, referenced not specified here): VaultPeek rename of user-facing strings (`MenuBarSummary.text` fallbacks, `PlaidBarConstants.appName`), Stripe entitlement broker design doc (§0.2), managed-linking unit-economics doc (owns all Plaid per-product pricing).

## 7. Open questions

1. Does the unusual-spend baseline (4-week trailing median, 2.0× multiplier) hold up against demo fixtures, or does it need seasonal damping? (Decide during AND-352 with fixture experiments.)
2. Should the monthly rollup writer ship inside AND-352/351 so AND-355 has history on day one of Plus launch? (Recommended: yes — it's ~1 day of the AND-355 estimate pulled forward.)
3. Entitlement receipt format and grace — the Stripe entitlements design doc now proposes an Ed25519-signed token (PASETO v4.public or equivalent) with 30-day TTL + 14-day post-expiry grace; this roadmap only requires "locally verifiable, time-boxed, fails open within grace." (Decision: Felipe, via that doc's D1/D4.)
4. Lock-screen detail toggle default: this doc says off; confirm against Plaid's user-privacy guidance before AND-353 ships.
