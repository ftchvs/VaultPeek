import Foundation
@testable import PlaidBarCore
import Testing

/// Tests for the override-aware additions to `SpendingSummary` (AND-527): the
/// summary surface that aggregates spend by category must resolve the *effective*
/// category (user override → rule → raw Plaid → `.other`) so a recategorization in
/// the Review Inbox moves the summarized totals, matching what the user sees in the
/// dashboard. Passing no metadata/rules (the default) must reproduce the legacy
/// raw-`transaction.category` behavior so existing callers/tests are unchanged.
///
/// All inputs are synthetic; no real Plaid data.
@Suite("Spending Summary Override Tests")
struct SpendingSummaryOverrideTests {
    private func tx(
        id: String,
        amount: Double = 40,
        date: String = "2026-06-10",
        name: String = "MERCHANT",
        category: SpendingCategory?,
        merchantName: String? = "Merchant",
        pendingTransactionId: String? = nil,
        lowConfidence: Bool = false
    ) -> TransactionDTO {
        TransactionDTO(
            id: id,
            accountId: "acc",
            amount: amount,
            date: date,
            name: name,
            merchantName: merchantName,
            category: category,
            pending: false,
            pendingTransactionId: pendingTransactionId,
            isLowConfidenceCategory: lowConfidence
        )
    }

    // MARK: - Legacy behavior preserved (default nil params)

    @Test("Default (no metadata/rules) buckets by raw Plaid category, unchanged")
    func legacyBucketsByRawCategory() {
        let transactions = [
            tx(id: "a", amount: 30, category: .shopping),
            tx(id: "b", amount: 20, category: .foodAndDrink),
        ]

        let legacy = SpendingSummary.spendingByCategory(from: transactions)
        let explicitNil = SpendingSummary.spendingByCategory(
            from: transactions,
            metadata: nil,
            rules: nil
        )

        let legacyDict = Dictionary(uniqueKeysWithValues: legacy)
        let explicitDict = Dictionary(uniqueKeysWithValues: explicitNil)
        #expect(legacyDict == explicitDict)
        #expect(legacyDict[.shopping] == 30)
        #expect(legacyDict[.foodAndDrink] == 20)
    }

    // MARK: - Override moves the summarized category

    @Test("A user category override moves spend to the overridden category")
    func userOverrideMovesSpend() {
        let transactions = [tx(id: "a", amount: 40, category: .shopping)]
        let metadata = [TransactionReviewMetadata(id: "a", userCategory: .foodAndDrink)]

        let resolved = SpendingSummary.spendingByCategory(
            from: transactions,
            metadata: metadata
        )
        let dict = Dictionary(uniqueKeysWithValues: resolved)

        // Raw Plaid said .shopping; the override re-attributes the $40 to food.
        #expect(dict[.foodAndDrink] == 40)
        #expect(dict[.shopping] == nil)
    }

    @Test("A matching rule re-categorizes summarized spend")
    func ruleMovesSpend() {
        let transactions = [tx(id: "a", amount: 25, name: "BLUE BOTTLE", category: .shopping, merchantName: "Blue Bottle")]
        let rules = [TransactionRule(matchMerchantContains: "Blue Bottle", category: .foodAndDrink)]

        let resolved = SpendingSummary.spendingByCategory(
            from: transactions,
            rules: rules
        )
        let dict = Dictionary(uniqueKeysWithValues: resolved)

        #expect(dict[.foodAndDrink] == 25)
        #expect(dict[.shopping] == nil)
    }

    // MARK: - Exclusions / transfers drop out of the summary

    @Test("An excluded-from-budgets override drops the row from the summary")
    func excludedRowDropsOut() {
        let transactions = [
            tx(id: "keep", amount: 15, category: .foodAndDrink),
            tx(id: "drop", amount: 99, category: .shopping),
        ]
        let metadata = [
            TransactionReviewMetadata(id: "drop", excludedFromBudgets: true),
        ]

        let resolved = SpendingSummary.spendingByCategory(
            from: transactions,
            metadata: metadata
        )
        let dict = Dictionary(uniqueKeysWithValues: resolved)

        #expect(dict[.foodAndDrink] == 15)
        #expect(dict[.shopping] == nil)
    }

    @Test("A transfer override drops the row even with a spend category")
    func transferOverrideDropsOut() {
        let transactions = [tx(id: "x", amount: 200, category: .shopping)]
        let metadata = [TransactionReviewMetadata(id: "x", isTransferOverride: true)]

        let resolved = SpendingSummary.spendingByCategory(
            from: transactions,
            metadata: metadata
        )

        #expect(resolved.isEmpty)
    }

    // MARK: - Pending → posted carry-forward

    @Test("Review metadata under a pending id carries into the posted charge")
    func pendingMetadataCarriesForward() {
        // A charge first seen as pending under id "pending-1"; the user recategorized
        // it. Plaid re-posts it as id "posted-1" linking back via pendingTransactionId.
        let transactions = [
            tx(id: "posted-1", amount: 50, category: .shopping, pendingTransactionId: "pending-1"),
        ]
        let metadata = [TransactionReviewMetadata(id: "pending-1", userCategory: .foodAndDrink)]

        let resolved = SpendingSummary.spendingByCategory(
            from: transactions,
            metadata: metadata
        )
        let dict = Dictionary(uniqueKeysWithValues: resolved)

        #expect(dict[.foodAndDrink] == 50)
        #expect(dict[.shopping] == nil)
    }

    // MARK: - periodSummary honors overrides

    @Test("periodSummary categories reflect overrides")
    func periodSummaryHonorsOverrides() {
        let transactions = [
            tx(id: "cur", amount: 40, date: "2026-06-10", category: .shopping),
        ]
        let metadata = [TransactionReviewMetadata(id: "cur", userCategory: .foodAndDrink)]

        let summary = SpendingSummary.periodSummary(
            from: transactions,
            currentStart: "2026-06-01",
            previousStart: "2026-05-01",
            metadata: metadata
        )
        let dict = Dictionary(uniqueKeysWithValues: summary.categories)

        #expect(dict[.foodAndDrink] == 40)
        #expect(dict[.shopping] == nil)
        #expect(summary.currentTotal == 40)
    }
}
