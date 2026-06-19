import Foundation
@testable import PlaidBarCore
import Testing

@Suite("Review Table Model Tests (AND-532)")
struct ReviewTableModelTests {
    // MARK: - Row mapping

    @Test("Row carries merchant, signed amount, date, category, and reasons")
    func rowCarriesFields() {
        let row = ReviewTableRow(item: item(
            id: "a",
            merchant: "Corner Store",
            amount: 42.5,
            date: "2026-06-01",
            category: .foodAndDrink,
            reasons: [.uncategorized, .newMerchant]
        ))

        #expect(row.id == "a")
        #expect(row.merchantName == "Corner Store")
        #expect(row.amount == 42.5)
        #expect(row.categoryTitle == SpendingCategory.foodAndDrink.displayName)
        #expect(row.categoryGlyph == SpendingCategory.foodAndDrink.iconName)
        #expect(row.category == .foodAndDrink)
        // Reason summary lists the reasons in display form, comma-separated, so the
        // "why is this here" never rides on color alone.
        #expect(row.reasonSummary.contains("Needs category"))
        #expect(row.reasonSummary.contains("New merchant"))
    }

    @Test("Uncategorized row falls back to the neutral pill, never a borrowed glyph")
    func uncategorizedRow() {
        let row = ReviewTableRow(item: item(id: "b", merchant: "Mystery", amount: 9, date: "2026-06-02", category: nil, reasons: [.uncategorized]))

        #expect(row.category == nil)
        #expect(row.categoryTitle == CategoryPillModel.uncategorizedTitle)
        #expect(row.categoryGlyph == CategoryPillModel.uncategorizedGlyph)
    }

    @Test("Row exposes transfer + NL-suggested provenance for badges")
    func rowProvenance() {
        let transferRow = ReviewTableRow(item: item(
            id: "t", merchant: "Move", amount: 100, date: "2026-06-03",
            category: .transfer, reasons: [.possibleTransfer], isTransfer: true
        ))
        #expect(transferRow.isTransfer)

        let suggestedRow = ReviewTableRow(item: item(
            id: "s", merchant: "Cafe", amount: 5, date: "2026-06-04",
            category: .entertainment, reasons: [.uncategorized],
            categorySource: .appleNaturalLanguage
        ))
        #expect(suggestedRow.isNLSuggested)
        #expect(!transferRow.isNLSuggested)
    }

    // MARK: - Privacy mask

    @Test("Masked amount/merchant text withholds figures; unmasked shows them")
    func maskedText() {
        let row = ReviewTableRow(item: item(id: "a", merchant: "Corner Store", amount: 42.5, date: "2026-06-01", category: .foodAndDrink, reasons: [.uncategorized]))

        let masked = row.amountText(isMasked: true)
        #expect(masked == PrivacyMaskPresentation.compactValue)

        let unmasked = row.amountText(isMasked: false)
        #expect(unmasked.contains("42"))

        // Merchant text is withheld under mask too (it can identify spend).
        #expect(row.merchantText(isMasked: true) == PrivacyMaskPresentation.compactValue)
        #expect(row.merchantText(isMasked: false) == "Corner Store")
    }

    @Test("Row builder maps a snapshot of items preserving order")
    func rowsFromItems() {
        let items = [
            item(id: "a", merchant: "A", amount: 1, date: "2026-06-01", category: .foodAndDrink, reasons: [.uncategorized]),
            item(id: "b", merchant: "B", amount: 2, date: "2026-06-02", category: nil, reasons: [.newMerchant]),
        ]
        let rows = ReviewTableRow.rows(from: items)
        #expect(rows.map(\.id) == ["a", "b"])
    }

    // MARK: - Bulk recategorize blast radius

    @Test("Bulk recategorize scopes to the selection intersected with listed rows")
    func bulkRecategorizeScopes() {
        let rows = [
            ReviewTableRow(item: item(id: "a", merchant: "A", amount: 1, date: "d", category: nil, reasons: [.uncategorized])),
            ReviewTableRow(item: item(id: "b", merchant: "B", amount: 2, date: "d", category: nil, reasons: [.uncategorized])),
            ReviewTableRow(item: item(id: "c", merchant: "C", amount: 3, date: "d", category: nil, reasons: [.uncategorized])),
        ]

        let plan = ReviewBulkRecategorizePlan.make(
            rows: rows,
            selection: ["c", "a"],
            category: .foodAndDrink
        )

        // List order is preserved (selection order does not leak), category recorded.
        #expect(plan.affectedIDs == ["a", "c"])
        #expect(plan.category == .foodAndDrink)
        #expect(plan.affectedMerchantNames == ["A", "C"])
        #expect(plan.count == 2)
        #expect(!plan.isEmpty)
    }

    @Test("Stale selected id that is no longer listed is dropped")
    func bulkRecategorizeStaleDropped() {
        let rows = [ReviewTableRow(item: item(id: "a", merchant: "A", amount: 1, date: "d", category: nil, reasons: [.uncategorized]))]

        let plan = ReviewBulkRecategorizePlan.make(rows: rows, selection: ["ghost"], category: .foodAndDrink)

        #expect(plan.isEmpty)
        #expect(plan.affectedIDs.isEmpty)
    }

    @Test("Empty selection produces an empty plan")
    func bulkRecategorizeEmptySelection() {
        let rows = [ReviewTableRow(item: item(id: "a", merchant: "A", amount: 1, date: "d", category: nil, reasons: [.uncategorized]))]

        let plan = ReviewBulkRecategorizePlan.make(rows: rows, selection: [], category: .foodAndDrink)

        #expect(plan.isEmpty)
        #expect(plan.count == 0)
    }

    @Test("Blast radius description states count, category, and which merchants")
    func bulkRecategorizeDescription() {
        let rows = [
            ReviewTableRow(item: item(id: "a", merchant: "Corner Store", amount: 1, date: "d", category: nil, reasons: [.uncategorized])),
            ReviewTableRow(item: item(id: "b", merchant: "Coffee Shop", amount: 2, date: "d", category: nil, reasons: [.uncategorized])),
        ]

        let plan = ReviewBulkRecategorizePlan.make(rows: rows, selection: ["a", "b"], category: .foodAndDrink)

        let description = plan.blastRadiusDescription()
        #expect(description.contains("2"))
        #expect(description.contains(SpendingCategory.foodAndDrink.displayName))
        #expect(description.contains("Corner Store"))
        #expect(description.contains("Coffee Shop"))
    }

    @Test("Singular noun for a single recategorized row")
    func bulkRecategorizeSingular() {
        let rows = [ReviewTableRow(item: item(id: "a", merchant: "Corner Store", amount: 1, date: "d", category: nil, reasons: [.uncategorized]))]
        let plan = ReviewBulkRecategorizePlan.make(rows: rows, selection: ["a"], category: .foodAndDrink)
        #expect(plan.blastRadiusDescription().contains("1 transaction "))
    }

    @Test("Description collapses overflow into 'and N more'")
    func bulkRecategorizeOverflow() {
        let rows = (1 ... 5).map { i in
            ReviewTableRow(item: item(id: "id-\(i)", merchant: "Merchant \(i)", amount: 1, date: "d", category: nil, reasons: [.uncategorized]))
        }
        let plan = ReviewBulkRecategorizePlan.make(rows: rows, selection: Set(rows.map(\.id)), category: .foodAndDrink)
        #expect(plan.blastRadiusDescription(previewLimit: 3).contains("and 2 more"))
    }

    // MARK: - Sorting

    @Test("Amount descending sorts by largest spend first; id breaks ties")
    func sortAmountDescending() {
        let rows = [
            ReviewTableRow(item: item(id: "a", merchant: "A", amount: 10, date: "2026-06-01", category: nil, reasons: [])),
            ReviewTableRow(item: item(id: "b", merchant: "B", amount: 30, date: "2026-06-01", category: nil, reasons: [])),
            ReviewTableRow(item: item(id: "c", merchant: "C", amount: 20, date: "2026-06-01", category: nil, reasons: [])),
        ]
        #expect(ReviewTableSort.amountDescending.sorted(rows).map(\.id) == ["b", "c", "a"])
        #expect(ReviewTableSort.amountAscending.sorted(rows).map(\.id) == ["a", "c", "b"])
    }

    @Test("Date descending sorts newest first")
    func sortDateDescending() {
        let rows = [
            ReviewTableRow(item: item(id: "a", merchant: "A", amount: 1, date: "2026-06-01", category: nil, reasons: [])),
            ReviewTableRow(item: item(id: "b", merchant: "B", amount: 1, date: "2026-06-10", category: nil, reasons: [])),
            ReviewTableRow(item: item(id: "c", merchant: "C", amount: 1, date: "2026-06-05", category: nil, reasons: [])),
        ]
        #expect(ReviewTableSort.dateDescending.sorted(rows).map(\.id) == ["b", "c", "a"])
    }

    @Test("Merchant sort is case-insensitive A–Z")
    func sortMerchant() {
        let rows = [
            ReviewTableRow(item: item(id: "1", merchant: "banana", amount: 1, date: "d", category: nil, reasons: [])),
            ReviewTableRow(item: item(id: "2", merchant: "Apple", amount: 1, date: "d", category: nil, reasons: [])),
            ReviewTableRow(item: item(id: "3", merchant: "cherry", amount: 1, date: "d", category: nil, reasons: [])),
        ]
        #expect(ReviewTableSort.merchant.sorted(rows).map(\.merchantName) == ["Apple", "banana", "cherry"])
    }

    @Test("Sort is total and deterministic — equal keys fall back to id order")
    func sortDeterministicTieBreak() {
        let rows = [
            ReviewTableRow(item: item(id: "z", merchant: "Same", amount: 5, date: "d", category: nil, reasons: [])),
            ReviewTableRow(item: item(id: "a", merchant: "Same", amount: 5, date: "d", category: nil, reasons: [])),
        ]
        #expect(ReviewTableSort.amountDescending.sorted(rows).map(\.id) == ["a", "z"])
    }

    // MARK: - Helpers

    private func item(
        id: String,
        merchant: String,
        amount: Double,
        date: String,
        category: SpendingCategory?,
        reasons: [TransactionReviewReason],
        isTransfer: Bool = false,
        categorySource: LocalAICategoryResolutionSource? = nil
    ) -> TransactionReviewItem {
        TransactionReviewItem(
            transaction: TransactionDTO(
                id: id,
                accountId: "test-account",
                amount: amount,
                date: date,
                name: merchant.uppercased(),
                merchantName: merchant,
                category: category,
                pending: false
            ),
            status: .needsReview,
            reasonCodes: reasons,
            effectiveCategory: category,
            effectiveMerchantName: merchant,
            isTransfer: isTransfer,
            excludedFromBudgets: isTransfer,
            matchedRuleIds: [],
            categorySource: categorySource
        )
    }
}
