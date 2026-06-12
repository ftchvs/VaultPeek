import Foundation
@testable import PlaidBarCore
import Testing

@Suite("AccountDetailInsights Tests")
struct AccountDetailInsightsTests {
    /// Fixed reference date so windowing never depends on the wall clock.
    /// With windowDays = 30 the current window is 2026-05-13...2026-06-11 and the
    /// previous window is 2026-04-13...2026-05-12.
    private let now = Formatters.parseTransactionDate("2026-06-11")!

    private func expense(
        _ id: String,
        amount: Double,
        date: String,
        category: SpendingCategory? = nil,
        pending: Bool = false
    ) -> TransactionDTO {
        TransactionDTO(
            id: id,
            accountId: "checking",
            amount: amount,
            date: date,
            name: id,
            category: category,
            pending: pending
        )
    }

    private func income(
        _ id: String,
        amount: Double,
        date: String,
        category: SpendingCategory? = .income
    ) -> TransactionDTO {
        TransactionDTO(
            id: id,
            accountId: "checking",
            amount: -amount,
            date: date,
            name: id,
            category: category
        )
    }

    // MARK: - Windowing

    @Test("Transaction exactly windowDays - 1 days old is in the current window")
    func windowBoundaryInclusion() {
        let insights = AccountDetailInsights.compute(
            transactions: [
                expense("boundary", amount: 40, date: "2026-05-13"), // 29 days old: current
                expense("previous", amount: 25, date: "2026-05-12"), // 30 days old: previous
            ],
            now: now
        )

        #expect(insights.windowDays == 30)
        #expect(insights.spendTotal == 40)
        #expect(insights.previousSpendTotal == 25)
    }

    @Test("Previous window totals cover exactly the windowDays before the current window")
    func previousWindowTotals() {
        let insights = AccountDetailInsights.compute(
            transactions: [
                expense("current", amount: 10, date: "2026-06-01"),
                expense("prev-newest", amount: 30, date: "2026-05-12"),
                expense("prev-oldest", amount: 20, date: "2026-04-13"),
                expense("too-old", amount: 99, date: "2026-04-12"),
                income("prev-income", amount: 500, date: "2026-05-01"),
                income("current-income", amount: 700, date: "2026-06-10"),
            ],
            now: now
        )

        #expect(insights.spendTotal == 10)
        #expect(insights.incomeTotal == 700)
        #expect(insights.previousSpendTotal == 50)
        #expect(insights.previousIncomeTotal == 500)
        #expect(insights.spendDelta == -40)
        #expect(insights.incomeDelta == 200)
    }

    @Test("Reference date falls back to the latest parseable transaction date")
    func referenceDateFallsBackToLatestTransaction() {
        let insights = AccountDetailInsights.compute(
            transactions: [
                expense("latest", amount: 15, date: "2026-06-11"),
                expense("boundary", amount: 35, date: "2026-05-13"),
                expense("unparseable", amount: 99, date: "not-a-date"),
            ]
        )

        #expect(insights.spendTotal == 50)
        #expect(insights.previousSpendTotal == 0)
    }

    // MARK: - Totals and categories

    @Test("Transfers are excluded from totals and from top categories")
    func transferExclusion() {
        let insights = AccountDetailInsights.compute(
            transactions: [
                expense("groceries", amount: 60, date: "2026-06-10", category: .foodAndDrink),
                expense("transfer-out", amount: 1000, date: "2026-06-10", category: .transferOut),
                income("transfer-in", amount: 1000, date: "2026-06-09", category: .transfer),
                expense("prev-transfer", amount: 800, date: "2026-05-01", category: .transferOut),
            ],
            now: now
        )

        #expect(insights.spendTotal == 60)
        #expect(insights.incomeTotal == 0)
        #expect(insights.previousSpendTotal == 0)
        #expect(insights.topCategories.map(\.category) == [.foodAndDrink])
    }

    @Test("Income is excluded from top categories but counted in incomeTotal")
    func incomeExcludedFromCategories() {
        let insights = AccountDetailInsights.compute(
            transactions: [
                expense("coffee", amount: 8, date: "2026-06-10", category: .foodAndDrink),
                income("paycheck", amount: 2400, date: "2026-06-09"),
                income("refund", amount: 30, date: "2026-06-08", category: .shopping),
            ],
            now: now
        )

        #expect(insights.incomeTotal == 2430)
        #expect(insights.topCategories.map(\.category) == [.foodAndDrink])
    }

    @Test("Category shares are fractions of the full window spend, including pending")
    func shareComputation() {
        let insights = AccountDetailInsights.compute(
            transactions: [
                expense("rent", amount: 150, date: "2026-06-01", category: .billsAndUtilities),
                expense("dinner", amount: 30, date: "2026-06-05", category: .foodAndDrink),
                expense("pending-lunch", amount: 20, date: "2026-06-10", category: .foodAndDrink, pending: true),
            ],
            now: now
        )

        #expect(insights.spendTotal == 200)
        #expect(insights.topCategories.count == 2)
        #expect(insights.topCategories[0].category == .billsAndUtilities)
        #expect(insights.topCategories[0].total == 150)
        #expect(insights.topCategories[0].share == 0.75)
        #expect(insights.topCategories[0].transactionCount == 1)
        #expect(insights.topCategories[1].category == .foodAndDrink)
        #expect(insights.topCategories[1].total == 50)
        #expect(insights.topCategories[1].share == 0.25)
        #expect(insights.topCategories[1].transactionCount == 2)
    }

    @Test("Capped categories keep shares relative to the full window spend")
    func sharesRemainFullWindowWhenCapped() {
        let insights = AccountDetailInsights.compute(
            transactions: [
                expense("big", amount: 75, date: "2026-06-01", category: .travel),
                expense("small", amount: 25, date: "2026-06-02", category: .foodAndDrink),
            ],
            maxCategories: 1,
            now: now
        )

        #expect(insights.topCategories.count == 1)
        #expect(insights.topCategories[0].category == .travel)
        #expect(insights.topCategories[0].share == 0.75)
    }

    @Test("Category cap applies after sorting by total descending, displayName ascending on ties")
    func categoryCapAndDeterministicOrdering() {
        let insights = AccountDetailInsights.compute(
            transactions: [
                expense("travel", amount: 50, date: "2026-06-01", category: .travel),
                expense("entertainment", amount: 50, date: "2026-06-02", category: .entertainment),
                expense("food", amount: 50, date: "2026-06-03", category: .foodAndDrink),
                expense("biggest", amount: 90, date: "2026-06-04", category: .shopping),
            ],
            maxCategories: 3,
            now: now
        )

        // Ties at 50 break on displayName: Entertainment < Food & Drink < Travel.
        #expect(insights.topCategories.map(\.category) == [.shopping, .entertainment, .foodAndDrink])
    }

    @Test("Uncategorized spending buckets into .other")
    func uncategorizedBucketsIntoOther() {
        let insights = AccountDetailInsights.compute(
            transactions: [
                expense("mystery-1", amount: 12, date: "2026-06-01"),
                expense("mystery-2", amount: 18, date: "2026-06-02"),
            ],
            now: now
        )

        #expect(insights.topCategories.map(\.category) == [.other])
        #expect(insights.topCategories[0].total == 30)
        #expect(insights.topCategories[0].transactionCount == 2)
    }

    // MARK: - Review items

    @Test("Pending items lead review, sorted date desc then amount desc then id asc")
    func reviewOrderingPendingBeforeLarge() {
        let insights = AccountDetailInsights.compute(
            transactions: [
                expense("large-posted", amount: 900, date: "2026-06-10"),
                expense("pending-old", amount: 5, date: "2026-06-01", pending: true),
                expense("pending-new", amount: 12, date: "2026-06-09", pending: true),
                expense("pending-new-bigger", amount: 40, date: "2026-06-09", pending: true),
                expense("small-posted", amount: 20, date: "2026-06-10"),
            ],
            now: now
        )

        #expect(insights.reviewItems.map(\.id) == [
            "pending-new-bigger", "pending-new", "pending-old", "large-posted",
        ])
        #expect(insights.reviewItems.map(\.reason) == [
            .pending, .pending, .pending, .largeAmount,
        ])
    }

    @Test("Review items tie-break equal date and amount by id ascending")
    func reviewTieBreaksById() {
        let insights = AccountDetailInsights.compute(
            transactions: [
                expense("b-twin", amount: 600, date: "2026-06-10"),
                expense("a-twin", amount: 600, date: "2026-06-10"),
            ],
            now: now
        )

        #expect(insights.reviewItems.map(\.id) == ["a-twin", "b-twin"])
    }

    @Test("Large amount boundary: equal to threshold included, below excluded")
    func largeThresholdBoundary() {
        let insights = AccountDetailInsights.compute(
            transactions: [
                expense("at-threshold", amount: 500, date: "2026-06-10"),
                expense("below-threshold", amount: 499.99, date: "2026-06-10"),
                income("large-income", amount: 5000, date: "2026-06-09"),
            ],
            now: now
        )

        #expect(insights.reviewItems.map(\.id) == ["at-threshold"])
        #expect(insights.reviewItems[0].reason == .largeAmount)
    }

    @Test("A pending transaction over the threshold appears once, as pending")
    func dedupPendingAndLarge() {
        let insights = AccountDetailInsights.compute(
            transactions: [
                expense("pending-large", amount: 750, date: "2026-06-10", pending: true),
                expense("posted-large", amount: 600, date: "2026-06-09"),
            ],
            now: now
        )

        #expect(insights.reviewItems.map(\.id) == ["pending-large", "posted-large"])
        #expect(insights.reviewItems.map(\.reason) == [.pending, .largeAmount])
    }

    @Test("Review list caps at maxReviewItems with pending taking priority")
    func maxReviewItemsCap() {
        let insights = AccountDetailInsights.compute(
            transactions: [
                expense("pending-1", amount: 10, date: "2026-06-10", pending: true),
                expense("pending-2", amount: 11, date: "2026-06-09", pending: true),
                expense("large-1", amount: 700, date: "2026-06-08"),
                expense("large-2", amount: 800, date: "2026-06-07"),
            ],
            maxReviewItems: 3,
            now: now
        )

        #expect(insights.reviewItems.count == 3)
        #expect(insights.reviewItems.map(\.id) == ["pending-1", "pending-2", "large-1"])
    }

    @Test("Review items only consider the current window")
    func reviewItemsIgnoreOlderWindows() {
        let insights = AccountDetailInsights.compute(
            transactions: [
                expense("old-pending", amount: 30, date: "2026-05-12", pending: true),
                expense("old-large", amount: 900, date: "2026-04-20"),
                expense("current-large", amount: 650, date: "2026-06-05"),
            ],
            now: now
        )

        #expect(insights.reviewItems.map(\.id) == ["current-large"])
    }

    // MARK: - Edge cases

    @Test("Empty input produces zeroed totals and empty collections")
    func emptyInput() {
        let insights = AccountDetailInsights.compute(transactions: [], now: now)

        #expect(insights.windowDays == 30)
        #expect(insights.spendTotal == 0)
        #expect(insights.incomeTotal == 0)
        #expect(insights.previousSpendTotal == 0)
        #expect(insights.previousIncomeTotal == 0)
        #expect(insights.spendDelta == 0)
        #expect(insights.incomeDelta == 0)
        #expect(insights.topCategories.isEmpty)
        #expect(insights.reviewItems.isEmpty)
    }

    @Test("Zero spend yields zero shares instead of dividing by zero")
    func zeroSpendShares() {
        let insights = AccountDetailInsights.compute(
            transactions: [
                income("paycheck", amount: 2000, date: "2026-06-10"),
            ],
            now: now
        )

        #expect(insights.spendTotal == 0)
        #expect(insights.topCategories.isEmpty)
    }

    @Test("maxCategories of zero returns an empty slice list while totals remain")
    func maxCategoriesZero() {
        let insights = AccountDetailInsights.compute(
            transactions: [
                expense("groceries", amount: 50, date: "2026-06-01", category: .foodAndDrink),
            ],
            maxCategories: 0,
            now: now
        )

        #expect(insights.spendTotal == 50)
        #expect(insights.topCategories.isEmpty)
    }

    @Test("maxReviewItems of zero returns an empty review list")
    func maxReviewItemsZero() {
        let insights = AccountDetailInsights.compute(
            transactions: [
                expense("large", amount: 900, date: "2026-06-02"),
                expense("pending", amount: 20, date: "2026-06-03", pending: true),
            ],
            maxReviewItems: 0,
            now: now
        )

        #expect(insights.reviewItems.isEmpty)
    }
}
