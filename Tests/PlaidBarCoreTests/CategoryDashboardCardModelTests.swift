import Foundation
import Testing
@testable import PlaidBarCore

@Suite("CategoryDashboardCardModel top-N + headline prep (AND-539)")
struct CategoryDashboardCardModelTests {
    // MARK: - Fixtures

    /// A group rollup with a single leaf of the given spend and optional limit.
    private func group(
        _ group: CategoryGroup,
        leaf category: SpendingCategory,
        spent: Double,
        limit: Double? = nil
    ) -> CategoryDashboardPresentation.GroupRollup {
        CategoryDashboardPresentation.GroupRollup(
            group: group,
            leaves: [CategoryDashboardPresentation.Leaf(category: category, spent: spent, monthlyLimit: limit)]
        )
    }

    private func presentation(_ groups: [CategoryDashboardPresentation.GroupRollup]) -> CategoryDashboardPresentation {
        CategoryDashboardPresentation(groups: groups)
    }

    // MARK: - Empty / first run

    @Test("empty presentation yields an empty card with no top groups or overflow")
    func emptyIsEmpty() {
        let model = CategoryDashboardCardModel(presentation: .empty)
        #expect(model.isEmpty)
        #expect(model.topGroups.isEmpty)
        #expect(model.overflowCount == 0)
        #expect(model.overflowText == nil)
        #expect(!model.hasAttention)
        // An unbudgeted empty month never claims "on track".
        #expect(model.attentionSummary(isBudgeted: false) == nil)
    }

    // MARK: - Top-N selection

    @Test("top groups are the spend-heaviest, capped to the limit")
    func topGroupsHeaviestFirst() {
        let p = presentation([
            group(.shopping, leaf: .shopping, spent: 100),
            group(.foodAndDining, leaf: .foodAndDrink, spent: 400),
            group(.transportation, leaf: .transportation, spent: 250),
            group(.entertainment, leaf: .entertainment, spent: 50),
        ])
        let model = CategoryDashboardCardModel(presentation: p, topGroupLimit: 3)
        #expect(model.topGroups.map(\.group) == [.foodAndDining, .transportation, .shopping])
        #expect(model.overflowCount == 1)
        #expect(model.overflowText == "+1 more")
    }

    @Test("equal-spend groups break ties on canonical order (deterministic)")
    func equalSpendTiebreak() {
        // foodAndDining (sortIndex 2) precedes shopping (sortIndex 4) at equal spend.
        let p = presentation([
            group(.shopping, leaf: .shopping, spent: 200),
            group(.foodAndDining, leaf: .foodAndDrink, spent: 200),
        ])
        let model = CategoryDashboardCardModel(presentation: p, topGroupLimit: 1)
        #expect(model.topGroups.map(\.group) == [.foodAndDining])
        #expect(model.overflowCount == 1)
    }

    @Test("a budgeted-but-unspent group never displaces a group with real spend")
    func unspentGroupDoesNotRank() {
        let p = presentation([
            group(.foodAndDining, leaf: .foodAndDrink, spent: 300),
            // Budgeted guardrail with zero spend — present in the tree, but not a "top
            // spending group" and never counted in overflow.
            group(.healthAndWellness, leaf: .healthAndFitness, spent: 0, limit: 200),
        ])
        let model = CategoryDashboardCardModel(presentation: p, topGroupLimit: 3)
        #expect(model.topGroups.map(\.group) == [.foodAndDining])
        #expect(model.overflowCount == 0)
        #expect(model.overflowText == nil)
    }

    @Test("a zero or negative top-group limit shows the donut only, all overflow")
    func zeroLimitClamps() {
        let p = presentation([
            group(.foodAndDining, leaf: .foodAndDrink, spent: 300),
            group(.shopping, leaf: .shopping, spent: 100),
        ])
        let model = CategoryDashboardCardModel(presentation: p, topGroupLimit: 0)
        #expect(model.topGroups.isEmpty)
        #expect(model.overflowCount == 2)
        let negative = CategoryDashboardCardModel(presentation: p, topGroupLimit: -5)
        #expect(negative.topGroups.isEmpty)
        #expect(negative.overflowCount == 2)
    }

    // MARK: - Headline / attention summary

    @Test("total spent text matches the donut center total")
    func totalMatchesDonut() {
        let p = presentation([
            group(.foodAndDining, leaf: .foodAndDrink, spent: 300),
            group(.shopping, leaf: .shopping, spent: 200),
        ])
        let model = CategoryDashboardCardModel(presentation: p)
        #expect(model.totalSpentText == model.donut.totalText)
        #expect(model.donut.total == 500)
    }

    @Test("attention summary counts over and nearing leaves, never by color")
    func attentionSummaryText() {
        let p = presentation([
            // 250/200 -> over
            group(.foodAndDining, leaf: .foodAndDrink, spent: 250, limit: 200),
            // 90/100 -> nearing (>= 80%)
            group(.shopping, leaf: .shopping, spent: 90, limit: 100),
        ])
        let model = CategoryDashboardCardModel(presentation: p)
        #expect(model.overBudgetCount == 1)
        #expect(model.nearingCount == 1)
        #expect(model.hasAttention)
        #expect(model.attentionSummary(isBudgeted: true) == "1 over budget · 1 nearing")
    }

    @Test("a fully on-track budgeted month reads 'On track'")
    func onTrackSummary() {
        let p = presentation([
            group(.foodAndDining, leaf: .foodAndDrink, spent: 50, limit: 200),
        ])
        let model = CategoryDashboardCardModel(presentation: p)
        #expect(!model.hasAttention)
        #expect(model.attentionSummary(isBudgeted: true) == "On track")
        // Without a budget context the card omits the line entirely.
        #expect(model.attentionSummary(isBudgeted: false) == nil)
    }

    @Test("currency code flows into the donut and headline formatting")
    func currencyCodeFlows() {
        let p = presentation([group(.foodAndDining, leaf: .foodAndDrink, spent: 300)])
        let model = CategoryDashboardCardModel(presentation: p, currencyCode: "EUR")
        #expect(model.currencyCode == "EUR")
        #expect(model.donut.currencyCode == "EUR")
    }
}
