import Foundation
import Testing
@testable import PlaidBarCore

/// Transaction splits — one transaction into N category allocations (AND-550).
///
/// Covers the model's sum invariant and validity, the resolver's additive
/// expansion (no split → byte-identical single row; valid split → one row per
/// part; malformed split → falls back to the parent), and split-aware spend across
/// the budget/summary consumers — including that **rollups count the parts, not
/// the parent**, that a per-part exclude flag is honored, and that removing the
/// split restores the original totals.
@Suite("Transaction splits (AND-550)")
struct TransactionSplitTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func tx(
        _ id: String,
        _ amount: Double,
        _ date: String,
        _ category: SpendingCategory?,
        name: String = "Target"
    ) -> TransactionDTO {
        TransactionDTO(
            id: id,
            accountId: "acct",
            amount: amount,
            date: date,
            name: name,
            category: category,
            pending: false
        )
    }

    // MARK: - Model: the sum invariant

    @Test("A split whose parts sum to the parent amount is balanced and valid")
    func balancedSplitIsValid() {
        let parent = tx("t1", 150, "2026-06-04", .shopping)
        let split = TransactionSplit(
            splitting: parent,
            into: [
                TransactionSplitAllocation(category: .foodAndDrink, amount: 90),
                TransactionSplitAllocation(category: .homeImprovement, amount: 60),
            ]
        )
        #expect(split.allocatedTotal == 150)
        #expect(split.unallocatedRemainder == 0)
        #expect(split.isBalanced())
        #expect(split.isValid)
    }

    @Test("A split whose parts do NOT sum to the parent amount is unbalanced and invalid")
    func unbalancedSplitIsInvalid() {
        let parent = tx("t1", 150, "2026-06-04", .shopping)
        let split = TransactionSplit(
            splitting: parent,
            into: [
                TransactionSplitAllocation(category: .foodAndDrink, amount: 90),
                TransactionSplitAllocation(category: .homeImprovement, amount: 40), // sums to 130
            ]
        )
        #expect(split.allocatedTotal == 130)
        #expect(split.unallocatedRemainder == 20)
        #expect(!split.isBalanced())
        #expect(!split.isValid)
    }

    @Test("Sub-cent float drift still balances within tolerance")
    func subCentDriftBalances() {
        // 100 / 3 thirds: 33.34 + 33.33 + 33.33 = 100.00 exactly here, but use a
        // case that drifts: three 33.333… parts rounded.
        let parent = tx("t1", 100, "2026-06-04", .shopping)
        let split = TransactionSplit(
            splitting: parent,
            into: [
                TransactionSplitAllocation(category: .foodAndDrink, amount: 33.34),
                TransactionSplitAllocation(category: .homeImprovement, amount: 33.33),
                TransactionSplitAllocation(category: .travel, amount: 33.33),
            ]
        )
        #expect(split.isBalanced()) // within the one-cent tolerance
        #expect(split.isValid)
    }

    @Test("An empty split is never balanced or valid")
    func emptySplitIsInvalid() {
        let split = TransactionSplit(transactionId: "t1", expectedTotal: 150, allocations: [])
        #expect(!split.isBalanced())
        #expect(!split.isValid)
    }

    @Test("evenSplit divides the parent exactly across two categories")
    func evenSplitIsBalanced() {
        let parent = tx("t1", 75.01, "2026-06-04", .shopping)
        let split = TransactionSplit.evenSplit(of: parent, between: .foodAndDrink, and: .homeImprovement)
        #expect(split.allocations.count == 2)
        // The two parts sum back to the parent to the cent (the first part absorbs
        // the rounding remainder).
        #expect(abs(split.allocatedTotal - 75.01) < 0.005)
        #expect(split.isValid)
    }

    @Test("A refund (negative parent) splits with negative parts")
    func negativeParentSplits() {
        let parent = tx("t1", -50, "2026-06-04", .shopping)
        let split = TransactionSplit(
            splitting: parent,
            into: [
                TransactionSplitAllocation(category: .foodAndDrink, amount: -30),
                TransactionSplitAllocation(category: .homeImprovement, amount: -20),
            ]
        )
        #expect(split.allocatedTotal == -50)
        #expect(split.isValid)
    }

    // MARK: - Resolver: additive expansion

    @Test("No split yields exactly one row identical to the parent")
    func noSplitYieldsParentRow() throws {
        let parent = tx("t1", 150, "2026-06-04", .shopping)
        let rows = TransactionSplitResolver.spendRows(from: [parent], splits: [])
        #expect(rows.count == 1)
        let row = try #require(rows.first)
        #expect(row.id == "t1")
        #expect(row.amount == 150)
        #expect(row.category == .shopping)
        #expect(!row.isSplitAllocation)
        #expect(!row.isSplitExcluded)
        #expect(row.date == "2026-06-04")
    }

    @Test("A valid split yields one row per allocation, none for the parent")
    func validSplitYieldsAllocationRows() {
        let parent = tx("t1", 150, "2026-06-04", .shopping)
        let split = TransactionSplit(
            splitting: parent,
            into: [
                TransactionSplitAllocation(category: .foodAndDrink, amount: 90),
                TransactionSplitAllocation(category: .homeImprovement, amount: 60, excludedFromBudgets: true),
            ]
        )
        let rows = TransactionSplitResolver.spendRows(from: [parent], splits: [split])
        #expect(rows.count == 2)
        let allAllocations = rows.allSatisfy { $0.isSplitAllocation }
        #expect(allAllocations)
        // Each row carries its own category + amount + exclude flag.
        #expect(rows[0].category == .foodAndDrink)
        #expect(rows[0].amount == 90)
        #expect(!rows[0].isSplitExcluded)
        #expect(rows[1].category == .homeImprovement)
        #expect(rows[1].amount == 60)
        #expect(rows[1].isSplitExcluded)
        // Rows have unique ids namespaced under the parent.
        #expect(Set(rows.map(\.id)).count == 2)
        let allPrefixed = rows.allSatisfy { $0.id.hasPrefix("t1#") }
        #expect(allPrefixed)
    }

    @Test("A malformed (unbalanced) split falls back to the single parent row")
    func malformedSplitFallsBackToParent() {
        let parent = tx("t1", 150, "2026-06-04", .shopping)
        let badSplit = TransactionSplit(
            splitting: parent,
            into: [TransactionSplitAllocation(category: .foodAndDrink, amount: 90)] // 90 != 150
        )
        let rows = TransactionSplitResolver.spendRows(from: [parent], splits: [badSplit])
        #expect(rows.count == 1)
        #expect(rows[0].category == .shopping) // parent category, not the bad allocation
        #expect(rows[0].amount == 150)
        #expect(!rows[0].isSplitAllocation)
    }

    // MARK: - Split-aware spend: rollups count parts, not the parent

    @Test("Override-aware spend buckets each allocation under its own category")
    func splitSpendCountsParts() {
        let parent = tx("t1", 150, "2026-06-04", .shopping)
        let split = TransactionSplit(
            splitting: parent,
            into: [
                TransactionSplitAllocation(category: .foodAndDrink, amount: 90),
                TransactionSplitAllocation(category: .homeImprovement, amount: 60),
            ]
        )

        let spend = CategoryBudgetPlanner.overrideAwareSpend(
            transactions: [parent],
            month: "2026-06",
            splits: [split],
            calendar: calendar
        )

        // The parent's own SHOPPING bucket is gone; the two parts are counted.
        #expect(spend[.shopping] == nil)
        #expect(spend[.foodAndDrink] == 90)
        #expect(spend[.homeImprovement] == 60)
        // Total spend is conserved (the sum invariant): 90 + 60 == the parent 150.
        #expect(spend.values.reduce(0, +) == 150)
    }

    @Test("A per-allocation exclude flag drops just that part, keeping the rest")
    func splitAllocationExcludeIsHonored() {
        let parent = tx("t1", 150, "2026-06-04", .shopping)
        let split = TransactionSplit(
            splitting: parent,
            into: [
                TransactionSplitAllocation(category: .foodAndDrink, amount: 90),
                TransactionSplitAllocation(category: .homeImprovement, amount: 60, excludedFromBudgets: true),
            ]
        )

        let spend = CategoryBudgetPlanner.overrideAwareSpend(
            transactions: [parent],
            month: "2026-06",
            splits: [split],
            calendar: calendar
        )

        #expect(spend[.foodAndDrink] == 90)
        // The excluded part contributes nothing, even though its category is valid.
        #expect(spend[.homeImprovement] == nil)
        #expect(spend.values.reduce(0, +) == 90)
    }

    @Test("A split into a transfer/income category never counts as spend")
    func splitIntoExcludedCategoryDropsOut() {
        let parent = tx("t1", 200, "2026-06-04", .shopping)
        let split = TransactionSplit(
            splitting: parent,
            into: [
                TransactionSplitAllocation(category: .foodAndDrink, amount: 120),
                TransactionSplitAllocation(category: .transfer, amount: 80), // own-account move
            ]
        )

        let spend = CategoryBudgetPlanner.overrideAwareSpend(
            transactions: [parent],
            month: "2026-06",
            splits: [split],
            calendar: calendar
        )

        #expect(spend[.foodAndDrink] == 120)
        #expect(spend[.transfer] == nil) // transfers are never spend
    }

    // MARK: - Editing/removing a split restores the original

    @Test("Removing the split restores the parent's original single-category spend")
    func removingSplitRestoresOriginal() {
        let parent = tx("t1", 150, "2026-06-04", .shopping)
        let split = TransactionSplit(
            splitting: parent,
            into: [
                TransactionSplitAllocation(category: .foodAndDrink, amount: 90),
                TransactionSplitAllocation(category: .homeImprovement, amount: 60),
            ]
        )

        // With the split, spend is split across two categories.
        let withSplit = CategoryBudgetPlanner.overrideAwareSpend(
            transactions: [parent], month: "2026-06", splits: [split], calendar: calendar
        )
        #expect(withSplit[.shopping] == nil)

        // Remove the split (pass none) → identical to never having split.
        let withoutSplit = CategoryBudgetPlanner.overrideAwareSpend(
            transactions: [parent], month: "2026-06", splits: [], calendar: calendar
        )
        let original = CategoryBudgetPlanner.overrideAwareSpend(
            transactions: [parent], month: "2026-06", calendar: calendar
        )
        #expect(withoutSplit == original)
        #expect(withoutSplit[.shopping] == 150)
        #expect(withoutSplit[.foodAndDrink] == nil)
    }

    @Test("replacingAllocations re-balances against the same expected total")
    func replacingAllocationsRebalances() {
        let parent = tx("t1", 150, "2026-06-04", .shopping)
        let split = TransactionSplit(
            splitting: parent,
            into: [TransactionSplitAllocation(category: .foodAndDrink, amount: 150)]
        )
        #expect(split.isValid)
        let edited = split.replacingAllocations([
            TransactionSplitAllocation(category: .foodAndDrink, amount: 100),
            TransactionSplitAllocation(category: .travel, amount: 50),
        ])
        #expect(edited.expectedTotal == 150)
        #expect(edited.isValid)
        #expect(edited.allocations.count == 2)
    }

    // MARK: - v1-safety: no split = byte-identical across consumers

    @Test("With no splits, override-aware spend is byte-identical to the no-split call")
    func noSplitSpendIsByteIdentical() {
        let transactions = [
            tx("t1", 150, "2026-06-04", .shopping),
            tx("t2", 40, "2026-06-05", .foodAndDrink),
            tx("t3", -1000, "2026-06-06", .income, name: "Payroll"),
        ]
        let metadata = [TransactionReviewMetadata(id: "t1", userCategory: .travel)]

        let withEmptySplits = CategoryBudgetPlanner.overrideAwareSpend(
            transactions: transactions, month: "2026-06", metadata: metadata, splits: [], calendar: calendar
        )
        let withoutSplitsParam = CategoryBudgetPlanner.overrideAwareSpend(
            transactions: transactions, month: "2026-06", metadata: metadata, calendar: calendar
        )
        #expect(withEmptySplits == withoutSplitsParam)
        // And the override still moves t1's spend (no split interferes).
        #expect(withEmptySplits[.travel] == 150)
        #expect(withEmptySplits[.foodAndDrink] == 40)
        #expect(withEmptySplits[.income] == nil)
    }

    @Test("SpendingSummary.spendingByCategory is split-aware and unchanged without splits")
    func summaryIsSplitAware() {
        let parent = tx("t1", 150, "2026-06-04", .shopping)
        let split = TransactionSplit(
            splitting: parent,
            into: [
                TransactionSplitAllocation(category: .foodAndDrink, amount: 90),
                TransactionSplitAllocation(category: .homeImprovement, amount: 60),
            ]
        )

        // Without splits → one SHOPPING bucket of 150 (legacy).
        let legacy = SpendingSummary.spendingByCategory(from: [parent])
        #expect(legacy.count == 1)
        #expect(legacy.first?.0 == .shopping)
        #expect(legacy.first?.1 == 150)

        // With the split → two buckets, parts counted, total conserved.
        let split150 = SpendingSummary.spendingByCategory(from: [parent], splits: [split])
        let byCategory = Dictionary(uniqueKeysWithValues: split150)
        #expect(byCategory[.shopping] == nil)
        #expect(byCategory[.foodAndDrink] == 90)
        #expect(byCategory[.homeImprovement] == 60)
        #expect(split150.reduce(0) { $0 + $1.1 } == 150)
    }

    @Test("A transfer/income split allocation is excluded from the summary (budget parity)")
    func transferSplitAllocationIsExcludedFromSummary() {
        // One purchase split into a real spend part, a transfer part, and an
        // income part. Only the spend part should count — mirroring
        // `CategoryBudgetPlanner.netSpendByCategory`, whose split branch drops
        // `excludedCategories = [.income, .transfer, .transferOut]`.
        let parent = tx("t1", 150, "2026-06-04", .shopping)
        let split = TransactionSplit(
            splitting: parent,
            into: [
                TransactionSplitAllocation(category: .foodAndDrink, amount: 90),
                TransactionSplitAllocation(category: .transfer, amount: 40),
                TransactionSplitAllocation(category: .income, amount: 20),
            ]
        )

        // Legacy path (no metadata/rules): transfer/income allocations drop out.
        let legacy = SpendingSummary.spendingByCategory(from: [parent], splits: [split])
        let legacyByCategory = Dictionary(uniqueKeysWithValues: legacy)
        #expect(legacyByCategory[.foodAndDrink] == 90)
        #expect(legacyByCategory[.transfer] == nil)
        #expect(legacyByCategory[.income] == nil)
        #expect(legacy.reduce(0) { $0 + $1.1 } == 90)

        // Override path (metadata supplied): same exclusion — the split
        // allocation bypasses per-parent resolution but still drops transfers.
        let override = SpendingSummary.spendingByCategory(
            from: [parent],
            metadata: [],
            splits: [split]
        )
        let overrideByCategory = Dictionary(uniqueKeysWithValues: override)
        #expect(overrideByCategory[.foodAndDrink] == 90)
        #expect(overrideByCategory[.transfer] == nil)
        #expect(overrideByCategory[.income] == nil)
        #expect(override.reduce(0) { $0 + $1.1 } == 90)
    }

    // MARK: - Exports respect splits

    @Test("splitsCSV emits one row per allocation, joined by transaction_id")
    func splitsCSVEmitsPerAllocationRows() {
        let parent = tx("t1", 150, "2026-06-04", .shopping)
        let split = TransactionSplit(
            splitting: parent,
            into: [
                TransactionSplitAllocation(category: .foodAndDrink, amount: 90),
                TransactionSplitAllocation(category: .homeImprovement, amount: 60, excludedFromBudgets: true),
            ]
        )
        let csv = DataExportBuilder.splitsCSV([split])
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: true)
        // header + 2 allocation rows
        #expect(lines.count == 3)
        #expect(lines[1].contains("t1"))
        #expect(lines[1].contains("FOOD_AND_DRINK"))
        #expect(lines[1].contains("90.00"))
        #expect(lines[2].contains("HOME_IMPROVEMENT"))
        #expect(lines[2].contains("true")) // the excluded flag
    }

    @Test("The JSON envelope carries splits and round-trips them")
    func envelopeRoundTripsSplits() throws {
        let parent = tx("t1", 150, "2026-06-04", .shopping)
        let split = TransactionSplit(
            splitting: parent,
            into: [
                TransactionSplitAllocation(category: .foodAndDrink, amount: 90),
                TransactionSplitAllocation(category: .homeImprovement, amount: 60),
            ]
        )
        let data = try DataExportBuilder.combinedJSON(
            accounts: [],
            transactions: [parent],
            balanceHistory: [],
            splits: [split],
            exportedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(DataExportBuilder.Envelope.self, from: data)
        #expect(envelope.schemaVersion == 3)
        #expect(envelope.counts.splits == 1)
        #expect(envelope.splits.count == 1)
        #expect(envelope.splits.first?.transactionId == "t1")
        #expect(envelope.splits.first?.allocations.count == 2)
        #expect(envelope.splits.first?.isValid == true)
    }

    @Test("A v2 envelope without splits decodes as empty (backward compatible)")
    func decodesV2EnvelopeWithoutSplits() throws {
        // A schemaVersion-2 backup written before AND-550 has no `splits` key and no
        // `counts.splits`. It must still decode cleanly with empty splits.
        let legacyJSON = """
        {
          "schemaVersion": 2,
          "exportedAt": "2026-06-24T00:00:00Z",
          "environment": "sandbox",
          "counts": { "accounts": 0, "transactions": 0, "balanceHistory": 0, "budgets": 0 },
          "accounts": [],
          "transactions": [],
          "balanceHistory": [],
          "budgets": []
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(
            DataExportBuilder.Envelope.self,
            from: Data(legacyJSON.utf8)
        )
        #expect(envelope.schemaVersion == 2)
        #expect(envelope.splits.isEmpty)
        #expect(envelope.counts.splits == 0)
    }
}
