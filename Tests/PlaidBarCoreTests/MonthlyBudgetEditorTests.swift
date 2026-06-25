import Foundation
import Testing
@testable import PlaidBarCore

/// Per-month budget editing under the historical-immutability rule (AND-548).
///
/// "Now" is always an explicit `asOf` month key — no wall-clock `Date()`. Verifies
/// the editor upserts/removes only on the current/future months, rejects edits to
/// frozen historical months (no-op), validates inputs, and forward-seeds the budget
/// template without clobbering existing forward edits.
@Suite("Monthly budget editor — immutable history (AND-548)")
struct MonthlyBudgetEditorTests {

    private let food = SpendingCategory.foodAndDrink.rawValue
    private let shopping = SpendingCategory.shopping.rawValue

    /// A seeded (taxonomy-complete) schema with no budgets — the realistic starting
    /// point after opt-in.
    private func emptySchema() -> BudgetingV2Schema {
        BudgetingV2Migration.seed()
    }

    // MARK: - Set on an editable month

    @Test("Setting a budget on the current month applies and stores the row")
    func setOnCurrentMonthApplies() {
        let result = MonthlyBudgetEditor.setBudget(
            in: emptySchema(),
            categoryId: food,
            month: "2026-06",
            monthlyLimit: 500,
            rollover: true,
            asOf: "2026-06"
        )
        #expect(result.applied)
        let row = result.schema.budgets.first { $0.month == "2026-06" && $0.categoryId == food }
        #expect(row?.monthlyLimit == 500)
        #expect(row?.rollover == true)
    }

    @Test("Setting a budget on a future month applies")
    func setOnFutureMonthApplies() {
        let result = MonthlyBudgetEditor.setBudget(
            in: emptySchema(),
            categoryId: food,
            month: "2026-08",
            monthlyLimit: 250,
            rollover: false,
            asOf: "2026-06"
        )
        #expect(result.applied)
        #expect(result.schema.budgets.contains { $0.month == "2026-08" })
    }

    @Test("Re-setting the same month/category upserts (no duplicate row)")
    func resetUpsertsInPlace() {
        var schema = emptySchema()
        schema = MonthlyBudgetEditor.setBudget(
            in: schema, categoryId: food, month: "2026-06",
            monthlyLimit: 500, rollover: true, asOf: "2026-06"
        ).schema
        schema = MonthlyBudgetEditor.setBudget(
            in: schema, categoryId: food, month: "2026-06",
            monthlyLimit: 600, rollover: false, asOf: "2026-06"
        ).schema

        let matching = schema.budgets.filter { $0.month == "2026-06" && $0.categoryId == food }
        #expect(matching.count == 1)
        #expect(matching.first?.monthlyLimit == 600)
        #expect(matching.first?.rollover == false)
    }

    // MARK: - Historical immutability

    @Test("Setting a budget on a past month is a no-op — history is frozen")
    func setOnPastMonthIsNoOp() {
        let before = emptySchema()
        let result = MonthlyBudgetEditor.setBudget(
            in: before,
            categoryId: food,
            month: "2026-05", // past relative to asOf
            monthlyLimit: 500,
            rollover: true,
            asOf: "2026-06"
        )
        #expect(!result.applied)
        #expect(result.schema == before) // byte-identical, nothing rewritten
    }

    @Test("Removing a budget from a past month is a no-op")
    func removeFromPastMonthIsNoOp() {
        // Build a schema that already holds a (frozen) historical budget.
        let seeded = BudgetingV2Migration.seed(
            carryingForward: [CategoryBudgetDTO(category: .foodAndDrink, monthlyLimit: 500)],
            month: "2026-05"
        )
        let result = MonthlyBudgetEditor.removeBudget(
            in: seeded, categoryId: food, month: "2026-05", asOf: "2026-06"
        )
        #expect(!result.applied)
        #expect(result.schema == seeded) // the historical row survives
    }

    @Test("Removing a budget from the current month applies")
    func removeFromCurrentMonthApplies() {
        var schema = emptySchema()
        schema = MonthlyBudgetEditor.setBudget(
            in: schema, categoryId: food, month: "2026-06",
            monthlyLimit: 500, rollover: true, asOf: "2026-06"
        ).schema
        let result = MonthlyBudgetEditor.removeBudget(
            in: schema, categoryId: food, month: "2026-06", asOf: "2026-06"
        )
        #expect(result.applied)
        #expect(!result.schema.budgets.contains { $0.month == "2026-06" && $0.categoryId == food })
    }

    // MARK: - Input validation

    @Test("A negative or non-finite limit is rejected (no-op)")
    func invalidLimitRejected() {
        let before = emptySchema()
        #expect(!MonthlyBudgetEditor.setBudget(
            in: before, categoryId: food, month: "2026-06",
            monthlyLimit: -10, rollover: false, asOf: "2026-06"
        ).applied)
        #expect(!MonthlyBudgetEditor.setBudget(
            in: before, categoryId: food, month: "2026-06",
            monthlyLimit: .nan, rollover: false, asOf: "2026-06"
        ).applied)
        #expect(!MonthlyBudgetEditor.setBudget(
            in: before, categoryId: food, month: "2026-06",
            monthlyLimit: .infinity, rollover: false, asOf: "2026-06"
        ).applied)
    }

    @Test("A zero limit is allowed (a deliberately zeroed envelope)")
    func zeroLimitAllowed() {
        let result = MonthlyBudgetEditor.setBudget(
            in: emptySchema(), categoryId: food, month: "2026-06",
            monthlyLimit: 0, rollover: false, asOf: "2026-06"
        )
        #expect(result.applied)
        #expect(result.schema.budgets.first { $0.month == "2026-06" }?.monthlyLimit == 0)
    }

    @Test("An unknown category id is rejected — a budget can't reference a missing category")
    func unknownCategoryRejected() {
        let result = MonthlyBudgetEditor.setBudget(
            in: emptySchema(), categoryId: "NOT_A_REAL_CATEGORY", month: "2026-06",
            monthlyLimit: 100, rollover: false, asOf: "2026-06"
        )
        #expect(!result.applied)
    }

    @Test("A malformed asOf freezes everything (fail closed)")
    func malformedAsOfFreezes() {
        let result = MonthlyBudgetEditor.setBudget(
            in: emptySchema(), categoryId: food, month: "2026-06",
            monthlyLimit: 100, rollover: false, asOf: "bad"
        )
        #expect(!result.applied)
    }

    // MARK: - Forward template seeding

    @Test("Forward-seeding copies the current month's budgets into the next month")
    func forwardSeedCopiesTemplate() {
        var schema = emptySchema()
        schema = MonthlyBudgetEditor.setBudget(
            in: schema, categoryId: food, month: "2026-06",
            monthlyLimit: 500, rollover: true, asOf: "2026-06"
        ).schema
        schema = MonthlyBudgetEditor.setBudget(
            in: schema, categoryId: shopping, month: "2026-06",
            monthlyLimit: 300, rollover: false, asOf: "2026-06"
        ).schema

        let result = MonthlyBudgetEditor.rolloverTemplateToNextMonth(
            in: schema, fromMonth: "2026-06", asOf: "2026-06"
        )
        #expect(result.applied)
        let july = result.schema.budgets.filter { $0.month == "2026-07" }
        #expect(july.count == 2)
        #expect(july.first { $0.categoryId == food }?.monthlyLimit == 500)
        #expect(july.first { $0.categoryId == food }?.rollover == true)
        #expect(july.first { $0.categoryId == shopping }?.monthlyLimit == 300)
    }

    @Test("Forward-seeding never clobbers an existing forward edit")
    func forwardSeedPreservesExistingNextMonth() {
        var schema = emptySchema()
        // Current month template.
        schema = MonthlyBudgetEditor.setBudget(
            in: schema, categoryId: food, month: "2026-06",
            monthlyLimit: 500, rollover: true, asOf: "2026-06"
        ).schema
        // A deliberate, different July edit already exists.
        schema = MonthlyBudgetEditor.setBudget(
            in: schema, categoryId: food, month: "2026-07",
            monthlyLimit: 999, rollover: false, asOf: "2026-06"
        ).schema

        let result = MonthlyBudgetEditor.rolloverTemplateToNextMonth(
            in: schema, fromMonth: "2026-06", asOf: "2026-06"
        )
        // Nothing to add — July's food row already exists and must win.
        #expect(!result.applied)
        #expect(result.schema.budgets.first { $0.month == "2026-07" && $0.categoryId == food }?
            .monthlyLimit == 999)
    }

    @Test("Forward-seeding is a no-op when the template month has no budgets")
    func forwardSeedEmptyTemplateIsNoOp() {
        let result = MonthlyBudgetEditor.rolloverTemplateToNextMonth(
            in: emptySchema(), fromMonth: "2026-06", asOf: "2026-06"
        )
        #expect(!result.applied)
    }

    // MARK: - End-to-end: edit then resolve carry

    @Test("Editing per-month budgets then resolving carry produces the expected envelope")
    func editThenResolveCarry() {
        var schema = emptySchema()
        // June: $500 limit, rollover on.
        schema = MonthlyBudgetEditor.setBudget(
            in: schema, categoryId: food, month: "2026-06",
            monthlyLimit: 500, rollover: true, asOf: "2026-06"
        ).schema
        // July: $500 limit, rollover on (future month, editable).
        schema = MonthlyBudgetEditor.setBudget(
            in: schema, categoryId: food, month: "2026-07",
            monthlyLimit: 500, rollover: true, asOf: "2026-06"
        ).schema

        let results = RolloverBudgetPlanner.resolveCarry(
            budgets: schema.budgets,
            spendByMonth: ["2026-06": 200], // $300 unspent rolls to July
            categoryId: food
        )
        #expect(results.map(\.month) == ["2026-06", "2026-07"])
        #expect(results[1].carriedIn == 300)
        #expect(results[1].available == 800)
    }
}
