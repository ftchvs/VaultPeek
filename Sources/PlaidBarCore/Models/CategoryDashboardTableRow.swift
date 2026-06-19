import Foundation

/// One row of the detached Category Dashboard's flat **SPENT / BUDGET / LEFT**
/// `Table` (AND-539). A row is a single leaf ``SpendingCategory`` carrying its
/// group context plus the three money columns, derived purely from the
/// override-aware ``CategoryDashboardPresentation`` the dashboard already built —
/// no recompute (spec §3/§4, Option A).
///
/// The flat table is the window's analytic counterpart to the two-level status-bar
/// tree: every leaf in one sortable list, grouped-by visually via the carried
/// ``groupTitle``. Each money column is exposed both as a raw `Double` (so a
/// `Table` column can sort numerically) and as a pre-formatted, optionally-masked
/// string (so the view stays a thin renderer). Budget pressure rides on the
/// ``CategoryBudgetStatus`` text + symbol, never color alone (ACCESSIBILITY.md).
///
/// An unbudgeted leaf has `nil` ``budget`` / ``remaining`` / ``status`` — the table
/// shows an em dash for those columns rather than a misleading `$0` or a false
/// "on track" verdict.
public struct CategoryDashboardTableRow: Sendable, Hashable, Identifiable {
    /// Stable identity (`category.rawValue`) — also the `Table` row id.
    public let id: String
    public let category: SpendingCategory
    public let group: CategoryGroup
    /// Parent group title, e.g. `"Food & Dining"` (the table's grouping context).
    public let groupTitle: String
    /// Leaf display name, e.g. `"Groceries"`.
    public let categoryName: String
    /// SF Symbol for the leaf (the table's leading glyph).
    public let iconName: String

    /// Net current-month spend (floored at 0 by the builder).
    public let spent: Double
    /// Monthly limit when budgeted; `nil` = no budget.
    public let budget: Double?
    /// `budget - spent` when budgeted (negative once over); `nil` when unbudgeted.
    public let remaining: Double?
    /// `spent / budget`, floored at 0; `nil` when unbudgeted.
    public let fractionUsed: Double?
    /// Budget band; `nil` when unbudgeted.
    public let status: CategoryBudgetStatus?

    /// Build a row from a dashboard leaf and its parent group.
    public init(leaf: CategoryDashboardPresentation.Leaf, group: CategoryGroup) {
        self.id = leaf.id
        self.category = leaf.category
        self.group = group
        self.groupTitle = group.title
        self.categoryName = leaf.category.displayName
        self.iconName = leaf.category.iconName
        self.spent = leaf.spent
        self.budget = leaf.monthlyLimit
        self.remaining = leaf.remaining
        self.fractionUsed = leaf.fractionUsed
        self.status = leaf.status
    }

    /// True when this row tracks a monthly limit.
    public var isBudgeted: Bool { budget != nil }
    /// True when the leaf is over its individual budget.
    public var isOverBudget: Bool { status == .over }

    /// Short verdict text — the band label when budgeted, else an explicit
    /// no-budget verdict (never silently "on track").
    public var statusText: String { status?.label ?? "No budget" }
    /// SF Symbol carrying the verdict without color.
    public var statusIconName: String { status?.iconName ?? "minus.circle" }
}

/// Pure builder for the detached dashboard's flat **SPENT / BUDGET / LEFT** table
/// (AND-539). Flattens the two-level ``CategoryDashboardPresentation`` into one
/// sortable list of leaf rows and bakes the column footer totals, so the SwiftUI
/// `Table` (which is not headlessly unit-testable) does no aggregation itself.
public enum CategoryDashboardTableModel {
    /// How the flat table is ordered before the user re-sorts it in the UI.
    public enum Order: Sendable, Hashable {
        /// Spend-heaviest leaf first (the default analytic view).
        case spendDescending
        /// Canonical group display order, then spend-heaviest leaf within a group
        /// (mirrors the status-bar tree so the two surfaces read the same).
        case groupThenSpend
    }

    /// Flatten the presentation into table rows in the requested order.
    ///
    /// - Parameters:
    ///   - presentation: the override-aware rollup (built once); never recomputed.
    ///   - order: initial ordering. Defaults to ``Order/spendDescending``.
    public static func rows(
        from presentation: CategoryDashboardPresentation,
        order: Order = .spendDescending
    ) -> [CategoryDashboardTableRow] {
        let rows = presentation.groups.flatMap { group in
            group.leaves.map { CategoryDashboardTableRow(leaf: $0, group: group.group) }
        }
        switch order {
        case .spendDescending:
            // Heaviest spend first; stable tiebreak on group order then name so equal
            // spend never reorders between builds (stable screenshots / tests).
            return rows.sorted { lhs, rhs in
                if lhs.spent != rhs.spent { return lhs.spent > rhs.spent }
                if lhs.group.sortIndex != rhs.group.sortIndex {
                    return lhs.group.sortIndex < rhs.group.sortIndex
                }
                return lhs.categoryName < rhs.categoryName
            }
        case .groupThenSpend:
            // `presentation.groups` is already in canonical display order and each
            // group's leaves are already spend-heaviest first, so flattening preserves
            // exactly that — the same order the status-bar tree renders.
            return rows
        }
    }

    /// Column footer totals for a flat table: total spent, total budgeted limit, and
    /// total remaining (budgeted leaves only). Income / transfers / excluded rows are
    /// already dropped upstream, so these equal the presentation aggregates.
    public struct Totals: Sendable, Hashable {
        /// Sum of every row's spend.
        public let spent: Double
        /// Sum of every *budgeted* row's limit.
        public let budget: Double
        /// `budget - spent over budgeted rows` (negative when collectively over).
        public let remaining: Double
        /// True when at least one row is budgeted (so the budget / left footers mean
        /// something — otherwise the view shows an em dash rather than `$0`).
        public let hasBudget: Bool
    }

    /// Compute the footer totals for the given rows.
    public static func totals(for rows: [CategoryDashboardTableRow]) -> Totals {
        let spent = rows.reduce(0) { $0 + $1.spent }
        let budgetedRows = rows.filter(\.isBudgeted)
        let budget = budgetedRows.reduce(0) { $0 + ($1.budget ?? 0) }
        return Totals(
            spent: spent,
            budget: budget,
            // Remaining is computed over budgeted rows only: an unbudgeted row has no
            // limit, so folding its spend into "left" would understate the figure.
            remaining: budget - budgetedRows.reduce(0) { $0 + $1.spent },
            hasBudget: !budgetedRows.isEmpty
        )
    }
}
