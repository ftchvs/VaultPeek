import Foundation
@testable import PlaidBarCore
import Testing

@Suite("Review Auto-Review Policy Tests (AND-553)")
struct ReviewAutoReviewPolicyTests {
    @Test("Auto-review preference is off by default")
    func preferenceOffByDefault() {
        #expect(ReviewAutoReviewPreference.defaultValue == .off)
        #expect(ReviewAutoReviewPreference.defaultValue.isEnabled == false)
    }

    @Test("A high-confidence, categorized, ordinary, non-transfer row is auto-reviewable")
    func happyPathEligible() {
        let row = item(reasons: [.newMerchant], category: .foodAndDrink, lowConfidence: false)
        #expect(ReviewAutoReviewPolicy.isAutoReviewable(row))
    }

    @Test("NEVER auto-reviews a low-confidence row")
    func neverLowConfidence() {
        let row = item(reasons: [.uncategorized], category: .foodAndDrink, lowConfidence: true)
        #expect(ReviewAutoReviewPolicy.isAutoReviewable(row) == false)
    }

    @Test("NEVER auto-reviews an uncategorized or 'Other' row")
    func neverUncategorizedOrOther() {
        let uncategorized = item(reasons: [.newMerchant], category: nil)
        let other = item(reasons: [.newMerchant], category: .other)
        #expect(ReviewAutoReviewPolicy.isAutoReviewable(uncategorized) == false)
        #expect(ReviewAutoReviewPolicy.isAutoReviewable(other) == false)
    }

    @Test("NEVER auto-reviews an unusual-amount row")
    func neverUnusual() {
        let row = item(reasons: [.unusualAmount], category: .foodAndDrink)
        #expect(ReviewAutoReviewPolicy.isAutoReviewable(row) == false)
    }

    @Test("NEVER auto-reviews a transfer — by flag, by reason, or by category")
    func neverTransfer() {
        let byFlag = item(reasons: [.newMerchant], category: .foodAndDrink, isTransfer: true)
        let byReason = item(reasons: [.possibleTransfer], category: .foodAndDrink)
        let byCategoryIn = item(reasons: [.newMerchant], category: .transfer)
        let byCategoryOut = item(reasons: [.newMerchant], category: .transferOut)

        #expect(ReviewAutoReviewPolicy.isAutoReviewable(byFlag) == false)
        #expect(ReviewAutoReviewPolicy.isAutoReviewable(byReason) == false)
        #expect(ReviewAutoReviewPolicy.isAutoReviewable(byCategoryIn) == false)
        #expect(ReviewAutoReviewPolicy.isAutoReviewable(byCategoryOut) == false)
    }

    @Test("NEVER auto-reviews a row carrying any high-priority reason")
    func neverHighPriorityReason() {
        // pendingChanged / recurringChanged / changedSinceReview are all
        // high-priority and must never be cleared automatically.
        for reason in [TransactionReviewReason.pendingChanged, .recurringChanged, .changedSinceReview] {
            let row = item(reasons: [reason], category: .foodAndDrink)
            #expect(ReviewAutoReviewPolicy.isAutoReviewable(row) == false)
        }
    }

    @Test("NEVER auto-reviews an on-device NL suggestion awaiting approval")
    func neverNLSuggestion() {
        let row = item(
            reasons: [.uncategorized],
            category: .foodAndDrink,
            categorySource: .appleNaturalLanguage
        )
        #expect(ReviewAutoReviewPolicy.isAutoReviewable(row) == false)
    }

    @Test("NEVER auto-reviews an already-resolved row")
    func neverAlreadyResolved() {
        let reviewed = item(reasons: [.newMerchant], category: .foodAndDrink, status: .reviewed)
        let ignored = item(reasons: [.newMerchant], category: .foodAndDrink, status: .ignored)
        #expect(ReviewAutoReviewPolicy.isAutoReviewable(reviewed) == false)
        #expect(ReviewAutoReviewPolicy.isAutoReviewable(ignored) == false)
    }

    @Test("autoReviewableIDs returns exactly the eligible rows in snapshot order")
    func snapshotFiltersToEligible() {
        let snapshot = TransactionReviewInboxSnapshot(items: [
            item(id: "eligible-1", reasons: [.newMerchant], category: .foodAndDrink),
            item(id: "low-conf", reasons: [.uncategorized], category: .foodAndDrink, lowConfidence: true),
            item(id: "transfer", reasons: [.possibleTransfer], category: .foodAndDrink),
            item(id: "eligible-2", reasons: [.newMerchant], category: .shopping),
            item(id: "unusual", reasons: [.unusualAmount], category: .shopping),
        ])

        let ids = ReviewAutoReviewPolicy.autoReviewableIDs(in: snapshot)
        #expect(ids == ["eligible-1", "eligible-2"])
    }

    @Test("autoReviewableIDs is empty when nothing qualifies — a no-op pass")
    func emptyWhenNothingQualifies() {
        let snapshot = TransactionReviewInboxSnapshot(items: [
            item(id: "a", reasons: [.uncategorized], category: nil),
            item(id: "b", reasons: [.possibleTransfer], category: .foodAndDrink),
        ])
        #expect(ReviewAutoReviewPolicy.autoReviewableIDs(in: snapshot).isEmpty)
    }

    // MARK: - Helpers

    private func item(
        id: String = "tx",
        reasons: [TransactionReviewReason],
        category: SpendingCategory?,
        lowConfidence: Bool = false,
        isTransfer: Bool = false,
        status: TransactionReviewStatus = .needsReview,
        categorySource: LocalAICategoryResolutionSource? = nil
    ) -> TransactionReviewItem {
        TransactionReviewItem(
            transaction: TransactionDTO(
                id: id,
                accountId: "acct",
                amount: 23.5,
                date: "2026-06-01",
                name: id.uppercased(),
                merchantName: id,
                category: category,
                pending: false,
                isLowConfidenceCategory: lowConfidence
            ),
            status: status,
            reasonCodes: reasons,
            effectiveCategory: category,
            effectiveMerchantName: id,
            isTransfer: isTransfer,
            excludedFromBudgets: isTransfer,
            matchedRuleIds: [],
            categorySource: categorySource
        )
    }
}
