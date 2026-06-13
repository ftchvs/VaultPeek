import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Category budgets (AND-402)")
struct CategoryBudgetPlannerTests {
    // June 13, 2026 — current month is June; trailing complete months are
    // May / April / March.
    private let now = Formatters.parseTransactionDate("2026-06-13")!
    private let calendar = Calendar(identifier: .gregorian)

    private func tx(
        _ amount: Double,
        _ date: String,
        _ category: SpendingCategory,
        pending: Bool = false,
        name: String = "Merchant"
    ) -> TransactionDTO {
        TransactionDTO(
            id: "\(name)-\(date)-\(amount)",
            accountId: "acct",
            amount: amount,
            date: date,
            name: name,
            category: category,
            pending: pending
        )
    }

    // MARK: - Progress

    @Test("Only the current month's spend counts — prior-month spend rolls off")
    func monthlyRollover() {
        let transactions = [
            tx(400, "2026-05-20", .foodAndDrink), // previous month — excluded
            tx(100, "2026-06-05", .foodAndDrink), // current month — counts
            tx(75, "2026-07-01", .foodAndDrink),  // next month — excluded
        ]
        let result = CategoryBudgetPlanner.presentation(
            budgets: [.foodAndDrink: 500],
            transactions: transactions,
            asOf: now,
            calendar: calendar
        )
        #expect(result.count == 1)
        #expect(result.items[0].spent == 100)
        #expect(result.items[0].remaining == 400)
        #expect(result.items[0].status == .under)
    }

    @Test("Spend is bucketed by each transaction's category, not its merchant")
    func categoryReassignment() {
        // Same merchant, two categories — each lands in its own bucket.
        let transactions = [
            tx(150, "2026-06-04", .shopping, name: "Target"),
            tx(50, "2026-06-09", .foodAndDrink, name: "Target"),
        ]
        let result = CategoryBudgetPlanner.presentation(
            budgets: [.shopping: 200, .foodAndDrink: 200],
            transactions: transactions,
            asOf: now,
            calendar: calendar
        )
        let byCategory = Dictionary(uniqueKeysWithValues: result.items.map { ($0.category, $0.spent) })
        #expect(byCategory[.shopping] == 150)
        #expect(byCategory[.foodAndDrink] == 50)
    }

    @Test("Refunds net against spend in the same category")
    func refundsNet() {
        let transactions = [
            tx(120, "2026-06-03", .shopping),  // purchase
            tx(-20, "2026-06-08", .shopping),  // refund (money in, same category)
        ]
        let result = CategoryBudgetPlanner.presentation(
            budgets: [.shopping: 200],
            transactions: transactions,
            asOf: now,
            calendar: calendar
        )
        #expect(result.items[0].spent == 100)
    }

    @Test("A net-negative category floors spend at zero")
    func netNegativeFloorsAtZero() {
        let transactions = [
            tx(40, "2026-06-03", .shopping),
            tx(-100, "2026-06-08", .shopping), // large refund > spend
        ]
        let result = CategoryBudgetPlanner.presentation(
            budgets: [.shopping: 200],
            transactions: transactions,
            asOf: now,
            calendar: calendar
        )
        #expect(result.items[0].spent == 0)
        #expect(result.items[0].fractionUsed == 0)
        #expect(result.items[0].status == .under)
    }

    @Test("Transfers and income are excluded from category spend")
    func transfersAndIncomeExcluded() {
        let spend = CategoryBudgetPlanner.netSpendByCategory(
            from: [
                tx(100, "2026-06-05", .foodAndDrink),
                tx(-2000, "2026-06-01", .income),      // paycheck
                tx(500, "2026-06-02", .transferOut),
                tx(-500, "2026-06-02", .transfer),
            ],
            startKey: "2026-06-01",
            endKey: "2026-07-01"
        )
        #expect(spend[.foodAndDrink] == 100)
        #expect(spend[.income] == nil)
        #expect(spend[.transfer] == nil)
        #expect(spend[.transferOut] == nil)
    }

    @Test("Pending transactions count toward spend")
    func pendingCounts() {
        let transactions = [
            tx(50, "2026-06-05", .foodAndDrink, pending: false),
            tx(30, "2026-06-11", .foodAndDrink, pending: true),
        ]
        let result = CategoryBudgetPlanner.presentation(
            budgets: [.foodAndDrink: 200],
            transactions: transactions,
            asOf: now,
            calendar: calendar
        )
        #expect(result.items[0].spent == 80)
    }

    // MARK: - Status bands + ordering

    @Test("Status bands and attention-first ordering")
    func statusBandsAndOrdering() {
        let transactions = [
            tx(150, "2026-06-05", .foodAndDrink),    // over: 150/100
            tx(85, "2026-06-05", .shopping),         // nearing: 85/100
            tx(40, "2026-06-05", .transportation),   // under: 40/100
        ]
        let result = CategoryBudgetPlanner.presentation(
            budgets: [.foodAndDrink: 100, .shopping: 100, .transportation: 100],
            transactions: transactions,
            asOf: now,
            calendar: calendar
        )
        #expect(result.items.map(\.status) == [.over, .nearing, .under])
        #expect(result.items.map(\.category) == [.foodAndDrink, .shopping, .transportation])
        #expect(result.overBudgetCount == 1)
        #expect(result.nearingCount == 1)
        #expect(result.totalLimit == 300)
        #expect(result.totalSpent == 275)
    }

    @Test("Nearing threshold is exactly 80% of the limit")
    func nearingThresholdBoundary() {
        #expect(CategoryBudgetStatus(fractionUsed: 0.79) == .under)
        #expect(CategoryBudgetStatus(fractionUsed: 0.80) == .nearing)
        #expect(CategoryBudgetStatus(fractionUsed: 1.0) == .nearing)
        #expect(CategoryBudgetStatus(fractionUsed: 1.01) == .over)
    }

    @Test("Non-positive limits are dropped; no budgets yields empty")
    func dropsNonPositiveAndEmpty() {
        let transactions = [tx(50, "2026-06-05", .foodAndDrink)]
        let zeroed = CategoryBudgetPlanner.presentation(
            budgets: [.foodAndDrink: 0, .shopping: -10],
            transactions: transactions,
            asOf: now,
            calendar: calendar
        )
        #expect(zeroed.isEmpty)

        let none = CategoryBudgetPlanner.presentation(
            budgets: [:],
            transactions: transactions,
            asOf: now,
            calendar: calendar
        )
        #expect(none.isEmpty)
    }

    // MARK: - Suggestions

    @Test("Suggestions come from trailing complete months, excluding the current month")
    func suggestionsFromTrailingMonths() {
        let transactions = [
            // Trailing months: food $300/mo, shopping $200/mo across Mar/Apr/May.
            tx(300, "2026-03-15", .foodAndDrink),
            tx(300, "2026-04-15", .foodAndDrink),
            tx(300, "2026-05-15", .foodAndDrink),
            tx(200, "2026-03-10", .shopping),
            tx(200, "2026-04-10", .shopping),
            tx(200, "2026-05-10", .shopping),
            // Current (partial) month must NOT seed a suggestion.
            tx(9999, "2026-06-02", .travel),
        ]
        let suggestions = CategoryBudgetPlanner.suggestedBudgets(
            from: transactions,
            asOf: now,
            calendar: calendar
        )
        #expect(suggestions[.foodAndDrink] == 300)
        #expect(suggestions[.shopping] == 200)
        #expect(suggestions[.travel] == nil) // current month excluded
    }

    @Test("Suggestions are capped at the requested top-N highest spenders")
    func suggestionsCappedAtTopN() {
        let transactions = [
            tx(500, "2026-05-01", .foodAndDrink),
            tx(400, "2026-05-01", .shopping),
            tx(300, "2026-05-01", .transportation),
            tx(200, "2026-05-01", .entertainment),
        ]
        let suggestions = CategoryBudgetPlanner.suggestedBudgets(
            from: transactions,
            asOf: now,
            calendar: calendar,
            topCategories: 2,
            trailingMonths: 1
        )
        #expect(suggestions.count == 2)
        #expect(suggestions[.foodAndDrink] != nil)
        #expect(suggestions[.shopping] != nil)
        #expect(suggestions[.transportation] == nil)
    }

    @Test("suggestedPresentation flags items and scores them against the current month")
    func suggestedPresentationFlags() {
        let transactions = [
            tx(300, "2026-05-15", .foodAndDrink), // seeds a ~300 suggestion
            tx(120, "2026-06-05", .foodAndDrink), // current-month spend
        ]
        let result = CategoryBudgetPlanner.suggestedPresentation(
            from: transactions,
            asOf: now,
            calendar: calendar,
            trailingMonths: 1
        )
        #expect(!result.isEmpty)
        let food = result.items.first { $0.category == .foodAndDrink }
        #expect(food?.isSuggested == true)
        #expect(food?.spent == 120)
        #expect(food?.monthlyLimit == 300) // 300 / 1 month → roundedSuggestedLimit(300) = 300
    }

    @Test("No history yields no suggestions")
    func noHistoryNoSuggestions() {
        #expect(CategoryBudgetPlanner.suggestedBudgets(from: [], asOf: now, calendar: calendar).isEmpty)
    }

    // MARK: - Rounding

    @Test("Suggested limits round up to tidy steps")
    func roundingSteps() {
        #expect(CategoryBudgetPlanner.roundedSuggestedLimit(0) == 0)
        #expect(CategoryBudgetPlanner.roundedSuggestedLimit(45) == 50)   // <100 → step 10
        #expect(CategoryBudgetPlanner.roundedSuggestedLimit(95) == 100)  // <100 → step 10
        #expect(CategoryBudgetPlanner.roundedSuggestedLimit(120) == 125) // <500 → step 25
        #expect(CategoryBudgetPlanner.roundedSuggestedLimit(300) == 300) // <500 → step 25
        #expect(CategoryBudgetPlanner.roundedSuggestedLimit(480) == 500) // <500 → step 25
        #expect(CategoryBudgetPlanner.roundedSuggestedLimit(600) == 600) // >=500 → step 50
        #expect(CategoryBudgetPlanner.roundedSuggestedLimit(610) == 650) // >=500 → step 50
    }
}
