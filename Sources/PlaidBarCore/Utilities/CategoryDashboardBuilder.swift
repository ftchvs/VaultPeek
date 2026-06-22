import Foundation

/// Pure, deterministic builder for the Copilot-style **category dashboard**
/// (AND-536). It rolls *override-aware* current-month spend up into a fixed,
/// 2-level category tree — per-leaf ``SpendingCategory`` totals nested under their
/// parent ``CategoryGroup`` — plus an overall total and a budget band
/// (under/nearing/over) for every leaf and group that has a budget.
///
/// The output ``CategoryDashboardPresentation`` is the `Sendable` view-model the
/// donut (AND-537) and the status-bars / tree (AND-538) consume. This is **Option A**
/// (display-only rollups): no schema change, no new server work, and no
/// new `SpendingCategory` raw values.
///
/// Like ``CategoryBudgetPlanner``, the builder is a stateless `enum` with an
/// explicit `asOf:` reference date and injected `Calendar` — there is no hidden
/// `Date()`, so every result is fully deterministic and testable. Spend is the
/// same **override-aware, net-signed** aggregate the planner computes
/// (``CategoryBudgetPlanner/netSpendByCategory(from:startKey:endKey:metadata:rules:)``):
/// user overrides / rules move spend, refunds net within a leaf, and
/// income / transfers / excluded rows are dropped before aggregation. An on-device
/// NL suggestion is never counted (it stays display-only until the user approves
/// it). Each leaf's net spend is floored at `0` for display, exactly as
/// ``CategoryBudgetPresentation/Item`` does, so a net-refund leaf never reads as a
/// negative bar and the leaf / group / overall totals all sum consistently.
public enum CategoryDashboardBuilder {
    /// Build the dashboard rollup for the month containing `date`.
    ///
    /// - Parameters:
    ///   - transactions: all known transactions; only those in the current month
    ///     are aggregated.
    ///   - budgets: per-category monthly limits. A leaf/group with no positive
    ///     limit gets a `nil` budget (and so a `nil` status) but still contributes
    ///     spend. Non-positive limits are treated as "no budget".
    ///   - date: the reference instant whose month is scored.
    ///   - calendar: the calendar used for the month boundary (injected for
    ///     determinism).
    ///   - metadata: optional review metadata; when supplied (even empty), spend is
    ///     bucketed by each row's *effective* override-aware category. Defaults to
    ///     `nil`, which preserves raw-Plaid-category bucketing.
    ///   - rules: optional recategorization rules, applied the same way.
    ///   - recurring: optional detected recurring streams. When supplied, each
    ///     leaf carries the monthly-equivalent committed recurring spend mapped to
    ///     its category (``RecurringCommitment``), surfaced as the dashed "committed"
    ///     ghost segment on the status bars (AND-559). Defaults to `nil`, so a row
    ///     with no recurring data simply has no ghost segment.
    public static func build(
        transactions: [TransactionDTO],
        budgets: [SpendingCategory: Double],
        asOf date: Date,
        calendar: Calendar = .current,
        metadata: [TransactionReviewMetadata]? = nil,
        rules: [TransactionRule]? = nil,
        recurring: [RecurringTransaction]? = nil
    ) -> CategoryDashboardPresentation {
        guard
            let monthStart = CategoryBudgetPlanner.monthStartDate(asOf: date, calendar: calendar),
            let nextMonthStart = calendar.date(byAdding: .month, value: 1, to: monthStart)
        else { return .empty }

        // Override-aware net spend per leaf category (income / transfers / excluded
        // already dropped, refunds netted). Reuse the planner so the dashboard and
        // the budget cards can never disagree on a category's spend.
        let netByCategory = CategoryBudgetPlanner.netSpendByCategory(
            from: transactions,
            startKey: Formatters.transactionDateString(monthStart),
            endKey: Formatters.transactionDateString(nextMonthStart),
            metadata: metadata,
            rules: rules
        )

        // Only positive limits count as a budget. A zero / negative limit is "no
        // budget" — it must not band a category as over on zero spend (first run).
        let positiveBudgets = budgets.filter { $0.value > 0 }

        // Committed monthly recurring spend per category (AND-559). Empty when no
        // recurring streams were supplied, so every leaf's `committed` stays nil.
        // Pass `asOf`/`rules` so stale streams are dropped and the ghost follows the
        // same override-aware category mapping as spend (addresses Codex review).
        let committedByCategory = recurring.map {
            RecurringCommitment.monthlyByCategory(
                $0,
                asOf: date,
                calendar: calendar,
                rules: rules ?? []
            )
        } ?? [:]

        // Every leaf that has spend OR a budget appears. Floor net spend at 0 for
        // display so a net-refund leaf reads as 0, not a negative bar — and so leaf,
        // group, and overall totals all sum from the same floored figures.
        var leafCategories = Set(positiveBudgets.keys)
        for (category, net) in netByCategory where net > 0 {
            leafCategories.insert(category)
        }
        // A category that nets to <= 0 with no budget contributes nothing and is
        // not surfaced; one that nets <= 0 *with* a budget still appears (status
        // under) so the user sees their guardrail.

        // Group leaves by their fixed parent group, in canonical display order.
        var leavesByGroup: [CategoryGroup: [CategoryDashboardPresentation.Leaf]] = [:]
        for category in leafCategories {
            let spent = max(0, netByCategory[category] ?? 0)
            let limit = positiveBudgets[category]
            let leaf = CategoryDashboardPresentation.Leaf(
                category: category,
                spent: spent,
                monthlyLimit: limit,
                committed: committedByCategory[category]
            )
            leavesByGroup[category.group, default: []].append(leaf)
        }

        let groups = CategoryGroup.displayOrder.compactMap { group -> CategoryDashboardPresentation.GroupRollup? in
            guard let leaves = leavesByGroup[group], !leaves.isEmpty else { return nil }
            // Leaves within a group order by spend (heaviest first), then name, so
            // the tree reads consistently regardless of dictionary iteration order.
            let orderedLeaves = leaves.sorted { lhs, rhs in
                lhs.spent != rhs.spent
                    ? lhs.spent > rhs.spent
                    : lhs.category.displayName < rhs.category.displayName
            }
            return CategoryDashboardPresentation.GroupRollup(group: group, leaves: orderedLeaves)
        }

        return CategoryDashboardPresentation(groups: groups)
    }
}
