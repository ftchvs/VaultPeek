import Foundation
import Testing
@testable import PlaidBarCore

/// Pins the exact hero-tile detail copy derived by ``BudgetsStatusSummary/Summary``
/// (extracted from `BudgetsDestinationView`'s inline `budgetedDetail` /
/// `spentDetail` / `remainingDetail` helpers — AND-583 window-first Budgets).
///
/// These are golden-string tests: the strings are user-visible hero copy with
/// singular/plural agreement, so every branch is pinned literally to guard the
/// grammar against regression.
@Suite("Budgets status summary detail copy")
struct BudgetsStatusSummaryDetailTests {
    /// Build a `Summary` with overridable fields; defaults describe an empty,
    /// budget-free month so each test only sets the fields its branch depends on.
    private func summary(
        health: BudgetsStatusSummary.Health = .noBudgets,
        overBudgetCount: Int = 0,
        nearingCount: Int = 0,
        budgetedCount: Int = 0,
        trackedCount: Int = 0,
        totalSpent: Double = 0,
        budgetedSpent: Double? = nil,
        totalLimit: Double = 0
    ) -> BudgetsStatusSummary.Summary {
        BudgetsStatusSummary.Summary(
            health: health,
            overBudgetCount: overBudgetCount,
            nearingCount: nearingCount,
            budgetedCount: budgetedCount,
            trackedCount: trackedCount,
            totalSpent: totalSpent,
            // Default budgeted-only spend to the all-leaves spend so existing
            // detail-copy cases (which assume all tracked spend is budgeted) are
            // unchanged; the regression test below sets it explicitly.
            budgetedSpent: budgetedSpent ?? totalSpent,
            totalLimit: totalLimit
        )
    }

    // MARK: - budgetedDetail

    @Test("budgetedDetail: no budgets yet")
    func budgetedDetailNoBudgets() {
        #expect(summary(budgetedCount: 0, trackedCount: 4).budgetedDetail == "No category budgets yet")
    }

    @Test("budgetedDetail: across N of M categories")
    func budgetedDetailCounts() {
        #expect(summary(budgetedCount: 3, trackedCount: 7).budgetedDetail == "Across 3 of 7 categories")
        // budgetedCount == 1 is not specially pluralized here — pin the literal.
        #expect(summary(budgetedCount: 1, trackedCount: 1).budgetedDetail == "Across 1 of 1 categories")
    }

    // MARK: - spentDetail

    @Test("spentDetail: over-budget wins, singular vs plural")
    func spentDetailOver() {
        #expect(summary(overBudgetCount: 1, nearingCount: 2).spentDetail == "1 category over its limit")
        #expect(summary(overBudgetCount: 3, nearingCount: 2).spentDetail == "3 categories over their limit")
    }

    @Test("spentDetail: nearing when none over, singular vs plural")
    func spentDetailNearing() {
        #expect(summary(overBudgetCount: 0, nearingCount: 1).spentDetail == "1 category nearing its limit")
        #expect(summary(overBudgetCount: 0, nearingCount: 4).spentDetail == "4 categories nearing a limit")
    }

    @Test("spentDetail: all clear")
    func spentDetailAllClear() {
        #expect(summary(overBudgetCount: 0, nearingCount: 0).spentDetail == "This month, all categories")
    }

    // MARK: - remainingDetail

    @Test("remainingDetail: aggregate over wins regardless of per-category counts")
    func remainingDetailAggregateOver() {
        // remaining = 100 - 150 = -50 < 0 → isAggregateOver.
        let over = summary(overBudgetCount: 2, budgetedCount: 1, totalSpent: 150, totalLimit: 100)
        #expect(over.isAggregateOver)
        #expect(over.remainingDetail == "Spending exceeds your budgeted total")
    }

    @Test("remainingDetail: room overall but some categories over, singular vs plural")
    func remainingDetailRoomButOver() {
        // remaining = 200 - 50 = +150 → not aggregate-over.
        let one = summary(overBudgetCount: 1, budgetedCount: 2, totalSpent: 50, totalLimit: 200)
        #expect(!one.isAggregateOver)
        #expect(one.remainingDetail == "Still room overall, but 1 category is over")

        let many = summary(overBudgetCount: 3, budgetedCount: 4, totalSpent: 50, totalLimit: 200)
        #expect(many.remainingDetail == "Still room overall, but 3 categories are over")
    }

    @Test("remainingDetail: clean remainder")
    func remainingDetailClean() {
        let clean = summary(overBudgetCount: 0, budgetedCount: 2, totalSpent: 50, totalLimit: 200)
        #expect(!clean.isAggregateOver)
        #expect(clean.remainingDetail == "Remaining across your budgeted total")
    }

    // MARK: - summarize(): budgeted-only over/left/used math (bug-hunt R3)

    private func tx(
        _ amount: Double,
        _ date: String,
        _ category: SpendingCategory,
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

    /// Regression: unbudgeted spend must NOT be subtracted from the budgeted limit.
    ///
    /// Before the fix, `remaining`/`fractionUsed` compared all-leaves `totalSpent`
    /// against the budgeted-only `totalLimit`, so $300 of unbudgeted shopping ate
    /// into the $200 food budget — a false "Over budget" with `fractionUsed == 1.0`.
    /// Now the aggregate math uses `budgetedSpent`, so the budgeted food category's
    /// $50/$200 reads +$150 left / 0.25 used regardless of the unbudgeted spend.
    @Test("summarize: unbudgeted spend never eats the budgeted left (bug-hunt R3)")
    func unbudgetedSpendDoesNotConsumeBudgetedLeft() {
        let now = Formatters.parseTransactionDate("2026-06-13")!
        let calendar = Calendar(identifier: .gregorian)
        let presentation = CategoryDashboardBuilder.build(
            transactions: [
                tx(50, "2026-06-02", .foodAndDrink),  // budgeted: 50 of 200
                tx(300, "2026-06-03", .shopping),     // UNBUDGETED: must not touch the food budget
            ],
            budgets: [.foodAndDrink: 200],  // only food is budgeted
            asOf: now,
            calendar: calendar
        )

        // Sanity: the presentation itself separates the two spend figures.
        #expect(presentation.totalLimit == 200)
        #expect(presentation.totalSpent == 350)    // all leaves (food 50 + shopping 300)
        #expect(presentation.budgetedSpent == 50)  // budgeted leaves only (food)

        let result = BudgetsStatusSummary.summarize(presentation)

        #expect(result.budgetedCount == 1)
        #expect(result.totalSpent == 350)   // "Spent" tile keeps all-leaves spend
        #expect(result.budgetedSpent == 50) // over/left/used math uses budgeted-only
        #expect(result.totalLimit == 200)
        // The bug produced remaining = 200 - 350 = -150 (false over) and 1.0 used.
        #expect(result.remaining == 150)
        #expect(result.isAggregateOver == false)
        #expect(result.fractionUsed == 0.25)
        #expect(result.health == .onTrack)
    }
}
