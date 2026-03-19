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

### Utilization Gradient

| Range | Color | Icon |
|-------|-------|------|
| 0-29% | Green | `checkmark.circle` |
| 30-49% | Yellow | `exclamationmark.triangle` |
| 50-74% | Orange | `exclamationmark.triangle` |
| 75%+ | Red | `xmark.octagon` |

### Data Palette (Charts)

Category colors defined in `SpendingCategory.colorHex` — consistent hex values for chart segments. See `SpendingCategory.swift` for full list.

## Typography Scale

5 levels, implemented as ViewModifiers in `Typography.swift`:

| Level | Token | SwiftUI | Used For |
|-------|-------|---------|----------|
| Hero | `.heroBalance()` | `.system(size: 28, weight: .bold, design: .rounded).monospacedDigit()` | Net balance header |
| Title | `.sectionTitle()` | `.caption.weight(.semibold).textCase(.uppercase)` | BANK ACCOUNTS, CREDIT CARDS |
| Body | system `.body` | default | Account names, transaction names |
| Detail | `.detailText()` | `.caption` + `.secondary` | Masks, categories, dates |
| Micro | `.microText()` | `.caption2.weight(.medium)` | Pending badge, percentages |

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
| `xs` | 4pt | Tight gaps (icon-to-text) |
| `sm` | 8pt | Standard padding, list item vertical |
| `md` | 12pt | Section spacing, card padding |
| `lg` | 16pt | Horizontal margins, major sections |
| `xl` | 24pt | Hero spacing, modal padding |

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
| Recurring (v0.3) | Small `repeat` icon badge on category icon; tappable for recurring detail |
| Filtered out | Hidden (`.transition(.opacity)`) when filter excludes |
| Tap/hover | `.background(.quaternarySystemFill)` on row |

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
| Transactions tab | TransactionRow list + date group headers + filter bar (v0.3) | Scroll; search via `Cmd+F` |
| Spending tab | Donut chart + Trend line + Income vs Expense | Scroll; chart tap for detail |
| Credit tab | CreditCardRow list + Utilization gauge | Scroll |
| Settings | Standard macOS Settings-style panes (General, Notifications v0.3) | TabView |
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

### Chart Palette Dark Mode Strategy

`SpendingCategory.colorHex` uses fixed hex values that were designed for light backgrounds. For dark mode:

- **Current behavior:** Hex colors render as-is on dark backgrounds. Most are vibrant enough to work, but some (e.g., light yellows) lose contrast.
- **Recommended fix:** Add a `colorHexDark` property to `SpendingCategory` with adjusted values for dark backgrounds, selected via `@Environment(\.colorScheme)`.
- **Interim:** Existing palette is acceptable. All chart segments maintain >3:1 contrast ratio against both `.background` and `.secondarySystemBackground` in dark mode.

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

### Motion

- All chart animations respect `@Environment(\.accessibilityReduceMotion)`
- When reduce-motion is on: charts render immediately without animation; transitions use `.opacity` instead of `.slide` or `.spring`
- Default animation: `.spring(response: 0.3, dampingFraction: 0.8)` for chart entry; `.easeInOut(duration: 0.2)` for view transitions
