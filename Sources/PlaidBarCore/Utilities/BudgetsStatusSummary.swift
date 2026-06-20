import Foundation

/// Pure, deterministic rollup for the **Budgets** workspace status column
/// (Epic 5 / AND-583, ADR-001 window-first surface).
///
/// The 3-column Budgets destination shows a category tree (content) → category
/// detail/editor (inspector). Its third pane needs a compact, glance-able health
/// summary for the whole month's budgets. Rather than recomputing anything in the
/// view, this enum reduces a finished ``CategoryDashboardPresentation`` (already
/// override-aware — it comes from ``CategoryDashboardBuilder`` /
/// ``CategoryBudgetPlanner/netSpendByCategory(from:startKey:endKey:metadata:rules:)``)
/// into a small `Sendable` ``Summary`` the status pane renders directly.
///
/// Every verdict carries text **and** an SF Symbol so budget pressure is never
/// communicated by color alone (ACCESSIBILITY.md). The view layers a redundant
/// tint on top; this model never encodes color.
public enum BudgetsStatusSummary {
    /// The overall budget-health band for the month, ordered worst-first so the
    /// view can pick a headline glyph/label without re-deriving precedence.
    public enum Health: String, Sendable, Hashable {
        /// At least one category is over its limit.
        case over
        /// No category is over, but at least one is nearing its limit.
        case nearing
        /// Budgets exist and everything is comfortably under.
        case onTrack
        /// No category carries a budget yet (first-run / never configured).
        case noBudgets

        /// Short verdict text — always paired with ``iconName`` (never color alone).
        public var label: String {
            switch self {
            case .over: "Over budget"
            case .nearing: "Nearing a limit"
            case .onTrack: "On track"
            case .noBudgets: "No budgets set"
            }
        }

        /// SF Symbol carrying the verdict without color.
        public var iconName: String {
            switch self {
            case .over: "exclamationmark.triangle.fill"
            case .nearing: "exclamationmark.circle"
            case .onTrack: "checkmark.circle"
            case .noBudgets: "slider.horizontal.3"
            }
        }
    }

    /// A finished, `Sendable` view-model the status pane renders directly.
    public struct Summary: Sendable, Hashable {
        /// Overall month band, worst-first precedence already applied.
        public let health: Health
        /// Number of leaf categories over their individual limit.
        public let overBudgetCount: Int
        /// Number of leaf categories in the nearing band (not yet over).
        public let nearingCount: Int
        /// Number of leaf categories that carry a positive budget.
        public let budgetedCount: Int
        /// Total leaf categories with spend or a budget in the rollup.
        public let trackedCount: Int
        /// Sum of every leaf's spend across all groups.
        public let totalSpent: Double
        /// Sum of every budgeted leaf's limit.
        public let totalLimit: Double

        /// `totalLimit - totalSpent` across budgeted categories; `nil` when no
        /// budget exists (so the view shows no "left/over" line at all).
        public var remaining: Double? {
            budgetedCount > 0 ? totalLimit - totalSpent : nil
        }

        /// True when the budgeted total has been exceeded in aggregate.
        public var isAggregateOver: Bool {
            (remaining ?? 0) < 0
        }

        /// Fraction of the budgeted total already spent, clamped to `0...1` for a
        /// progress affordance; `nil` when there is no budget.
        public var fractionUsed: Double? {
            guard budgetedCount > 0, totalLimit > 0 else { return nil }
            return min(1, max(0, totalSpent / totalLimit))
        }
    }

    /// Reduce a finished dashboard rollup into the status summary.
    ///
    /// - Parameter presentation: the override-aware month rollup the tree renders.
    public static func summarize(
        _ presentation: CategoryDashboardPresentation
    ) -> Summary {
        let leaves = presentation.leaves
        let budgetedCount = leaves.reduce(0) { $0 + ($1.isBudgeted ? 1 : 0) }

        let health: Health
        if presentation.overBudgetCount > 0 {
            health = .over
        } else if presentation.nearingCount > 0 {
            health = .nearing
        } else if budgetedCount > 0 {
            health = .onTrack
        } else {
            health = .noBudgets
        }

        return Summary(
            health: health,
            overBudgetCount: presentation.overBudgetCount,
            nearingCount: presentation.nearingCount,
            budgetedCount: budgetedCount,
            trackedCount: leaves.count,
            totalSpent: presentation.totalSpent,
            totalLimit: presentation.totalLimit
        )
    }
}
