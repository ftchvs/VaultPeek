import Foundation
import Testing
@testable import PlaidBarCore

@Suite("FinanceSnapshot spending fields (AND-586)")
struct FinanceSnapshotSpendingTests {
    private let asOf = Date(timeIntervalSince1970: 1_780_000_000)

    @Test("A pre-AND-586 snapshot (no spending keys) decodes with empty defaults")
    func decodesLegacySnapshotWithoutSpendingKeys() throws {
        // A snapshot JSON written by an older build had no `periodSpending` /
        // `topSpendingCategories` keys. It must still decode, defaulting them.
        let legacyJSON = """
        {
          "safeToSpend": 1000,
          "totalBalance": 5000,
          "accountBalances": [],
          "nextRecurringBills": [],
          "isoCurrencyCode": "USD",
          "generatedAt": "2026-05-28T00:00:00Z",
          "isMasked": false
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(FinanceSnapshot.self, from: Data(legacyJSON.utf8))
        #expect(snapshot.periodSpending == 0)
        #expect(snapshot.topSpendingCategories.isEmpty)
        #expect(snapshot.totalBalance == 5_000)
    }

    @Test("Spending fields round-trip through Codable")
    func spendingFieldsRoundTrip() throws {
        let snapshot = FinanceSnapshot(
            safeToSpend: 1_000,
            totalBalance: 5_000,
            accountBalances: [],
            nextRecurringBills: [],
            creditUtilization: nil,
            generatedAt: asOf,
            isMasked: false,
            periodSpending: 640,
            topSpendingCategories: [
                FinanceSnapshot.CategorySpend(category: .foodAndDrink, amount: 400),
            ]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(FinanceSnapshot.self, from: encoder.encode(snapshot))
        #expect(decoded == snapshot)
        #expect(decoded.topSpendingCategories.first?.category == .foodAndDrink)
    }

    @Test("A spending-only snapshot is non-empty so intents answer it")
    func spendingOnlySnapshotIsNonEmpty() {
        let snapshot = FinanceSnapshot(
            safeToSpend: 0,
            totalBalance: 0,
            accountBalances: [],
            nextRecurringBills: [],
            creditUtilization: nil,
            generatedAt: asOf,
            isMasked: false,
            periodSpending: 250,
            topSpendingCategories: [FinanceSnapshot.CategorySpend(category: .travel, amount: 250)]
        )
        #expect(!snapshot.isEmpty)
    }

    @Test("CategorySpend recovers its SpendingCategory from the stored key")
    func categorySpendRecoversCategory() {
        let row = FinanceSnapshot.CategorySpend(category: .billsAndUtilities, amount: 100)
        #expect(row.categoryKey == SpendingCategory.billsAndUtilities.rawValue)
        #expect(row.category == .billsAndUtilities)
        // An unknown key decodes to a nil category (forward-compat), not a crash.
        let unknown = FinanceSnapshot.CategorySpend(categoryKey: "FUTURE_CATEGORY", displayName: "Future", amount: 5)
        #expect(unknown.category == nil)
    }
}
