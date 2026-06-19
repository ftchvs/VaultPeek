import Foundation

/// Display-ready 2-level rollup of override-aware current-month spend for the
/// Copilot-style category dashboard (AND-536). Built by ``CategoryDashboardBuilder``
/// and consumed by the donut (AND-537) and the status bars / tree (AND-538).
///
/// The tree has exactly two levels: ``GroupRollup`` parents (``CategoryGroup``)
/// each holding their ``Leaf`` children (``SpendingCategory``). Spend is the
/// net-signed, override-aware figure ``CategoryBudgetPlanner`` computes, floored at
/// `0` per leaf for display; every aggregate is derived from the floored leaf
/// spend, so leaf totals, group totals, and ``totalSpent`` always sum consistently.
///
/// Budget bands (``CategoryBudgetStatus``) are carried as text + symbol, never
/// color alone (ACCESSIBILITY.md). A `nil` ``Leaf/monthlyLimit`` /
/// ``GroupRollup/monthlyLimit`` means "no budget" — its ``status`` is `nil`, and it
/// is never counted as over or nearing (so an empty / first-run dataset can never
/// produce a false "over").
public struct CategoryDashboardPresentation: Sendable, Hashable {
    /// A single leaf category's rollup — spend plus its budget band when budgeted.
    public struct Leaf: Sendable, Hashable, Identifiable {
        /// Stable per-category identity (`category.rawValue`).
        public let id: String
        public let category: SpendingCategory
        /// Net current-month spend, floored at `0` (refunds net within the leaf;
        /// transfers / income / excluded rows never reach here).
        public let spent: Double
        /// The monthly limit, when this leaf is budgeted. `nil` = no budget.
        public let monthlyLimit: Double?
        /// `spent / monthlyLimit`, floored at 0; `nil` when there is no budget.
        public let fractionUsed: Double?
        /// Budget band (under/nearing/over); `nil` when there is no budget.
        public let status: CategoryBudgetStatus?
        /// Monthly-equivalent committed recurring spend mapped to this category
        /// (``RecurringCommitment``), when at least one recurring stream maps here.
        /// `nil` = no recurring stream for this category, so no ghost segment
        /// (AND-559). Always strictly positive when present.
        public let committed: Double?

        public init(
            category: SpendingCategory,
            spent: Double,
            monthlyLimit: Double?,
            committed: Double? = nil
        ) {
            self.id = category.rawValue
            self.category = category
            let netSpent = max(0, spent)
            self.spent = netSpent
            if let limit = monthlyLimit, limit > 0 {
                self.monthlyLimit = limit
                let fraction = max(0, netSpent / limit)
                self.fractionUsed = fraction
                self.status = CategoryBudgetStatus(fractionUsed: fraction)
            } else {
                self.monthlyLimit = nil
                self.fractionUsed = nil
                self.status = nil
            }
            // Only a positive commitment is meaningful; treat 0/negative as none.
            self.committed = committed.flatMap { $0 > 0 ? $0 : nil }
        }

        /// `monthlyLimit - spent` when budgeted; `nil` otherwise.
        public var remaining: Double? {
            monthlyLimit.map { $0 - spent }
        }

        /// Share of the budget already committed to recurring bills, clamped to
        /// `0...1`. `nil` when unbudgeted or no recurring stream maps here — so the
        /// dashed ghost segment is hidden (AND-559).
        public var committedFraction: Double? {
            guard let limit = monthlyLimit, limit > 0, let committed else { return nil }
            return min(1, max(0, committed / limit))
        }

        public var isBudgeted: Bool { monthlyLimit != nil }
        public var isOverBudget: Bool { status == .over }
        public var needsAttention: Bool { status != nil && status != .under }
    }

    /// A parent group's rollup — its leaves plus the summed spend / limit / band.
    public struct GroupRollup: Sendable, Hashable, Identifiable {
        /// Stable identity (`group.rawValue`).
        public let id: String
        public let group: CategoryGroup
        /// The leaf categories under this group, spend-heaviest first.
        public let leaves: [Leaf]
        /// Sum of leaf spend.
        public let spent: Double
        /// Sum of budgeted leaves' limits; `nil` when no leaf in the group is
        /// budgeted (so the group has no budget band — independent of its leaves).
        public let monthlyLimit: Double?
        /// `spent / monthlyLimit`, floored at 0; `nil` when the group has no budget.
        public let fractionUsed: Double?
        /// Group budget band — computed from the group's *summed* spend vs *summed*
        /// limit, so a group can be over while every leaf is individually under
        /// (spec §7). `nil` when the group has no budget.
        public let status: CategoryBudgetStatus?
        /// Sum of the group's leaves' committed recurring spend; `nil` when no leaf
        /// has a recurring stream (AND-559). Always strictly positive when present.
        public let committed: Double?

        public init(group: CategoryGroup, leaves: [Leaf]) {
            self.id = group.rawValue
            self.group = group
            self.leaves = leaves
            let totalSpent = leaves.reduce(0) { $0 + $1.spent }
            self.spent = totalSpent
            // A group is budgeted iff at least one of its leaves is budgeted; its
            // limit is the sum of those leaves' limits.
            let budgetedLimits = leaves.compactMap(\.monthlyLimit)
            if budgetedLimits.isEmpty {
                self.monthlyLimit = nil
                self.fractionUsed = nil
                self.status = nil
            } else {
                let limit = budgetedLimits.reduce(0, +)
                self.monthlyLimit = limit
                let fraction = limit > 0 ? max(0, totalSpent / limit) : 0
                self.fractionUsed = fraction
                self.status = CategoryBudgetStatus(fractionUsed: fraction)
            }
            let totalCommitted = leaves.compactMap(\.committed).reduce(0, +)
            self.committed = totalCommitted > 0 ? totalCommitted : nil
        }

        /// `monthlyLimit - spent` when budgeted; `nil` otherwise.
        public var remaining: Double? {
            monthlyLimit.map { $0 - spent }
        }

        /// Share of the group budget committed to recurring bills, clamped to
        /// `0...1`; `nil` when unbudgeted or no leaf has a recurring stream.
        public var committedFraction: Double? {
            guard let limit = monthlyLimit, limit > 0, let committed else { return nil }
            return min(1, max(0, committed / limit))
        }

        public var isBudgeted: Bool { monthlyLimit != nil }
        public var title: String { group.title }
    }

    /// Group rollups in canonical ``CategoryGroup/displayOrder``; only groups with
    /// spend or a budget are present.
    public let groups: [GroupRollup]
    /// Sum of every leaf's spend across all groups (the overall total).
    public let totalSpent: Double
    /// Sum of every budgeted leaf's limit.
    public let totalLimit: Double
    /// Count of *leaves* over their individual limit.
    public let overBudgetCount: Int
    /// Count of *leaves* in the nearing band (not yet over).
    public let nearingCount: Int

    public init(groups: [GroupRollup]) {
        self.groups = groups
        self.totalSpent = groups.reduce(0) { $0 + $1.spent }
        let leaves = groups.flatMap(\.leaves)
        self.totalLimit = leaves.reduce(0) { $0 + ($1.monthlyLimit ?? 0) }
        self.overBudgetCount = leaves.reduce(0) { $0 + ($1.status == .over ? 1 : 0) }
        self.nearingCount = leaves.reduce(0) { $0 + ($1.status == .nearing ? 1 : 0) }
    }

    /// True when there is no spend and no budget to show.
    public var isEmpty: Bool { groups.isEmpty }

    /// Every leaf across all groups, flattened (groups stay in display order).
    public var leaves: [Leaf] { groups.flatMap(\.leaves) }

    /// The rollup for `group`, or `nil` when that group has no spend / budget.
    public func group(_ group: CategoryGroup) -> GroupRollup? {
        groups.first { $0.group == group }
    }

    /// The leaf rollup for `category`, or `nil` when it has no spend / budget.
    public func leaf(_ category: SpendingCategory) -> Leaf? {
        for group in groups {
            if let match = group.leaves.first(where: { $0.category == category }) {
                return match
            }
        }
        return nil
    }

    public static let empty = CategoryDashboardPresentation(groups: [])
}
