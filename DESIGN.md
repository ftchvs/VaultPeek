---
version: alpha
name: VaultPeek
description: Native macOS menu bar finance instrument with liquid-glass restraint, dense account telemetry, and privacy-first local presentation.
colors:
  primary: "#0066CC"
  on-primary: "#FFFFFF"
  secondary: "#8E8E93"
  background: "#F5F5F7"
  surface: "rgba(255, 255, 255, 0.72)"
  surface-dark: "rgba(28, 28, 30, 0.72)"
  text: "#1D1D1F"
  text-secondary: "#6E6E73"
  hairline: "rgba(0, 0, 0, 0.10)"
  income: "#34C759"
  expense: "#1D1D1F"
  credit-debt: "#FF3B30"
  available: "#34C759"
  warning: "#FF9500"
  pending: "#FF9500"
  sparkline: "#0A84FF"
  recurring: "#5856D6"
typography:
  display-balance:
    fontFamily: SF Pro
    fontSize: 30px
    fontWeight: 600
    lineHeight: 1.12
    fontFeature: "tnum"
  hero-balance-legacy:
    fontFamily: SF Pro Rounded
    fontSize: 28px
    fontWeight: 700
    lineHeight: 1.14
    fontFeature: "tnum"
  section-title:
    fontFamily: SF Pro
    fontSize: 12px
    fontWeight: 500
    lineHeight: 1.2
    letterSpacing: 0.06em
  data-text:
    fontFamily: SF Pro
    fontSize: 15px
    fontWeight: 600
    lineHeight: 1.25
    fontFeature: "tnum"
  body:
    fontFamily: SF Pro
    fontSize: 13px
    fontWeight: 400
    lineHeight: 1.3
  detail:
    fontFamily: SF Pro
    fontSize: 12px
    fontWeight: 400
    lineHeight: 1.25
  micro:
    fontFamily: SF Pro
    fontSize: 11px
    fontWeight: 500
    lineHeight: 1.2
rounded:
  cell: 2px
  control: 6px
  panel: 8px
spacing:
  xxs: 2px
  xs: 4px
  sm: 8px
  md: 12px
  lg: 16px
  xl: 24px
  row-vertical: 6px
components:
  status-item:
    textColor: "{colors.text}"
    typography: "{typography.data-text}"
    padding: "{spacing.xs}"
  popover-root:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.text}"
    rounded: "{rounded.panel}"
    padding: "{spacing.lg}"
  popover-root-dark:
    backgroundColor: "{colors.surface-dark}"
    textColor: "{colors.on-primary}"
    rounded: "{rounded.panel}"
    padding: "{spacing.lg}"
  panel-raised:
    backgroundColor: "{colors.background}"
    textColor: "{colors.text}"
    rounded: "{rounded.panel}"
    padding: "{spacing.md}"
  panel-inset:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.text-secondary}"
    rounded: "{rounded.panel}"
    padding: "{spacing.sm}"
  row-selected:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.on-primary}"
    rounded: "{rounded.control}"
    padding: "{spacing.sm}"
  income-metric:
    textColor: "{colors.income}"
    typography: "{typography.data-text}"
  expense-metric:
    textColor: "{colors.expense}"
    typography: "{typography.data-text}"
  credit-debt-metric:
    textColor: "{colors.credit-debt}"
    typography: "{typography.data-text}"
  available-metric:
    textColor: "{colors.available}"
    typography: "{typography.data-text}"
  warning-badge:
    backgroundColor: "{colors.warning}"
    textColor: "{colors.text}"
    rounded: "{rounded.control}"
    padding: "{spacing.xs}"
  pending-badge:
    backgroundColor: "{colors.pending}"
    textColor: "{colors.text}"
    rounded: "{rounded.control}"
    padding: "{spacing.xs}"
  sparkline:
    textColor: "{colors.sparkline}"
    size: 20px
  recurring-badge:
    backgroundColor: "{colors.recurring}"
    textColor: "{colors.on-primary}"
    rounded: "{rounded.control}"
    padding: "{spacing.xs}"
  divider-hairline:
    backgroundColor: "{colors.hairline}"
    height: 1px
---
# VaultPeek Design System

This file implements the [DESIGN.md](https://github.com/google-labs-code/design.md) format: YAML front matter is the machine-readable token source; the markdown below is the product/design rationale agents should preserve.

Visual design spec and component catalog for VaultPeek (formerly PlaidBar;
code paths and SwiftPM target names keep the PlaidBar prefix).

## Colors

### Semantic Tokens

| Token | SwiftUI | Meaning |
|-------|---------|---------|
| `income` | `.green` | Money in (+$3,200) |
| `expense` | `.primary` | Money out ($67.42) |
| `creditDebt` | `.red` | Credit card balances owed |
| `available` | `.green` | Available credit, positive balances |
| `warning` | `.orange` | Utilization above threshold |
| `positive` | `.green` | Gains, good status |
| `negative` | `.red` | Losses, high utilization |
| `pending` | `.orange` | Pending transactions |
| `sparkline` | `.blue` | Balance history sparkline stroke |
| `brand` | `.blue` | App brand color (About view icon, accent) |
| `brandSecondary` | `.orange` | Secondary brand color |
| `recurring` | `.indigo` | Recurring transaction badge background |

### Utilization Gradient

Yellow is excluded from the text ramp: yellow caption text falls below 4.5:1
contrast in both appearances. The icon ladder carries the severity step inside
the shared orange band, and dashboard rows show the icon + tint only at or
above the user's warning threshold — below it the line stays `.secondary`.

| Range | Color | Icon |
|-------|-------|------|
| 0-29% | Green | `checkmark.circle` |
| 30-49% | Orange | `exclamationmark.triangle` |
| 50-74% | Orange | `exclamationmark.triangle.fill` |
| 75%+ | Red | `xmark.octagon` |

### Data Palette (Charts)

Category colors from `SpendingCategory.colorHex` — fixed hex values for chart segments, legends, and category indicators.

| Category | Display Name | Hex | SF Symbol | Notes |
|----------|-------------|-----|-----------|-------|
| `foodAndDrink` | Food & Drink | `#FF6B6B` | `fork.knife` | |
| `transportation` | Transportation | `#4ECDC4` | `car.fill` | |
| `shopping` | Shopping | `#45B7D1` | `bag.fill` | |
| `entertainment` | Entertainment | `#96CEB4` | `tv.fill` | |
| `personalCare` | Personal Care | `#FFEAA7` | `heart.fill` | Low dark-mode contrast — see Dark Mode |
| `healthAndFitness` | Health & Fitness | `#DDA0DD` | `cross.case.fill` | |
| `billsAndUtilities` | Bills & Utilities | `#98D8C8` | `bolt.fill` | |
| `homeImprovement` | Home | `#F7DC6F` | `house.fill` | Low dark-mode contrast — see Dark Mode |
| `travel` | Travel | `#BB8FCE` | `airplane` | |
| `education` | Education | `#85C1E9` | `book.fill` | |
| `subscriptions` | Subscriptions | `#F8C471` | `creditcard.fill` | Maps to LOAN_PAYMENTS |
| `income` | Income | `#82E0AA` | `arrow.down.circle.fill` | |
| `transfer` | Transfer In | `#AEB6BF` | `arrow.left.arrow.right` | |
| `transferOut` | Transfer Out | `#D5DBDB` | `arrow.right.circle.fill` | Low dark-mode contrast |
| `bankFees` | Bank Fees | `#E74C3C` | `banknote.fill` | |
| `government` | Government | `#5DADE2` | `building.columns.fill` | |
| `other` | Other | `#BDC3C7` | `questionmark.circle.fill` | Low dark-mode contrast |

## Typography

Implemented as ViewModifiers in `Typography.swift`. Weights are capped at
semibold; labels are medium — hierarchy comes from size, casing, and opacity,
not boldness.

| Level | Token | SwiftUI | Used For |
|-------|-------|---------|----------|
| Display | `.displayBalance()` | `.system(size: 30, weight: .semibold).monospacedDigit()` | The one hero number per surface (net worth) |
| Hero (legacy) | `.heroBalance()` | `.system(size: 28, weight: .bold, design: .rounded).monospacedDigit()` | Legacy detail surfaces only |
| Title | `.sectionTitle()` | `.caption.weight(.medium).textCase(.uppercase)` | ACCOUNTS, 365D SPEND |
| Data | `.dataText()` | `.callout.weight(.semibold).monospacedDigit()` | Row amounts, tabular figures |
| Body | system `.body` | default | Account names, transaction names |
| Detail | `.detailText()` | `.caption` + `.secondary` | Masks, categories, dates |
| Micro | `.microText()` | `.caption2.weight(.medium)` | Pending badge, percentages |

> **Usage note:** `.callout.weight(.medium)` is used for the spending comparison delta text (SpendingView). Not part of the 5-level type scale but used consistently for secondary emphasis.

## Iconography

### Rules

- **Actions** use outline variants: `arrow.clockwise`, `plus.circle`, `gear`
- **Status** uses filled variants: `exclamationmark.triangle.fill`, `checkmark.circle.fill`
- **Content** uses `.regular` weight, matched to accompanying text size
- **Category icons** are filled for visual weight in lists (defined per `SpendingCategory`)

### Standard Icons

| Context | Icon | Style |
|---------|------|-------|
| Add account | `plus.circle` | Action (outline) |
| Refresh | `arrow.clockwise` | Action (outline) |
| Settings | `gear` | Action (outline) |
| Warning | `exclamationmark.triangle.fill` | Status (filled) |
| Error | `xmark.circle.fill` | Status (filled) |
| Credit owed | `creditcard` | Content |
| Search | `magnifyingglass` | Content |

## Layout

8-point grid system via `Spacing` enum:

| Token | Value | Use |
|-------|-------|-----|
| `xxs` | 2pt | Minimal gaps (label-to-badge vertical) |
| `xs` | 4pt | Tight gaps (icon-to-text) |
| `sm` | 8pt | Standard padding, list item vertical |
| `md` | 12pt | Section spacing, card padding |
| `lg` | 16pt | Horizontal margins, major sections |
| `xl` | 24pt | Hero spacing, modal padding |
| `rowVertical` | 6pt | Row vertical padding (RecurringRow, TransactionRow) |

## Elevation & Depth

VaultPeek is a macOS menu bar instrument, so surfaces should feel native and
compact rather than like stacked web cards. The surface system in
`SharedModifiers.swift` splits **chrome** from **data** by surface *type*, not a
boolean (AND-980): chrome-rank panels carry native Liquid Glass, while data
surfaces are always solid so a financial figure never samples a translucent
backdrop ("Liquid Glass on chrome, not data" — R-08). Surfaces draw a hairline
stroke; separation between sibling cards comes from spacing, not from nested
chrome.

| Modifier | Purpose |
|----------------|---------|
| `.nativePanelSurface(...)` | Chrome-rank panels: fill + hairline **under native Liquid Glass**. Navigation/chrome surfaces only |
| `.solidDataSurface(...)` | Solid (non-glass) data surfaces: lists, rows, dense cards, insight bodies — values stay legible over an opaque backdrop (R-08) |
| `.nativeInsetSurface(...)` | Quiet inset data surface (thin wrapper over `solidDataSurface`): secondary rows, metric strips |
| `.emphasizedDataSurface(tint:)` | Attention states only — solid tinted fill plus tinted hairline (never glass) |
| `.heroAccentSurface(tint:)` | Decorative hero-accent solid surface: tinted gradient wash; never carries financial/status meaning alone |
| `Radius.panel` / `.control` / `.cell` | 8 / 6 / 2pt corner radius scale |
| `Sizing` | Icon (16/20/28), status dot (8), 28pt minimum hit target |
| `MotionTokens.micro/.standard/.content` | 120ms / 200ms / spring(0.3, 0.85); all gated by `MotionTokens.animation(_:reduceMotion:)` |
| `.hoverHighlight()` | Rounded, 120ms-animated hover wash for rows |

Liquid Glass is the baseline treatment for **chrome** surfaces only. VaultPeek's
minimum floor is macOS 26 (Tahoe), so Apple SwiftUI's `Glass.regular` and
`glassEffect` APIs are always available and used directly on chrome-rank panels —
no availability gates or SwiftUI material/fill fallback are required. Data
surfaces are always solid regardless (R-08).

The primitive numeric scales behind these tokens (spacing, radius, sizing,
motion) live as pure, SwiftUI-free values in `RawDesignTokens` in `PlaidBarCore`
(AND-979/AND-980), which the popover-scale `DesignTokens.swift` and window-scale
`WindowMetrics.swift` token layers bridge to SwiftUI. Colors stay app-target-only
because they must resolve per-appearance / Increase Contrast at draw time.

## Components

### RepoBar-Style Finance Overview

**Reference:** RepoBar menu popover pattern: contribution heatmap header, compact
filter bar, dense rows, selected row highlight, and chevron-based drill-in. Use
the RepoBar visual language as inspiration, not as literal GitHub UI.

**Anatomy (three-column, AND-367):** HStack | permanent **Wealth Summary** rail
(left, 320pt): net-worth hero + trend, assets/debt, balance mix, cashflow,
credit, attention | center **dashboard** (480pt): change receipt | financial
heatmap (`last 365 days`, Spend or Net mode) | native segmented filter (`All`,
`Cash`, `Credit`, `Savings`, `Debt`, `Status`) | account/card rows | local-only
insight receipt | footer with the single sync/mode status line | always-present
**account inspector** (right, 320pt). Widths: setup 480pt; three-column 1122pt
default post-setup (the inspector column is always open), clamped on-screen near a
display edge.

The left rail owns the portfolio totals, so the center no longer repeats the
net-worth hero (AND-376) or the summary cards / balance mix (AND-372). The right
inspector column is always open post-setup; selecting a row fills it with that
account's detail without hiding the rail or center, and the left edge stays
anchored so the rail does not jump (AND-370). Esc (clears the selection first,
then dismisses the popover), the inspector's ✕, re-clicking the row, or switching
filters clears the selection — the inspector reverts to an empty-selection prompt
rather than collapsing the layout to two columns. The binding contract covers
geometry, anchoring, screen-constrained fallback, and
selection/keyboard/accessibility behavior.

> **History:** this replaced an earlier **swap** model where a single left
> fly-out showed the Wealth Summary *or* the selected account detail (inspecting
> an account hid portfolio context).

| Element | VaultPeek Meaning |
|---------|------------------|
| Heatmap header | Daily spending intensity or net cashflow from transactions, switchable in place. Spend mode uses a NEUTRAL Less/More intensity ramp (green means money-in everywhere else in the app); Net mode uses bidirectional Income/Outflow color keys with an explicit legend. |
| Repo row | Account/card row with institution, type, balance, status, and freshness |
| Repo stats | Balance, available credit, utilization, pending count, sync state |
| Selected repo highlight | Selected account/card detail target |
| Submenu/drill-in | Inline account/card detail surface below the selected row |

**Account/card row anatomy:** status dot or account-type icon | institution +
account name | secondary line with type, mask, sync freshness, pending count |
trailing primary metric (balance owed/cash balance) | secondary metric
(utilization, available credit, or last updated) | chevron.

| State | Behavior |
|-------|----------|
| Healthy cash account | Green/neutral status, cash balance primary, latest sync secondary |
| Savings account | Cash row with savings label; preserve same density as checking |
| Credit card | Credit balance owed primary, utilization and available credit secondary |
| High utilization | Warning/negative utilization color plus text label, not color alone |
| Degraded item | Warning status and `Reconnect` in detail surface |
| Selected | Blue/accent highlight matching native menu selection; detail surface opens |
| No data | Keep overview shell and show one compact recovery action |

### AccountDetailFlyout

The contextual account inspector. It is the always-present RIGHT column of the
three-column popover (post-setup); selecting a row fills it with that account's
detail. One chrome-rank panel surface, sections separated by spacing (never
nested cards).

**Anatomy:** header (account name + institution/type/mask metadata + close ✕)
| Status (connection badge + sync freshness + recovery action when degraded)
| Balances (Available / Current / Utilization) | Changes · 30 days (spending
and income totals with signed deltas vs the prior 30-day window — arrow +
sign + color, never color alone) | To review (pending + large transactions
with reason chips) | Top categories · 30 days (icon + name + total + share
bar) | Recent activity (6 rows) | account actions (reconnect / remove /
settings).

**Code reference:** `Sources/PlaidBar/Views/AccountDetailFlyout.swift`;
insight math in `Sources/PlaidBarCore/Utilities/AccountDetailInsights.swift`
(pure, tested).

| State | Behavior |
|-------|----------|
| Empty selection (default) | No account selected: the column hosts the **Review Inbox** (`ReviewInboxView(embedded:)` — no own surface, scrolls, shows an "Inbox Clear" prompt when the queue is empty) so the third column is always working space |
| Selected | A row is selected: the inspector fills with that account's detail; content animates in with `MotionTokens.content` (gated by Reduce Motion). The popover width does not change — it is already the 1122pt three-column default |
| Resolving persisted selection | A persisted selection is still loading: a brief progress placeholder holds the column until the account resolves |
| Deselect | ✕ button, Esc, re-clicking the selected row, or switching filters reverts the content to the **Review Inbox** (the default empty-selection state); the column and the 1122pt layout stay in place |
| Degraded item | Status section shows recovery detail + Reconnect/Refresh action |
| No review items / categories | Sections are omitted entirely, never shown empty |
| Demo mode | Actions reduce to the demo-safe set (`DashboardDrillInAction.accountDrillInActions`) |

### AccountRow

**Anatomy:** Institution avatar (28×28 circle, DJB2-hashed color) | Account name (`.body`) + mask (`.detailText()`) | Amount (`.monospacedDigit`) with semantic color | Credit accounts: `creditcard` icon prefix + utilization badge

**Density audit (2026-06-08, T021):** Account rows should preserve one shared
two-line rhythm across checking, savings, credit card, loan, investment, and
other account types. The current dashboard row implementation uses one 28pt
leading glyph/status affordance, `Spacing.compactRowContentSpacing` horizontal
gaps, `Spacing.compactRowVerticalPadding` vertical padding, a one-line primary
label, a one-line secondary label, a trailing primary amount, a trailing
secondary status/available-credit line, and a chevron. Checking and savings rows
therefore occupy the same height as credit, loan, and other rows; richer credit
metadata is compressed into the trailing secondary line rather than adding a
third text row. Legacy account-list rows keep the same 28pt leading affordance
and two-line text structure, but the dashboard row is the production-density
reference for PR-005 follow-up work.

| Account family | Primary metric | Secondary density rule |
|----------------|----------------|------------------------|
| Checking | Cash balance | Type/mask/freshness fit on the subtitle line |
| Savings | Cash balance | Same row height and subtitle rhythm as checking |
| Credit card | Balance owed | Utilization and available credit share one trailing line |
| Loan | Balance owed | Uses the shared debt amount treatment without extra row height |
| Investment/other | Current balance | Uses the same subtitle/status slot as cash rows |

| State | Behavior |
|-------|----------|
| Default | All elements visible; amount colored by account type |
| Loading (sync in progress) | Shimmer placeholder on amount; avatar and name visible |
| Disconnected (token expired) | Dimmed row (`.opacity(0.5)`); inline "Reconnect" link; amount shows "—" |
| Error (API failure) | Amount shows "Error" in `.secondary`; tap row shows error detail |
| Hover | `.background(.quaternarySystemFill)` highlight on row; cursor: pointer |

### CreditCardRow

**Anatomy:** Card name + status icon | Progress bar (12pt height, rounded corners, `Spacing.sm` corner radius) | Balance / limit + available credit + percentage | Font weight increases at warning thresholds

| State | Behavior |
|-------|----------|
| Default (0-29%) | Green progress fill; `checkmark.circle` icon; `.regular` weight |
| Warning (30-49%) | Yellow fill; `exclamationmark.triangle` icon; `.medium` weight |
| High (50-74%) | Orange fill; `exclamationmark.triangle` icon; `.semibold` weight |
| Critical (75%+) | Red fill; `xmark.octagon` icon; `.bold` weight |
| Loading | Shimmer on progress bar and amounts; icon placeholder |
| Account disconnected | Gray progress bar; "Reconnect" inline; amounts show "—" |

### TransactionRow

**Anatomy:** Category icon (24pt frame, filled style) | Merchant name (`.body`) + category (`.detailText()`) | Amount with semantic color | Optional "Pending" micro badge

| State | Behavior |
|-------|----------|
| Default (posted) | Full-opacity; amount in `income`/`expense` color |
| Pending | `.opacity(0.7)` on row; orange "Pending" `.microText()` badge below amount |
| Filtered out | Hidden (`.transition(.opacity)`) when filter excludes |
| Tap/hover | `.background(.quaternarySystemFill)` on row |
| Tap → detail sheet | `onTapGesture` sets `selectedTransaction`, presenting `TransactionDetailView` as `.sheet` |

### TransactionDetailView

**Anatomy:** NavigationStack > Form (grouped) | Header section: category icon (title2) + merchant name (.title3.bold) + raw transaction name (.detailText) | Details section: LabeledContent rows for Amount (color-coded, monospacedDigit), Category (Label with icon), Date, Account, Status (colored dot + "Posted"/"Pending") | Toolbar "Done" button | `.presentationSizing(.fitted)`

**Code reference:** `Sources/PlaidBar/Views/TransactionDetailView.swift`

| State | Behavior |
|-------|----------|
| Default (posted expense) | Full details; amount in `expense` color; green "Posted" dot |
| Pending transaction | Amount in `expense` color; orange "Pending" dot + text |
| Income transaction | Amount in `income` color with `+` prefix; green "Posted" dot |
| Expense transaction | Amount in `expense` color (no prefix); green "Posted" dot |
| Missing category | Category icon falls back to `.other` (`questionmark.circle.fill`); LabeledContent("Category") hidden |
| Unknown account | Account row shows "Unknown" |

### FilterChipsView

**Anatomy:** `ScrollView(.horizontal)` > `HStack` of `Menu` chips | Each chip: text + chevron.down in capsule background | Active chip: `.accentColor.opacity(0.15)` background, accent foreground | Inactive: `.quaternary.opacity(0.5)` background, `.secondary` foreground | Clear button: `xmark.circle.fill` (appears when ≥1 filter active)

**Code reference:** `Sources/PlaidBar/Views/FilterChipsView.swift`

| State | Behavior |
|-------|----------|
| No filters active | 3 chips (Category, Account, Date=All) in inactive style; no clear button |
| 1+ filters active | Active chip(s) highlighted in accent; clear button visible |
| Category selected | Chip text changes to category display name (e.g., "Food & Drink") |
| Account selected | Chip text changes to account name (e.g., "Chase Checking") |
| Date range selected | Chip text changes to range label (e.g., "This Week") |
| Clear all tapped | All filters reset: category=nil, accountId=nil, dateRange=.all |

### RecurringView

**Anatomy:** VStack | Header: "EST. MONTHLY COST" (`.sectionTitle()`) + normalized total (`.heroBalance()`) | Divider | `ForEach` of `RecurringRow` items | Empty state: `ContentUnavailableView` with `arrow.clockwise` icon

**Code reference:** `Sources/PlaidBar/Views/RecurringView.swift`

| State | Behavior |
|-------|----------|
| Populated | Header shows monthly estimate (normalizes weekly/annual via `monthlyMultiplier`); rows listed by amount descending |
| Empty (no recurring detected) | `ContentUnavailableView`: "No Recurring Transactions" with explanation text |
| Normalized amounts | Weekly items × 4.33, annual ÷ 12, quarterly ÷ 3 for monthly total |

### RecurringRow

**Anatomy:** HStack | Category icon (`.body`, `.secondary`, 24pt frame) | VStack: merchant name (`.body`) + frequency badge (`.microText()` in indigo capsule `SemanticColors.recurring.opacity(0.15)`) + average amount (`.detailText()`, monospacedDigit) + "Last: {date}" (`.detailText()`) | `.hoverHighlight()`

**Code reference:** `Sources/PlaidBar/Views/RecurringView.swift` (private struct)

| State | Behavior |
|-------|----------|
| Weekly | Badge shows "Weekly" in indigo capsule |
| Biweekly | Badge shows "Biweekly" in indigo capsule |
| Monthly | Badge shows "Monthly" in indigo capsule |
| Quarterly | Badge shows "Quarterly" in indigo capsule |
| Annual | Badge shows "Annual" in indigo capsule |
| Hover | `.hoverHighlight()` background applied |

### NotificationSettingsView

**Anatomy:** `Form` + `.formStyle(.grouped)` + switch-style toggles | First section: macOS permission status row (icon + label + detail + optional recovery action) and master toggle "Enable notifications" | Section "Transaction alerts": Large transactions toggle + "Large transaction threshold" field ($), Low balance warning toggle + "Low balance threshold" field ($) | Section "Credit alerts": High utilization toggle + reference to credit warning threshold from General

**Code reference:** `Sources/PlaidBar/Settings/SettingsView.swift`

| State | Behavior |
|-------|----------|
| Notifications off | Master toggle off; all sub-toggles and fields disabled |
| Notifications enabled | Master toggle on; sub-toggles and threshold fields enabled |
| Permission denied (macOS) | Permission status row shows warning icon + "Denied" label, explanation text, and an "Open System Settings" recovery button; sub-controls disabled |
| Individual trigger disabled | Specific toggle off; associated threshold field disabled |
| Zero-dollar threshold | `InlineSettingsNotice` (`bell.badge` icon + warning tint + text) explains a $0 threshold alerts on every outgoing transaction |
| High utilization reference | Shows "Uses credit warning threshold ({X}%)" in `.detailText()` — threshold set in General tab |

### SpendingComparison

**Anatomy:** (Inline in SpendingView) VStack | HStack: directional arrow icon + delta text (absolute + percent) in `.callout.weight(.medium)` | "vs. last period" in `.microText()` + `.secondary` | Color: increase → `SemanticColors.negative` (red), decrease → `SemanticColors.positive` (green) | `.contentTransition(.numericText())` animation

**Code reference:** `Sources/PlaidBar/Views/SpendingView.swift` (inline in body)

| State | Behavior |
|-------|----------|
| Spending increased | `arrow.up.right` icon; red text; positive delta with "+" prefix |
| Spending decreased | `arrow.down.right` icon; green text; negative delta |
| No previous period data | Comparison section hidden entirely (`if previousPeriodSpending > 0`) |
| Period changed | Recalculates based on `selectedPeriod` (week/month/30d); animated transition |

### Local Insight Receipt

**Anatomy:** Header "Local Insight Receipt" + local runtime status pill | one-line headline | evidence chips for source-row count, time window, top display category, recurring estimate, and category-hint count when present | compact confidence and limitation rows | local-only badge + reversible action copy.

**Code reference:** `LocalAIInsightReceipt` in `Sources/PlaidBarCore/Models/LocalAIInsights.swift`; rendered by `LocalInsightsCard` in `Sources/PlaidBar/Views/MainPopover.swift`.

| Element | Rule |
|---------|------|
| Headline | Short deterministic summary or future local-model summary after known local source identifiers are redacted |
| Evidence chips | Display-safe counts, categories, amounts, and window labels only; never raw account IDs, item IDs, transaction IDs, tokens, or Plaid payload text |
| Time window | Explicit current range such as `2026-06-05 to 2026-06-11`; no vague "recently" when source windows are known |
| Local-only badge | Always visible as `Local-only`; no cloud AI fallback language except to state it is unsupported |
| Confidence | Names deterministic/local source-row confidence and downgrades when no runtime, no rows, or limited history is available |
| Limitations | States missing runtime, missing source rows, missing comparison windows, and display-safe evidence boundaries plainly |
| Unavailable | Shows no-runtime or no-history state without blocking the dashboard; user can continue using non-AI views |
| Reversible action | Category hints are local overlays; accepting or rejecting them is reversible and does not mutate raw Plaid records |

### Charts

**Shared behavior:** All charts animate on appearance with `.spring(response: 0.3, dampingFraction: 0.8)`. When `accessibilityReduceMotion` is on, render immediately without animation.

| Chart | Anatomy | Empty State | Error State |
|-------|---------|-------------|-------------|
| **Donut** | Category segments; inner label shows category name + % when segment >10% | "No spending data yet" with `chart.pie` SF Symbol | "Unable to load" with retry |
| **Trend line** | Daily spending dots + area fill; x-axis = dates, y-axis = amount | "Not enough data — need 7+ days" | Gray placeholder area |
| **Income vs Expense** | Monthly grouped bars (green = income, primary = expense) | "Need 1+ month of data" | Gray placeholder bars |
| **Utilization gauge** | Circular gauge (0-100%); color follows utilization gradient | "No credit cards linked" | "—" with gray ring |

### Empty States

Pattern for all empty states:

| Element | Spec |
|---------|------|
| Icon | SF Symbol, `.font(.system(size: 40))`, `.foregroundStyle(.tertiary)` |
| Title | `.body.weight(.medium)`, 1 line, centered |
| Description | `.detailText()`, max 2 lines, centered, `.multilineTextAlignment(.center)` |
| Action button | Optional; `.buttonStyle(.borderedProminent)` for primary, `.borderedStyle` for secondary |
| Spacing | `Spacing.lg` between icon and title; `Spacing.sm` between title and description; `Spacing.md` before button |

### Screen-Level Patterns

| Screen | Components Used | Nav Pattern |
|--------|----------------|-------------|
| Menu bar popover (main) | Dashboard header, status strip, summary values, 365-day heatmap, segmented finance filters, dense account rows, inline selected account drill-down, footer actions | One scroll surface; row selection expands drill-down in place; `Cmd+R` refreshes and `Cmd+N` adds account |
| Account rows | Compact account/card rows with balance, utilization/status, sync freshness, pending count, and chevron affordance | Click row to expand the selected account details inline |
| Selected account panel | Connection badge, balance metrics, pending/inflow/outflow/sync pills, recent transactions, reconnect/refresh actions | Inline recovery actions for stale or degraded items |
| Spending activity | GitHub-style 365-day grid with month labels, Spend/Net toggle, intensity legend, and total header | Hover cells for day-level transaction count plus spend or net cashflow |
| Legacy detail views | Removed (AND-312): the dead tab tree — AccountsView, TransactionsView, SpendingView, CreditView, StatusView and their chart helpers — was deleted. The dashboard popover plus `AccountDetailFlyout` is the only detail surface | Build new detail surfaces as dashboard drill-ins; do not reintroduce a tab container |
| Settings | 4-tab TabView: General, Accounts, Notifications, About; each tab is a native grouped `Form` with switch-style toggles and sentence-case section headers; resizable window (min 560×480) | TabView + `Form(.grouped)` |
| Onboarding | Demo/Sandbox/Production choice with local-storage disclosure before Plaid Link | Mode choice, Back, Check Connection |

### Popover Surface Inventory

Inventory for T006: surfaces that still risk feeling tab-heavy or card-heavy.
Keep this inventory about visual structure only. Do not record real balances,
account masks, institution names, transaction names, item IDs, tokens, or local
absolute paths when adding screenshot or review evidence.

| Surface | Code reference | Current pattern | Risk | Recommended follow-up |
|---------|----------------|-----------------|------|-----------------------|
| Dashboard summary stack | `DashboardSummaryCards`, `MetricCard`, and `BalanceCompositionStrip` in `Sources/PlaidBar/Views/MainPopover.swift` | Several rounded panels appear after the heatmap and before account rows | Reads like stacked dashboard cards instead of one compact menu-bar instrument | Flatten at least one summary group into separator-backed inline metrics before adding more dashboard sections |
| Selected account detail | `SelectedAccountPanel`, `AccountSignalPill`, recovery detail, and recent activity in `Sources/PlaidBar/Views/MainPopover.swift` | Inline drill-in uses an outer panel plus nested inset pills and a recovery panel | Clearest nested-card pattern in the main popover when an account is selected | Keep the inline drill-in, but reduce nested panel treatment to status color, separators, and compact rows |
| Local insights | `LocalInsightsCard` and `InsightMetricPill` in `Sources/PlaidBar/Views/MainPopover.swift` | Optional local-only AI/status content is presented as a card with nested metric pills | Can feel like product/marketing chrome if it competes with financial rows | Prefer a compact disclosure or status row unless local insights become the selected detail focus |
| Status and readiness | `DashboardStatusReadinessPanel` and `DashboardEmptyAccountState` in `Sources/PlaidBar/Views/MainPopover.swift` | Recovery and empty states use prominent rounded panels | Appropriate when degraded, but card-heavy if shown alongside several other panels | Keep panels exceptional for action-needed states; avoid duplicating status panels in normal healthy dashboard flow |
| Detail drill-in | `AccountDetailFlyout` in `Sources/PlaidBar/Views/` | Per-account fly-out is the surviving detail surface after the legacy tab tree was removed (AND-312) | Risk of regrowing into a tab-heavy container if multiple detail views are stacked | Keep detail as a single dashboard drill-in; the old `AccountsView`/`TransactionsView`/`SpendingView`/`CreditView`/`StatusView` tab tree is gone and should not return |
| Settings | `SettingsView` | 4-tab macOS settings window; each tab a native grouped `Form` (no hand-rolled card stacks since AND-311) | Tab-heavy by design, but outside the primary popover dashboard | Keep native `Form(.grouped)` idioms for new settings rows instead of reintroducing custom card containers |
| Onboarding/setup | `SetupView` | Demo/Sandbox/Production choices, preflight rows, and local-storage disclosure use multiple callout blocks | First-run flow can feel card-heavy and marketing-like if choices duplicate each other | Keep boundary explanations, but consolidate duplicate choice surfaces before adding more setup panels |

## Extending the Design System

### Adding a New Component

Checklist for contributors:

1. **Tokens first:** Use existing `Spacing`, `Typography`, and semantic color tokens. Never hardcode values.
2. **Document anatomy:** List every visual element with its token reference.
3. **States table:** Minimum: default, loading, error, empty, hover. Add domain-specific states as needed.
4. **Accessibility:** Add VoiceOver label to the Accessibility section. Ensure no color-only indicators.
5. **Dark mode:** Verify component renders correctly in both appearances. Add to dark mode testing checklist.
6. **Code reference:** Note the SwiftUI file where the component lives.

### Adding a New Chart Type

1. Use `Swift Charts` framework (not custom drawing)
2. Follow shared chart behavior: `.spring()` animation, `accessibilityReduceMotion` respect
3. Add chart colors to `SpendingCategory` if category-based, or define semantic tokens if not
4. Document empty state and error state in the Charts table above
5. Add VoiceOver summary string (pattern: "{chart type}. {key insight}.")

### Adding a New Spending Category

1. Add case to `SpendingCategory` enum in `SpendingCategory.swift`
2. Define `colorHex` (light mode) — choose a hue not adjacent to existing categories on the color wheel
3. Define `icon` — use filled SF Symbol consistent with existing category icons
4. Optionally add `colorHexDark` if the light-mode hex has <3:1 contrast on dark backgrounds

### Adding a Filter Chip

1. Add a new `@State` property to `TransactionsView` for the filter value
2. Add a `@Binding` parameter to `FilterChipsView`
3. Add a new `Menu` block in `FilterChipsView.body` following the chip pattern (Menu > Button items > chipLabel)
4. Update `activeFilterCount` computed property to include the new filter
5. Add filtering logic in `TransactionsView.filteredTransactions`
6. Add clear logic in the "Clear all" button action

### Adding a Frequency Badge

1. Add a new case to `RecurringFrequency` enum in `RecurringTransaction.swift`
2. Provide `displayName`, `iconName`, `estimatedDays`, and `monthlyMultiplier`
3. Add the median interval range in `RecurringDetector.classifyFrequency`
4. Badge rendering in `RecurringRow` is automatic (uses `frequency.displayName`)

### Adding a Detail Sheet

1. Add a new `@State` property of optional type for the item to detail
2. Attach `.sheet(item:)` modifier to the parent view
3. Build the detail view following `TransactionDetailView` pattern: `NavigationStack` > `Form` > sections with `LabeledContent`
4. Add a "Done" toolbar button calling `dismiss()`
5. Apply `.presentationSizing(.fitted)` for content-appropriate sheet size
6. Add `.accessibilityElement(children: .contain)` to the root

## Dark Mode

VaultPeek runs on macOS, where dark mode usage is ~60%. All tokens must work in both appearances.

### Token Behavior by Appearance

| Token | Light Mode | Dark Mode | Adapts Automatically? |
|-------|-----------|-----------|----------------------|
| `income` (`.green`) | System green | System green (lighter) | Yes — SwiftUI semantic |
| `expense` (`.primary`) | Label primary | Label primary (white) | Yes — SwiftUI semantic |
| `creditDebt` (`.red`) | System red | System red (lighter) | Yes — SwiftUI semantic |
| `warning` (`.orange`) | System orange | System orange (lighter) | Yes — SwiftUI semantic |
| `pending` (`.orange`) | System orange | System orange (lighter) | Yes — SwiftUI semantic |
| `.secondary` (detail text) | Gray | Light gray | Yes — SwiftUI semantic |
| Chart hex colors | Fixed hex values | **Same hex values** | **No — requires manual dark variants** |
| `brand` (`.blue`) | System blue | System blue (lighter) | Yes — SwiftUI semantic |
| `brandSecondary` (`.orange`) | System orange | System orange (lighter) | Yes — SwiftUI semantic |
| `recurring` (`.indigo`) | System indigo | System indigo (lighter) | Yes — SwiftUI semantic |
| `sparkline` (`.blue`) | System blue | System blue (lighter) | Yes — SwiftUI semantic |

#### Chart Palette — Problem Colors

These `SpendingCategory.colorHex` values have <3:1 contrast ratio against dark background (`#1E1E1E`):

| Category | Hex | Contrast vs Dark BG | Recommended Dark Variant |
|----------|-----|---------------------|-------------------------|
| `personalCare` | `#FFEAA7` | ~2.5:1 | `#F0D890` (desaturate) |
| `homeImprovement` | `#F7DC6F` | ~2.3:1 | `#E8CD60` (darken) |
| `transferOut` | `#D5DBDB` | ~2.8:1 | `#B8C0C0` (darken) |
| `other` | `#BDC3C7` | ~2.6:1 | `#A0A8AC` (darken) |
| `income` | `#82E0AA` | ~2.9:1 | `#6FCC98` (darken slightly) |

### Chart Palette Dark Mode Strategy

`SpendingCategory.colorHex` uses fixed hex values that were designed for light backgrounds. For dark mode:

- **Current behavior:** Hex colors render as-is on dark backgrounds. Most are vibrant enough to work, but some (e.g., light yellows) lose contrast.
- **Recommended fix:** Add a `colorHexDark` property to `SpendingCategory` with adjusted values for dark backgrounds, selected via `@Environment(\.colorScheme)`.
- **Interim:** Existing palette is acceptable for most categories. 5 categories (see Problem Colors above) fall below 3:1 contrast on dark backgrounds — a `colorHexDark` property is the recommended fix.

### Testing Checklist

- [ ] All semantic tokens readable on `.background` in both appearances
- [ ] Chart donut labels readable over colored segments in both appearances
- [ ] Utilization progress bar colors distinguishable in dark mode
- [ ] Empty state SF Symbols render correctly (use `.primary` foreground, not hardcoded color)
- [ ] Pending badge (`.orange` + `.background`) maintains contrast in dark mode

## Accessibility

### Contrast Ratios

All text/background combinations must meet WCAG AA (4.5:1 for body text, 3:1 for large text).

| Combination | Light Mode | Dark Mode | Passes AA? |
|-------------|-----------|-----------|-----------|
| `.primary` on `.background` | ~15:1 | ~15:1 | Yes |
| `.secondary` on `.background` | ~5.5:1 | ~5.5:1 | Yes |
| `.green` on `.background` | ~3.5:1 | ~4:1 | Large text only — pair with secondary cue |
| `.red` on `.background` | ~4.5:1 | ~4.8:1 | Yes |
| `.orange` on `.background` | ~3.2:1 | ~3.5:1 | Large text only — pair with secondary cue |

### Color-Independent Cues

Every element that uses color to convey meaning must have a secondary, non-color indicator:

| Element | Color Cue | Secondary Cue |
|---------|-----------|---------------|
| Utilization level | Green → Yellow → Orange → Red | Icon changes: `checkmark.circle` → `exclamationmark.triangle` → `xmark.octagon` |
| Income transaction | `.green` amount | `+` prefix on amount |
| Expense transaction | `.primary` amount | No prefix (default) — distinguishable by absence of `+` |
| Pending transaction | `.orange` badge | "Pending" text label on badge |
| Credit utilization bar | Color fill | Percentage text label always visible |
| Chart segments | Category color | Category name in legend; inner label at >10% |
| Recurring frequency | Indigo badge color | Text label on badge: "Weekly" / "Monthly" / "Annual" etc. |
| Spending delta direction | Red (increase) / Green (decrease) | Arrow icon: `arrow.up.right` / `arrow.down.right` + signed amount text |
| Transaction status (detail) | Green dot (posted) / Orange dot (pending) | "Posted" / "Pending" text label beside dot |
| Active filter chips | Accent background | Chip text changes from placeholder ("Category") to selected value ("Food & Drink") |

### VoiceOver Labels

| Component | VoiceOver Announcement |
|-----------|----------------------|
| AccountRow | "{institution} {account name}, balance {amount}" |
| CreditCardRow | "{card name}, {balance} of {limit}, {percent} utilization, {status}" where status = "good" / "warning" / "high" |
| TransactionRow | "{merchant}, {amount}, {category}, {date}" + "pending" if applicable |
| Menu bar icon | "VaultPeek net cash {amount}. Status {summary}" (varies by summary mode) |
| Utilization gauge | "Credit utilization {percent}, {status level}" |
| Chart (donut) | "Spending by category. Largest: {category} at {percent}" |
| Refresh button | "Refresh accounts" + "Last updated {time}" as hint |
| FilterChipsView | "{N} filters active" or "Transaction filters" (when none active) |
| RecurringRow | "{merchant}, {frequency}, {amount}" |
| RecurringView (header) | "Estimated monthly recurring cost: {amount}" |
| TransactionDetailView | Container with combined children: merchant, amount, category, date, account, status |
| SpendingComparison | "Spending {increased/decreased} by {amount}, {percent} {more/less} than last period" |

### Motion

- All chart animations respect `@Environment(\.accessibilityReduceMotion)`
- When reduce-motion is on: charts render immediately without animation; transitions use `.opacity` instead of `.slide` or `.spring`
- Default animation: `.spring(response: 0.3, dampingFraction: 0.8)` for chart entry; `.easeInOut(duration: 0.2)` for view transitions
