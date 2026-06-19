import Foundation

/// A fixed, 2-level grouping over the closed 16-case ``SpendingCategory`` taxonomy.
///
/// `CategoryGroup` is the *parent* level of the category tree the Copilot-style
/// dashboard renders (AND-521 / AND-536…AND-538). It is **purely additive**: it does
/// not change any ``SpendingCategory`` `rawValue`, DTO, or persisted format. Aggregation
/// always rolls leaf ``SpendingCategory`` totals up into one of these groups via
/// ``SpendingCategory/group``.
///
/// The grouping is exhaustive — every one of the 16 leaf categories maps to exactly one
/// group — and the group set is closed, so `switch` statements over it stay exhaustive.
public enum CategoryGroup: String, Codable, Sendable, CaseIterable, Hashable {
    case income = "INCOME"
    case housing = "HOUSING"
    case foodAndDining = "FOOD_AND_DINING"
    case transportation = "TRANSPORTATION"
    case shopping = "SHOPPING"
    case billsAndUtilities = "BILLS_AND_UTILITIES"
    case healthAndWellness = "HEALTH_AND_WELLNESS"
    case entertainment = "ENTERTAINMENT"
    case transfers = "TRANSFERS"
    case other = "OTHER"

    /// Stable, human-readable group title for dashboard headers and rollup rows.
    ///
    /// Titles are part of the group's stable contract — the dashboard and design spec
    /// reference them by name — so they must not drift with display tweaks.
    public var title: String {
        switch self {
        case .income: "Income"
        case .housing: "Housing"
        case .foodAndDining: "Food & Dining"
        case .transportation: "Transportation"
        case .shopping: "Shopping"
        case .billsAndUtilities: "Bills & Utilities"
        case .healthAndWellness: "Health & Wellness"
        case .entertainment: "Entertainment"
        case .transfers: "Transfers"
        case .other: "Other"
        }
    }

    /// Canonical top-to-bottom display order for the group tree.
    ///
    /// Income leads (money in), `Other` trails (catch-all), and spend groups sit between
    /// in a stable, intuitive order. The dashboard renders groups in exactly this order;
    /// keep it stable so screenshots and the QA matrix don't churn.
    public static let displayOrder: [CategoryGroup] = [
        .income,
        .housing,
        .foodAndDining,
        .transportation,
        .shopping,
        .billsAndUtilities,
        .healthAndWellness,
        .entertainment,
        .transfers,
        .other,
    ]

    /// Position of this group within ``displayOrder`` (0-based, contiguous).
    ///
    /// Useful as a `Comparable`/sort key when building ordered rollups without threading
    /// ``displayOrder`` through call sites. `Other` is intentionally the largest index.
    public var sortIndex: Int {
        // `displayOrder` is exhaustive over `allCases`, so this lookup never fails;
        // the fallback keeps the property total without a force-unwrap.
        CategoryGroup.displayOrder.firstIndex(of: self) ?? CategoryGroup.displayOrder.count
    }

    /// The leaf ``SpendingCategory`` cases that roll up into this group.
    ///
    /// Derived from ``SpendingCategory/group`` so the mapping has a single source of
    /// truth: changing a leaf's group automatically updates this membership list.
    public var categories: [SpendingCategory] {
        SpendingCategory.allCases.filter { $0.group == self }
    }
}

public extension SpendingCategory {
    /// The fixed parent ``CategoryGroup`` this leaf category rolls up into.
    ///
    /// Total over all 16 cases — the closed `switch` is the single source of truth for
    /// the leaf→group mapping. Pure and `Sendable`; no I/O, no migration.
    var group: CategoryGroup {
        switch self {
        case .income:
            .income
        case .homeImprovement:
            .housing
        case .foodAndDrink:
            .foodAndDining
        case .transportation:
            .transportation
        case .shopping:
            .shopping
        case .billsAndUtilities, .subscriptions:
            // `subscriptions` is Plaid `LOAN_PAYMENTS` (recurring obligations), which sit
            // with bills/utilities as fixed monthly outflows rather than discretionary spend.
            .billsAndUtilities
        case .healthAndFitness, .personalCare:
            .healthAndWellness
        case .entertainment, .travel, .education:
            // Travel and education are discretionary/lifestyle spend; they fold into the
            // Entertainment group rather than spawning low-volume singleton groups.
            .entertainment
        case .transfer, .transferOut:
            .transfers
        case .bankFees, .government, .other:
            .other
        }
    }
}
