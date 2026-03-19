# PlaidBar Design System

Visual design spec and component catalog for PlaidBar.

## Color System

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

| Range | Color | Icon |
|-------|-------|------|
| 0-29% | Green | `checkmark.circle` |
| 30-49% | Yellow | `exclamationmark.triangle` |
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

## Typography Scale

5 levels, implemented as ViewModifiers in `Typography.swift`:

| Level | Token | SwiftUI | Used For |
|-------|-------|---------|----------|
| Hero | `.heroBalance()` | `.system(size: 28, weight: .bold, design: .rounded).monospacedDigit()` | Net balance header |
| Title | `.sectionTitle()` | `.caption.weight(.semibold).textCase(.uppercase)` | BANK ACCOUNTS, CREDIT CARDS |
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

## Spacing

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

## Component Catalog

### AccountRow

**Anatomy:** Institution avatar (28×28 circle, DJB2-hashed color) | Account name (`.body`) + mask (`.detailText()`) | Amount (`.monospacedDigit`) with semantic color | Credit accounts: `creditcard` icon prefix + utilization badge

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

**Anatomy:** Form | Master toggle "Enable notifications" | Permission denied warning (if applicable): `exclamationmark.triangle` icon + explanation text | Section "Transaction Alerts": Large transactions toggle + threshold field ($), Low balance toggle + threshold field ($) | Section "Credit Alerts": High utilization toggle + reference to credit warning threshold from General

**Code reference:** `Sources/PlaidBar/Settings/SettingsView.swift`

| State | Behavior |
|-------|----------|
| Notifications off | Master toggle off; all sub-toggles and fields disabled |
| Notifications enabled | Master toggle on; sub-toggles and threshold fields enabled |
| Permission denied (macOS) | Warning banner: `exclamationmark.triangle` + "Enable in System Settings > Notifications"; master toggle forced off |
| Individual trigger disabled | Specific toggle off; associated threshold field disabled |
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
| Menu bar popover (main) | TabView with 4 tabs: Accounts, Transactions, Spending, Credit | `Cmd+1` through `Cmd+4` |
| Accounts tab | AccountRow list grouped by `.depository` / `.credit` | Scroll; pull-to-refresh via `Cmd+R` |
| Transactions tab | Segmented picker (Recent/Recurring) + Search bar + FilterChipsView + TransactionRow list + date group headers → tap: TransactionDetailView sheet; OR RecurringView | Scroll; search via `Cmd+F` |
| Spending tab | Period picker (segmented) + Hero total + SpendingComparison + Chart picker (Categories/Trend/In vs Out) + Donut/SpendingTrendChart/IncomeExpenseChart | Scroll; period and chart type selectable |
| Credit tab | CreditCardRow list + Utilization gauge | Scroll |
| Settings | 4-tab TabView: General, Accounts, Notifications, About (480×380) | TabView |
| Onboarding | 3-step flow: Welcome → Plaid Link → Success | Next/Back buttons |

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

PlaidBar runs on macOS, where dark mode usage is ~60%. All tokens must work in both appearances.

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
| Menu bar icon | "PlaidBar, net balance {amount}" |
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
