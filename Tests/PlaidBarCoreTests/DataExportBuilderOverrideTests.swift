import Foundation
@testable import PlaidBarCore
import Testing

/// Tests for the override-aware additions to `DataExportBuilder.transactionsCSV`
/// (AND-527): the CSV `category` column must reflect the *effective* category
/// (user override → rule → raw Plaid → empty) so an exported file matches what the
/// user saw and reviewed in-app, instead of the raw Plaid guess. Passing no
/// metadata/rules (the default) must reproduce the legacy raw-`transaction.category`
/// column so existing importers and tests are unchanged.
///
/// All inputs are synthetic; no real Plaid data.
@Suite("Data Export Builder Override Tests")
struct DataExportBuilderOverrideTests {
    private func tx(
        id: String,
        category: SpendingCategory?,
        name: String = "MERCHANT",
        merchantName: String? = "Merchant",
        pendingTransactionId: String? = nil
    ) -> TransactionDTO {
        TransactionDTO(
            id: id,
            accountId: "acc1",
            amount: 12.34,
            date: "2026-06-15",
            name: name,
            merchantName: merchantName,
            category: category,
            pending: false,
            pendingTransactionId: pendingTransactionId,
            isoCurrencyCode: "USD"
        )
    }

    private func categoryColumn(_ csv: String) -> [String] {
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        // category is the 8th field (index 7) in the declared header order.
        return lines.dropFirst().map { line in
            let fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            return fields.count > 7 ? fields[7] : ""
        }
    }

    // MARK: - Legacy behavior preserved (default nil params)

    @Test("Default (no metadata/rules) writes the raw Plaid category, unchanged")
    func legacyWritesRawCategory() {
        let transactions = [tx(id: "a", category: .shopping)]

        let legacy = DataExportBuilder.transactionsCSV(transactions)
        let explicitNil = DataExportBuilder.transactionsCSV(
            transactions,
            metadata: nil,
            rules: nil
        )

        #expect(legacy == explicitNil)
        // `.shopping` serializes to its Plaid PFCv2 rawValue "GENERAL_MERCHANDISE".
        #expect(categoryColumn(legacy) == ["GENERAL_MERCHANDISE"])
    }

    // MARK: - Override changes the exported category column

    @Test("A user override changes the exported category column")
    func userOverrideChangesColumn() {
        let transactions = [tx(id: "a", category: .shopping)]
        let metadata = [TransactionReviewMetadata(id: "a", userCategory: .foodAndDrink)]

        let csv = DataExportBuilder.transactionsCSV(transactions, metadata: metadata)

        #expect(categoryColumn(csv) == ["FOOD_AND_DRINK"])
    }

    @Test("A matching rule changes the exported category column")
    func ruleChangesColumn() {
        let transactions = [tx(id: "a", category: .shopping, name: "BLUE BOTTLE", merchantName: "Blue Bottle")]
        let rules = [TransactionRule(matchMerchantContains: "Blue Bottle", category: .foodAndDrink)]

        let csv = DataExportBuilder.transactionsCSV(transactions, rules: rules)

        #expect(categoryColumn(csv) == ["FOOD_AND_DRINK"])
    }

    // MARK: - Uncategorized stays empty (no NL leakage)

    @Test("An unapproved NL-suggestable row keeps an empty category column")
    func nlSuggestionDoesNotLeakIntoExport() {
        // Blue Bottle would get an NL suggestion, but with no override/rule and no
        // Plaid category the export must stay blank (suggestions are display-only).
        let transactions = [tx(id: "a", category: nil, name: "BLUE BOTTLE COFFEE", merchantName: nil)]

        let csv = DataExportBuilder.transactionsCSV(transactions, metadata: [], rules: [])

        #expect(categoryColumn(csv) == [""])
    }

    // MARK: - Pending → posted carry-forward

    @Test("Review metadata under a pending id carries into the exported posted row")
    func pendingMetadataCarriesForward() {
        let transactions = [
            tx(id: "posted-1", category: .shopping, pendingTransactionId: "pending-1"),
        ]
        let metadata = [TransactionReviewMetadata(id: "pending-1", userCategory: .foodAndDrink)]

        let csv = DataExportBuilder.transactionsCSV(transactions, metadata: metadata)

        #expect(categoryColumn(csv) == ["FOOD_AND_DRINK"])
    }

    // MARK: - Row count / other columns unchanged

    @Test("Override-aware export keeps one row per transaction and other columns intact")
    func rowCountAndOtherColumnsUnchanged() {
        let transactions = [
            tx(id: "tx1", category: .shopping),
            tx(id: "tx2", category: .foodAndDrink),
        ]
        let metadata = [TransactionReviewMetadata(id: "tx1", userCategory: .travel)]

        let csv = DataExportBuilder.transactionsCSV(transactions, metadata: metadata)
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)

        #expect(lines.count == 3) // header + 2 rows
        #expect(lines[1].hasPrefix("tx1,acc1,2026-06-15,MERCHANT,Merchant,12.34,USD,TRAVEL,false"))
        #expect(lines[2].hasPrefix("tx2,acc1,2026-06-15,MERCHANT,Merchant,12.34,USD,FOOD_AND_DRINK,false"))
    }
}
