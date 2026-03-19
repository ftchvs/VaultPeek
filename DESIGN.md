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
- Institution avatar (28x28 circle, DJB2-hashed color)
- Account name (body) + mask (detail)
- Amount (monospacedDigit) with semantic color
- Credit accounts show `creditcard` icon prefix
- Utilization badge on credit accounts

### CreditCardRow
- Name + status icon
- Progress bar (12pt height, rounded corners)
- Balance / limit + available + percentage
- Font weight increases at warning thresholds

### TransactionRow
- Category icon (24pt frame)
- Name (body) + category (detail)
- Amount with income/expense semantic color
- "Pending" micro badge when applicable

### Charts
- **Donut**: Category spending with inner label at >10%
- **Trend line**: Daily spending with area fill
- **Income vs Expense**: Monthly grouped bars
- **Utilization gauge**: Circular gauge in credit summary

### Empty States
- SF Symbol composition (system image)
- Descriptive copy
- Inline action button where applicable
