import Foundation
import Testing
@testable import PlaidBarCore

/// Budget rebalance — redistribute budget within a fixed total (AND-549 — deferred
/// epic AND-524).
///
/// Every test is deterministic: budget rows and per-category spend are supplied
/// directly, and "now" is an explicit `YYYY-MM` key — never wall-clock `Date()`.
/// Covers the conservation invariant (move $X from A to B, total unchanged),
/// rejection of moves that would break conservation or edit a frozen month,
/// surplus→overage suggestions, and lossless undo (a move then its inverse restores
/// the schema byte-for-byte).
@Suite("Budget rebalance planner — total-preserving redistribution (AND-549)")
struct BudgetRebalancePlannerTests {

    private let food = SpendingCategory.foodAndDrink.rawValue
    private let shopping = SpendingCategory.shopping.rawValue
    private let travel = SpendingCategory.travel.rawValue
    private let asOf = "2026-06"

    // MARK: - Schema fixtures

    /// A v2 schema seeded with the closed taxonomy (via the AND-546 migration seed)
    /// plus the supplied month budgets.
    private func schema(_ budgets: [MonthlyBudgetV2]) -> BudgetingV2Schema {
        let seeded = BudgetingV2Migration.seed()
        return BudgetingV2Schema(
            groups: seeded.groups,
            categories: seeded.categories,
            budgets: budgets
        )
    }

    private func budget(
        _ month: String,
        _ category: String,
        _ limit: Double,
        rollover: Bool = false
    ) -> MonthlyBudgetV2 {
        MonthlyBudgetV2(month: month, categoryId: category, monthlyLimit: limit, rollover: rollover)
    }

    private func move(
        _ month: String,
        from source: String,
        to destination: String,
        _ amount: Double
    ) -> BudgetRebalancePlanner.BudgetRebalanceMove {
        BudgetRebalancePlanner.BudgetRebalanceMove(
            month: month,
            sourceCategoryId: source,
            destinationCategoryId: destination,
            amount: amount
        )
    }

    // MARK: - AC 1: move $X from A to B, total unchanged

    @Test("Applying a move shifts X from source to destination")
    func applyShiftsBudget() {
        let start = schema([
            budget("2026-06", food, 500),
            budget("2026-06", shopping, 300),
        ])
        let result = BudgetRebalancePlanner.apply(
            move("2026-06", from: food, to: shopping, 100),
            to: start,
            asOf: asOf
        )

        #expect(result.applied)
        let foodRow = BudgetRebalancePlanner.row(in: result.schema, month: "2026-06", categoryId: food)
        let shoppingRow = BudgetRebalancePlanner.row(
            in: result.schema, month: "2026-06", categoryId: shopping
        )
        #expect(foodRow?.monthlyLimit == 400)
        #expect(shoppingRow?.monthlyLimit == 400)
    }

    @Test("Month total is invariant under any applied rebalance")
    func totalIsInvariant() {
        let start = schema([
            budget("2026-06", food, 500),
            budget("2026-06", shopping, 300),
            budget("2026-06", travel, 200),
        ])
        let totalBefore = BudgetRebalancePlanner.monthTotal(in: start, month: "2026-06")
        #expect(totalBefore == 1000)

        // Two chained moves; total must hold after each.
        let after1 = BudgetRebalancePlanner.apply(
            move("2026-06", from: travel, to: food, 150), to: start, asOf: asOf
        )
        #expect(after1.applied)
        #expect(BudgetRebalancePlanner.monthTotal(in: after1.schema, month: "2026-06") == totalBefore)

        let after2 = BudgetRebalancePlanner.apply(
            move("2026-06", from: shopping, to: food, 75), to: after1.schema, asOf: asOf
        )
        #expect(after2.applied)
        #expect(BudgetRebalancePlanner.monthTotal(in: after2.schema, month: "2026-06") == totalBefore)
    }

    @Test("A move that exactly drains the source is allowed and conserves the total")
    func drainSourceToZero() {
        let start = schema([
            budget("2026-06", food, 200),
            budget("2026-06", shopping, 100),
        ])
        let result = BudgetRebalancePlanner.apply(
            move("2026-06", from: food, to: shopping, 200), to: start, asOf: asOf
        )
        #expect(result.applied)
        #expect(
            BudgetRebalancePlanner.row(in: result.schema, month: "2026-06", categoryId: food)?
                .monthlyLimit == 0
        )
        #expect(
            BudgetRebalancePlanner.row(in: result.schema, month: "2026-06", categoryId: shopping)?
                .monthlyLimit == 300
        )
        #expect(BudgetRebalancePlanner.monthTotal(in: result.schema, month: "2026-06") == 300)
    }

    @Test("Rollover flags and other months are untouched by a rebalance")
    func unrelatedRowsUntouched() {
        let start = schema([
            budget("2026-06", food, 500, rollover: true),
            budget("2026-06", shopping, 300),
            budget("2026-07", food, 500), // different month, must not move
        ])
        let result = BudgetRebalancePlanner.apply(
            move("2026-06", from: food, to: shopping, 100), to: start, asOf: asOf
        )
        #expect(result.applied)
        // Rollover flag preserved on the mutated source.
        #expect(
            BudgetRebalancePlanner.row(in: result.schema, month: "2026-06", categoryId: food)?
                .rollover == true
        )
        // July untouched.
        #expect(
            BudgetRebalancePlanner.row(in: result.schema, month: "2026-07", categoryId: food)?
                .monthlyLimit == 500
        )
        #expect(BudgetRebalancePlanner.monthTotal(in: result.schema, month: "2026-07") == 500)
    }

    // MARK: - Rejected moves (no-op, conservation preserved)

    @Test("A move larger than the source limit is rejected (source can't go negative)")
    func rejectOverdraw() {
        let start = schema([
            budget("2026-06", food, 100),
            budget("2026-06", shopping, 100),
        ])
        let result = BudgetRebalancePlanner.apply(
            move("2026-06", from: food, to: shopping, 150), to: start, asOf: asOf
        )
        #expect(!result.applied)
        #expect(result.undo == nil)
        #expect(result.schema == start) // byte-identical
    }

    @Test("Editing a frozen historical month is rejected")
    func rejectFrozenMonth() {
        let start = schema([
            budget("2026-01", food, 500),
            budget("2026-01", shopping, 300),
        ])
        let result = BudgetRebalancePlanner.apply(
            move("2026-01", from: food, to: shopping, 100), to: start, asOf: asOf
        )
        #expect(!result.applied)
        #expect(result.schema == start)
    }

    @Test("A move where either endpoint is unbudgeted that month is rejected")
    func rejectMissingRow() {
        let start = schema([budget("2026-06", food, 500)]) // shopping has no row
        let result = BudgetRebalancePlanner.apply(
            move("2026-06", from: food, to: shopping, 100), to: start, asOf: asOf
        )
        #expect(!result.applied)
        #expect(result.schema == start)
    }

    @Test("Self-move and non-positive / non-finite amounts are rejected")
    func rejectDegenerate() {
        let start = schema([
            budget("2026-06", food, 500),
            budget("2026-06", shopping, 300),
        ])
        // Same source and destination.
        #expect(
            !BudgetRebalancePlanner.apply(
                move("2026-06", from: food, to: food, 50), to: start, asOf: asOf
            ).applied
        )
        // Zero amount.
        #expect(
            !BudgetRebalancePlanner.apply(
                move("2026-06", from: food, to: shopping, 0), to: start, asOf: asOf
            ).applied
        )
        // Negative amount.
        #expect(
            !BudgetRebalancePlanner.apply(
                move("2026-06", from: food, to: shopping, -50), to: start, asOf: asOf
            ).applied
        )
        // Non-finite amount.
        #expect(
            !BudgetRebalancePlanner.apply(
                move("2026-06", from: food, to: shopping, .infinity), to: start, asOf: asOf
            ).applied
        )
    }

    // MARK: - AC 3: undo round-trips losslessly

    @Test("Applying a move then its undo restores the schema byte-for-byte")
    func undoRoundTrips() {
        let start = schema([
            budget("2026-06", food, 500, rollover: true),
            budget("2026-06", shopping, 300),
            budget("2026-06", travel, 120),
        ])
        let forward = BudgetRebalancePlanner.apply(
            move("2026-06", from: food, to: shopping, 137.5), to: start, asOf: asOf
        )
        #expect(forward.applied)
        let undoToken = try! #require(forward.undo)

        let restored = BudgetRebalancePlanner.apply(undoToken, to: forward.schema, asOf: asOf)
        #expect(restored.applied)
        // The schema after undo equals the original (rows + limits + flags).
        #expect(restored.schema == start)
    }

    @Test("The undo token is the exact inverse of the move")
    func undoTokenIsInverse() {
        let m = move("2026-06", from: food, to: shopping, 80)
        #expect(m.inverse.sourceCategoryId == shopping)
        #expect(m.inverse.destinationCategoryId == food)
        #expect(m.inverse.amount == 80)
        #expect(m.inverse.month == "2026-06")
        #expect(m.inverse.inverse == m) // double inverse is identity
    }

    // MARK: - AC 2: suggestions from surplus toward over-trending

    @Test("Suggests pulling from a surplus category toward an over-trending one")
    func suggestsSurplusTowardOverage() {
        let start = schema([
            budget("2026-06", food, 400),     // over: spent 500
            budget("2026-06", shopping, 400), // surplus: spent 100
        ])
        let suggestions = BudgetRebalancePlanner.suggestRebalances(
            in: start,
            month: "2026-06",
            spendByCategory: [food: 500, shopping: 100],
            asOf: asOf
        )

        #expect(!suggestions.isEmpty)
        let first = suggestions[0]
        #expect(first.move.sourceCategoryId == shopping) // the under-spent one funds
        #expect(first.move.destinationCategoryId == food) // the over-trending one receives
        #expect(first.move.amount > 0)
        // Surplus = 400 - 100 = 300; default cushion pulls at most half → 150.
        #expect(first.move.amount <= 150)
        // The destination overage context is the food shortfall (500 - 400 = 100).
        #expect(first.destinationOverage == 100)
    }

    @Test("Applying all suggestions preserves the month total")
    func applyingSuggestionsConservesTotal() {
        let start = schema([
            budget("2026-06", food, 300),     // over by 200 (spent 500)
            budget("2026-06", shopping, 600), // surplus 500 (spent 100)
            budget("2026-06", travel, 200),   // over by 50 (spent 250)
        ])
        let spend = [food: 500.0, shopping: 100.0, travel: 250.0]
        let totalBefore = BudgetRebalancePlanner.monthTotal(in: start, month: "2026-06")

        let suggestions = BudgetRebalancePlanner.suggestRebalances(
            in: start, month: "2026-06", spendByCategory: spend, asOf: asOf
        )
        #expect(!suggestions.isEmpty)

        var current = start
        for suggestion in suggestions {
            let result = BudgetRebalancePlanner.apply(suggestion.move, to: current, asOf: asOf)
            #expect(result.applied)
            current = result.schema
        }
        // Total unchanged after applying every suggestion.
        #expect(BudgetRebalancePlanner.monthTotal(in: current, month: "2026-06") == totalBefore)
    }

    @Test("A zero-limit overspent category is an eligible rebalance destination (AND-672)")
    func zeroLimitDestinationReceivesShare() {
        // `travel` was just zeroed (limit 0) but already has spend, so it is
        // overspent and a legitimate destination. `shopping` carries the surplus.
        let start = schema([
            budget("2026-06", shopping, 600), // surplus: spent 100 → headroom 500
            budget("2026-06", travel, 0),     // zero-limit but overspent (spent 90)
        ])
        let totalBefore = BudgetRebalancePlanner.monthTotal(in: start, month: "2026-06")
        #expect(totalBefore == 600)

        let suggestions = BudgetRebalancePlanner.suggestRebalances(
            in: start,
            month: "2026-06",
            spendByCategory: [shopping: 100, travel: 90],
            asOf: asOf
        )

        // (a) The zero-limit category must receive a positive share — not be dropped.
        #expect(!suggestions.isEmpty)
        let toTravel = suggestions.filter { $0.move.destinationCategoryId == travel }
        #expect(!toTravel.isEmpty)
        #expect(toTravel.allSatisfy { $0.move.amount > 0 })
        #expect(toTravel.contains { $0.move.sourceCategoryId == shopping })

        // (b) Applying every suggestion keeps the month total invariant.
        var current = start
        for suggestion in suggestions {
            let result = BudgetRebalancePlanner.apply(suggestion.move, to: current, asOf: asOf)
            #expect(result.applied)
            current = result.schema
        }
        #expect(BudgetRebalancePlanner.monthTotal(in: current, month: "2026-06") == totalBefore)
        // The once-zero-limit destination now holds a positive limit.
        let travelRow = BudgetRebalancePlanner.row(in: current, month: "2026-06", categoryId: travel)
        #expect((travelRow?.monthlyLimit ?? 0) > 0)
    }

    @Test("No suggestions when nothing is over budget")
    func noOverageNoSuggestions() {
        let start = schema([
            budget("2026-06", food, 500),
            budget("2026-06", shopping, 500),
        ])
        let suggestions = BudgetRebalancePlanner.suggestRebalances(
            in: start,
            month: "2026-06",
            spendByCategory: [food: 100, shopping: 100], // both under
            asOf: asOf
        )
        #expect(suggestions.isEmpty)
    }

    @Test("No suggestions when there is no surplus to pull from")
    func noSurplusNoSuggestions() {
        let start = schema([
            budget("2026-06", food, 400),     // over
            budget("2026-06", shopping, 300), // also over
        ])
        let suggestions = BudgetRebalancePlanner.suggestRebalances(
            in: start,
            month: "2026-06",
            spendByCategory: [food: 500, shopping: 400],
            asOf: asOf
        )
        #expect(suggestions.isEmpty)
    }

    @Test("A frozen month yields no suggestions")
    func frozenMonthNoSuggestions() {
        let start = schema([
            budget("2026-01", food, 400),
            budget("2026-01", shopping, 400),
        ])
        let suggestions = BudgetRebalancePlanner.suggestRebalances(
            in: start,
            month: "2026-01",
            spendByCategory: [food: 500, shopping: 100],
            asOf: asOf
        )
        #expect(suggestions.isEmpty)
    }

    @Test("Suggestions are ranked destination-overage-first, then deterministic")
    func suggestionsRankedDeterministically() {
        // Two over categories: travel over by 300, food over by 100. Travel should
        // be funded first (bigger overage).
        let start = schema([
            budget("2026-06", food, 200),     // over by 100
            budget("2026-06", travel, 200),   // over by 300
            budget("2026-06", shopping, 2000), // big surplus (spent 0)
        ])
        let suggestions = BudgetRebalancePlanner.suggestRebalances(
            in: start,
            month: "2026-06",
            spendByCategory: [food: 300, travel: 500, shopping: 0],
            asOf: asOf
        )
        #expect(suggestions.count >= 1)
        #expect(suggestions[0].move.destinationCategoryId == travel)
    }

    @Test("Suggestions are stable across runs (pure, deterministic)")
    func suggestionsStable() {
        let start = schema([
            budget("2026-06", food, 300),
            budget("2026-06", shopping, 600),
            budget("2026-06", travel, 200),
        ])
        let spend = [food: 500.0, shopping: 100.0, travel: 250.0]
        let a = BudgetRebalancePlanner.suggestRebalances(
            in: start, month: "2026-06", spendByCategory: spend, asOf: asOf
        )
        let b = BudgetRebalancePlanner.suggestRebalances(
            in: start, month: "2026-06", spendByCategory: spend, asOf: asOf
        )
        #expect(a == b)
    }
}
