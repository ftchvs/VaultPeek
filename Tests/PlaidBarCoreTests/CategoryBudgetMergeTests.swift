import Foundation
@testable import PlaidBarCore
import Testing

/// Covers the merge/aggregate logic lifted out of AppState in Step 3:
/// `CategoryBudgetPresentation(items:)`, `CategoryBudgetPlanner.merge`, and the
/// `mergedPresentation` composition.
@Suite("Category budget merge")
struct CategoryBudgetMergeTests {
    private let now = Formatters.parseTransactionDate("2026-06-13")!
    private let calendar = Calendar(identifier: .gregorian)

    private func tx(_ amount: Double, _ date: String, _ category: SpendingCategory) -> TransactionDTO {
        TransactionDTO(
            id: "\(category.rawValue)-\(date)-\(amount)",
            accountId: "acct",
            amount: amount,
            date: date,
            name: "Merchant",
            category: category,
            pending: false
        )
    }

    private func item(
        _ category: SpendingCategory,
        limit: Double,
        spent: Double,
        suggested: Bool
    ) -> CategoryBudgetPresentation.Item {
        CategoryBudgetPresentation.Item(
            category: category,
            monthlyLimit: limit,
            spent: spent,
            isSuggested: suggested
        )
    }

    // MARK: - Convenience init derives aggregates

    @Test("Presentation(items:) derives totals and counts from its items")
    func convenienceInitTotals() {
        let presentation = CategoryBudgetPresentation(items: [
            item(.foodAndDrink, limit: 100, spent: 150, suggested: false), // over
            item(.shopping, limit: 100, spent: 90, suggested: false), // nearing
            item(.travel, limit: 100, spent: 10, suggested: false), // under
        ])
        #expect(presentation.totalLimit == 300)
        #expect(presentation.totalSpent == 250)
        #expect(presentation.overBudgetCount == 1)
        #expect(presentation.nearingCount == 1)
    }

    @Test("Presentation(items:) of no items is empty")
    func convenienceInitEmpty() {
        let presentation = CategoryBudgetPresentation(items: [])
        #expect(presentation.isEmpty)
        #expect(presentation.totalLimit == 0)
        #expect(presentation.totalSpent == 0)
    }

    // MARK: - merge

    @Test("merge: explicit budgets win on identity; suggestions fill the rest")
    func mergeDedup() {
        let explicit = CategoryBudgetPresentation(items: [
            item(.foodAndDrink, limit: 100, spent: 50, suggested: false),
        ])
        let suggested = CategoryBudgetPresentation(items: [
            item(.foodAndDrink, limit: 200, spent: 100, suggested: true), // dropped — explicit wins
            item(.shopping, limit: 100, spent: 10, suggested: true),
        ])
        let merged = CategoryBudgetPlanner.merge(explicit: explicit, suggested: suggested)
        #expect(merged.count == 2)
        let food = merged.items.first { $0.id == SpendingCategory.foodAndDrink.rawValue }
        #expect(food?.isSuggested == false)
        #expect(food?.monthlyLimit == 100) // the explicit limit, not the suggested 200
        let hasShopping = merged.items.contains { $0.id == SpendingCategory.shopping.rawValue }
        #expect(hasShopping)
    }

    @Test("merge: ranks attention-first — over, then nearing, then under")
    func mergeStatusOrder() {
        let explicit = CategoryBudgetPresentation(items: [
            item(.foodAndDrink, limit: 100, spent: 10, suggested: false), // under
        ])
        let suggested = CategoryBudgetPresentation(items: [
            item(.shopping, limit: 100, spent: 150, suggested: true), // over
            item(.travel, limit: 100, spent: 90, suggested: true), // nearing
        ])
        let merged = CategoryBudgetPlanner.merge(explicit: explicit, suggested: suggested)
        let order = merged.items.map(\.category)
        #expect(order == [.shopping, .travel, .foodAndDrink])
    }

    @Test("merge: explicit precedes suggested on a tie, overriding the name fallback")
    func mergeSuggestedTiebreaker() {
        // Same status (under) and fractionUsed (0.5). Names are chosen so the
        // alphabetical fallback ("Education" < "Travel") would reverse the order —
        // proving the explicit-before-suggested tiebreaker wins.
        let explicit = CategoryBudgetPresentation(items: [
            item(.travel, limit: 100, spent: 50, suggested: false),
        ])
        let suggested = CategoryBudgetPresentation(items: [
            item(.education, limit: 200, spent: 100, suggested: true),
        ])
        let merged = CategoryBudgetPlanner.merge(explicit: explicit, suggested: suggested)
        let order = merged.items.map(\.category)
        #expect(order == [.travel, .education])
    }

    // MARK: - mergedPresentation (composition)

    @Test("mergedPresentation: no explicit budgets returns suggestions only")
    func mergedNoExplicit() {
        let transactions = [
            tx(300, "2026-03-15", .foodAndDrink),
            tx(300, "2026-04-15", .foodAndDrink),
            tx(300, "2026-05-15", .foodAndDrink),
        ]
        let merged = CategoryBudgetPlanner.mergedPresentation(
            explicitBudgets: [:],
            transactions: transactions,
            asOf: now,
            calendar: calendar
        )
        #expect(!merged.isEmpty)
        let allSuggested = merged.items.allSatisfy(\.isSuggested)
        #expect(allSuggested)
    }

    @Test("mergedPresentation: an explicit budget replaces its suggestion and is not flagged suggested")
    func mergedExplicitOverridesSuggestion() {
        let transactions = [
            // Trailing history seeds suggestions for food (~300) and shopping (~200).
            tx(300, "2026-03-15", .foodAndDrink),
            tx(300, "2026-04-15", .foodAndDrink),
            tx(300, "2026-05-15", .foodAndDrink),
            tx(200, "2026-03-10", .shopping),
            tx(200, "2026-04-10", .shopping),
            tx(200, "2026-05-10", .shopping),
            // Current-month spend on the explicitly-budgeted category.
            tx(50, "2026-06-05", .foodAndDrink),
        ]
        let merged = CategoryBudgetPlanner.mergedPresentation(
            explicitBudgets: [.foodAndDrink: 400],
            transactions: transactions,
            asOf: now,
            calendar: calendar
        )
        let food = merged.items.first { $0.id == SpendingCategory.foodAndDrink.rawValue }
        #expect(food?.isSuggested == false) // explicit, not the dropped suggestion
        #expect(food?.monthlyLimit == 400)
        #expect(food?.spent == 50)
        // foodAndDrink appears exactly once — its suggestion was de-duped.
        let foodCount = merged.items.filter { $0.id == SpendingCategory.foodAndDrink.rawValue }.count
        #expect(foodCount == 1)
        // Shopping has no explicit budget, so it stays a suggestion.
        let shopping = merged.items.first { $0.id == SpendingCategory.shopping.rawValue }
        #expect(shopping?.isSuggested == true)
    }
}
