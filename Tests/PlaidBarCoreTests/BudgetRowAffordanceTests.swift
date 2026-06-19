import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Budget row affordance (AND-541)")
struct BudgetRowAffordanceTests {
    // MARK: - Visibility

    @Test("A budgetable category always offers an affordance")
    func budgetableCategoryShowsAffordance() {
        let unbudgeted = BudgetRowAffordance(category: .foodAndDrink, isBudgeted: false)
        let budgeted = BudgetRowAffordance(category: .shopping, isBudgeted: true)
        #expect(unbudgeted.isAvailable)
        #expect(budgeted.isAvailable)
    }

    @Test("Income and transfer categories never offer an affordance")
    func excludedCategoriesHaveNoAffordance() {
        for excluded in CategoryBudgetPlanner.excludedCategories {
            let affordance = BudgetRowAffordance(category: excluded, isBudgeted: false)
            #expect(!affordance.isAvailable)
            // Even if some upstream path mislabels it budgeted, it stays unavailable.
            #expect(!BudgetRowAffordance(category: excluded, isBudgeted: true).isAvailable)
        }
    }

    // MARK: - Action verb

    @Test("An unbudgeted category invites setting a budget")
    func unbudgetedShowsSet() {
        let affordance = BudgetRowAffordance(category: .foodAndDrink, isBudgeted: false)
        #expect(affordance.action == .setBudget)
        #expect(affordance.title == "Set a budget")
        #expect(affordance.systemImage == "plus.circle")
    }

    @Test("A budgeted category invites editing the budget")
    func budgetedShowsEdit() {
        let affordance = BudgetRowAffordance(category: .shopping, isBudgeted: true)
        #expect(affordance.action == .editBudget)
        #expect(affordance.title == "Edit")
        #expect(affordance.systemImage == "slider.horizontal.3")
    }

    // MARK: - Accessibility

    @Test("Accessibility label names the category and the action")
    func accessibilityLabelCarriesCategoryAndAction() {
        let set = BudgetRowAffordance(category: .foodAndDrink, isBudgeted: false)
        #expect(set.accessibilityLabel == "Set a budget for Food & Drink")

        let edit = BudgetRowAffordance(category: .shopping, isBudgeted: true)
        #expect(edit.accessibilityLabel == "Edit budget for Shopping")
    }

    @Test("Unavailable categories expose an empty, action-less affordance")
    func unavailableAffordanceIsInert() {
        let affordance = BudgetRowAffordance(category: .income, isBudgeted: false)
        #expect(!affordance.isAvailable)
        #expect(affordance.action == nil)
        #expect(affordance.title == "")
        #expect(affordance.accessibilityLabel == "")
    }

    // MARK: - Convenience builders mirror the dashboard rows

    @Test("Leaf builder reads the leaf's budget state")
    func builtFromLeaf() {
        let budgetedLeaf = CategoryDashboardPresentation.Leaf(
            category: .foodAndDrink,
            spent: 120,
            monthlyLimit: 300
        )
        let unbudgetedLeaf = CategoryDashboardPresentation.Leaf(
            category: .shopping,
            spent: 80,
            monthlyLimit: nil
        )
        #expect(BudgetRowAffordance(leaf: budgetedLeaf).action == .editBudget)
        #expect(BudgetRowAffordance(leaf: unbudgetedLeaf).action == .setBudget)
    }
}
