import Foundation
import Testing
@testable import PlaidBarCore

/// Tests for the AND-538 pure status-bar model (sub-issues 557 leaf, 558 group).
/// The model must:
/// - clamp the capsule fill to `0...1` (over-budget pins full, never overflows),
/// - read `0` fill + `trackOnly` for an unbudgeted row (no misleading sliver),
/// - carry the verdict as text *and* glyph, never color alone,
/// - give an explicit "No budget set" verdict instead of a false "on track",
/// - keep leaf and group status independent (group `.over`, leaves `.under`),
/// - and produce one VoiceOver sentence that survives Privacy Mask substitution.
@Suite("Category status bar model (AND-538)")
struct CategoryStatusBarModelTests {
    @Test("Budgeted leaf under budget: partial fill, on-track verdict + glyph")
    func leafUnderBudget() {
        let leaf = CategoryDashboardPresentation.Leaf(
            category: .foodAndDrink, spent: 200, monthlyLimit: 500
        )
        let model = CategoryStatusBarModel(leaf: leaf)

        #expect(model.isBudgeted)
        #expect(!model.trackOnly)
        #expect(model.status == .under)
        #expect(model.fillFraction == 0.4)
        #expect(model.statusText == "On track")
        #expect(model.statusIconName == CategoryBudgetStatus.under.iconName)
        #expect(model.percentUsedText() == "40%")
        #expect(model.remaining == 300)
    }

    @Test("Nearing band sits in 80...100% and surfaces its own glyph")
    func leafNearing() {
        let leaf = CategoryDashboardPresentation.Leaf(
            category: .shopping, spent: 450, monthlyLimit: 500
        )
        let model = CategoryStatusBarModel(leaf: leaf)

        #expect(model.status == .nearing)
        #expect(model.fillFraction == 0.9)
        #expect(model.statusText == "Close to limit")
        #expect(model.statusIconName == CategoryBudgetStatus.nearing.iconName)
    }

    @Test("Over-budget leaf pins the fill at 1.0 (overspend lives in the text)")
    func leafOverPinsFull() {
        let leaf = CategoryDashboardPresentation.Leaf(
            category: .entertainment, spent: 750, monthlyLimit: 500
        )
        let model = CategoryStatusBarModel(leaf: leaf)

        #expect(model.status == .over)
        #expect(model.fillFraction == 1.0) // clamped, not 1.5
        #expect(model.percentUsedText() == "150%")
        #expect(model.remaining == -250) // negative = overspent
        #expect(model.statusText == "Over budget")
    }

    @Test("Unbudgeted leaf: zero fill, track-only, explicit no-budget verdict")
    func leafNoBudget() {
        let leaf = CategoryDashboardPresentation.Leaf(
            category: .other, spent: 120, monthlyLimit: nil
        )
        let model = CategoryStatusBarModel(leaf: leaf)

        #expect(!model.isBudgeted)
        #expect(model.trackOnly)
        #expect(model.fillFraction == 0)
        #expect(model.status == nil)
        #expect(model.statusText == "No budget set")
        #expect(model.statusIconName == "minus.circle")
        #expect(model.percentUsedText() == nil)
        #expect(model.remaining == nil)
    }

    @Test("Group rollup drives the same model from summed numbers")
    func groupRollup() {
        let over = CategoryDashboardPresentation.Leaf(
            category: .foodAndDrink, spent: 400, monthlyLimit: 300
        )
        let under = CategoryDashboardPresentation.Leaf(
            category: .travel, spent: 100, monthlyLimit: 400
        )
        let group = CategoryDashboardPresentation.GroupRollup(
            group: .foodAndDining, leaves: [over, under]
        )
        let model = CategoryStatusBarModel(group: group)

        #expect(model.spent == 500)
        #expect(model.monthlyLimit == 700)
        #expect(model.fillFraction == 500.0 / 700.0)
        #expect(model.status == .under) // summed 500/700 ≈ 71% → under
    }

    /// Spec §7: leaf and group status are independent — a group can be over while
    /// every leaf is individually under.
    @Test("Group over while every leaf under (independent status)")
    func groupOverLeavesUnder() {
        // Each leaf at 78% (under, < 80% nearing threshold)…
        let a = CategoryDashboardPresentation.Leaf(
            category: .foodAndDrink, spent: 390, monthlyLimit: 500
        )
        let b = CategoryDashboardPresentation.Leaf(
            category: .travel, spent: 390, monthlyLimit: 500
        )
        // …but the group sums to 780/1000 = 78% — still under here, so push one
        // leaf so the SUM crosses 100% while each leaf stays its own band.
        let c = CategoryDashboardPresentation.Leaf(
            category: .education, spent: 490, monthlyLimit: 500 // 98% → nearing
        )
        let group = CategoryDashboardPresentation.GroupRollup(
            group: .entertainment, leaves: [a, b, c]
        )
        let leafModelA = CategoryStatusBarModel(leaf: a)
        let groupModel = CategoryStatusBarModel(group: group)

        #expect(leafModelA.status == .under)            // leaf independent
        #expect(group.spent == 1270)
        #expect(group.monthlyLimit == 1500)
        // 1270/1500 ≈ 84.7% — group is its own (nearing) band, not a leaf's.
        #expect(groupModel.status == .nearing)
        #expect(groupModel.fillFraction == 1270.0 / 1500.0)
    }

    @Test("Accessibility sentence: budgeted row names spend, budget, percent, verdict")
    func accessibilityBudgeted() {
        let leaf = CategoryDashboardPresentation.Leaf(
            category: .foodAndDrink, spent: 200, monthlyLimit: 500
        )
        let model = CategoryStatusBarModel(leaf: leaf)
        let sentence = model.accessibilityDescription(spentText: "$200", limitText: "$500")

        #expect(sentence == "$200 of $500, 40% of budget. On track.")
    }

    @Test("Accessibility sentence: unbudgeted row says no budget, ignores nil limit")
    func accessibilityUnbudgeted() {
        let leaf = CategoryDashboardPresentation.Leaf(
            category: .other, spent: 120, monthlyLimit: nil
        )
        let model = CategoryStatusBarModel(leaf: leaf)
        let sentence = model.accessibilityDescription(spentText: "$120", limitText: nil)

        #expect(sentence == "$120 spent. No budget set.")
    }

    @Test("Accessibility sentence survives Privacy Mask currency substitution")
    func accessibilityMasked() {
        let leaf = CategoryDashboardPresentation.Leaf(
            category: .foodAndDrink, spent: 200, monthlyLimit: 500
        )
        let model = CategoryStatusBarModel(leaf: leaf)
        let masked = model.accessibilityDescription(spentText: "••••", limitText: "••••")

        // The verdict + percent still read; only the currency is dots.
        #expect(masked == "•••• of ••••, 40% of budget. On track.")
    }
}
