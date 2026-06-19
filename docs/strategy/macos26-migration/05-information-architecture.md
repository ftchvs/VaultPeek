# VaultPeek macOS 26 — Information Architecture & Navigation Specification

Status: **Design proposal** (future-state). Part of the `macos26-migration`
strategy series. This document specifies the information architecture, navigation
model, and per-destination screen hierarchy for VaultPeek as a **single
integrated macOS 26 application** — a persistent windowed shell with a sidebar,
plus a reduced menu-bar glance.

> No real account identifiers, balances, institution names, Plaid payloads,
> tokens, local SQLite data, or private screenshots appear in this document. All
> examples use demo fixtures, per `CLAUDE.md` and the three-column popover
> contract.

This spec **reuses** the existing design language (`DESIGN.md`), accessibility
rules (`ACCESSIBILITY.md`), tokens (`Theme/DesignTokens`, `Typography`, the 8pt
`Spacing` grid), and the shipped SwiftUI components. It does not invent a parallel
system. Where it proposes new structure it names exactly which existing component
carries over and what new shell-level scaffolding is required.

---

## 0. Scope and the one structural change

Today VaultPeek is a **menu-bar popover** that became, through AND-367, a
three-column workspace (Wealth Summary rail · Dashboard center · Review/Inspector
column) with an on-demand detached `NSWindow` (AND-384, ux-audit-2026-06-13).
That three-column popover is dense and well-loved, but it forces *every* surface —
Review Inbox, Recurring, Category Dashboard, Settings — to either cram into a
320pt column or escape into a detached satellite window
(`ReviewTableWindow`, `CategoryDashboardWindow`, `RecurringPaymentsView`).

The macOS 26 future state inverts the default: **the window is primary, the
popover is a glance.** One `NavigationSplitView` shell hosts every destination as
a first-class sidebar item. The satellite windows collapse back into the shell as
sidebar destinations. No critical workflow lives in a popover.

This is the migration the ux-audit-2026-06-13 explicitly deferred ("SwiftUI
`Window` scene migration … out of scope given the popover-primary decision;
revisit if the product ever goes desktop-first"). This document is that revisit.

---

## 1. Design philosophy & principles

VaultPeek is a **finance instrument**, not a budgeting funnel. The product north
star (CLAUDE.md, GOAL.md) is RepoBar/CodexBar density: high-signal numbers one
keystroke away, native macOS restraint, privacy-first local presentation. Three
tensions define the design.

### 1.1 Trust before flash

Money UI lives or dies on trust. Every number must be sourced, dated, and
reversible. This is already encoded across the codebase and must carry into the
shell:

- **Sourced.** The Local Insight Receipt (`LocalAIInsightReceipt`) names its
  evidence — row count, time window, top category — and never invents. The
  "What the bank said" ledger (`BalanceTimeMachineView`) shows raw reported
  balances next to derived ones. The shell keeps this provenance visible, not
  buried.
- **Dated.** Safe-to-Spend shows "Updated 2 minutes ago"; sync freshness rides on
  every account row. No vague "recently."
- **Reversible.** Category overrides, rules, and bulk review actions are local
  overlays that never mutate raw Plaid records, and every one is undoable
  (`⌘Z`). The shell surfaces an explicit Undo affordance in the toolbar of any
  destination that mutates review/budget state.
- **Honest about storage.** The "Where your data lives" / Local Trust Receipt
  disclosure (`LocalTrustReceiptView`) appears in onboarding and Settings →
  Privacy, never hidden behind marketing language.

### 1.2 Calm under density

The shell must be *dense* (many numbers visible) and *calm* (no anxiety, no
clutter) at the same time. The levers, all already in the design system:

- **Hierarchy from size, casing, and opacity — not boldness or color.** Weights
  cap at semibold (`Typography.swift`). One hero number per surface
  (`.displayBalance()`); section labels are uppercase `.sectionTitle()`; data is
  `.dataText()` monospaced for column alignment.
- **Spacing, not cards, for grouping.** The `glassSurface(.raised/.inset/
  .emphasized)` three-rank system (SharedModifiers.swift) never nests more than
  two ranks; default surfaces draw no stroke. The shell extends this: sidebar and
  content are vibrancy-backed regions, not stacked web cards.
- **Color is reserved for meaning, never decoration.** Green = money in,
  red = debt/loss, orange = warning/pending, indigo = recurring, blue = brand.
  The same semantic palette governs every destination.

### 1.3 Glanceable everywhere

The same fact should read the same way in three places — menu-bar glance, sidebar
badge, and full destination — so the user builds one mental model. Example: the
Review queue count appears as (a) an optional menu-bar glance metric, (b) a count
badge on the **Review** sidebar row, and (c) the section headers inside the Review
Inbox. The attention rollup (`AttentionQueue`, max 3 rows) is the canonical
"do I need to act?" signal and surfaces identically in all three.

### 1.4 Operating principles (carried from GOAL.md, made shell-aware)

| Principle | Shell expression |
|-----------|------------------|
| At-a-glance first | Menu-bar glance + sidebar badges answer the 5 north-star questions without opening a destination |
| Dense but calm | `glassSurface` ranks; size/casing/opacity hierarchy; compact density mode |
| Status-rich | Persistent connection-health strip; per-destination empty/loading/error states |
| Finance-native semantics | One semantic color map across all 11 destinations |
| Keyboard-first | Command palette (`⌘K`) + global shortcut map + per-row keys; every action reachable without the mouse |
| Accessible by default | No meaning by color alone; VoiceOver labels; Reduce Motion; audio graphs for charts |
| Local-first / private | Privacy Mask + App Lock gate every destination uniformly |

---

## 2. Information architecture — destination tree

The sidebar is grouped into four bands. **Overview** is the daily landing zone;
**Workflows** are the verbs (where time is spent); **Money** is the noun reference
(accounts, the source of truth); **System** is configuration. Grouping the verbs
together is the Linear move — the sidebar reads as a list of *jobs to do*, not a
list of *data tables*.

```
VaultPeek (NavigationSplitView shell)
│
├── ▸ OVERVIEW
│   └── Dashboard ........................ [⌘1]  default landing destination
│         ├── Wealth Summary band (net worth hero, assets/debt, balance mix, 30D cashflow, credit)
│         ├── Attention rollup (≤3 rows, AttentionQueue)
│         ├── 365-day financial heatmap (Spend | Net toggle)
│         ├── Safe-to-Spend card (explainable headline)
│         ├── Spending-by-category preview → deep-links to Budgets
│         └── Recent / large transactions → deep-links to Transactions
│
├── ▸ WORKFLOWS
│   ├── Review .......................... [⌘2]  badge: unreviewed count
│   │     ├── List pane (date sections: Today / Yesterday / This Week / Earlier)
│   │     ├── Detail/triage pane (selected transaction: approve, recategorize, rule, rename, transfer, ignore)
│   │     └── Inspector (optional): rule preview / blast-radius / merchant history
│   │
│   ├── Budgets ......................... [⌘3]  badge: over-budget count
│   │     ├── Category tree (2-level groups → leaves, CategoryTreeView)
│   │     ├── Donut + totals header (SpendDonutChart)
│   │     ├── Flat sortable table (Category · Spent · Budget · Left · Status · Plan)
│   │     └── Budget editor (inspector/sheet: limit, suggested "ghost guardrail")
│   │
│   ├── Planning ........................ [⌘4]
│   │     ├── Projected balance forecast (ProjectedBalanceChart, 30–90D)
│   │     ├── Recurring obligations / subscriptions (RecurringPaymentsView)
│   │     ├── Income → category flow (IncomeCategoryFlowChart, Sankey)
│   │     └── Cashflow runway / what-if horizon controls
│   │
│   └── Goals ........................... [⌘5]  (new destination; see §5.6)
│         ├── Goal list (savings targets, payoff targets)
│         ├── Goal detail (progress ring, contribution pace, projected completion)
│         └── New-goal editor (inspector)
│
├── ▸ INSIGHTS
│   ├── Insights ........................ [⌘6]
│   │     ├── Local Insight Receipt feed (LocalAIInsightReceipt, sourced + dated)
│   │     ├── Weekly Review checklist (WeeklyReviewCard → full surface)
│   │     └── Trends (spend deltas, category drift, recurring changes)
│   │
│   └── Alerts .......................... [⌘7]  badge: unacknowledged count
│         ├── Alert feed (large txn, low balance, high utilization, recurring change, broken connection)
│         ├── Watchlist (merchant/category thresholds, AND-501)
│         └── Alert rule editor (inspector) → mirrors Notifications settings
│
├── ▸ MONEY
│   └── Accounts ........................ [⌘8]
│         ├── Institution groups (connection health, account count, sync state)
│         ├── Account list rows (type icon, balance, utilization, freshness)
│         └── Account inspector (AccountDetailFlyout: status, balances, 30D changes, to-review, top categories, recent activity, reconnect/remove)
│
└── ▸ SYSTEM
    └── Settings ........................ [⌘,]  (native Settings scene; tabs unchanged)
          └── General · Accounts · Appearance · Notifications · Privacy · About
```

Notes on the tree:

- **11 primary destinations** as required: Dashboard, Transactions (= the
  Transactions *view*, reachable from Review/Accounts deep-links and as a
  filtered list — see §5.2), Budgets, Planning, Goals, Review, Insights, Alerts,
  Accounts, Settings. Review and Transactions are distinct: **Review is the
  triage *inbox* (a queue of items needing a decision); Transactions is the full
  searchable *ledger*.** Both render the same `TransactionRow` vocabulary.
- **Transactions** is listed in the sidebar under WORKFLOWS between Review and
  Budgets (omitted from the band diagram above for brevity; see §5.2). It is the
  reference ledger; Review is the action queue over a subset of it.
- The four satellite windows that exist today (`ReviewTableWindow`,
  `CategoryDashboardWindow`, `RecurringPaymentsView` window, the detached
  dashboard panel) all become **content of a sidebar destination**, not separate
  windows. Power users can still tear a destination into its own window via the
  standard macOS `⌘N`-new-window / "Open in New Window" path (see §3.6).

### 2.1 Selection & deep-linking model

A single `@Observable` `NavigationModel` owns the selected destination, the
selection within a destination (e.g. `selectedTransactionID`,
`selectedAccountID`, `selectedCategory`, `selectedGoalID`), and the inspector
state. This replaces today's scattered `@AppStorage("dashboard.selectedAccountId")`
/ `"dashboard.accountFilter"` keys with one routable state.

Deep links use a typed `Route` enum so any surface can navigate anywhere:

```
enum Route {
  case dashboard
  case review(itemID: String?)
  case transactions(filter: TransactionFilter, focus: String?)
  case budgets(category: SpendingCategory?)
  case planning(section: PlanningSection)
  case goals(id: UUID?)
  case insights(section: InsightSection)
  case alerts(id: String?)
  case accounts(itemID: String?)
  case settings(tab: SettingsTab)
}
```

Examples of routing that the shell must support:
- Dashboard "category preview" row → `budgets(category: .food)` (opens Budgets
  with that leaf focused).
- Account inspector "To review (N)" → `review(itemID: firstID)` (jumps to Review
  with that item selected).
- Alert "High utilization on card" → `accounts(itemID:)` (opens Accounts with the
  card inspector).
- Weekly Review checklist item → its `WeeklyReviewNavigationTarget`
  (`.reviewInbox` / `.recurring` / `.safeToSpend`) maps onto the new routes.
- Menu-bar glance "Open VaultPeek" → `dashboard`; a glance attention chip →
  `review` or `alerts`.

Selection persistence: the last destination and per-destination selection persist
across launches (as today via `@AppStorage`), but now keyed on the `Route` so a
relaunch lands exactly where the user left off — modulo App Lock, which forces the
gate first.

---

## 3. Navigation model

### 3.1 The shell — `NavigationSplitView`

The shell is a single `NavigationSplitView`. Every destination chooses **2-column**
(sidebar + content) or **3-column** (sidebar + content + detail/inspector) based on
whether it has a meaningful master→detail relationship. macOS 26
`NavigationSplitView` handles column visibility, the unified toolbar, and sidebar
collapse natively.

| Destination | Columns | Rationale |
|-------------|---------|-----------|
| **Dashboard** | **2** | A composed overview canvas; no list→detail. Drill-ins deep-link to other destinations rather than opening a local third column. |
| **Review** | **3** | The core triage flow is list ↔ detail; the optional third pane shows rule-preview / blast-radius. This is the marquee 3-column case. |
| **Transactions** | **3** | Table (list) → transaction inspector (detail). Filter rail folds into a toolbar + optional left filter section. |
| **Budgets** | **3** | Category tree/table (list) → budget editor inspector (detail). |
| **Planning** | **2** | A composed analytical canvas (forecast + recurring + flow); sub-sections switch via a segmented control, not a master list. |
| **Goals** | **3** | Goal list → goal detail/progress → new-goal editor inspector. |
| **Insights** | **2** | A feed of receipts + weekly review; reading surface, not master→detail. Selecting a receipt expands in place. |
| **Alerts** | **3** | Alert feed (list) → alert detail / rule editor (inspector). |
| **Accounts** | **3** | Institution/account list → `AccountDetailFlyout` inspector (the existing, proven master→detail). |
| **Settings** | n/a | Native macOS `Settings` scene (separate window, tabbed) — unchanged. |

**Verdict in one line:** Dashboard, Planning, Insights are **2-column**; Review,
Transactions, Budgets, Goals, Alerts, Accounts are **3-column**; Settings stays a
native tabbed Settings window.

The third column is **content-gated, not existence-gated** — the lesson the
ux-audit-2026-06-13 made explicit and the three-column contract codified: keep the
column, vary its content. With nothing selected, the inspector shows a
`ContentUnavailableView` prompt (e.g. "Select a transaction to review"), never a
collapse. `NavigationSplitView`'s `.detailColumnWidth` and the `preferredCompact`
behavior cover the screen-constrained fallback the popover had to hand-roll
(AND-374); on narrow displays the detail column collapses to a push-navigation
sheet rather than overlaying.

### 3.2 Sidebar

The sidebar is a new shell-level `List` with `Section` headers for the four bands.
Each row: SF Symbol + label + optional **count badge** (trailing, secondary,
text — never a color-only dot). Badges:

| Destination | Badge source | Hidden when |
|-------------|-------------|-------------|
| Review | `TransactionReviewInboxSnapshot.totalCount` (high-priority emphasized) | queue clear |
| Budgets | `CategoryBudgetPresentation.overBudgetCount` | nothing over |
| Alerts | unacknowledged alert count | none unacked |
| Accounts | items needing reconnect (`AttentionQueue` blocked rows) | all healthy |

The sidebar footer holds a **persistent connection-health strip**
(`ConnectionHealthStripView`) and the data-mode chip (Demo / Sandbox /
Production) — the status the popover footer carries today, now always visible.

Sidebar is collapsible (`⌘\` and the native control); collapsing favors the dense
content+detail layout for small screens.

### 3.3 Command palette (`⌘K`)

A new shell-level component (the single most important new piece). A
spotlight-style overlay with fuzzy search across three action classes:

1. **Navigate** — "Go to Budgets", "Open Review", "Accounts → Chase". Jump to any
   `Route`, including a specific account, category, or goal.
2. **Act** — verbs that work from anywhere: "Refresh", "Add account", "Set budget
   for Groceries", "Mark all reviewed", "Create rule…", "Toggle Privacy Mask",
   "Export CSV", "Undo".
3. **Find** — search transactions by merchant/amount/category and jump to the
   match in Transactions or Review.

Implementation: a `CommandRegistry` of `Command { id, title, subtitle, symbol,
shortcut?, action, isEnabled }`. Each destination registers its contextual
commands when active; global commands (refresh, add account, privacy, navigate)
are always registered. The palette respects Privacy Mask (no merchant names in
results while masked) and App Lock (unavailable while locked).

This is what makes the app **keyboard-first**: any action that exists is one
`⌘K`-and-type away, so the keyboard map below is a fast-path layer over the
palette, not the only way in.

### 3.4 Global keyboard map

A real `CommandGroup` / `CommandMenu` structure (the codebase has *no* centralized
command menu today — shortcuts are ad-hoc per-view). The shell introduces menu-bar
menus (View, Go, Account, Edit) so shortcuts are discoverable in the menu bar and
in the `⌘K` palette.

| Shortcut | Action | Scope |
|----------|--------|-------|
| `⌘K` | Open command palette | Global |
| `⌘1`…`⌘8` | Go to destination N (Dashboard…Accounts) | Global |
| `⌘,` | Settings | Global |
| `⌘R` | Refresh / sync now | Global (carries over) |
| `⌘N` | Add account / connect bank | Global (carries over) |
| `⌘F` | Focus search (current destination) | Global |
| `⌘⇧P` | Toggle Privacy Mask | Global (carries over) |
| `⇧⌘V` | Summon VaultPeek from any app | System hotkey (carries over) |
| `⌘\` | Toggle sidebar | Global |
| `⌘Z` / `⇧⌘Z` | Undo / Redo last review or budget action | Global (carries over) |
| `↑` / `↓` or `J` / `K` | Move selection in list pane | List destinations |
| `Return` | Open / confirm selection | List destinations |
| `Esc` | Clear selection → (2nd press) close inspector / dismiss | Global |

Per-row triage keys inside **Review** (carried verbatim from `ReviewInboxView`):

| Key | Action |
|-----|--------|
| `A` | Approve selected |
| `C` | Recategorize (opens category menu) |
| `T` | Toggle transfer / not transfer |
| `R` | Rule menu (create durable rule) |
| `M` | Rename merchant |
| `I` | Ignore |
| `⌘Z` | Undo last review action |

> Conflict note: today `A/C/T/I/M/R` are bare keys inside the Review surface. In
> the windowed shell they remain bare-key accelerators **only while focus is in
> the Review list/detail**; they are never global (so typing in a search field is
> safe). The `⌘1–8` navigation and `⌘K` palette take precedence at the shell
> level.

### 3.5 Selection & focus behavior

- Selecting a list row fills the detail column and shows the native accent
  highlight; the two stay synchronized (one selection state), exactly the
  contract the three-column popover already guarantees (§6 of
  `three-column-popover-contract.md`).
- `Esc` clears the selection first (detail reverts to its `ContentUnavailableView`
  prompt), then on a second press dismisses any inspector sheet — never both at
  once.
- After a triage action that removes the row from the queue (approve/ignore),
  focus advances to the **next** item so the user can clear the inbox without
  touching the mouse (Linear/Reeder inbox behavior). After deselect, focus
  returns to the previously selected row.

### 3.6 Menu-bar glance → window hand-off

The menu bar keeps a `MenuBarExtra` but its content shrinks to a **glance**
(see §6). The hand-off:

- Click "Open VaultPeek" (or the menu-bar icon's primary action) →
  `NSApp.activate` + bring the main window forward at the last `Route`. If the
  window is closed, create it; if minimized, deminiaturize.
- A glance attention chip ("3 to review", "Card over 75%") is a button that opens
  the window **at the relevant destination** (`review` / `alerts` / `accounts`),
  not just the dashboard.
- `⇧⌘V` (summon hotkey) does the same window-forward, from any app.
- The glance never opens a popover workflow; it is a launcher + status readout.

---

## 4. Component reuse map

What carries over unchanged, what adapts, and what is genuinely new.

### 4.1 Carries over unchanged (tokens + components)

| Asset | Where it lives | Reuse in shell |
|-------|----------------|----------------|
| `Spacing` (8pt grid), `Radius`, `Sizing` | DesignTokens | All shell layout |
| `Typography` modifiers (`.displayBalance`, `.sectionTitle`, `.dataText`, `.detailText`, `.microText`) | Typography.swift | All text |
| Semantic colors + utilization ladder | DESIGN.md / SemanticColors | All destinations |
| `glassSurface(.raised/.inset/.emphasized)` | SharedModifiers.swift | Content panels everywhere |
| `MotionTokens` (+ Reduce Motion gating) | SharedModifiers.swift | All animation |
| `AccountDetailFlyout` + `AccountDetailInsights` | Views / Core | **Accounts** detail column verbatim |
| `ReviewInboxView` (+ rows, banners, rule prompt) | ReviewInboxView.swift | **Review** list pane |
| `ReviewTableWindow` table + bulk model | ReviewTableWindow.swift | **Transactions/Review** table mode |
| `CategoryTreeView`, `CategoryDashboardWindow`, `CategoryStatusBar`, `CategoryDashboardCard` | Views | **Budgets** |
| `BudgetEditorSheet`, `SuggestedBudgetAcceptButton` | Views | **Budgets** editor |
| `SafeToSpendCard` | Views | Dashboard + Planning |
| `RecurringPaymentsView`, `RecurringObligationsSection` | Views | **Planning** |
| `ProjectedBalanceChart`, `IncomeCategoryFlowChart`, `SpendDonutChart`, `BalanceTrendChart` | Charts | Planning / Budgets / Dashboard |
| `WealthSummaryFlyout` sections | WealthSummaryFlyout.swift | **Dashboard** overview band |
| `WeeklyReviewCard` | WeeklyReviewCard.swift | **Insights** |
| `AttentionQueueView` + `AttentionQueue` model | Views / Core | Dashboard + sidebar badges + glance |
| `BalanceTimeMachineView` ("What the bank said") | Views | Accounts / Planning |
| `LocalAIInsightReceipt` + `LocalInsightsCard` | Core / MainPopover | **Insights** feed |
| `ConnectionHealthStripView` | Views | Sidebar footer |
| Privacy Mask + App Lock gate, snapshots | AppState | Shell-wide overlay |
| `SettingsView` (6 tabs) | Settings | **Settings** scene verbatim |
| All pure presentation/Core models | PlaidBarCore | Unchanged |

### 4.2 Adapts (same component, new host)

- **`MainPopover`'s three-column body** → decomposed: the Wealth Summary becomes
  the **Dashboard** overview band; the center heatmap/filters/rows split between
  **Dashboard** and **Transactions**; the inspector logic moves into per-
  destination detail columns. `PopoverGeometry`/`PopoverWindowAnchor` retire
  (the window manages its own geometry).
- **The detached `NSWindow` host** (`DetachedDashboardCoordinator`) → becomes the
  *main* window; the popover-as-primary plumbing inverts. True translucency
  (`NSVisualEffectView(.behindWindow)`, `isOpaque=false`) carries over for the
  Liquid Glass backdrop the audit already shipped.
- **`MenuBarLabel`** → keeps the summary-mode picker logic but feeds the reduced
  glance, not a full popover.
- **Esc / selection / focus contract** → generalizes from the inspector column to
  every 3-column destination.

### 4.3 New shell-level components

| New component | Responsibility |
|---------------|----------------|
| `AppShellView` (NavigationSplitView host) | Sidebar + content + detail; column policy per destination |
| `SidebarView` + `SidebarItem` | Banded list, count badges, footer health strip + mode chip |
| `NavigationModel` (`@Observable`) | Selected `Route`, per-destination selection, inspector state, persistence |
| `CommandPalette` + `CommandRegistry` | `⌘K` overlay; navigate / act / find |
| `AppCommands` (`CommandMenu`/`CommandGroup`) | Menu-bar menus + global shortcut definitions |
| `DestinationToolbar` | Per-destination unified toolbar (search, filter, refresh, Undo) |
| `TransactionsView` | The full searchable ledger destination (new framing over existing rows/table) |
| `GoalsView` + `GoalEditor` + `GoalProgressRing` | The new Goals destination (§5.6) |
| `AlertsView` | Alert feed over existing notification/watchlist models |
| `GlanceView` | The reduced menu-bar content (§6) |

Everything in 4.3 is **scaffolding** — it composes existing dense components into
a shell. No new finance logic; per CLAUDE.md, any genuinely new logic (e.g. Goals
math) lands in `PlaidBarCore` as pure, `Sendable`, tested types.

---

## 5. Screen hierarchy — per destination

Each destination below: regions, key components (reused names), density treatment,
primary/secondary actions, and states. Deepest treatment for **Review**,
**Transactions**, **Budgets/Planning**, **Insights**, per the brief.

### 5.1 Dashboard (2-column) — `[⌘1]`

**Purpose:** answer the five north-star questions in one glance. The composed
landing canvas.

**Regions (content column, single scroll):**
1. **Header** — one net-worth hero (`.displayBalance()`) + `BalanceTrendChart`
   sparkline + sync-health pill. *(One hero per surface; the rule the contract
   enforces — net worth lives here, not duplicated elsewhere.)*
2. **Attention rollup** — `AttentionQueueView`, ≤3 rows, each with an action
   button (reconnect / refresh / add account). Hidden when all healthy.
3. **Metric band** — assets / debt / balance mix / 30D cashflow (income · spend ·
   net) from `WealthSummaryFlyout` sections, laid out as inline separator-backed
   metrics (not nested cards — the AND-372 flatten lesson).
4. **365-day heatmap** — Spend | Net toggle, neutral Less/More ramp in Spend mode,
   bidirectional legend in Net mode. The signature RepoBar surface.
5. **Safe-to-Spend** — `SafeToSpendCard`, collapsed by default, expandable
   breakdown.
6. **Category preview** — `CategoryDashboardCard` top-3 groups → "Open dashboard"
   deep-links to **Budgets**.
7. **Recent / large transactions** — a few `TransactionRow`s → deep-link to
   **Transactions**.

**Density:** highest-density destination; everything visible without expansion.
Comfortable vs Compact density preference (`AppDensityPreference`) tightens row
padding.

**Primary actions:** Refresh (`⌘R`), Add account (`⌘N`). **Secondary:** toggle
heatmap mode, expand Safe-to-Spend, any deep-link.

**States:** Loading → skeletons (`LoadingSkeletons`, `.loadingRedaction()`).
Empty (no accounts) → `ContentUnavailableView` "Connect a bank to begin" + Connect
button (no fake cards). Offline/error → attention rollup carries the recovery
action; the rest of the shell stays usable. Masked → values dotted, structure
intact.

### 5.2 Transactions (3-column) — the ledger

**Purpose:** the full, searchable transaction history. The *reference*, distinct
from Review's *queue*.

**Regions:**
- **List/table column** — `ReviewTableWindow`'s table engine reframed as the
  ledger: columns **Merchant · Amount · Date · Category · Account · Status**,
  sortable (`ReviewTableSort` extended). Rows are `TransactionRow` /
  `ReviewTableRow`. Date-grouped or flat (toolbar toggle).
- **Toolbar** — `⌘F` search field (merchant / amount / category); filter controls
  reusing `DashboardAccountFilter` (All · Cash · Credit · Savings · Debt ·
  Investments) + category + date-range chips (`FilterChipsView` vocabulary);
  Export menu (CSV / JSON, disabled while masked/locked).
- **Detail column (inspector)** — `TransactionDetailView` content (category icon,
  merchant, raw name, amount, date, account, status) **plus** the same triage
  controls Review offers (recategorize, rule, transfer, rename) so the user can
  act without bouncing to Review.

**Density:** table density; monospaced amounts; zebra-free, hairline separators.
Virtualized list (the large-history virtualization + paged fetch already shipped,
AND-567) carries over.

**Primary actions:** Search (`⌘F`), filter, sort, recategorize/rule from
inspector. **Secondary:** export, jump-to-account, "Review this" → `review(itemID)`.

**States:** Loading → paged skeleton rows. Empty distinguishes **no synced
history** ("No transactions yet — sync to populate") from **filters return zero**
("No matches — clear filters"), per GOAL.md's sharper-empty-states requirement.
Error → "Couldn't load history" + retry. Masked → amounts/merchants dotted.

### 5.3 Review (3-column) — the triage inbox **[deepest]** — `[⌘2]`

**Purpose:** clear the queue of transactions needing a human decision. This is the
flagship keyboard-driven workflow — the Linear/Reeder inbox, applied to money.

**The flow, end to end:**

1. **List column** — `ReviewInboxView(embedded:)` content, date-sectioned
   (**Today / Yesterday / This Week / Earlier**). Each `ReviewInboxRow`: merchant
   · amount · `CategoryPill` · reason chips (uncategorized / new merchant /
   unusual amount / possible transfer / recurring changed / pending changed /
   changed since review — `TransactionReviewReason`, text + glyph, never color
   alone). High-priority reasons sort to the top.
2. **Detail/triage column** — the selected item's full triage surface:
   - **Approve** (`A`) — mark reviewed, advance to next.
   - **Recategorize** (`C`) — category menu; on apply, offers the inline
     `InlineCategoryRulePromptBanner` — *"Always categorize {merchant} as
     {category}?"* → **Create rule** / **Dismiss** (suppressed if masked, blank,
     or a duplicate rule exists).
   - **Rule** (`R`) — create a durable `TransactionRule` (merchant→category or
     transfer) without recategorizing first.
   - **Transfer / Not transfer** (`T`) — toggle the transfer override (excludes
     from budgets).
   - **Rename merchant** (`M`) — text field + Rename.
   - **Ignore** (`I`) — mark reviewed unless materially changed.
   - Every action fires a `ReviewActionConfirmationBanner` (auto-dismiss 2.5s) +
     haptic (AND-576) + VoiceOver announcement; all are `⌘Z`-undoable.
3. **Inspector (optional 3rd region within detail, or a slide-over)** —
   **rule preview / blast radius**: when creating a rule or staging a bulk action,
   show exactly which transactions it will touch
   (`ReviewBulkActionPlan.blastRadiusDescription` — "Mark N reviewed: A, B, C, and
   M more") *before* applying. Also: merchant history (prior categorizations) to
   inform the decision.

**Bulk / multi-select:** the `ReviewTableWindow` model becomes a **table mode**
toggle inside Review (segmented: *Triage* | *Table*). Table mode gives
multi-select with `Recategorize` / `Mark transfer` / `Mark reviewed` over a
selection, each gated by a blast-radius confirmation dialog (titles + confirm
labels from `PendingReviewBulkAction`). Per-section **"Approve N"** stays in
triage mode for fast section-clearing.

**Density & progressive disclosure:** the list is compact (one two-line row); the
*selected* row's full control set lives in the detail column, not inline, so the
list stays scannable (progressive disclosure done right). Compact density mode
tightens row height further.

**Keyboard-first:** the whole loop is `↓` to next, `A`/`C`/`T`/`R`/`M`/`I` to act,
`⌘Z` to undo — no mouse. This is the destination that most embodies the
keyboard-first principle.

**States:**
- **Empty / clear** — `ContentUnavailableView` "Inbox Clear — New or unusual
  transactions show up here to review, recategorize, or rename." (verbatim copy).
- **Loading** — skeleton rows; never an offline verdict while `isBooting`.
- **Masked** — "Review items, merchants, and amounts are hidden while Privacy Mask
  or App Lock is active." (verbatim); triage controls disabled.
- **No selection** — detail shows "Select a transaction to review."
- **Error** — sync error banner with retry; queue from last good snapshot stays
  readable.

### 5.4 Budgets (3-column) **[deep]** — `[⌘3]`

**Purpose:** see where the month's money went by category and set/keep limits.
Copilot-style category dashboard, now a first-class destination.

**Regions:**
- **List column** — `CategoryTreeView`: 2-level disclosure (group rollups →
  leaves). Each row a `CategoryStatusBar` (track fill + verdict: **On track /
  Close to limit / Over budget / No budget set** — text + glyph, never color
  alone; 80% = nearing threshold). Groups that are *over* or *nearing* expand by
  default. Toolbar toggle to a **flat sortable table**
  (`CategoryDashboardWindow` table: Category · Spent · Budget · Left · Status ·
  Plan; sort by Spend↓ or Group-then-Spend; footer totals).
- **Header band** — `SpendDonutChart` (this month, by `CategoryGroup`, center
  total) + Spent / Budgeted / Left totals.
- **Detail column (editor inspector)** — `BudgetEditorSheet` content inline:
  monthly-limit field, validation footer ("Enter a positive dollar amount." /
  "Sets the monthly limit to $X." / "Saving 0 removes this budget."), and the
  **suggested "ghost guardrail"** row with one-tap `SuggestedBudgetAcceptButton`
  ("Set $X limit", `wand.and.stars`). Income/transfer categories show the
  read-only advisory "Income and transfer categories can't have a budget."

**Density:** tree rows are compact; the status bar packs spend/limit/% into one
line. Progressive disclosure: groups collapse; the editor lives in the inspector,
not inline per row.

**Primary actions:** Set/Edit budget (per row → inspector), Accept suggestion.
**Secondary:** sort, switch tree/table, deep-link a category from Dashboard.

**States:** Empty → "No category spending yet — Spending appears here once this
month's transactions arrive." Loading → skeleton rows. No-suggestion → "Not enough
history." Masked → amounts dotted, structure intact.

### 5.5 Planning (2-column) **[deep]** — `[⌘4]`

**Purpose:** look forward — runway, recurring obligations, and where income flows.

**Regions (segmented sub-sections, not a master list):**
1. **Forecast** — `ProjectedBalanceChart`: solid recorded trend → dashed forward
   30–90D, "today" anchor rule, projected-low marker, confidence cue ("Forecast
   from recurring patterns" / "Indicative only"). Horizon control (30 / 60 / 90D)
   + a what-if input (manual expected income, safety buffer — feeds
   `SafeToSpendInputs`).
2. **Recurring & subscriptions** — `RecurringPaymentsView` content: per-row
   merchant · amount · frequency · last/next dates · confidence · flag
   explanations (price increase / stale / forgotten) · "How to cancel" link.
   Monthly-estimate header.
3. **Income → category flow** — `IncomeCategoryFlowChart` (Sankey): income sources
   → spending categories, proportional ribbons, text legend, "aggregate-
   proportional, not per-transaction" caveat.

**Density:** chart-forward (more whitespace than the ledger); legends are
text+glyph for color independence; audio graphs (`ChartAudioGraphDescriptor`) for
VoiceOver.

**Primary actions:** change horizon, what-if inputs, "How to cancel" (per
subscription). **Secondary:** jump to a category's budget; jump to an account.

**States:** Forecast needs history → "Forecast appears after ~7 days of data."
Recurring empty → "No recurring payments detected — VaultPeek will list
subscriptions here after enough history." Offline/error → "Recurring charges
unavailable" + cause + retry (verbatim load-state copy). Masked → amounts dotted.

### 5.6 Goals (3-column) — `[⌘5]` (new destination)

**Purpose:** track savings/payoff targets against real balances. GOAL.md scopes
VaultPeek away from "full budgeting," so Goals stays **lightweight and
observational**: it reads balances + recurring + safe-to-spend and projects pace;
it does not move money or enforce.

**Regions:**
- **List column** — goal rows: name · target · current · progress ring
  (`GoalProgressRing`, % + text label) · projected-completion date. Two kinds:
  *savings target* (account balance → target) and *payoff target* (debt → $0).
- **Detail column** — progress ring large, contribution pace (derived from 30D
  cashflow / recurring), projected completion, and a "on pace / behind / ahead"
  verdict (text + glyph). Links to the underlying account.
- **Editor inspector** — name, kind, target amount, target date, linked
  account(s).

**New logic** (`PlaidBarCore`, pure + tested): `Goal`, `GoalProgress`,
`GoalProjection` (pace from cashflow, ETA, on-pace verdict). No network surface;
goals are local overlays.

**Density:** medium; progress rings give a fast read; numbers monospaced.

**States:** Empty → "No goals yet — Create a savings or payoff goal." Insufficient
data → "Add more history to project a completion date." Masked → amounts dotted,
ring + label still shown.

### 5.7 Insights (2-column) **[deep]** — `[⌘6]`

**Purpose:** the local-AI / deterministic insight surface and the weekly ritual.
Strictly local, strictly sourced — the trust principle made a destination.

**Regions (feed):**
1. **Local Insight Receipts** — `LocalAIInsightReceipt` cards: one-line headline,
   evidence chips (source-row count, time window e.g. `2026-06-05 to 2026-06-11`,
   top display category, recurring estimate), confidence + limitations rows, an
   always-visible **Local-only** badge, and reversible-action copy. Receipts never
   show raw IDs/tokens; headlines redact known local identifiers.
2. **Weekly Review** — `WeeklyReviewCard` expanded into a full checklist:
   outcome badge ("Looks good" / "Review these few items" / "Pay attention" /
   "Transaction review required"), N/M complete, items each with a checkbox +
   severity icon + action button routing to `reviewInbox` / `recurring` /
   `safeToSpend`. A "Complete Review" affordance.
3. **Trends** — spend deltas vs prior period (`SpendingComparison`: arrow +
   signed amount + "vs last period", color *and* arrow), category drift, recurring
   changes.

**Density:** reading-density (generous), but each receipt is compact. Progressive
disclosure: receipts expand to show full evidence/limitations; weekly items expand
to detail.

**Primary actions:** complete a weekly item, accept/reject a category hint
(reversible local overlay), check local-AI availability. **Secondary:** route to
the source destination.

**States:** Local AI off / no runtime → the receipt states it plainly ("Local
runtime unavailable") *without blocking* — deterministic receipts still render;
the rest of the app is unaffected. Not-enough-history → confidence downgrades and
says so. Weekly not due → "Weekly review not ready" + next date. Waiting on data →
"Weekly review will appear once transaction data is ready." Masked → headlines/
evidence use display-safe counts only (already the contract).

### 5.8 Alerts (3-column) — `[⌘7]`

**Purpose:** a feed of things VaultPeek flagged, plus the watchlist that generates
them. Mirrors Notifications settings but as a *destination* (history + state),
not just a config screen.

**Regions:**
- **List column** — alert feed: large-transaction, low-balance, high-utilization,
  recurring-change, broken-connection, and watchlist hits. Each row: severity
  glyph + title + detail + timestamp + acknowledged state.
- **Detail column** — the triggering transaction/account/recurring stream + a
  jump-to action (deep-links to Transactions / Accounts / Planning).
- **Watchlist editor (inspector)** — AND-501 watchlist: add by Merchant or
  Category + threshold; saved watches list. Plus a link to Settings →
  Notifications for the trigger toggles + thresholds.

**Density:** feed-density; unacknowledged emphasized (weight + glyph, not color
alone). Sidebar badge = unacknowledged count.

**Primary actions:** acknowledge / acknowledge-all, add watch. **Secondary:** jump
to source, mute a trigger (routes to Notifications).

**States:** Empty → "No alerts — You're all caught up." Notifications permission
denied → status row + "Open System Settings". Masked → alert bodies use safe copy
(no merchant/exact balance), matching the lock-screen notification policy.

### 5.9 Accounts (3-column) — `[⌘8]`

**Purpose:** the source-of-truth ledger of connected institutions and accounts.

**Regions:**
- **List column** — institution groups (`AccountSettingsView` grouping):
  institution name + connection-health (icon + signal label) + account count +
  sync state; recovery action (Reconnect / Refresh) when login-required / error /
  stale; Remove (destructive). Account rows: type icon + name + type + balance
  (monospaced) + utilization (for credit) + sync freshness.
- **Detail column** — `AccountDetailFlyout` **verbatim**: header (name /
  institution / type / mask), Status (connection badge + freshness + recovery),
  Balances (Available / Current / Utilization), Changes · 30 days (signed deltas,
  arrow + sign + color), To review (pending + large, with reason chips, → Review),
  Top categories · 30 days, Recent activity (6 rows), account actions (reconnect /
  remove / settings) + "What the bank said" ledger (`BalanceTimeMachineView`).

**Density:** the proven account-row density (one shared two-line rhythm across all
account families, T021). Detail is sectioned by spacing, never nested cards.

**Primary actions:** Add account (`⌘N`), Reconnect, Refresh, Remove. **Secondary:**
"To review" → Review; settings.

**States:** Empty → "No accounts connected" + Connect. Degraded item →
Status section recovery detail + Reconnect. Loading → shimmer on amounts, name/
avatar visible. Disconnected → dimmed row + inline Reconnect + "—" amount.

### 5.10 Settings (native Settings scene) — `[⌘,]`

Unchanged: the native macOS `Settings` window, 6 tabs — **General · Accounts ·
Appearance · Notifications · Privacy · About** — each a grouped `Form`. The shell
opens it via `⌘,` and the app menu; it is a separate window, as macOS expects. The
in-shell **Accounts** destination handles the *operational* (reconnect/inspect)
side; Settings → Accounts keeps the *configuration* side (this is fine — they
serve different intents and already coexist).

---

## 6. Menu-bar glance spec

The menu bar shrinks from a full workspace to a **glance**: a launcher with status
and 2–4 metrics. This is the deliberate inversion — the popover stops being where
work happens.

**What the glance shows (top to bottom):**
1. **Menu-bar label** (`MenuBarLabel`, unchanged) — the chosen summary mode
   (Net worth / Total cash / Credit utilization / Recent spend / Icon-only) +
   optional live signal meter (AND-485). Privacy-mask aware (dots).
2. **Status line** — data mode (Demo / Sandbox / Production) · server state
   (Connected / Offline / Syncing / Error) · last-sync freshness. The
   `ConnectionHealthStripView` condensed to one line.
3. **2–4 glance metrics** — a tight grid, user-relevant, read-only:
   - Net cash (or net worth) · highest credit utilization · safe-to-spend ·
     "N to review". Each is a `dataText` number + a one-word label; attention
     items (over-utilization, items to review) render as **buttons** that open the
     window at the right destination.
4. **Attention chips** — up to 3 `AttentionQueue` rows (reconnect needed, sync
   error) — tappable, route into the window.
5. **"Open VaultPeek"** — the primary affordance; `⇧⌘V` also summons. Plus a
   compact Refresh and a Privacy-Mask toggle (`⌘⇧P`).

**What the glance must NOT do:**
- No triage (no approve/recategorize/rule) — that is Review in the window.
- No budget editing, no goal editing, no settings forms.
- No tables, no charts beyond the menu-bar signal meter, no account inspector.
- No multi-column layout, no detached-workspace mode.
- No scrolling lists of transactions.
- Never present a workflow that can't be finished in the glance — if it needs a
  decision, the glance routes to the window.

The glance is **read + route**, period. It answers "do I need to open the app?"
and gets you there in one click. (A future iteration could mirror this as a
WidgetKit widget + Control Center control reusing the same `Glance` model — the
App Intents `FinanceSnapshot` already exists.)

---

## 7. Onboarding / first run (windowed)

The existing `SetupView` three-stage flow (Choose → Link-prep → Connecting) is
sound; it moves from "popover at 480pt" to **the main window's content column with
the sidebar hidden** until setup completes (the contract's "Setup renders alone"
rule, generalized).

**Flow:**
1. **Choose** — window opens centered, sidebar suppressed. App icon + "VaultPeek"
   + three `OnboardingChoiceButton`s: **View Demo** (instant fixtures) ·
   **Connect Sandbox** · **Connect Production**. The "Where your data lives"
   disclosure (`LocalTrustReceiptView`) is present before any link — storage path,
   credential location, no-cloud statement.
2. **Link-prep** — storage disclosure + preflight panel (per-check rows: ready /
   blocked / unknown) + (production) plan preview (`PlanSelectionShell`,
   count-only). "Open Link" (disabled if preflight blocked) · "Back".
3. **Connecting** — progress through "Waiting for Plaid Link" → "Item linked" →
   "First sync" → "Dashboard ready" with `FirstRunCompletionPanel`.
4. **First success** — sidebar reveals (animated, Reduce-Motion-gated); the window
   lands on **Dashboard** with `FirstRunSnapshotView` (Cash / Net worth / MTD /
   Credit + large recent transactions), self-dismissible.

**Empty-state coaching:** newly revealed destinations with no data show
purposeful empties (Review "Inbox Clear", Budgets "No category spending yet",
Goals "Create a savings or payoff goal") rather than blank columns — so the
sidebar teaches the app's vocabulary on first run.

A lightweight **what's-here tour** (optional, dismissible) can highlight the
sidebar bands and `⌘K` once, the first time the window is shown post-setup.

---

## 8. Accessibility & keyboard-first notes

Per `ACCESSIBILITY.md` and the three-column contract, these are non-negotiable and
apply to **every** destination:

- **No meaning by color alone.** Already enforced component-by-component
  (utilization ladder = icon change; income = `+` prefix; pending = "Pending"
  text; status bars = verdict text + glyph; selection = native highlight + state
  announced). The shell adds: **sidebar badges are text counts, not color dots;
  attention/severity always carry a glyph + label; over-budget and behind-pace
  verdicts are text-first.**
- **VoiceOver.** Each destination is a labeled landmark; the sidebar announces
  destination + badge ("Review, 4 items to review"). The Review triage loop
  announces every action ("Approved {merchant}") and the inspector announces
  "Shows transaction detail." Charts ship audio graphs
  (`ChartAudioGraphDescriptor`) and a summary string ("Spending by category.
  Largest: {category} at {percent}.").
- **Keyboard-first / focus order.** Sidebar → content → detail is the tab order;
  `⌘1–8` jump destinations; `⌘K` reaches any action; `↑/↓` + `Return` drive lists;
  `Esc` clears-then-dismisses; the Review per-row keys work only with list focus
  (never global, so search fields are safe). Every inspector close affordance has
  a label and a focus stop. No action is mouse-only.
- **Reduce Motion.** Column reveal, sidebar collapse, selection transitions, chart
  entry, and the matched-geometry filter reflow (AND-577) all route through
  `MotionTokens.animation(_:reduceMotion:)` — opacity instead of slide/spring when
  on.
- **Contrast / Increase Contrast / Reduce Transparency.** Honor the
  `AppContrastPreference` and the transparency slider; the glass backdrop must
  degrade to a legible solid under Reduce Transparency (the audit's open P2 — the
  shell should dim *under* the glass, not paint over it).
- **Text size & density.** macOS ignores system Dynamic Type, so the
  `TextSizePreference` lever and Comfortable/Compact `AppDensityPreference` are the
  knobs; the largest steps must reflow, not clip — the multi-pane layout makes this
  easier than the fixed-width popover did.
- **Privacy as accessibility of trust.** Privacy Mask and App Lock gate every
  destination uniformly; masked surfaces keep structure (so VoiceOver users still
  get layout) while withholding values, and the command palette / search hide
  merchant names while masked.

---

## 9. Migration sequencing (non-normative)

A suggested order so the shell can land incrementally without a big-bang rewrite
(each step ships behind the existing strict-concurrency gate):

1. **Shell skeleton** — `AppShellView` (NavigationSplitView) + `SidebarView` +
   `NavigationModel`, hosting the *existing* dashboard as the Dashboard
   destination. Window becomes primary; popover reduced to the glance.
2. **Lift satellites into destinations** — Review (from `ReviewTableWindow` +
   `ReviewInboxView`), Budgets (from `CategoryDashboardWindow`), Planning (from
   `RecurringPaymentsView` + charts), Accounts (from `AccountDetailFlyout` +
   `AccountSettingsView`). Retire the satellite `NSWindow` coordinators.
3. **New destinations** — Transactions (ledger framing), Alerts (over existing
   notification/watchlist models), Insights (receipts + weekly review).
4. **Command palette + global command menus** — `⌘K`, `CommandRegistry`,
   `AppCommands`.
5. **Goals** — the one genuinely new feature; pure `Goal*` models in Core first,
   then the destination.
6. **Polish** — Reduce-Transparency degradation, density reflow at large text,
   widget/Control Center parity for the glance.

This document governs the *target IA*; the sequencing above is a path, not a
contract.
