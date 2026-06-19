import Foundation
import Testing
@testable import PlaidBarCore

/// Tests for override-aware spend math (AND-526): `CategoryBudgetPlanner`'s
/// `netSpendByCategory` now accepts optional `metadata` / `rules` so a user
/// recategorizing or excluding a transaction in the Review Inbox actually moves
/// the budget totals downstream (the load-bearing fix from the category-dashboard
/// spec §2/§4).
///
/// The contract:
/// - **Default-nil params reproduce the legacy raw-category totals** (so every
///   existing `CategoryBudgetPlannerTests` case stays green, asserted directly
///   here too).
/// - **A `userCategory` override moves that transaction's spend** to the new
///   category (Codex's demo finding: a Food & Drink override counts under Food &
///   Drink, not Other).
/// - **An `excludedFromBudgets` or transfer row is removed** from the totals.
/// - **A rule-driven recategorization / exclusion takes effect** the same way.
///
/// All inputs are synthetic; no real Plaid data.
@Suite("Override-aware spend math (AND-526)")
struct OverrideAwareSpendMathTests {
    private let startKey = "2026-06-01"
    private let endKey = "2026-07-01"

    private func tx(
        _ amount: Double,
        _ date: String = "2026-06-05",
        _ category: SpendingCategory?,
        id: String? = nil,
        name: String = "MERCHANT",
        merchantName: String? = "Merchant",
        pending: Bool = false,
        pendingTransactionId: String? = nil,
        lowConfidence: Bool = false
    ) -> TransactionDTO {
        TransactionDTO(
            id: id ?? "\(name)-\(date)-\(amount)",
            accountId: "acct",
            amount: amount,
            date: date,
            name: name,
            merchantName: merchantName,
            category: category,
            pending: pending,
            pendingTransactionId: pendingTransactionId,
            isLowConfidenceCategory: lowConfidence
        )
    }

    // MARK: - (a) Default-nil params reproduce the current totals

    @Test("Default-nil metadata/rules reproduce the legacy raw-category totals")
    func defaultNilReproducesLegacy() {
        let transactions = [
            tx(150, "2026-06-04", .shopping),
            tx(50, "2026-06-09", .foodAndDrink),
            tx(-20, "2026-06-08", .shopping),       // refund nets
            tx(-2000, "2026-06-01", .income),       // excluded
            tx(500, "2026-06-02", .transferOut),    // excluded
            tx(99, "2026-05-31", .shopping),        // out of range (before window)
            tx(99, "2026-07-01", .shopping),        // out of range (>= end)
        ]

        // No metadata/rules → identical to the legacy overload.
        let resolved = CategoryBudgetPlanner.netSpendByCategory(
            from: transactions,
            startKey: startKey,
            endKey: endKey,
            metadata: nil,
            rules: nil
        )
        let legacy = CategoryBudgetPlanner.netSpendByCategory(
            from: transactions,
            startKey: startKey,
            endKey: endKey
        )

        #expect(resolved == legacy)
        #expect(resolved[.shopping] == 130) // 150 - 20
        #expect(resolved[.foodAndDrink] == 50)
        #expect(resolved[.income] == nil)
        #expect(resolved[.transferOut] == nil)
    }

    @Test("Empty (non-nil) metadata/rules also reproduce the raw-category totals")
    func emptyResolvedReproducesLegacy() {
        // A transaction with NO metadata and NO rules must resolve to its raw
        // confident Plaid category — so passing empty collections matches legacy.
        let transactions = [
            tx(120, "2026-06-04", .shopping),
            tx(40, "2026-06-06", .foodAndDrink),
        ]
        let resolved = CategoryBudgetPlanner.netSpendByCategory(
            from: transactions,
            startKey: startKey,
            endKey: endKey,
            metadata: [],
            rules: []
        )
        #expect(resolved[.shopping] == 120)
        #expect(resolved[.foodAndDrink] == 40)
    }

    // MARK: - (b) A userCategory override moves spend

    @Test("A userCategory override moves spend to the new category (Codex demo finding)")
    func userCategoryOverrideMovesSpend() {
        // Plaid says Other; the user recategorized it as Food & Drink. With the
        // override applied the spend must land under Food & Drink, NOT Other.
        let transaction = tx(60, "2026-06-05", .other, id: "coffee")
        let metadata = [
            TransactionReviewMetadata(id: "coffee", userCategory: .foodAndDrink),
        ]
        let resolved = CategoryBudgetPlanner.netSpendByCategory(
            from: [transaction],
            startKey: startKey,
            endKey: endKey,
            metadata: metadata,
            rules: nil
        )
        #expect(resolved[.foodAndDrink] == 60)
        #expect(resolved[.other] == nil)

        // And without the override it stays under Other (legacy behavior).
        let legacy = CategoryBudgetPlanner.netSpendByCategory(
            from: [transaction],
            startKey: startKey,
            endKey: endKey
        )
        #expect(legacy[.other] == 60)
        #expect(legacy[.foodAndDrink] == nil)
    }

    // MARK: - (c) Excluded / transfer rows are removed

    @Test("An excludedFromBudgets row is removed from the totals")
    func excludedRowRemoved() {
        let transactions = [
            tx(100, "2026-06-05", .shopping, id: "keep"),
            tx(80, "2026-06-06", .shopping, id: "drop"),
        ]
        let metadata = [
            TransactionReviewMetadata(id: "drop", excludedFromBudgets: true),
        ]
        let resolved = CategoryBudgetPlanner.netSpendByCategory(
            from: transactions,
            startKey: startKey,
            endKey: endKey,
            metadata: metadata,
            rules: nil
        )
        // Only the non-excluded $100 remains under Shopping.
        #expect(resolved[.shopping] == 100)
    }

    @Test("A transfer-override row is removed from the totals")
    func transferOverrideRowRemoved() {
        // Plaid categorized it as Shopping, but the user marked it a transfer
        // (e.g. a card payment miscategorized). Transfers never count as spend.
        let transactions = [
            tx(200, "2026-06-05", .shopping, id: "payment"),
            tx(45, "2026-06-07", .shopping, id: "real"),
        ]
        let metadata = [
            TransactionReviewMetadata(id: "payment", isTransferOverride: true),
        ]
        let resolved = CategoryBudgetPlanner.netSpendByCategory(
            from: transactions,
            startKey: startKey,
            endKey: endKey,
            metadata: metadata,
            rules: nil
        )
        #expect(resolved[.shopping] == 45)
    }

    // MARK: - (d) Rule-driven recategorization / exclusion

    @Test("A rule recategorizes matching transactions before aggregation")
    func ruleRecategorizes() {
        let transaction = tx(
            75, "2026-06-05", .other,
            id: "sbux", name: "STARBUCKS STORE 1234", merchantName: "Starbucks"
        )
        let rules = [
            TransactionRule(matchMerchantContains: "Starbucks", category: .foodAndDrink),
        ]
        let resolved = CategoryBudgetPlanner.netSpendByCategory(
            from: [transaction],
            startKey: startKey,
            endKey: endKey,
            metadata: nil,
            rules: rules
        )
        #expect(resolved[.foodAndDrink] == 75)
        #expect(resolved[.other] == nil)
    }

    @Test("A rule that excludes matching transactions removes them from totals")
    func ruleExcludes() {
        let transactions = [
            tx(
                300, "2026-06-05", .shopping,
                id: "venmo", name: "VENMO PAYMENT", merchantName: "Venmo"
            ),
            tx(60, "2026-06-08", .shopping, id: "keep"),
        ]
        let rules = [
            TransactionRule(matchOriginalNameContains: "VENMO", excludedFromBudgets: true),
        ]
        let resolved = CategoryBudgetPlanner.netSpendByCategory(
            from: transactions,
            startKey: startKey,
            endKey: endKey,
            metadata: nil,
            rules: rules
        )
        #expect(resolved[.shopping] == 60)
    }

    @Test("A user override on a metadata id wins over a conflicting rule category")
    func userOverrideBeatsRule() {
        let transaction = tx(
            90, "2026-06-05", .other,
            id: "target", name: "TARGET 4451", merchantName: "Target"
        )
        let metadata = [TransactionReviewMetadata(id: "target", userCategory: .shopping)]
        let rules = [TransactionRule(matchMerchantContains: "Target", category: .foodAndDrink)]
        let resolved = CategoryBudgetPlanner.netSpendByCategory(
            from: [transaction],
            startKey: startKey,
            endKey: endKey,
            metadata: metadata,
            rules: rules
        )
        #expect(resolved[.shopping] == 90)
        #expect(resolved[.foodAndDrink] == nil)
    }

    // MARK: - Pending→posted metadata carry-forward (spec §4 edge case)

    @Test("Review metadata under a pending id carries into its posted replacement")
    func pendingMetadataCarriesForward() {
        // The charge was reviewed while pending (under "pending-1"); Plaid then
        // re-posts it under a new id "posted-1" that links back via
        // pendingTransactionId. The Food & Drink override must still apply.
        let posted = tx(
            42, "2026-06-05", .other,
            id: "posted-1", pendingTransactionId: "pending-1"
        )
        let metadata = [
            TransactionReviewMetadata(id: "pending-1", userCategory: .foodAndDrink),
        ]
        let resolved = CategoryBudgetPlanner.netSpendByCategory(
            from: [posted],
            startKey: startKey,
            endKey: endKey,
            metadata: metadata,
            rules: nil
        )
        #expect(resolved[.foodAndDrink] == 42)
        #expect(resolved[.other] == nil)
    }

    @Test("Own posted-id metadata wins over carried-forward pending metadata")
    func ownMetadataWinsOverPending() {
        // Both ids carry metadata; the user re-decided under the posted id, so the
        // posted-id override (Shopping) must win over the pending-phase one (Food).
        let posted = tx(
            55, "2026-06-05", .other,
            id: "posted-2", pendingTransactionId: "pending-2"
        )
        let metadata = [
            TransactionReviewMetadata(id: "pending-2", userCategory: .foodAndDrink),
            TransactionReviewMetadata(id: "posted-2", userCategory: .shopping),
        ]
        let resolved = CategoryBudgetPlanner.netSpendByCategory(
            from: [posted],
            startKey: startKey,
            endKey: endKey,
            metadata: metadata,
            rules: nil
        )
        #expect(resolved[.shopping] == 55)
        #expect(resolved[.foodAndDrink] == nil)
    }

    // MARK: - Nil-effective-category rows fall back to raw Plaid / .other

    // Previously `uncategorizedStaysOut`, which asserted `resolved.isEmpty`. That
    // codified a live regression: an uncategorized row whose budget category
    // resolved to nil (no override, no rule, no confident Plaid category) was
    // *dropped* from every bucket. Per the spend precedence (user override → rule →
    // raw Plaid → `.other`, spec §4/§5) such a row must **fall back** to its raw
    // Plaid bucket — or `.other` when Plaid gave nothing — not vanish. So a nil-
    // category row now lands under `.other`, matching the legacy raw-category total.
    @Test("An uncategorized (nil-category) row with no override/rule falls back to .other")
    func uncategorizedFallsBackToOther() {
        // Nil category, no override, no rule → resolver returns nil budget category,
        // which must fall back to `.other` (Plaid gave nothing), matching legacy.
        let transaction = tx(
            30, "2026-06-05", nil,
            id: "mystery", name: "SQ *KMNT LLC 9921", merchantName: nil
        )
        let resolved = CategoryBudgetPlanner.netSpendByCategory(
            from: [transaction],
            startKey: startKey,
            endKey: endKey,
            metadata: [],
            rules: []
        )
        #expect(resolved[.other] == 30)

        // It must match the legacy raw-category bucket for the same row.
        let legacy = CategoryBudgetPlanner.netSpendByCategory(
            from: [transaction],
            startKey: startKey,
            endKey: endKey
        )
        #expect(resolved == legacy)
    }

    @Test("An .other row with no override/rule counts under .other (matches legacy)")
    func otherCategoryFallsBackToOther() {
        // Codex regression repro: a $400 `.other` charge. The resolver's budget
        // category is nil for `.other` (it is not a *confident* Plaid category), so
        // before the fix this row vanished — a user budgeting `.other` saw spent==0
        // instead of 400. It must now count under `.other`, matching legacy.
        let transaction = tx(400, "2026-06-05", .other, id: "uncat")
        let resolved = CategoryBudgetPlanner.netSpendByCategory(
            from: [transaction],
            startKey: startKey,
            endKey: endKey,
            metadata: [],
            rules: []
        )
        #expect(resolved[.other] == 400)

        let legacy = CategoryBudgetPlanner.netSpendByCategory(
            from: [transaction],
            startKey: startKey,
            endKey: endKey
        )
        #expect(legacy[.other] == 400)
        #expect(resolved == legacy)
    }

    @Test("A low-confidence Plaid row keeps its raw Plaid bucket (not dropped)")
    func lowConfidencePlaidRowKeepsRawBucket() {
        // Plaid returned Food & Drink but flagged it low/unknown confidence. The
        // resolver treats that as no *confident* category (budget category nil), but
        // the row must still fall back to its raw Plaid bucket — Food & Drink — not
        // disappear. (Before the fix every low-confidence row was dropped.)
        let transaction = tx(
            85, "2026-06-05", .foodAndDrink,
            id: "lowconf", name: "UNKNOWN CAFE", merchantName: nil,
            lowConfidence: true
        )
        let resolved = CategoryBudgetPlanner.netSpendByCategory(
            from: [transaction],
            startKey: startKey,
            endKey: endKey,
            metadata: [],
            rules: []
        )
        #expect(resolved[.foodAndDrink] == 85)
        #expect(resolved[.other] == nil)

        // Matches the legacy raw-category bucket (legacy ignores confidence).
        let legacy = CategoryBudgetPlanner.netSpendByCategory(
            from: [transaction],
            startKey: startKey,
            endKey: endKey
        )
        #expect(resolved == legacy)
    }

    @Test("Excluded and transfer rows are still skipped even with the nil-category fallback")
    func excludedAndTransferStillSkippedWithFallback() {
        // The nil-category fallback must not resurrect excluded/transfer rows. Mix a
        // kept `.other` row, an income row (excludedCategories), a transfer-override
        // row, and a rule-excluded row — only the kept `.other` should remain.
        let transactions = [
            tx(120, "2026-06-05", .other, id: "keep"),
            tx(-900, "2026-06-02", .income, id: "salary"),       // excludedCategories
            tx(200, "2026-06-06", .other, id: "xfer"),           // transfer override
            tx(
                75, "2026-06-07", nil,
                id: "venmo", name: "VENMO PAYMENT", merchantName: "Venmo"
            ),                                                   // rule-excluded
        ]
        let metadata = [TransactionReviewMetadata(id: "xfer", isTransferOverride: true)]
        let rules = [TransactionRule(matchOriginalNameContains: "VENMO", excludedFromBudgets: true)]
        let resolved = CategoryBudgetPlanner.netSpendByCategory(
            from: transactions,
            startKey: startKey,
            endKey: endKey,
            metadata: metadata,
            rules: rules
        )
        #expect(resolved[.other] == 120)
        #expect(resolved[.income] == nil)
        #expect(resolved[.transfer] == nil)
        #expect(resolved.count == 1)
    }

    // MARK: - End-to-end presentation wiring

    @Test("presentation forwards metadata/rules so the override moves the scored spend")
    func presentationHonorsOverrides() {
        let now = Formatters.parseTransactionDate("2026-06-13")!
        let calendar = Calendar(identifier: .gregorian)
        let transaction = tx(60, "2026-06-05", .other, id: "coffee")
        let metadata = [TransactionReviewMetadata(id: "coffee", userCategory: .foodAndDrink)]

        let result = CategoryBudgetPlanner.presentation(
            budgets: [.foodAndDrink: 200, .other: 200],
            transactions: [transaction],
            asOf: now,
            calendar: calendar,
            metadata: metadata,
            rules: nil
        )
        let byCategory = Dictionary(uniqueKeysWithValues: result.items.map { ($0.category, $0.spent) })
        #expect(byCategory[.foodAndDrink] == 60)
        #expect(byCategory[.other] == 0)
    }

    @Test("mergedPresentation forwards metadata/rules into the scored spend")
    func mergedPresentationHonorsOverrides() {
        let now = Formatters.parseTransactionDate("2026-06-13")!
        let calendar = Calendar(identifier: .gregorian)
        let transaction = tx(60, "2026-06-05", .other, id: "coffee")
        let metadata = [TransactionReviewMetadata(id: "coffee", userCategory: .foodAndDrink)]

        let result = CategoryBudgetPlanner.mergedPresentation(
            explicitBudgets: [.foodAndDrink: 200],
            transactions: [transaction],
            asOf: now,
            calendar: calendar,
            metadata: metadata,
            rules: nil
        )
        let food = result.items.first { $0.category == .foodAndDrink }
        #expect(food?.spent == 60)
    }
}
