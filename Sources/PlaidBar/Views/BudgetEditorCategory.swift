import PlaidBarCore
import SwiftUI

/// A tiny `Identifiable` wrapper around a `SpendingCategory` so the Category
/// Dashboard surfaces can drive `BudgetEditorSheet` via `.sheet(item:)` (AND-541)
/// without making the Core enum `Identifiable` (its identity is presentation glue,
/// not a model concern). Both the popover card and the detached window present the
/// editor through this, so the wrapper is shared rather than duplicated per view.
struct BudgetEditorCategory: Identifiable, Hashable {
    let category: SpendingCategory
    var id: String { category.rawValue }

    init(_ category: SpendingCategory) {
        self.category = category
    }
}
