import PlaidBarCore
import SwiftUI

/// The **one** category → `Color` mapping for UI accents (icons, chart
/// foreground styles, row tints). Deliberately native `Color` cases (`.pink`,
/// `.teal`, ...), not hex — matching the redesign's "system colors, never
/// hex" doctrine (Gate-0, AND-979): a system color case adapts to dark mode
/// and Increase Contrast automatically, where a fixed hex value would need
/// per-call-site `colorScheme` threading to do the same, and would still
/// only ever hit two discrete points instead of the system's full ramp.
///
/// `SpendingCategory.colorHex`/`colorHexDark` (`PlaidBarCore`) is a
/// **separate, legitimate** system, not a duplicate of this one: it seeds
/// the Budgets v2 category editor's user-**customizable** swatches
/// (`CategoryEditorView`, `CategoryFormSheet`, `BudgetingV2Schema`), which
/// must be hex because a user-chosen color isn't limited to this switch's
/// fixed system-color cases. Investigated during the Gate-0 token-foundation
/// pass (AND-980) — the two systems serve different domains (fixed-enum
/// chart/icon accents vs. user-editable swatches) and should not be merged;
/// what WAS dead was `chartHex(for:colorScheme:)` below, which had zero
/// call sites and is removed.
enum CategoryAccentTokens {
    static func color(for category: SpendingCategory) -> Color {
        switch category {
        case .foodAndDrink:
            .pink
        case .transportation:
            .teal
        case .shopping:
            .cyan
        case .entertainment:
            .mint
        case .personalCare:
            .purple
        case .healthAndFitness:
            .red
        case .billsAndUtilities:
            .orange
        case .homeImprovement:
            .brown
        case .travel:
            .indigo
        case .education:
            .blue
        case .subscriptions:
            SemanticColors.recurring
        case .income:
            SemanticColors.positive
        case .transfer, .transferOut:
            .secondary
        case .bankFees:
            SemanticColors.negative
        case .government:
            SemanticColors.brandSecondary
        case .other:
            .secondary
        }
    }
}
