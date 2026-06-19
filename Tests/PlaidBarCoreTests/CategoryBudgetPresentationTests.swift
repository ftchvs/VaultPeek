import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Category budget presentation")
struct CategoryBudgetPresentationTests {
    // MARK: Status bands

    @Test("Status bands follow the consumed fraction with an 80% nearing threshold")
    func statusBands() {
        #expect(CategoryBudgetStatus(fractionUsed: 0.5) == .under)
        #expect(CategoryBudgetStatus(fractionUsed: 0.79) == .under)
        #expect(CategoryBudgetStatus(fractionUsed: 0.8) == .nearing)
        #expect(CategoryBudgetStatus(fractionUsed: 1.0) == .nearing)
        #expect(CategoryBudgetStatus(fractionUsed: 1.01) == .over)
        #expect(CategoryBudgetStatus.nearingThreshold == 0.8)
    }

    @Test("Each status band has a non-empty label and distinct icon")
    func statusLabelsAndIcons() {
        for status in CategoryBudgetStatus.allCases {
            #expect(!status.label.isEmpty)
            #expect(!status.iconName.isEmpty)
        }
        let icons = CategoryBudgetStatus.allCases.map(\.iconName)
        #expect(Set(icons).count == icons.count)
    }

    // MARK: Item derivations

    @Test("Item derives remaining, fraction, status, and identity from limit and spend")
    func itemDerivations() {
        let item = CategoryBudgetPresentation.Item(
            category: .foodAndDrink, monthlyLimit: 200, spent: 250, isSuggested: true
        )
        #expect(item.id == "FOOD_AND_DRINK")
        #expect(item.spent == 250)
        #expect(item.remaining == -50)
        #expect(item.fractionUsed == 1.25)
        #expect(item.status == .over)
        #expect(item.isOverBudget)
        #expect(item.needsAttention)
        #expect(item.isSuggested)
    }

    @Test("Negative spend floors at zero")
    func negativeSpendFloors() {
        let item = CategoryBudgetPresentation.Item(
            category: .shopping, monthlyLimit: 100, spent: -30, isSuggested: false
        )
        #expect(item.spent == 0)
        #expect(item.remaining == 100)
        #expect(item.fractionUsed == 0)
        #expect(item.status == .under)
        #expect(!item.needsAttention)
    }

    @Test("A non-positive limit yields a zero fraction rather than dividing by zero")
    func nonPositiveLimit() {
        let item = CategoryBudgetPresentation.Item(
            category: .travel, monthlyLimit: 0, spent: 40, isSuggested: false
        )
        #expect(item.fractionUsed == 0)
        #expect(item.status == .under)
    }

    // MARK: Aggregates

    @Test("Aggregate initializer derives totals and pressure counts from items")
    func aggregateInit() {
        let items = [
            CategoryBudgetPresentation.Item(category: .foodAndDrink, monthlyLimit: 100, spent: 130, isSuggested: false),
            CategoryBudgetPresentation.Item(category: .shopping, monthlyLimit: 100, spent: 85, isSuggested: false),
            CategoryBudgetPresentation.Item(category: .travel, monthlyLimit: 100, spent: 10, isSuggested: false),
        ]
        let presentation = CategoryBudgetPresentation(items: items)
        #expect(presentation.totalLimit == 300)
        #expect(presentation.totalSpent == 225)
        #expect(presentation.overBudgetCount == 1)
        #expect(presentation.nearingCount == 1)
        #expect(presentation.count == 3)
        #expect(!presentation.isEmpty)
    }

    @Test("Empty presentation is empty with zeroed aggregates")
    func emptyPresentation() {
        #expect(CategoryBudgetPresentation.empty.isEmpty)
        #expect(CategoryBudgetPresentation.empty.count == 0)
        #expect(CategoryBudgetPresentation.empty.totalLimit == 0)
        #expect(CategoryBudgetPresentation.empty.overBudgetCount == 0)
    }

    @Test("The explicit initializer preserves supplied aggregates verbatim")
    func explicitInit() {
        let presentation = CategoryBudgetPresentation(
            items: [], totalLimit: 99, totalSpent: 50, overBudgetCount: 2, nearingCount: 3
        )
        #expect(presentation.totalLimit == 99)
        #expect(presentation.totalSpent == 50)
        #expect(presentation.overBudgetCount == 2)
        #expect(presentation.nearingCount == 3)
    }
}
