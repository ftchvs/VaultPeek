import Foundation
@testable import PlaidBarCore
import Testing

/// Equivalence tests for the single override-aware spend kernel (AND-664 #1).
///
/// `SpendingSummary.spendingByCategory` and `CategoryBudgetPlanner.netSpendByCategory`
/// now route through one `OverrideAwareSpendKernel.bucketedSpend`, parameterized only
/// by amount selector, optional date range, and the post-resolution exclusion flag.
/// These tests pin BOTH parameterizations against the documented behavior so the
/// extraction is provably behavior-preserving — and lock the two ways the call sites
/// must keep diverging (the `abs` magnitude vs signed-netting amount, and whether an
/// override **to** an excluded bucket is dropped).
///
/// All inputs are synthetic; no real Plaid data.
@Suite("Override-aware spend kernel equivalence (AND-664)")
struct OverrideAwareSpendKernelTests {
    private func tx(
        id: String,
        amount: Double,
        date: String = "2026-06-10",
        name: String = "MERCHANT",
        category: SpendingCategory?,
        merchantName: String? = "Merchant",
        pendingTransactionId: String? = nil
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
            pendingTransactionId: pendingTransactionId
        )
    }

    // Re-derives `SpendingSummary.spendingByCategory`'s parameterization directly so
    // the test pins the kernel knobs the summary surface relies on.
    private func summaryKernel(
        _ transactions: [TransactionDTO],
        metadata: [TransactionReviewMetadata]? = nil,
        rules: [TransactionRule]? = nil,
        splits: [TransactionSplit] = []
    ) -> [SpendingCategory: Double] {
        OverrideAwareSpendKernel.bucketedSpend(
            from: SpendingSummary.expenseTransactions(from: transactions),
            metadata: metadata,
            rules: rules,
            splitIndex: TransactionSplitResolver.index(splits),
            dateRange: nil,
            amount: abs,
            excludePostResolution: false
        )
    }

    // Re-derives `CategoryBudgetPlanner.netSpendByCategory`'s parameterization.
    private func budgetKernel(
        _ transactions: [TransactionDTO],
        start: String = "2026-06-01",
        end: String = "2026-07-01",
        metadata: [TransactionReviewMetadata]? = nil,
        rules: [TransactionRule]? = nil,
        splits: [TransactionSplit] = []
    ) -> [SpendingCategory: Double] {
        OverrideAwareSpendKernel.bucketedSpend(
            from: transactions,
            metadata: metadata,
            rules: rules,
            splitIndex: TransactionSplitResolver.index(splits),
            dateRange: (start: start, end: end),
            amount: { $0 },
            excludePostResolution: true
        )
    }

    // MARK: - The kernel IS what each public call site produces

    @Test("Kernel reproduces SpendingSummary.spendingByCategory exactly (legacy + resolved)")
    func kernelMatchesSummary() {
        let transactions = [
            tx(id: "shop", amount: 30, category: .shopping),
            tx(id: "food", amount: 20, category: .foodAndDrink),
            tx(id: "refund", amount: -12, category: .shopping),     // income-side → pre-filtered
            tx(id: "salary", amount: -2000, category: .income),     // pre-filtered
            tx(id: "xfer", amount: 80, category: .transfer),        // pre-filtered
        ]
        let metadata = [TransactionReviewMetadata(id: "shop", userCategory: .travel)]

        // Legacy (no review state) and resolved (override) parameterizations both
        // equal the public function's output.
        let legacyPublic = Dictionary(uniqueKeysWithValues: SpendingSummary.spendingByCategory(from: transactions))
        #expect(summaryKernel(transactions) == legacyPublic)

        let resolvedPublic = Dictionary(
            uniqueKeysWithValues: SpendingSummary.spendingByCategory(from: transactions, metadata: metadata)
        )
        #expect(summaryKernel(transactions, metadata: metadata) == resolvedPublic)
    }

    @Test("Kernel reproduces CategoryBudgetPlanner.netSpendByCategory exactly (legacy + resolved)")
    func kernelMatchesBudget() {
        let transactions = [
            tx(id: "shop", amount: 30, category: .shopping),
            tx(id: "food", amount: 20, category: .foodAndDrink),
            tx(id: "refund", amount: -12, category: .shopping),     // nets via signed amount
            tx(id: "salary", amount: -2000, category: .income),     // excluded
            tx(id: "out-of-window", amount: 99, date: "2026-05-30", category: .shopping),
        ]
        let metadata = [TransactionReviewMetadata(id: "shop", userCategory: .travel)]

        let legacyPublic = CategoryBudgetPlanner.netSpendByCategory(
            from: transactions, startKey: "2026-06-01", endKey: "2026-07-01"
        )
        #expect(budgetKernel(transactions) == legacyPublic)

        let resolvedPublic = CategoryBudgetPlanner.netSpendByCategory(
            from: transactions, startKey: "2026-06-01", endKey: "2026-07-01", metadata: metadata
        )
        #expect(budgetKernel(transactions, metadata: metadata) == resolvedPublic)
    }

    // MARK: - Amount selector: magnitude (summary) vs signed netting (budget)

    @Test("Summary uses magnitude; budget nets refunds via signed amount")
    func amountSelectorDiverges() {
        // A purchase and a same-category refund in the window.
        let transactions = [
            tx(id: "buy", amount: 100, category: .shopping),
            tx(id: "refund", amount: -40, category: .shopping),
        ]

        // Summary: the refund is income-side, dropped by `expenseTransactions`, so
        // only the +100 magnitude counts.
        #expect(summaryKernel(transactions)[.shopping] == 100)

        // Budget: the signed refund nets against spend → 100 + (-40) = 60.
        #expect(budgetKernel(transactions)[.shopping] == 60)
    }

    // MARK: - Override / exclusion / transfer edge cases (both parameterizations)

    @Test("A user override moves spend in BOTH surfaces")
    func overrideMovesSpend() {
        let transactions = [tx(id: "a", amount: 40, category: .shopping)]
        let metadata = [TransactionReviewMetadata(id: "a", userCategory: .foodAndDrink)]

        #expect(summaryKernel(transactions, metadata: metadata)[.foodAndDrink] == 40)
        #expect(summaryKernel(transactions, metadata: metadata)[.shopping] == nil)
        #expect(budgetKernel(transactions, metadata: metadata)[.foodAndDrink] == 40)
        #expect(budgetKernel(transactions, metadata: metadata)[.shopping] == nil)
    }

    @Test("Excluded-from-budgets and transfer overrides drop the row in BOTH surfaces")
    func excludedAndTransferDrop() {
        let transactions = [
            tx(id: "keep", amount: 15, category: .foodAndDrink),
            tx(id: "excl", amount: 99, category: .shopping),
            tx(id: "xfer", amount: 200, category: .shopping),
        ]
        let metadata = [
            TransactionReviewMetadata(id: "excl", excludedFromBudgets: true),
            TransactionReviewMetadata(id: "xfer", isTransferOverride: true),
        ]

        let summary = summaryKernel(transactions, metadata: metadata)
        #expect(summary[.foodAndDrink] == 15)
        #expect(summary[.shopping] == nil)

        let budget = budgetKernel(transactions, metadata: metadata)
        #expect(budget[.foodAndDrink] == 15)
        #expect(budget[.shopping] == nil)
    }

    @Test("Post-resolution exclusion: an override TO income is kept by summary, dropped by budget")
    func overrideToIncomeDivergesPostResolution() {
        // The single behavior the `excludePostResolution` knob governs: a row the
        // user overrode to `.income` survives resolution (the resolver does not flag
        // income as transfer/excluded). The summary surface counts it (its inputs are
        // already income/transfer pre-filtered, and it never had a post-resolution
        // drop); the budget surface drops it (income is never category spend).
        let transactions = [tx(id: "weird", amount: 75, category: .shopping)]
        let metadata = [TransactionReviewMetadata(id: "weird", userCategory: .income)]

        #expect(summaryKernel(transactions, metadata: metadata)[.income] == 75)
        #expect(budgetKernel(transactions, metadata: metadata)[.income] == nil)
        #expect(budgetKernel(transactions, metadata: metadata).isEmpty)
    }

    // MARK: - Missing override / zero / fallback

    @Test("Missing override falls back to the raw Plaid bucket in BOTH surfaces")
    func missingOverrideFallsBackToRawBucket() {
        // Opt into the resolved path (empty metadata) with no record for this row →
        // it must fall back to its confident raw Plaid category, not vanish.
        let transactions = [tx(id: "a", amount: 50, category: .shopping)]

        #expect(summaryKernel(transactions, metadata: [])[.shopping] == 50)
        #expect(budgetKernel(transactions, metadata: [])[.shopping] == 50)
    }

    @Test("A nil-category row with no override resolves to .other in BOTH surfaces")
    func nilCategoryFallsBackToOther() {
        let transactions = [tx(id: "a", amount: 22, category: nil)]

        #expect(summaryKernel(transactions, metadata: [])[.other] == 22)
        #expect(budgetKernel(transactions, metadata: [])[.other] == 22)
    }

    @Test("A zero-amount row contributes a zero bucket, not a dropped one")
    func zeroAmountKeepsCategoryAtZero() {
        let transactions = [tx(id: "z", amount: 0, category: .shopping)]

        // Magnitude(0) and signed(0) both land 0 under .shopping in the resolved path.
        #expect(summaryKernel(transactions, metadata: [])[.shopping] == 0)
        #expect(budgetKernel(transactions, metadata: [])[.shopping] == 0)
    }

    @Test("Pending-id review metadata carries into the posted charge in BOTH surfaces")
    func pendingMetadataCarriesForward() {
        let transactions = [
            tx(id: "posted-1", amount: 50, category: .shopping, pendingTransactionId: "pending-1"),
        ]
        let metadata = [TransactionReviewMetadata(id: "pending-1", userCategory: .foodAndDrink)]

        #expect(summaryKernel(transactions, metadata: metadata)[.foodAndDrink] == 50)
        #expect(budgetKernel(transactions, metadata: metadata)[.foodAndDrink] == 50)
    }
}
