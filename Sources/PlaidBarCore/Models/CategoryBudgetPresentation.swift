import Foundation

/// Discrete budget-pressure band for a single category — text + symbol, never
/// color alone (ACCESSIBILITY.md). Derived purely from the fraction of the
/// monthly limit consumed so the UI and any alert logic agree on the verdict.
public enum CategoryBudgetStatus: String, Sendable, Hashable, CaseIterable {
    /// Comfortably below the limit.
    case under
    /// Within reach of the limit — the early-warning band the feature exists for.
    case nearing
    /// Spend has passed the limit.
    case over

    /// `under`/`nearing` boundary, as a fraction of the limit. 0.8 = 80%.
    public static let nearingThreshold = 0.8

    /// Band a category falls into for a given consumed fraction. `> 1.0` is over;
    /// `>= nearingThreshold` (and `<= 1.0`) is nearing; everything else is under.
    public init(fractionUsed: Double) {
        if fractionUsed > 1.0 {
            self = .over
        } else if fractionUsed >= Self.nearingThreshold {
            self = .nearing
        } else {
            self = .under
        }
    }

    public var label: String {
        switch self {
        case .under: "On track"
        case .nearing: "Close to limit"
        case .over: "Over budget"
        }
    }

    /// SF Symbol carrying the verdict without relying on color.
    public var iconName: String {
        switch self {
        case .under: "checkmark.circle"
        case .nearing: "exclamationmark.circle"
        case .over: "exclamationmark.triangle.fill"
        }
    }
}

/// Display-ready view of lightweight category budgets (AND-402).
///
/// Pure presentation logic: given a set of monthly limits and the transaction
/// history, it computes each category's current-month spend, remaining amount,
/// and pressure band, plus the aggregates a glance surface needs. All formatting
/// stays in the view; this type owns ordering, netting, and the derived numbers
/// so they are testable and identical across surfaces.
///
/// This is the *read-only* / suggestion half of AND-402. The limits here are
/// either user-set or the planner's suggestions (`areSuggested`); persisting a
/// user's edits (create / edit / delete a saved budget) is deliberately out of
/// scope and shares the budgeting-suite persistence decision tracked across
/// AND-399 / 400 / 402 / 403.
public struct CategoryBudgetPresentation: Sendable, Hashable {
    public struct Item: Sendable, Hashable, Identifiable {
        /// Stable per-category identity (`category.rawValue`).
        public let id: String
        public let category: SpendingCategory
        /// The monthly limit being tracked (suggested or user-set).
        public let monthlyLimit: Double
        /// Net current-month spend for the category, floored at 0. "Net" means
        /// refunds (negative-amount transactions sharing the category) reduce the
        /// figure; transfers and income are excluded entirely.
        public let spent: Double
        /// `monthlyLimit - spent`. Negative once the category is over budget.
        public let remaining: Double
        /// `spent / monthlyLimit`, floored at 0; 0 when the limit is non-positive.
        public let fractionUsed: Double
        public let status: CategoryBudgetStatus
        /// True when this limit is a planner suggestion the user has not saved.
        public let isSuggested: Bool

        public init(
            category: SpendingCategory,
            monthlyLimit: Double,
            spent: Double,
            isSuggested: Bool
        ) {
            self.id = category.rawValue
            self.category = category
            self.monthlyLimit = monthlyLimit
            let netSpent = max(0, spent)
            self.spent = netSpent
            self.remaining = monthlyLimit - netSpent
            let fraction = monthlyLimit > 0 ? max(0, netSpent / monthlyLimit) : 0
            self.fractionUsed = fraction
            self.status = CategoryBudgetStatus(fractionUsed: fraction)
            self.isSuggested = isSuggested
        }

        public var isOverBudget: Bool { status == .over }
        public var needsAttention: Bool { status != .under }
    }

    /// Budgets, attention-first (over, then nearing) then by spend pressure — see
    /// `CategoryBudgetPlanner.presentation`.
    public let items: [Item]
    /// Sum of every tracked limit.
    public let totalLimit: Double
    /// Sum of every category's net current-month spend.
    public let totalSpent: Double
    /// Count of categories over their limit.
    public let overBudgetCount: Int
    /// Count of categories in the nearing band (not yet over).
    public let nearingCount: Int

    public init(
        items: [Item],
        totalLimit: Double,
        totalSpent: Double,
        overBudgetCount: Int,
        nearingCount: Int
    ) {
        self.items = items
        self.totalLimit = totalLimit
        self.totalSpent = totalSpent
        self.overBudgetCount = overBudgetCount
        self.nearingCount = nearingCount
    }

    public var isEmpty: Bool { items.isEmpty }
    public var count: Int { items.count }

    public static let empty = CategoryBudgetPresentation(
        items: [],
        totalLimit: 0,
        totalSpent: 0,
        overBudgetCount: 0,
        nearingCount: 0
    )
}
