import Foundation
import Testing
@testable import PlaidBarCore

@Suite("SpendDonutModel slice + label prep (AND-537)")
struct SpendDonutModelTests {
    // MARK: - Fixtures

    /// A group rollup with a single leaf of the given spend (no budget).
    private func group(_ group: CategoryGroup, leaf category: SpendingCategory, spent: Double) -> CategoryDashboardPresentation.GroupRollup {
        CategoryDashboardPresentation.GroupRollup(
            group: group,
            leaves: [CategoryDashboardPresentation.Leaf(category: category, spent: spent, monthlyLimit: nil)]
        )
    }

    private func presentation(_ groups: [CategoryDashboardPresentation.GroupRollup]) -> CategoryDashboardPresentation {
        CategoryDashboardPresentation(groups: groups)
    }

    // MARK: - Construction / totals

    @Test("empty presentation yields an empty donut")
    func emptyIsEmpty() {
        let model = SpendDonutModel(presentation: .empty)
        #expect(model.isEmpty)
        #expect(model.slices.isEmpty)
        #expect(model.total == 0)
        #expect(model.sliceCount == 0)
    }

    @Test("total equals the sum of slice spend and matches the presentation total")
    func totalSumsSlices() {
        let p = presentation([
            group(.foodAndDining, leaf: .foodAndDrink, spent: 300),
            group(.shopping, leaf: .shopping, spent: 100),
            group(.transportation, leaf: .transportation, spent: 100),
        ])
        let model = SpendDonutModel(presentation: p)
        #expect(model.total == 500)
        #expect(model.total == p.totalSpent)
        #expect(model.slices.reduce(0) { $0 + $1.amount } == 500)
    }

    // MARK: - Ordering

    @Test("slices are ordered spend-heaviest first")
    func sortedBySpendDescending() {
        let p = presentation([
            group(.shopping, leaf: .shopping, spent: 100),
            group(.foodAndDining, leaf: .foodAndDrink, spent: 400),
            group(.transportation, leaf: .transportation, spent: 250),
        ])
        let model = SpendDonutModel(presentation: p)
        #expect(model.slices.map(\.group) == [.foodAndDining, .transportation, .shopping])
    }

    @Test("equal-spend groups break ties on canonical display order (deterministic)")
    func equalSpendTiebreak() {
        // foodAndDining (sortIndex 2) precedes shopping (sortIndex 4) at equal spend.
        let p = presentation([
            group(.shopping, leaf: .shopping, spent: 200),
            group(.foodAndDining, leaf: .foodAndDrink, spent: 200),
        ])
        let model = SpendDonutModel(presentation: p)
        #expect(model.slices.map(\.group) == [.foodAndDining, .shopping])
    }

    // MARK: - Shares

    @Test("slice fractions are spend / total and sum to ~1")
    func fractionsSumToOne() {
        let p = presentation([
            group(.foodAndDining, leaf: .foodAndDrink, spent: 300),
            group(.shopping, leaf: .shopping, spent: 100),
        ])
        let model = SpendDonutModel(presentation: p)
        let food = try! #require(model.slices.first { $0.group == .foodAndDining })
        #expect(abs(food.fraction - 0.75) < 1e-9)
        #expect(abs(model.slices.reduce(0) { $0 + $1.fraction } - 1.0) < 1e-9)
    }

    @Test("share text is whole-percent")
    func shareTextWholePercent() {
        #expect(SpendDonutModel.shareText(0.3412) == "34%")
        #expect(SpendDonutModel.shareText(0.5) == "50%")
        #expect(SpendDonutModel.shareText(1.0) == "100%")
    }

    @Test("a tiny but present share floors to <1%, never 0%")
    func tinyShareNeverZero() {
        let p = presentation([
            group(.foodAndDining, leaf: .foodAndDrink, spent: 1000),
            group(.shopping, leaf: .shopping, spent: 1), // ~0.0999%
        ])
        let model = SpendDonutModel(presentation: p)
        let shopping = try! #require(model.slices.first { $0.group == .shopping })
        #expect(shopping.shareText == "<1%")
        #expect(shopping.shareText != "0%")
    }

    // MARK: - Labels (color-independent)

    @Test("each slice label carries group title, amount, and share as text")
    func sliceLabelCarriesTextMeaning() {
        let p = presentation([
            group(.foodAndDining, leaf: .foodAndDrink, spent: 420),
            group(.shopping, leaf: .shopping, spent: 580),
        ])
        let model = SpendDonutModel(presentation: p)
        let food = try! #require(model.slices.first { $0.group == .foodAndDining })
        #expect(food.title == "Food & Dining")
        #expect(food.amountText == "$420.00")
        #expect(food.shareText == "42%")
        #expect(food.label == "Food & Dining, $420.00, 42%")
    }

    @Test("center total text is the formatted overall spend")
    func centerTotalText() {
        let p = presentation([
            group(.foodAndDining, leaf: .foodAndDrink, spent: 1200),
            group(.shopping, leaf: .shopping, spent: 34),
        ])
        let model = SpendDonutModel(presentation: p)
        #expect(model.totalText == "$1,234.00")
        #expect(model.centerCaption == "Spent this month")
    }

    @Test("currency code threads through every formatted amount")
    func currencyCodeThreads() {
        let p = presentation([group(.foodAndDining, leaf: .foodAndDrink, spent: 100)])
        let model = SpendDonutModel(presentation: p, currencyCode: "EUR")
        #expect(model.currencyCode == "EUR")
        // EUR formatting differs from USD ("$"); just assert it isn't a dollar string.
        #expect(!model.totalText.contains("$"))
    }

    // MARK: - Accessibility

    @Test("empty donut has a spoken no-spending summary")
    func emptyAccessibilityLabel() {
        let model = SpendDonutModel(presentation: .empty)
        #expect(model.accessibilityLabel == "Spending by category. No spending this month.")
    }

    @Test("accessibility label names the total and every slice's breakdown")
    func accessibilityLabelDescribesEverySlice() {
        let p = presentation([
            group(.foodAndDining, leaf: .foodAndDrink, spent: 300),
            group(.shopping, leaf: .shopping, spent: 100),
        ])
        let model = SpendDonutModel(presentation: p)
        let label = model.accessibilityLabel
        #expect(label.contains("$400.00"))
        #expect(label.contains("2 groups"))
        #expect(label.contains("Food & Dining, $300.00, 75%"))
        #expect(label.contains("Shopping, $100.00, 25%"))
    }

    @Test("single-slice accessibility label uses singular 'group'")
    func singularGroupGrammar() {
        let p = presentation([group(.foodAndDining, leaf: .foodAndDrink, spent: 100)])
        let model = SpendDonutModel(presentation: p)
        #expect(model.accessibilityLabel.contains("1 group."))
        #expect(!model.accessibilityLabel.contains("1 groups"))
    }
}
