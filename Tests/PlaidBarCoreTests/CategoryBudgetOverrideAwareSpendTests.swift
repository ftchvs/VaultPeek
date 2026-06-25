import Foundation
import Testing
@testable import PlaidBarCore

/// Override-aware spend math (AND-546): the v2-foundation fix for the
/// override-unaware default in `CategoryBudgetPlanner.netSpendByCategory`.
///
/// The new `overrideAwareSpend` entrypoint *always* resolves per-transaction user
/// overrides, recategorization rules, and budget-exclusions before bucketing,
/// while the v1 default path is left identical so a not-opted-in v1 user is
/// unaffected.
@Suite("Override-aware category spend (AND-546)")
struct CategoryBudgetOverrideAwareSpendTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func tx(
        _ id: String,
        _ amount: Double,
        _ date: String,
        _ category: SpendingCategory?,
        name: String = "Merchant",
        pendingTransactionId: String? = nil
    ) -> TransactionDTO {
        TransactionDTO(
            id: id,
            accountId: "acct",
            amount: amount,
            date: date,
            name: name,
            category: category,
            pending: false,
            pendingTransactionId: pendingTransactionId
        )
    }

    // MARK: - The override-aware fix

    @Test("A user category override moves spend to the chosen category")
    func userOverrideMovesSpend() {
        // Plaid says SHOPPING; the user recategorized it to FOOD_AND_DRINK.
        let transactions = [tx("t1", 150, "2026-06-04", .shopping, name: "Target")]
        let metadata = [TransactionReviewMetadata(id: "t1", userCategory: .foodAndDrink)]

        let spend = CategoryBudgetPlanner.overrideAwareSpend(
            transactions: transactions,
            month: "2026-06",
            metadata: metadata,
            calendar: calendar
        )

        // Spend lands on the override, NOT the raw Plaid bucket.
        #expect(spend[.foodAndDrink] == 150)
        #expect(spend[.shopping] == nil)
    }

    @Test("A recategorization rule moves spend even without per-transaction metadata")
    func ruleMovesSpend() {
        let transactions = [tx("t1", 80, "2026-06-10", .shopping, name: "Costco Wholesale")]
        let rules = [
            TransactionRule(matchMerchantContains: "costco", category: .foodAndDrink),
        ]

        let spend = CategoryBudgetPlanner.overrideAwareSpend(
            transactions: transactions,
            month: "2026-06",
            rules: rules,
            calendar: calendar
        )

        #expect(spend[.foodAndDrink] == 80)
        #expect(spend[.shopping] == nil)
    }

    @Test("A user-excluded transaction drops out of spend entirely")
    func excludedTransactionDropsOut() {
        let transactions = [
            tx("t1", 100, "2026-06-04", .shopping),
            tx("t2", 200, "2026-06-05", .shopping),
        ]
        let metadata = [TransactionReviewMetadata(id: "t2", excludedFromBudgets: true)]

        let spend = CategoryBudgetPlanner.overrideAwareSpend(
            transactions: transactions,
            month: "2026-06",
            metadata: metadata,
            calendar: calendar
        )

        // Only the non-excluded row counts.
        #expect(spend[.shopping] == 100)
    }

    @Test("Pending-phase review metadata carries into the posted charge")
    func pendingMetadataCarriesForward() {
        // The posted charge links back to the pending id; the override was saved
        // while pending and must still move the spend after it posts.
        let transactions = [
            tx("posted-1", 60, "2026-06-08", .shopping, pendingTransactionId: "pending-1"),
        ]
        let metadata = [TransactionReviewMetadata(id: "pending-1", userCategory: .entertainment)]

        let spend = CategoryBudgetPlanner.overrideAwareSpend(
            transactions: transactions,
            month: "2026-06",
            metadata: metadata,
            calendar: calendar
        )

        #expect(spend[.entertainment] == 60)
        #expect(spend[.shopping] == nil)
    }

    @Test("A confident Plaid row with no override keeps its raw bucket")
    func confidentPlaidFallsThrough() {
        let transactions = [tx("t1", 45, "2026-06-03", .transportation)]
        let spend = CategoryBudgetPlanner.overrideAwareSpend(
            transactions: transactions,
            month: "2026-06",
            metadata: [],
            rules: [],
            calendar: calendar
        )
        #expect(spend[.transportation] == 45)
    }

    @Test("Income and transfers never count as category spend")
    func incomeAndTransfersExcluded() {
        let transactions = [
            tx("inc", -2000, "2026-06-01", .income, name: "Payroll"),
            tx("xfer", -500, "2026-06-02", .transfer, name: "Move"),
            tx("buy", 75, "2026-06-03", .shopping),
        ]
        let spend = CategoryBudgetPlanner.overrideAwareSpend(
            transactions: transactions,
            month: "2026-06",
            metadata: [],
            calendar: calendar
        )
        #expect(spend[.income] == nil)
        #expect(spend[.transfer] == nil)
        #expect(spend[.shopping] == 75)
    }

    @Test("Refunds net against spend within the month")
    func refundsNet() {
        let transactions = [
            tx("buy", 200, "2026-06-04", .shopping),
            tx("refund", -50, "2026-06-09", .shopping),
        ]
        let spend = CategoryBudgetPlanner.overrideAwareSpend(
            transactions: transactions,
            month: "2026-06",
            metadata: [],
            calendar: calendar
        )
        #expect(spend[.shopping] == 150)
    }

    @Test("Out-of-month transactions are excluded")
    func monthBounds() {
        let transactions = [
            tx("prev", 100, "2026-05-31", .shopping),
            tx("cur", 40, "2026-06-15", .shopping),
            tx("next", 70, "2026-07-01", .shopping),
        ]
        let spend = CategoryBudgetPlanner.overrideAwareSpend(
            transactions: transactions,
            month: "2026-06",
            metadata: [],
            calendar: calendar
        )
        #expect(spend[.shopping] == 40)
    }

    @Test("A malformed month key yields empty spend (no crash)")
    func malformedMonthKey() {
        let transactions = [tx("t1", 100, "2026-06-04", .shopping)]
        for bad in ["", "2026", "2026-13", "2026-6", "20260-06", "abcd-ef"] {
            let spend = CategoryBudgetPlanner.overrideAwareSpend(
                transactions: transactions,
                month: bad,
                calendar: calendar
            )
            #expect(spend.isEmpty, "month key \(bad) should be rejected")
        }
    }

    // MARK: - v1 NOT-opted-in: identical behavior

    @Test("v1 default scoring is unaffected — the legacy raw-Plaid path ignores overrides")
    func v1DefaultPathUnaffected() {
        // A v1, not-opted-in user calls `presentation` WITHOUT metadata/rules. The
        // override below must be ignored — spend stays on the raw Plaid bucket,
        // exactly as v1 always behaved. This is the v1-safety guarantee: opting into
        // override-aware spend is explicit (overrideAwareSpend / passing metadata),
        // never imposed on the legacy default.
        let now = Formatters.parseTransactionDate("2026-06-13")!
        let transactions = [tx("t1", 150, "2026-06-04", .shopping, name: "Target")]

        // v1 path: no metadata, no rules.
        let v1 = CategoryBudgetPlanner.presentation(
            budgets: [.shopping: 500, .foodAndDrink: 500],
            transactions: transactions,
            asOf: now,
            calendar: calendar
        )
        let v1Shopping = v1.items.first { $0.category == .shopping }
        let v1Food = v1.items.first { $0.category == .foodAndDrink }
        #expect(v1Shopping?.spent == 150) // raw Plaid bucket
        #expect(v1Food?.spent == 0)       // override is NOT applied on the legacy path

        // Same inputs through the override-aware surface DO move the spend — proving
        // the two paths diverge only when the user opts in.
        let resolved = CategoryBudgetPlanner.overrideAwareSpend(
            transactions: transactions,
            month: "2026-06",
            metadata: [TransactionReviewMetadata(id: "t1", userCategory: .foodAndDrink)],
            calendar: calendar
        )
        #expect(resolved[.foodAndDrink] == 150)
        #expect(resolved[.shopping] == nil)
    }
}
