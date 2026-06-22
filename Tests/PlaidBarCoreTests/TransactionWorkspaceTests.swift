import Foundation
import PlaidBarCore
import Testing

/// Unit coverage for the pure Transaction Workspace pipeline (AND-582, Epic 4):
/// filter facets, search, sort, override-aware row building, the NavigationState
/// transitions, and the `userNote` Codable round-trip.
@Suite("Transaction Workspace")
struct TransactionWorkspaceTests {
    // MARK: - Fixtures

    private func tx(
        _ id: String,
        account: String = "acc1",
        amount: Double = 50,
        date: String = "2026-06-10",
        name: String = "Coffee Shop",
        merchant: String? = "Coffee Shop",
        category: SpendingCategory? = .foodAndDrink,
        pending: Bool = false
    ) -> TransactionDTO {
        TransactionDTO(
            id: id,
            accountId: account,
            amount: amount,
            date: date,
            name: name,
            merchantName: merchant,
            category: category,
            pending: pending
        )
    }

    private let now = Formatters.parseTransactionDate("2026-06-15")!

    // MARK: - Row building (override-aware)

    @Test("Rows surface the override-aware effective category and merchant rename")
    func rowsAreOverrideAware() {
        let transactions = [tx("a", category: .other)]
        let metadata = [
            TransactionReviewMetadata(
                id: "a",
                status: .reviewed,
                userCategory: .shopping,
                userMerchantName: "Renamed Co"
            ),
        ]
        let rows = TransactionWorkspace.rows(transactions: transactions, metadata: metadata, rules: [])
        #expect(rows.count == 1)
        #expect(rows[0].effectiveCategory == .shopping)
        #expect(rows[0].merchantName == "Renamed Co")
        #expect(rows[0].status == .reviewed)
    }

    @Test("A transfer override marks the row as transfer + excluded from budgets")
    func transferOverrideReflected() {
        let metadata = [TransactionReviewMetadata(id: "a", isTransferOverride: true)]
        let rows = TransactionWorkspace.rows(transactions: [tx("a")], metadata: metadata, rules: [])
        #expect(rows[0].isTransfer)
        #expect(rows[0].excludedFromBudgets)
    }

    @Test("A row with no metadata defaults to needsReview and no note")
    func defaultStatus() {
        let rows = TransactionWorkspace.rows(transactions: [tx("a")], metadata: [], rules: [])
        #expect(rows[0].status == .needsReview)
        #expect(rows[0].note == nil)
        #expect(!rows[0].hasNote)
    }

    @Test("A note is surfaced and drives hasNote")
    func noteSurfaced() {
        let metadata = [TransactionReviewMetadata(id: "a", userNote: "  trip reimbursement  ")]
        let rows = TransactionWorkspace.rows(transactions: [tx("a")], metadata: metadata, rules: [])
        #expect(rows[0].note == "trip reimbursement")
        #expect(rows[0].hasNote)
    }

    // MARK: - Plaid restore affordance (codex #1 / #3)

    @Test("A user override over confident Plaid is restorable per-row")
    func userOverrideRowIsRestorable() {
        let metadata = [TransactionReviewMetadata(id: "a", userCategory: .travel)]
        let rows = TransactionWorkspace.rows(
            transactions: [tx("a", category: .shopping)],
            metadata: metadata,
            rules: []
        )
        #expect(rows[0].isOverridingPlaid)
        #expect(rows[0].overrideOrigin == .user)
        #expect(rows[0].canRestorePlaidCategory)
        #expect(!rows[0].isOverriddenByRule)
    }

    @Test("A rule-backed category over Plaid is NOT per-row restorable")
    func ruleBackedRowNotRestorable() {
        // The "Restore Plaid category" button only clears the per-transaction
        // userCategory, which a rule-backed row does not have — so the inspector must
        // not offer it (it would no-op). The row reports the override as rule-origin.
        let rule = TransactionRule(matchMerchantContains: "Acme", category: .homeImprovement)
        let rows = TransactionWorkspace.rows(
            transactions: [tx("a", name: "ACME STORE", merchant: "Acme", category: .shopping)],
            metadata: [],
            rules: [rule]
        )
        #expect(rows[0].isOverridingPlaid)
        #expect(rows[0].overrideOrigin == .rule)
        #expect(!rows[0].canRestorePlaidCategory)
        #expect(rows[0].isOverriddenByRule)
    }

    @Test("A low-confidence Plaid row with no override is not restorable")
    func lowConfidenceNoOverrideNotRestorable() {
        let transactions = [
            TransactionDTO(
                id: "a",
                accountId: "acc1",
                amount: 50,
                date: "2026-06-10",
                name: "MYSTERY LLC",
                merchantName: nil,
                category: .other,
                pending: false,
                isLowConfidenceCategory: true
            ),
        ]
        let rows = TransactionWorkspace.rows(transactions: transactions, metadata: [], rules: [])
        #expect(!rows[0].isOverridingPlaid)
        #expect(rows[0].overrideOrigin == nil)
        #expect(!rows[0].canRestorePlaidCategory)
        #expect(!rows[0].isOverriddenByRule)
    }

    // MARK: - Filtering (each facet, and composition)

    private func rows() -> [TransactionWorkspace.Row] {
        let transactions = [
            tx("food", account: "acc1", amount: 12, date: "2026-06-14", merchant: "Cafe", category: .foodAndDrink),
            tx("shop", account: "acc2", amount: 240, date: "2026-06-01", merchant: "Big Store", category: .shopping),
            tx("old", account: "acc1", amount: 800, date: "2026-01-02", merchant: "Flight", category: .travel),
        ]
        let metadata = [
            TransactionReviewMetadata(id: "food", status: .needsReview),
            TransactionReviewMetadata(id: "shop", status: .reviewed),
            TransactionReviewMetadata(id: "old", status: .ignored),
        ]
        return TransactionWorkspace.rows(transactions: transactions, metadata: metadata, rules: [])
    }

    @Test("Account facet narrows to one account")
    func accountFacet() {
        let filter = TransactionWorkspace.Filter(accountID: "acc2")
        let out = TransactionWorkspace.filtered(rows(), by: filter, now: now)
        #expect(out.map(\.id) == ["shop"])
    }

    @Test("Category facet matches the effective category")
    func categoryFacet() {
        let filter = TransactionWorkspace.Filter(category: .travel)
        let out = TransactionWorkspace.filtered(rows(), by: filter, now: now)
        #expect(out.map(\.id) == ["old"])
    }

    @Test("Date range facet drops rows older than the window")
    func dateFacet() {
        let filter = TransactionWorkspace.Filter(dateRange: .last30Days)
        let out = TransactionWorkspace.filtered(rows(), by: filter, now: now)
        // "old" (2026-01-02) is older than 30 days before 2026-06-15.
        #expect(Set(out.map(\.id)) == ["food", "shop"])
    }

    @Test("Amount band facet filters by magnitude")
    func amountFacet() {
        let filter = TransactionWorkspace.Filter(amountBand: .over500)
        let out = TransactionWorkspace.filtered(rows(), by: filter, now: now)
        #expect(out.map(\.id) == ["old"])
    }

    @Test("Status facet filters by review status")
    func statusFacet() {
        let filter = TransactionWorkspace.Filter(status: .reviewed)
        let out = TransactionWorkspace.filtered(rows(), by: filter, now: now)
        #expect(out.map(\.id) == ["shop"])
    }

    @Test("Search matches merchant case-insensitively")
    func searchFacet() {
        let filter = TransactionWorkspace.Filter(searchText: "big")
        let out = TransactionWorkspace.filtered(rows(), by: filter, now: now)
        #expect(out.map(\.id) == ["shop"])
    }

    @Test("Search also matches the note text")
    func searchMatchesNote() {
        let transactions = [tx("a", merchant: "Generic")]
        let metadata = [TransactionReviewMetadata(id: "a", userNote: "vacation flight")]
        let built = TransactionWorkspace.rows(transactions: transactions, metadata: metadata, rules: [])
        let filter = TransactionWorkspace.Filter(searchText: "vacation")
        #expect(TransactionWorkspace.filtered(built, by: filter, now: now).map(\.id) == ["a"])
    }

    @Test("Facets compose with AND semantics")
    func facetsCompose() {
        let filter = TransactionWorkspace.Filter(accountID: "acc1", amountBand: .over500)
        let out = TransactionWorkspace.filtered(rows(), by: filter, now: now)
        #expect(out.map(\.id) == ["old"])
    }

    @Test("The default filter passes everything and is inactive")
    func defaultFilterPassesAll() {
        let filter = TransactionWorkspace.Filter()
        #expect(!filter.isActive)
        #expect(TransactionWorkspace.filtered(rows(), by: filter, now: now).count == 3)
    }

    @Test("Whitespace-only search is not active and does not blank the list")
    func whitespaceSearchInert() {
        let filter = TransactionWorkspace.Filter(searchText: "   ")
        #expect(!filter.isActive)
        #expect(TransactionWorkspace.filtered(rows(), by: filter, now: now).count == 3)
    }

    // MARK: - Sorting

    @Test("Date descending then ascending sort")
    func dateSorts() {
        let r = rows()
        #expect(TransactionWorkspace.Sort.dateDescending.sorted(r).map(\.id) == ["food", "shop", "old"])
        #expect(TransactionWorkspace.Sort.dateAscending.sorted(r).map(\.id) == ["old", "shop", "food"])
    }

    @Test("Amount descending then ascending sort")
    func amountSorts() {
        let r = rows()
        #expect(TransactionWorkspace.Sort.amountDescending.sorted(r).map(\.id) == ["old", "shop", "food"])
        #expect(TransactionWorkspace.Sort.amountAscending.sorted(r).map(\.id) == ["food", "shop", "old"])
    }

    @Test("Merchant A–Z sort")
    func merchantSort() {
        let r = rows()
        // Big Store, Cafe, Flight
        #expect(TransactionWorkspace.Sort.merchantAscending.sorted(r).map(\.id) == ["shop", "food", "old"])
    }

    @Test("Full resolve pipeline filters then sorts")
    func fullPipeline() {
        let transactions = [
            tx("a", amount: 10, date: "2026-06-14", category: .foodAndDrink),
            tx("b", amount: 30, date: "2026-06-13", category: .foodAndDrink),
            tx("c", amount: 20, date: "2026-06-12", category: .shopping),
        ]
        let out = TransactionWorkspace.resolve(
            transactions: transactions,
            metadata: [],
            rules: [],
            filter: TransactionWorkspace.Filter(category: .foodAndDrink),
            sort: .amountDescending,
            now: now
        )
        #expect(out.map(\.id) == ["b", "a"])
    }

    // MARK: - AmountBand / DateRange boundaries

    @Test("Amount bands cover contiguous magnitude ranges")
    func amountBandBoundaries() {
        #expect(TransactionWorkspace.AmountBand.under25.contains(24.99))
        #expect(!TransactionWorkspace.AmountBand.under25.contains(25))
        #expect(TransactionWorkspace.AmountBand.from25to100.contains(25))
        #expect(TransactionWorkspace.AmountBand.from25to100.contains(99.99))
        #expect(TransactionWorkspace.AmountBand.from100to500.contains(100))
        #expect(TransactionWorkspace.AmountBand.over500.contains(500))
        #expect(TransactionWorkspace.AmountBand.any.contains(0))
    }

    @Test("All-time range imposes no lower bound; this-year starts Jan 1")
    func dateRangeBounds() {
        #expect(TransactionWorkspace.DateRange.allTime.lowerBoundKey(now: now) == nil)
        #expect(TransactionWorkspace.DateRange.thisYear.lowerBoundKey(now: now) == "2026-01-01")
    }
}

// MARK: - NavigationState transitions

@Suite("NavigationState transaction workspace")
struct NavigationStateTransactionTests {
    @Test("Setting a different filter clears the row selection")
    func filterChangeClearsSelection() {
        var state = NavigationState()
        state.selectTransaction(id: "tx1")
        state.setTransactionFilter(TransactionWorkspace.Filter(category: .travel))
        #expect(state.selectedTransactionID == "")
        #expect(state.transactionFilter.category == .travel)
    }

    @Test("Setting the same filter is a no-op and keeps the selection")
    func sameFilterKeepsSelection() {
        var state = NavigationState()
        state.selectTransaction(id: "tx1")
        state.setTransactionFilter(TransactionWorkspace.Filter())
        #expect(state.selectedTransactionID == "tx1")
    }

    @Test("Sort changes do not clear the selection")
    func sortKeepsSelection() {
        var state = NavigationState()
        state.selectTransaction(id: "tx1")
        state.setTransactionSort(.amountDescending)
        #expect(state.selectedTransactionID == "tx1")
        #expect(state.transactionSort == .amountDescending)
    }

    @Test("Deselect clears the row selection")
    func deselect() {
        var state = NavigationState()
        state.selectTransaction(id: "tx1")
        state.deselectTransaction()
        #expect(state.selectedTransactionID == "")
    }

    @Test("Reconcile drops a selection no longer visible")
    func reconcile() {
        var state = NavigationState()
        state.selectTransaction(id: "gone")
        let didClear = state.reconcileTransactionSelection(visibleTransactionIDs: ["a", "b"])
        #expect(didClear)
        #expect(state.selectedTransactionID == "")
        // A still-visible selection survives.
        state.selectTransaction(id: "a")
        let didClearVisible = state.reconcileTransactionSelection(visibleTransactionIDs: ["a", "b"])
        #expect(!didClearVisible)
        #expect(state.selectedTransactionID == "a")
    }

    @Test("Two states hold independent transaction selection (per-window)")
    func independentWindows() {
        var one = NavigationState()
        var two = NavigationState()
        one.selectTransaction(id: "tx1")
        two.selectTransaction(id: "tx2")
        #expect(one.selectedTransactionID == "tx1")
        #expect(two.selectedTransactionID == "tx2")
    }
}

// MARK: - userNote Codable compatibility

@Suite("TransactionReviewMetadata userNote")
struct TransactionReviewMetadataNoteTests {
    @Test("userNote round-trips through Codable")
    func roundTrip() throws {
        let original = TransactionReviewMetadata(id: "a", status: .reviewed, userNote: "remember this")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TransactionReviewMetadata.self, from: data)
        #expect(decoded.userNote == "remember this")
        #expect(decoded == original)
    }

    @Test("Records written before userNote existed still decode (nil note)")
    func forwardCompatibleDecode() throws {
        // Simulate an older payload with no `userNote` key.
        let json = """
        {"id":"a","status":"reviewed","excludedFromBudgets":false,"reviewReasonCodes":[]}
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(TransactionReviewMetadata.self, from: data)
        #expect(decoded.id == "a")
        #expect(decoded.status == .reviewed)
        #expect(decoded.userNote == nil)
    }
}
