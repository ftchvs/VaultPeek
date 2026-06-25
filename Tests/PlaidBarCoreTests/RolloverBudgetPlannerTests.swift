import Foundation
import Testing
@testable import PlaidBarCore

/// Per-month budgets + rollover ("envelope carry") math (AND-548 — deferred epic
/// AND-524).
///
/// Every test is deterministic: budget rows and per-month spend are supplied
/// directly, and "now" is an explicit `YYYY-MM` key or an injected UTC `Calendar`
/// — never wall-clock `Date()`. Covers carry-forward of unspent and overspend,
/// per-category opt-out (row flag + global toggle), gap/boundary resets, the
/// historical-immutability policy, month-key arithmetic, and the additive guarantee
/// that an empty/unbudgeted input yields no carry.
@Suite("Rollover budget planner — per-month carry-forward (AND-548)")
struct RolloverBudgetPlannerTests {

    private let food = SpendingCategory.foodAndDrink.rawValue

    private func budget(
        _ month: String,
        _ limit: Double,
        rollover: Bool,
        category: String? = nil
    ) -> MonthlyBudgetV2 {
        MonthlyBudgetV2(
            month: month,
            categoryId: category ?? food,
            monthlyLimit: limit,
            rollover: rollover
        )
    }

    // MARK: - Carry of unspent (positive remainder)

    @Test("Unspent remainder of a rollover month adds to the next month's available")
    func unspentCarriesForward() {
        let budgets = [
            budget("2026-01", 500, rollover: true),
            budget("2026-02", 500, rollover: true),
        ]
        // Spent $300 in Jan → $200 unspent carries into Feb.
        let results = RolloverBudgetPlanner.resolveCarry(
            budgets: budgets,
            spendByMonth: ["2026-01": 300, "2026-02": 0],
            categoryId: food
        )

        #expect(results.count == 2)
        let jan = results[0]
        #expect(jan.carriedIn == 0)
        #expect(jan.available == 500)
        #expect(jan.remaining == 200)
        #expect(jan.carriedOut == 200)

        let feb = results[1]
        #expect(feb.carriedIn == 200)
        #expect(feb.available == 700) // 500 limit + 200 carried
        #expect(feb.remaining == 700)
        #expect(feb.carriedOut == 700)
    }

    @Test("Carry compounds across three contiguous rollover months")
    func carryCompoundsAcrossMonths() {
        let budgets = [
            budget("2026-01", 100, rollover: true),
            budget("2026-02", 100, rollover: true),
            budget("2026-03", 100, rollover: true),
        ]
        // Spend nothing — each month's full limit should pile up.
        let results = RolloverBudgetPlanner.resolveCarry(
            budgets: budgets,
            spendByMonth: [:],
            categoryId: food
        )
        #expect(results.map(\.available) == [100, 200, 300])
        #expect(results.map(\.carriedOut) == [100, 200, 300])
    }

    // MARK: - Carry of overspend (negative remainder)

    @Test("Overspend carries as a negative remainder, reducing next month's available")
    func overspendCarriesForward() {
        let budgets = [
            budget("2026-01", 500, rollover: true),
            budget("2026-02", 500, rollover: true),
        ]
        // Spent $650 in Jan → -$150 overspend carries into Feb.
        let results = RolloverBudgetPlanner.resolveCarry(
            budgets: budgets,
            spendByMonth: ["2026-01": 650],
            categoryId: food
        )
        let jan = results[0]
        #expect(jan.remaining == -150)
        #expect(jan.carriedOut == -150)

        let feb = results[1]
        #expect(feb.carriedIn == -150)
        #expect(feb.available == 350) // 500 - 150 overspend
    }

    // MARK: - Per-category opt-out (row flag)

    @Test("A month with rollover off carries nothing; the next month starts from its bare limit")
    func rolloverOffBreaksCarry() {
        let budgets = [
            budget("2026-01", 500, rollover: false), // opted out this month
            budget("2026-02", 500, rollover: true),
        ]
        let results = RolloverBudgetPlanner.resolveCarry(
            budgets: budgets,
            spendByMonth: ["2026-01": 100], // $400 unspent — but not carried
            categoryId: food
        )
        #expect(results[0].rolloverActive == false)
        #expect(results[0].carriedOut == 0)
        #expect(results[1].carriedIn == 0)
        #expect(results[1].available == 500) // bare limit, no carry
    }

    // MARK: - Per-category opt-out (global toggle)

    @Test("Global per-category opt-out forces every month's carry to zero, even with row flag on")
    func globalOptOutForcesZeroCarry() {
        let budgets = [
            budget("2026-01", 500, rollover: true),
            budget("2026-02", 500, rollover: true),
        ]
        let results = RolloverBudgetPlanner.resolveCarry(
            budgets: budgets,
            spendByMonth: ["2026-01": 100],
            categoryId: food,
            optedOut: true
        )
        #expect(results.allSatisfy { !$0.rolloverActive })
        #expect(results.allSatisfy { $0.carriedOut == 0 })
        #expect(results[1].carriedIn == 0)
        #expect(results[1].available == 500)
    }

    @Test("resolveCarryByCategory honors the opted-out category set independently per category")
    func optOutSetIsPerCategory() {
        let dining = SpendingCategory.foodAndDrink.rawValue
        let shopping = SpendingCategory.shopping.rawValue
        let budgets = [
            budget("2026-01", 200, rollover: true, category: dining),
            budget("2026-02", 200, rollover: true, category: dining),
            budget("2026-01", 300, rollover: true, category: shopping),
            budget("2026-02", 300, rollover: true, category: shopping),
        ]
        let byCategory = RolloverBudgetPlanner.resolveCarryByCategory(
            budgets: budgets,
            spendByMonthByCategory: [
                dining: ["2026-01": 50],   // $150 unspent
                shopping: ["2026-01": 50], // $250 unspent
            ],
            optedOutCategoryIds: [shopping] // only shopping opted out
        )
        // Dining carries: Feb available = 200 + 150 = 350.
        #expect(byCategory[dining]?[1].available == 350)
        // Shopping opted out: Feb available stays the bare 300.
        #expect(byCategory[shopping]?[1].available == 300)
        #expect(byCategory[shopping]?.allSatisfy { !$0.rolloverActive } == true)
    }

    // MARK: - Month boundaries

    @Test("Carry crosses a year boundary (Dec → Jan)")
    func carryCrossesYearBoundary() {
        let budgets = [
            budget("2025-12", 400, rollover: true),
            budget("2026-01", 400, rollover: true),
        ]
        let results = RolloverBudgetPlanner.resolveCarry(
            budgets: budgets,
            spendByMonth: ["2025-12": 100], // $300 unspent
            categoryId: food
        )
        #expect(results[1].month == "2026-01")
        #expect(results[1].carriedIn == 300)
        #expect(results[1].available == 700)
    }

    @Test("A gap month (no budget row) resets the carry — a later month starts fresh")
    func gapResetsCarry() {
        // Jan and March budgeted; Feb has no row → the envelope can't carry through.
        let budgets = [
            budget("2026-01", 500, rollover: true),
            budget("2026-03", 500, rollover: true),
        ]
        let results = RolloverBudgetPlanner.resolveCarry(
            budgets: budgets,
            spendByMonth: ["2026-01": 0], // $500 unspent in Jan
            categoryId: food
        )
        #expect(results.count == 2)
        #expect(results[0].month == "2026-01")
        #expect(results[1].month == "2026-03")
        // March does NOT inherit January's $500 across the missing February.
        #expect(results[1].carriedIn == 0)
        #expect(results[1].available == 500)
    }

    @Test("Unsorted input is resolved in chronological order")
    func inputIsSortedChronologically() {
        let budgets = [
            budget("2026-03", 100, rollover: true),
            budget("2026-01", 100, rollover: true),
            budget("2026-02", 100, rollover: true),
        ]
        let results = RolloverBudgetPlanner.resolveCarry(
            budgets: budgets,
            spendByMonth: [:],
            categoryId: food
        )
        #expect(results.map(\.month) == ["2026-01", "2026-02", "2026-03"])
        #expect(results.map(\.available) == [100, 200, 300])
    }

    @Test("Rows for other categories are ignored")
    func otherCategoryRowsIgnored() {
        let budgets = [
            budget("2026-01", 100, rollover: true, category: food),
            budget("2026-01", 999, rollover: true, category: SpendingCategory.shopping.rawValue),
        ]
        let results = RolloverBudgetPlanner.resolveCarry(
            budgets: budgets,
            spendByMonth: [:],
            categoryId: food
        )
        #expect(results.count == 1)
        #expect(results[0].baseLimit == 100)
    }

    @Test("Empty budgets yield no results — an unbudgeted category has no carry (additive)")
    func emptyBudgetsYieldNoCarry() {
        let results = RolloverBudgetPlanner.resolveCarry(
            budgets: [],
            spendByMonth: ["2026-01": 100],
            categoryId: food
        )
        #expect(results.isEmpty)
    }

    @Test("Missing spend for a month is treated as zero")
    func missingSpendIsZero() {
        let results = RolloverBudgetPlanner.resolveCarry(
            budgets: [budget("2026-01", 250, rollover: true)],
            spendByMonth: [:],
            categoryId: food
        )
        #expect(results[0].spent == 0)
        #expect(results[0].remaining == 250)
        #expect(results[0].carriedOut == 250)
    }

    @Test("Duplicate month rows collapse to the last one (degrades, never crashes)")
    func duplicateMonthCollapses() {
        let budgets = [
            budget("2026-01", 100, rollover: true),
            budget("2026-01", 200, rollover: true), // dup month, last wins
        ]
        let results = RolloverBudgetPlanner.resolveCarry(
            budgets: budgets,
            spendByMonth: [:],
            categoryId: food
        )
        #expect(results.count == 1)
        #expect(results[0].baseLimit == 200)
    }

    // MARK: - Historical immutability policy

    @Test("Current and future months are editable; past months are frozen")
    func editabilityPolicy() {
        #expect(RolloverBudgetPlanner.isMonthEditable("2026-06", asOf: "2026-06")) // current
        #expect(RolloverBudgetPlanner.isMonthEditable("2026-07", asOf: "2026-06")) // future
        #expect(!RolloverBudgetPlanner.isMonthEditable("2026-05", asOf: "2026-06")) // past
        #expect(!RolloverBudgetPlanner.isMonthEditable("2025-12", asOf: "2026-01")) // past, prior year
    }

    @Test("A malformed month key is never editable (fail closed)")
    func malformedMonthNotEditable() {
        #expect(!RolloverBudgetPlanner.isMonthEditable("2026-13", asOf: "2026-06"))
        #expect(!RolloverBudgetPlanner.isMonthEditable("nope", asOf: "2026-06"))
        #expect(!RolloverBudgetPlanner.isMonthEditable("2026-06", asOf: "garbage"))
    }

    // MARK: - Month-key arithmetic

    @Test("nextMonthKey / previousMonthKey roll across month and year boundaries")
    func monthKeyArithmetic() {
        #expect(RolloverBudgetPlanner.nextMonthKey("2026-01") == "2026-02")
        #expect(RolloverBudgetPlanner.nextMonthKey("2026-12") == "2027-01")
        #expect(RolloverBudgetPlanner.previousMonthKey("2026-01") == "2025-12")
        #expect(RolloverBudgetPlanner.previousMonthKey("2026-03") == "2026-02")
        #expect(RolloverBudgetPlanner.nextMonthKey("bad") == nil)
        #expect(RolloverBudgetPlanner.previousMonthKey("2026-00") == nil)
    }

    @Test("monthKey(for:calendar:) derives the bucket from an injected calendar (no wall clock)")
    func monthKeyFromInjectedCalendar() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // 2026-06-13T12:00:00Z
        let date = Date(timeIntervalSince1970: 1_781_352_000)
        #expect(RolloverBudgetPlanner.monthKey(for: date, calendar: calendar) == "2026-06")
    }
}
