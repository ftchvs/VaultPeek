import Foundation
import Testing
@testable import PlaidBarCore

/// Tests for the Epic 5 / AND-583 Budgets status rollup. The summary must:
/// - pick the worst-first overall health band (over > nearing > onTrack > noBudgets),
/// - count over / nearing leaves and budgeted vs. tracked categories,
/// - compute the aggregate remaining only when a budget exists, and
/// - be a pure reduction of a finished dashboard presentation (no `Date()`).
@Suite("Budgets status summary (AND-583)")
struct BudgetsStatusSummaryTests {
    // June 13, 2026 — current month is June (matches the builder fixtures).
    private let now = Formatters.parseTransactionDate("2026-06-13")!
    private let calendar = Calendar(identifier: .gregorian)

    private func tx(
        _ amount: Double,
        _ date: String,
        _ category: SpendingCategory?,
        name: String = "Merchant"
    ) -> TransactionDTO {
        TransactionDTO(
            id: "\(name)-\(date)-\(amount)",
            accountId: "acct",
            amount: amount,
            date: date,
            name: name,
            merchantName: name,
            category: category,
            pending: false,
            pendingTransactionId: nil,
            isLowConfidenceCategory: false
        )
    }

    private func presentation(
        transactions: [TransactionDTO],
        budgets: [SpendingCategory: Double]
    ) -> CategoryDashboardPresentation {
        CategoryDashboardBuilder.build(
            transactions: transactions,
            budgets: budgets,
            asOf: now,
            calendar: calendar
        )
    }

    // MARK: - Health band precedence

    @Test("No budgets → noBudgets health, no remaining")
    func noBudgets() {
        let result = presentation(
            transactions: [tx(100, "2026-06-02", .foodAndDrink)],
            budgets: [:]
        )
        let summary = BudgetsStatusSummary.summarize(result)

        #expect(summary.health == .noBudgets)
        #expect(summary.budgetedCount == 0)
        #expect(summary.trackedCount == 1)
        #expect(summary.remaining == nil)
        #expect(summary.fractionUsed == nil)
        #expect(summary.isAggregateOver == false)
    }

    @Test("All comfortably under a budget → onTrack")
    func onTrack() {
        let result = presentation(
            transactions: [tx(20, "2026-06-02", .foodAndDrink)],
            budgets: [.foodAndDrink: 200]
        )
        let summary = BudgetsStatusSummary.summarize(result)

        #expect(summary.health == .onTrack)
        #expect(summary.overBudgetCount == 0)
        #expect(summary.nearingCount == 0)
        #expect(summary.budgetedCount == 1)
        #expect(summary.remaining == 180)
        #expect(summary.isAggregateOver == false)
    }

    @Test("A nearing leaf (no over) → nearing health")
    func nearing() {
        // 190 of a 200 budget is in the nearing band (>= ~75%, < 100%).
        let result = presentation(
            transactions: [tx(190, "2026-06-02", .foodAndDrink)],
            budgets: [.foodAndDrink: 200]
        )
        let summary = BudgetsStatusSummary.summarize(result)

        #expect(summary.health == .nearing)
        #expect(summary.overBudgetCount == 0)
        #expect(summary.nearingCount == 1)
    }

    @Test("Any over-budget leaf wins precedence → over health")
    func overWinsPrecedence() {
        let result = presentation(
            transactions: [
                tx(300, "2026-06-02", .foodAndDrink),  // over its 200 limit
                tx(190, "2026-06-03", .shopping),      // nearing its 200 limit
            ],
            budgets: [.foodAndDrink: 200, .shopping: 200]
        )
        let summary = BudgetsStatusSummary.summarize(result)

        #expect(summary.health == .over)
        #expect(summary.overBudgetCount == 1)
        #expect(summary.nearingCount == 1)
        #expect(summary.budgetedCount == 2)
    }

    // MARK: - Aggregate remaining

    @Test("Aggregate remaining sums budgeted limits minus spend; over reads negative")
    func aggregateRemaining() {
        let result = presentation(
            transactions: [
                tx(300, "2026-06-02", .foodAndDrink),  // spent 300 of 200
                tx(50, "2026-06-03", .shopping),       // spent 50 of 200
            ],
            budgets: [.foodAndDrink: 200, .shopping: 200]
        )
        let summary = BudgetsStatusSummary.summarize(result)

        // totalLimit 400, totalSpent 350 → +50 remaining overall, not over.
        #expect(summary.totalLimit == 400)
        #expect(summary.totalSpent == 350)
        #expect(summary.remaining == 50)
        #expect(summary.isAggregateOver == false)
    }

    @Test("Empty presentation → noBudgets, zero counts")
    func emptyPresentation() {
        let summary = BudgetsStatusSummary.summarize(.empty)

        #expect(summary.health == .noBudgets)
        #expect(summary.trackedCount == 0)
        #expect(summary.budgetedCount == 0)
        #expect(summary.totalSpent == 0)
        #expect(summary.totalLimit == 0)
        #expect(summary.remaining == nil)
    }

    // MARK: - Health labels carry text + glyph (ACCESSIBILITY.md)

    @Test("Every health band has non-empty text and an SF Symbol")
    func healthLabelsArePopulated() {
        for health in [
            BudgetsStatusSummary.Health.over,
            .nearing,
            .onTrack,
            .noBudgets,
        ] {
            #expect(!health.label.isEmpty)
            #expect(!health.iconName.isEmpty)
        }
    }
}
