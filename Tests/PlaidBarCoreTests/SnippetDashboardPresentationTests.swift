import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Snippet / large-widget mini-dashboard (AND-586)")
struct SnippetDashboardPresentationTests {
    private let asOf = Date(timeIntervalSince1970: 1_780_000_000)

    @Test("Data snapshot yields the three headline metric rows + categories")
    func dataSnapshotRows() {
        let model = SnippetDashboardPresentation.model(from: dataSnapshot())
        #expect(!model.isWithheld)
        #expect(model.rows.count == 3)
        #expect(model.rows.map(\.id) == ["total-balance", "safe-to-spend", "period-spending"])
        #expect(model.categories.count == 2)
        // The headline leads with net balance.
        #expect(model.headline.lowercased().contains("balance"))
    }

    @Test("Categories are truncated to the documented maximum")
    func categoriesTruncated() {
        let many = (0..<6).map { index in
            FinanceSnapshot.CategorySpend(categoryKey: "K\(index)", displayName: "Cat\(index)", amount: Double(index))
        }
        let model = SnippetDashboardPresentation.model(from: dataSnapshot(categories: many))
        #expect(model.categories.count == SnippetDashboardPresentation.maxCategories)
    }

    @Test("Masked snapshot withholds every figure with the dot placeholder")
    func maskedWithholds() {
        let model = SnippetDashboardPresentation.model(from: dataSnapshot(isMasked: true))
        #expect(model.isWithheld)
        // No real figure leaks: every row value is the masked dot placeholder, and
        // no category rows are emitted.
        for row in model.rows {
            #expect(row.value == PrivacyMaskPresentation.compactValue)
        }
        #expect(model.categories.isEmpty)
        #expect(!model.accessibilityLabel.contains("8,000"))
    }

    @Test("Nil snapshot shows the setup/unavailable state")
    func nilSnapshotUnavailable() {
        let model = SnippetDashboardPresentation.model(from: nil)
        #expect(model.isWithheld)
        #expect(model.rows.isEmpty)
        #expect(model.headline.lowercased().contains("open vaultpeek"))
    }

    @Test("Empty snapshot shows the setup state, not a misleading $0 dashboard")
    func emptySnapshotUnavailable() {
        let model = SnippetDashboardPresentation.model(from: .placeholder(generatedAt: asOf))
        #expect(model.isWithheld)
        #expect(model.rows.isEmpty)
    }

    // MARK: - Helpers

    private func dataSnapshot(
        isMasked: Bool = false,
        categories: [FinanceSnapshot.CategorySpend]? = nil
    ) -> FinanceSnapshot {
        FinanceSnapshot(
            safeToSpend: 1_200,
            totalBalance: 8_000,
            accountBalances: [FinanceSnapshot.AccountBalance(displayName: "Checking", balance: 8_000)],
            nextRecurringBills: [],
            creditUtilization: 22,
            generatedAt: asOf,
            isMasked: isMasked,
            periodSpending: 540,
            topSpendingCategories: categories ?? [
                FinanceSnapshot.CategorySpend(category: .foodAndDrink, amount: 320),
                FinanceSnapshot.CategorySpend(category: .shopping, amount: 180),
            ]
        )
    }
}
