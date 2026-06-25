import Foundation

/// Pure, deterministic budget **rebalance** math for budgeting v2
/// (AND-549 — deferred epic AND-524).
///
/// ## What this adds on top of AND-546 / AND-548
///
/// AND-546 persists ``MonthlyBudgetV2`` rows keyed by `(month, category)`; AND-548
/// (``RolloverBudgetPlanner`` / ``MonthlyBudgetEditor``) adds the per-month carry
/// math and immutability-aware editing. This planner is Copilot's **Rebalance**:
/// move budget *from* an under-spent category *to* an over-spent one **within a
/// single month, keeping that month's total budget constant**. It only ever
/// reshuffles the existing `monthlyLimit` values for one month — it never changes
/// the sum, never touches spend, and never edits a frozen historical month.
///
/// ## The invariant (AC 1)
///
/// A rebalance moves an amount `X` from a source category to a destination
/// category for one `month`:
///
/// ```text
/// source.monthlyLimit -= X
/// dest.monthlyLimit   += X
/// ```
///
/// so the month's total budget (`Σ monthlyLimit` over that month's rows) is
/// **provably unchanged** — every applied move is `+X` and `−X` on the same total.
/// ``apply(_:to:asOf:)`` enforces this exactly; ``BudgetRebalanceMove/amount`` is
/// validated `> 0`, finite, and `<= source.monthlyLimit` so a source can never go
/// negative and the conservation holds bit-for-bit.
///
/// ## Suggestions (AC 2)
///
/// ``suggestRebalances(...)`` proposes moves from categories with a **surplus**
/// (limit comfortably above the month's override-aware spend) toward categories
/// **trending over** (spend already above, or projected to exceed, the limit). It
/// is greedy and total-preserving: it pulls only from real surplus and gives only
/// what closes a real overage, so applying every suggestion leaves the month total
/// unchanged. Suggestions are read-only proposals — nothing is mutated until the
/// user applies a move.
///
/// ## Undo (AC 3)
///
/// Every applied ``BudgetRebalanceMove`` has an exact inverse
/// (``BudgetRebalanceMove/inverse``: swap source/dest, same amount). Re-applying
/// the inverse restores the pre-move limits **byte-for-byte**, so a rebalance is
/// fully undoable and the dashboard reflects either state immediately (the result
/// is just a new ``BudgetingV2Schema`` the read model re-renders from).
///
/// ## Determinism
///
/// Like ``RolloverBudgetPlanner`` and ``CategoryBudgetPlanner``, there is no hidden
/// `Date()`: editability is gated by the explicit `asOf` month key, and spend is
/// supplied by the caller (typically via
/// ``CategoryBudgetPlanner/overrideAwareSpend(transactions:month:metadata:rules:calendar:)``).
/// Every result is reproducible in `PlaidBarCore` unit tests.
public enum BudgetRebalancePlanner {

    // MARK: - Move

    /// A single total-preserving rebalance: move `amount` of budget from
    /// `sourceCategoryId` to `destinationCategoryId` for `month`. Pure value type;
    /// `Sendable`. This is also the **undo token** — keep it to reverse the move via
    /// ``inverse``.
    public struct BudgetRebalanceMove: Codable, Sendable, Hashable, Identifiable {
        /// The `YYYY-MM` month this move applies to. A rebalance is always within one
        /// month so the month total is conserved.
        public let month: String
        /// The category budget is pulled *from* (``BudgetCategoryV2/id``).
        public let sourceCategoryId: String
        /// The category budget is pushed *to* (``BudgetCategoryV2/id``).
        public let destinationCategoryId: String
        /// The amount moved, in the account's display currency. Always `> 0`;
        /// direction is encoded by source/destination, not by sign.
        public let amount: Double

        /// Stable identity — one move per `(month, source→dest, amount)`.
        public var id: String {
            "\(month)|\(sourceCategoryId)>\(destinationCategoryId)|\(amount)"
        }

        public init(
            month: String,
            sourceCategoryId: String,
            destinationCategoryId: String,
            amount: Double
        ) {
            self.month = month
            self.sourceCategoryId = sourceCategoryId
            self.destinationCategoryId = destinationCategoryId
            self.amount = amount
        }

        /// The exact inverse move — swap source and destination, same amount. Applying
        /// a move then its inverse restores the original limits byte-for-byte, which is
        /// how undo (AC 3) round-trips losslessly.
        public var inverse: BudgetRebalanceMove {
            BudgetRebalanceMove(
                month: month,
                sourceCategoryId: destinationCategoryId,
                destinationCategoryId: sourceCategoryId,
                amount: amount
            )
        }
    }

    // MARK: - Apply result

    /// Outcome of applying a rebalance move: the (possibly unchanged) schema, whether
    /// the move applied, and — when it applied — the undo token to reverse it.
    /// `applied == false` means the move was rejected (frozen month, missing/invalid
    /// row, or an amount that would push the source negative) and the schema is
    /// byte-identical to the input.
    public struct ApplyResult: Sendable, Hashable {
        public let schema: BudgetingV2Schema
        public let applied: Bool
        /// The token to undo this move, present only when `applied`. Re-apply it via
        /// ``BudgetRebalancePlanner/apply(_:to:asOf:)`` to restore the prior limits.
        public let undo: BudgetRebalanceMove?

        public init(schema: BudgetingV2Schema, applied: Bool, undo: BudgetRebalanceMove?) {
            self.schema = schema
            self.applied = applied
            self.undo = undo
        }
    }

    // MARK: - Apply (AC 1 + AC 3)

    /// Apply a total-preserving rebalance `move` to `schema` for `move.month`,
    /// validating the conservation invariant and historical immutability.
    ///
    /// The move is rejected (no-op, `applied == false`, schema byte-identical) when:
    /// - `move.month` is frozen history as of `asOf`
    ///   (``RolloverBudgetPlanner/isMonthEditable(_:asOf:)``);
    /// - source and destination are the same category (a no-op move);
    /// - `amount` is not finite or not `> 0`;
    /// - either category has no budget row for `month` (you can only move budget
    ///   between two *budgeted* categories — there is no limit to pull from or a
    ///   well-defined limit to add to otherwise);
    /// - `amount` exceeds the source row's `monthlyLimit` (a source limit can never
    ///   go negative — that would break conservation against a clamped floor).
    ///
    /// On success the source row's limit drops by `amount` and the destination's
    /// rises by `amount`, so the month total is unchanged, and the returned
    /// ``ApplyResult/undo`` is the inverse move.
    ///
    /// - Parameters:
    ///   - move: the rebalance to apply.
    ///   - schema: the current v2 snapshot.
    ///   - asOf: the current `YYYY-MM` (injected "now") gating editability.
    public static func apply(
        _ move: BudgetRebalanceMove,
        to schema: BudgetingV2Schema,
        asOf: String
    ) -> ApplyResult {
        guard
            RolloverBudgetPlanner.isMonthEditable(move.month, asOf: asOf),
            move.sourceCategoryId != move.destinationCategoryId,
            move.amount.isFinite,
            move.amount > 0
        else {
            return ApplyResult(schema: schema, applied: false, undo: nil)
        }

        // Both endpoints must already be budgeted for the month.
        guard
            let sourceRow = row(in: schema, month: move.month, categoryId: move.sourceCategoryId),
            let destinationRow = row(
                in: schema, month: move.month, categoryId: move.destinationCategoryId
            )
        else {
            return ApplyResult(schema: schema, applied: false, undo: nil)
        }

        // Conservation guard: the source limit can never go negative.
        guard move.amount <= sourceRow.monthlyLimit else {
            return ApplyResult(schema: schema, applied: false, undo: nil)
        }

        let updatedSource = MonthlyBudgetV2(
            month: sourceRow.month,
            categoryId: sourceRow.categoryId,
            monthlyLimit: sourceRow.monthlyLimit - move.amount,
            rollover: sourceRow.rollover
        )
        let updatedDestination = MonthlyBudgetV2(
            month: destinationRow.month,
            categoryId: destinationRow.categoryId,
            monthlyLimit: destinationRow.monthlyLimit + move.amount,
            rollover: destinationRow.rollover
        )

        var budgets = schema.budgets.filter { budget in
            !(budget.month == move.month
                && (budget.categoryId == move.sourceCategoryId
                    || budget.categoryId == move.destinationCategoryId))
        }
        budgets.append(updatedSource)
        budgets.append(updatedDestination)
        budgets.sort { lhs, rhs in
            lhs.month != rhs.month ? lhs.month < rhs.month : lhs.categoryId < rhs.categoryId
        }

        return ApplyResult(
            schema: BudgetingV2Schema(
                schemaVersion: schema.schemaVersion,
                groups: schema.groups,
                categories: schema.categories,
                budgets: budgets
            ),
            applied: true,
            undo: move.inverse
        )
    }

    // MARK: - Suggestions (AC 2)

    /// A proposed rebalance plus the surplus/overage context that justified it, so
    /// the UI can explain *why* (never communicate the source/destination roles by
    /// color alone). Pure value type; `Sendable`.
    public struct RebalanceSuggestion: Sendable, Hashable, Identifiable {
        /// The total-preserving move this suggestion would apply.
        public let move: BudgetRebalanceMove
        /// The source category's surplus before the move (`limit - spend`, `> 0`).
        public let sourceSurplus: Double
        /// The destination category's overage before the move (`spend - limit`,
        /// `> 0`) — how far over it is trending.
        public let destinationOverage: Double

        public var id: String { move.id }

        public init(
            move: BudgetRebalanceMove,
            sourceSurplus: Double,
            destinationOverage: Double
        ) {
            self.move = move
            self.sourceSurplus = sourceSurplus
            self.destinationOverage = destinationOverage
        }
    }

    /// Default share of a category's surplus a single suggestion is willing to pull,
    /// leaving a cushion so a "surplus" category isn't drained to the bone. `0.5`
    /// keeps half the headroom in place.
    public static let defaultMaxSurplusFraction = 0.5

    /// Suggest total-preserving rebalances for `month`: pull from categories with a
    /// **surplus** (limit comfortably above spend) toward categories **trending
    /// over** (spend above limit).
    ///
    /// Greedy and conservation-safe by construction: each suggested move pulls only
    /// from real surplus (capped at ``defaultMaxSurplusFraction`` of the source's
    /// headroom, configurable) and gives only what closes the destination's overage,
    /// so applying every suggestion never changes the month total. Sources are spent
    /// most-surplus-first; destinations are filled most-over-first; ties break by
    /// category id for determinism.
    ///
    /// - Parameters:
    ///   - schema: the current v2 snapshot (its `month` rows define the limits).
    ///   - month: the `YYYY-MM` to rebalance.
    ///   - spendByCategory: override-aware net spend per category id for `month`
    ///     (typically from ``CategoryBudgetPlanner/overrideAwareSpend(transactions:month:metadata:rules:calendar:)``,
    ///     keyed by ``BudgetCategoryV2/id``). A missing category is treated as `0`
    ///     spend (pure surplus).
    ///   - asOf: the current `YYYY-MM`; suggestions are only produced for an editable
    ///     month (a frozen month yields none).
    ///   - maxSurplusFraction: the share of a source's surplus a single suggestion may
    ///     pull. Defaults to ``defaultMaxSurplusFraction``.
    /// - Returns: suggested moves, destination-overage-first; empty when there is no
    ///   surplus, no overage, or the month is frozen.
    public static func suggestRebalances(
        in schema: BudgetingV2Schema,
        month: String,
        spendByCategory: [String: Double],
        asOf: String,
        maxSurplusFraction: Double = defaultMaxSurplusFraction
    ) -> [RebalanceSuggestion] {
        guard
            RolloverBudgetPlanner.isMonthEditable(month, asOf: asOf),
            maxSurplusFraction.isFinite,
            maxSurplusFraction > 0
        else { return [] }

        let monthRows = schema.budgets.filter { $0.month == month && $0.monthlyLimit > 0 }
        guard !monthRows.isEmpty else { return [] }

        // Sources: categories under budget, ranked by how much we may pull (a cushion
        // share of the surplus). Destinations: categories over budget, ranked by how
        // far over. Both deterministic (amount desc, then category id asc).
        var sources: [(categoryId: String, available: Double)] = []
        var destinations: [(categoryId: String, overage: Double)] = []

        for row in monthRows {
            let spend = spendByCategory[row.categoryId] ?? 0
            let remaining = row.monthlyLimit - spend
            if remaining > 0 {
                // Pull at most a fraction of the surplus, but never more than the limit.
                let pullable = min(remaining * maxSurplusFraction, row.monthlyLimit)
                if pullable > 0 {
                    sources.append((row.categoryId, pullable))
                }
            } else if remaining < 0 {
                destinations.append((row.categoryId, -remaining))
            }
        }

        guard !sources.isEmpty, !destinations.isEmpty else { return [] }

        sources.sort { lhs, rhs in
            lhs.available != rhs.available
                ? lhs.available > rhs.available
                : lhs.categoryId < rhs.categoryId
        }
        destinations.sort { lhs, rhs in
            lhs.overage != rhs.overage
                ? lhs.overage > rhs.overage
                : lhs.categoryId < rhs.categoryId
        }

        // Original surplus/overage for the suggestion's explanatory context, captured
        // before the greedy walk consumes the running pools.
        var sourceSurplusById: [String: Double] = [:]
        for source in sources { sourceSurplusById[source.categoryId] = source.available }
        var destinationOverageById: [String: Double] = [:]
        for destination in destinations {
            destinationOverageById[destination.categoryId] = destination.overage
        }

        var suggestions: [RebalanceSuggestion] = []
        var sourceIndex = 0
        var remainingBySource = sources.map(\.available)
        var remainingNeedByDest = destinations.map(\.overage)

        for destinationIndex in destinations.indices {
            var need = remainingNeedByDest[destinationIndex]
            let destinationId = destinations[destinationIndex].categoryId

            while need > 0, sourceIndex < sources.count {
                let available = remainingBySource[sourceIndex]
                let sourceId = sources[sourceIndex].categoryId

                // A source can't fund its own overage (it's a source *because* it has
                // surplus, so it never appears as a destination) — no self-move guard
                // needed beyond the available pool. Skip a drained source.
                guard available > 0 else { sourceIndex += 1; continue }

                let move = min(available, need)
                suggestions.append(
                    RebalanceSuggestion(
                        move: BudgetRebalanceMove(
                            month: month,
                            sourceCategoryId: sourceId,
                            destinationCategoryId: destinationId,
                            amount: move
                        ),
                        sourceSurplus: sourceSurplusById[sourceId] ?? move,
                        destinationOverage: destinationOverageById[destinationId] ?? move
                    )
                )
                remainingBySource[sourceIndex] = available - move
                need -= move
                if remainingBySource[sourceIndex] <= 0 { sourceIndex += 1 }
            }

            remainingNeedByDest[destinationIndex] = need
            if sourceIndex >= sources.count { break }
        }

        return suggestions
    }

    // MARK: - Totals (invariant helper)

    /// The total budget for `month`: `Σ monthlyLimit` over that month's rows. Exposed
    /// so callers (and tests) can assert the rebalance invariant — this value is
    /// unchanged by every ``apply(_:to:asOf:)`` that applied.
    public static func monthTotal(in schema: BudgetingV2Schema, month: String) -> Double {
        schema.budgets.reduce(0) { partial, budget in
            budget.month == month ? partial + budget.monthlyLimit : partial
        }
    }

    // MARK: - Internals

    /// The budget row for `(month, categoryId)` in `schema`, or `nil` if the category
    /// is not budgeted that month. Last-wins on a malformed duplicate, matching
    /// ``MonthlyBudgetEditor``'s upsert contract.
    static func row(
        in schema: BudgetingV2Schema,
        month: String,
        categoryId: String
    ) -> MonthlyBudgetV2? {
        schema.budgets.last { $0.month == month && $0.categoryId == categoryId }
    }
}
