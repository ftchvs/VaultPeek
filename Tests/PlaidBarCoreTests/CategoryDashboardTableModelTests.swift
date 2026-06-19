import Foundation
import Testing
@testable import PlaidBarCore

@Suite("CategoryDashboardTableModel flat SPENT/BUDGET/LEFT rows (AND-539)")
struct CategoryDashboardTableModelTests {
    // MARK: - Fixtures

    private func leaf(_ category: SpendingCategory, spent: Double, limit: Double? = nil) -> CategoryDashboardPresentation.Leaf {
        CategoryDashboardPresentation.Leaf(category: category, spent: spent, monthlyLimit: limit)
    }

    private func group(_ group: CategoryGroup, _ leaves: [CategoryDashboardPresentation.Leaf]) -> CategoryDashboardPresentation.GroupRollup {
        CategoryDashboardPresentation.GroupRollup(group: group, leaves: leaves)
    }

    private func presentation(_ groups: [CategoryDashboardPresentation.GroupRollup]) -> CategoryDashboardPresentation {
        CategoryDashboardPresentation(groups: groups)
    }

    // MARK: - Flatten

    @Test("flatten produces one row per leaf across all groups")
    func oneRowPerLeaf() {
        let p = presentation([
            group(.foodAndDining, [leaf(.foodAndDrink, spent: 300), leaf(.travel, spent: 80)]),
            group(.shopping, [leaf(.shopping, spent: 120)]),
        ])
        // travel maps to entertainment group, not foodAndDining — use real groupings.
        let rows = CategoryDashboardTableModel.rows(from: p)
        #expect(rows.count == 3)
        #expect(Set(rows.map(\.id)).count == 3)
    }

    @Test("empty presentation yields no rows and zeroed, unbudgeted totals")
    func emptyTable() {
        let rows = CategoryDashboardTableModel.rows(from: .empty)
        #expect(rows.isEmpty)
        let totals = CategoryDashboardTableModel.totals(for: rows)
        #expect(totals.spent == 0)
        #expect(totals.budget == 0)
        #expect(totals.remaining == 0)
        #expect(!totals.hasBudget)
    }

    // MARK: - Ordering

    @Test("spendDescending orders rows heaviest-spend first")
    func spendDescendingOrder() {
        let p = presentation([
            group(.foodAndDining, [leaf(.foodAndDrink, spent: 100)]),
            group(.shopping, [leaf(.shopping, spent: 400)]),
            group(.transportation, [leaf(.transportation, spent: 250)]),
        ])
        let rows = CategoryDashboardTableModel.rows(from: p, order: .spendDescending)
        #expect(rows.map(\.category) == [.shopping, .transportation, .foodAndDrink])
    }

    @Test("groupThenSpend preserves canonical group order then per-group spend order")
    func groupThenSpendOrder() {
        // Within a group the builder hands leaves spend-heaviest first; the model
        // preserves that and keeps groups in canonical display order.
        let p = presentation([
            group(.foodAndDining, [leaf(.foodAndDrink, spent: 300), leaf(.foodAndDrink, spent: 50)]),
            group(.shopping, [leaf(.shopping, spent: 999)]),
        ])
        let rows = CategoryDashboardTableModel.rows(from: p, order: .groupThenSpend)
        // foodAndDining group precedes shopping in canonical order, even though
        // shopping's single leaf outspends both food leaves.
        #expect(rows.first?.group == .foodAndDining)
        #expect(rows.last?.group == .shopping)
    }

    // MARK: - Row columns

    @Test("an unbudgeted row has nil budget / remaining / status and a no-budget verdict")
    func unbudgetedRowColumns() {
        let p = presentation([group(.foodAndDining, [leaf(.foodAndDrink, spent: 120)])])
        let row = CategoryDashboardTableModel.rows(from: p)[0]
        #expect(row.spent == 120)
        #expect(row.budget == nil)
        #expect(row.remaining == nil)
        #expect(row.status == nil)
        #expect(!row.isBudgeted)
        #expect(row.statusText == "No budget")
        #expect(row.statusIconName == "minus.circle")
    }

    @Test("a budgeted row carries budget, remaining, and the correct band")
    func budgetedRowColumns() {
        // 250 spent / 200 limit -> over, remaining -50.
        let p = presentation([group(.foodAndDining, [leaf(.foodAndDrink, spent: 250, limit: 200)])])
        let row = CategoryDashboardTableModel.rows(from: p)[0]
        #expect(row.budget == 200)
        #expect(row.remaining == -50)
        #expect(row.status == .over)
        #expect(row.isBudgeted)
        #expect(row.isOverBudget)
        #expect(row.statusText == "Over budget")
    }

    // MARK: - Footer totals

    @Test("totals sum spent across all rows but budget/remaining only over budgeted rows")
    func totalsBudgetedOnly() {
        let p = presentation([
            group(.foodAndDining, [leaf(.foodAndDrink, spent: 150, limit: 200)]),
            // Unbudgeted: its spend counts toward total spent but NOT toward remaining.
            group(.shopping, [leaf(.shopping, spent: 90)]),
        ])
        let rows = CategoryDashboardTableModel.rows(from: p)
        let totals = CategoryDashboardTableModel.totals(for: rows)
        #expect(totals.spent == 240)      // 150 + 90
        #expect(totals.budget == 200)     // only the budgeted leaf
        #expect(totals.remaining == 50)   // 200 - 150 (unbudgeted 90 excluded)
        #expect(totals.hasBudget)
    }

    @Test("collectively-over budgeted rows yield a negative remaining total")
    func negativeRemaining() {
        let p = presentation([
            group(.foodAndDining, [leaf(.foodAndDrink, spent: 250, limit: 200)]),
            group(.shopping, [leaf(.shopping, spent: 60, limit: 50)]),
        ])
        let rows = CategoryDashboardTableModel.rows(from: p)
        let totals = CategoryDashboardTableModel.totals(for: rows)
        #expect(totals.budget == 250)     // 200 + 50
        #expect(totals.remaining == -60)  // 250 - 310
        #expect(totals.hasBudget)
    }
}
