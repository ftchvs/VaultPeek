import Foundation
@testable import PlaidBarCore
import Testing

@Suite("Review Bulk Action Plan Tests")
struct ReviewBulkActionTests {
    @Test("No selection marks every unresolved listed row")
    func allListedWhenNoSelection() {
        let items = [
            item(id: "a", merchant: "Corner Store"),
            item(id: "b", merchant: "Coffee Shop"),
            item(id: "c", merchant: "Gas Station"),
        ]

        let plan = ReviewBulkActionPlan.markReviewed(items: items)

        #expect(plan.affectedIDs == ["a", "b", "c"])
        #expect(plan.count == 3)
        #expect(plan.affectedMerchantNames == ["Corner Store", "Coffee Shop", "Gas Station"])
    }

    @Test("Explicit selection scopes to listed rows in list order")
    func explicitSelectionScopes() {
        let items = [
            item(id: "a", merchant: "Corner Store"),
            item(id: "b", merchant: "Coffee Shop"),
            item(id: "c", merchant: "Gas Station"),
        ]

        // Selection order should NOT leak through — list order is preserved so
        // the announced "which" matches what the user sees.
        let plan = ReviewBulkActionPlan.markReviewed(items: items, selectedIDs: ["c", "a"])

        #expect(plan.affectedIDs == ["a", "c"])
        #expect(plan.affectedMerchantNames == ["Corner Store", "Gas Station"])
    }

    @Test("Stale selected id that already left the list never marks anything")
    func staleSelectionIgnored() {
        let items = [
            item(id: "a", merchant: "Corner Store"),
        ]

        let plan = ReviewBulkActionPlan.markReviewed(items: items, selectedIDs: ["ghost"])

        #expect(plan.isEmpty)
        #expect(plan.affectedIDs.isEmpty)
    }

    @Test("Already-reviewed rows are excluded from the blast radius")
    func reviewedRowsExcluded() {
        let items = [
            item(id: "a", merchant: "Corner Store", status: .needsReview),
            item(id: "b", merchant: "Reopened", status: .reviewed),
            item(id: "c", merchant: "Gas Station", status: .needsReview),
        ]

        // No selection: only the two unresolved rows are in scope.
        let all = ReviewBulkActionPlan.markReviewed(items: items)
        #expect(all.affectedIDs == ["a", "c"])

        // Explicit selection of the reviewed row resolves to nothing.
        let selected = ReviewBulkActionPlan.markReviewed(items: items, selectedIDs: ["b"])
        #expect(selected.isEmpty)
    }

    @Test("Empty inbox produces an empty plan")
    func emptyInbox() {
        let plan = ReviewBulkActionPlan.markReviewed(items: [])

        #expect(plan.isEmpty)
        #expect(plan.count == 0)
        #expect(plan.blastRadiusDescription() == "No transactions to mark reviewed")
    }

    @Test("Blast radius description states the count and which merchants")
    func descriptionStatesCountAndNames() {
        let items = [
            item(id: "a", merchant: "Corner Store"),
            item(id: "b", merchant: "Coffee Shop"),
        ]

        let plan = ReviewBulkActionPlan.markReviewed(items: items)

        #expect(plan.blastRadiusDescription() == "Mark 2 transactions reviewed: Corner Store, Coffee Shop")
    }

    @Test("Singular noun for a single transaction")
    func singularNoun() {
        let plan = ReviewBulkActionPlan.markReviewed(items: [item(id: "a", merchant: "Corner Store")])

        #expect(plan.blastRadiusDescription() == "Mark 1 transaction reviewed: Corner Store")
    }

    @Test("Description collapses overflow into 'and N more'")
    func descriptionCollapsesOverflow() {
        let items = (1 ... 5).map { item(id: "id-\($0)", merchant: "Merchant \($0)") }

        let plan = ReviewBulkActionPlan.markReviewed(items: items)

        #expect(
            plan.blastRadiusDescription(previewLimit: 3)
                == "Mark 5 transactions reviewed: Merchant 1, Merchant 2, Merchant 3, and 2 more"
        )
    }

    private func item(
        id: String,
        merchant: String,
        status: TransactionReviewStatus = .needsReview
    ) -> TransactionReviewItem {
        TransactionReviewItem(
            transaction: TransactionDTO(
                id: id,
                accountId: "test-account",
                amount: 12,
                date: "2026-06-01",
                name: merchant.uppercased(),
                merchantName: merchant,
                category: nil,
                pending: false
            ),
            status: status,
            reasonCodes: [.uncategorized],
            effectiveCategory: nil,
            effectiveMerchantName: merchant,
            isTransfer: false,
            excludedFromBudgets: false,
            matchedRuleIds: []
        )
    }
}
