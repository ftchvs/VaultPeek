import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Budget editor input parsing (AND-540)")
struct BudgetEditorInputTests {
    // MARK: - Budgetable categories

    @Test("Income and transfer categories are never budgetable")
    func excludedCategoriesNotBudgetable() {
        for excluded in CategoryBudgetPlanner.excludedCategories {
            #expect(!BudgetEditorInput.isBudgetable(excluded))
            #expect(
                BudgetEditorInput.parse("200", category: excluded)
                    == .categoryNotBudgetable
            )
        }
    }

    @Test("A spend category is budgetable")
    func spendCategoryBudgetable() {
        #expect(BudgetEditorInput.isBudgetable(.foodAndDrink))
        #expect(BudgetEditorInput.isBudgetable(.shopping))
    }

    // MARK: - Empty / invalid

    @Test("Blank text is empty (not committable)")
    func blankIsEmpty() {
        #expect(BudgetEditorInput.parse("", category: .foodAndDrink) == .empty)
        #expect(BudgetEditorInput.parse("   ", category: .foodAndDrink) == .empty)
        #expect(!BudgetEditorInput.parse("", category: .foodAndDrink).isCommittable)
    }

    @Test("Non-numeric or negative text is invalid")
    func invalidText() {
        #expect(BudgetEditorInput.parse("abc", category: .foodAndDrink) == .invalid)
        #expect(BudgetEditorInput.parse("-50", category: .foodAndDrink) == .invalid)
        #expect(BudgetEditorInput.parse("12.3.4", category: .foodAndDrink) == .invalid)
        #expect(BudgetEditorInput.parse("1e9", category: .foodAndDrink) == .invalid)
        #expect(!BudgetEditorInput.parse("abc", category: .foodAndDrink).isCommittable)
    }

    // MARK: - Save

    @Test("A positive amount resolves to .save")
    func positiveSaves() {
        #expect(
            BudgetEditorInput.parse("500", category: .foodAndDrink)
                == .save(amount: 500)
        )
        #expect(
            BudgetEditorInput.parse("499.99", category: .shopping)
                == .save(amount: 499.99)
        )
        #expect(BudgetEditorInput.parse("500", category: .foodAndDrink).isCommittable)
    }

    @Test("Currency symbol and grouping separators are tolerated")
    func toleratesFormatting() {
        #expect(
            BudgetEditorInput.parse("$1,200", category: .travel)
                == .save(amount: 1200)
        )
        #expect(
            BudgetEditorInput.parse("$1,200.50", category: .travel)
                == .save(amount: 1200.50)
        )
        #expect(
            BudgetEditorInput.parse(" 750 ", category: .travel)
                == .save(amount: 750)
        )
    }

    @Test("Comma-as-decimal (European) parses as cents")
    func commaDecimal() {
        #expect(
            BudgetEditorInput.parse("12,50", category: .foodAndDrink)
                == .save(amount: 12.50)
        )
        #expect(
            BudgetEditorInput.parse("1.200,50", category: .foodAndDrink)
                == .save(amount: 1200.50)
        )
    }

    // MARK: - Clear

    @Test("Zero resolves to .clear (committable)")
    func zeroClears() {
        #expect(BudgetEditorInput.parse("0", category: .foodAndDrink) == .clear)
        #expect(BudgetEditorInput.parse("0.00", category: .foodAndDrink) == .clear)
        #expect(BudgetEditorInput.parse("0", category: .foodAndDrink).isCommittable)
    }
}
