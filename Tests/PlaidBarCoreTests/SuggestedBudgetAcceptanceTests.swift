import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Suggested budget acceptance (AND-542)")
struct SuggestedBudgetAcceptanceTests {
    private func item(
        _ category: SpendingCategory,
        limit: Double,
        spent: Double = 0,
        isSuggested: Bool
    ) -> CategoryBudgetPresentation.Item {
        CategoryBudgetPresentation.Item(
            category: category,
            monthlyLimit: limit,
            spent: spent,
            isSuggested: isSuggested
        )
    }

    // MARK: - Accept

    @Test("A suggested, budgetable, positive-limit item with no saved budget is acceptable")
    func acceptsGhostGuardrail() {
        let outcome = SuggestedBudgetAcceptance.evaluate(
            item: item(.foodAndDrink, limit: 500, isSuggested: true),
            existingBudgets: [:]
        )
        #expect(outcome == .accept(category: .foodAndDrink, amount: 500))
        #expect(outcome.acceptedAmount == 500)
        #expect(outcome.isAcceptable)
    }

    @Test("The accepted amount is exactly the suggested monthly limit")
    func acceptsSuggestedLimitVerbatim() {
        let outcome = SuggestedBudgetAcceptance.evaluate(
            item: item(.shopping, limit: 225, spent: 180, isSuggested: true),
            existingBudgets: [:]
        )
        #expect(outcome == .accept(category: .shopping, amount: 225))
    }

    // MARK: - Reject: not a suggestion

    @Test("An explicit (already-saved) item is not acceptable — nothing to accept")
    func rejectsExplicitItem() {
        let outcome = SuggestedBudgetAcceptance.evaluate(
            item: item(.foodAndDrink, limit: 500, isSuggested: false),
            existingBudgets: [:]
        )
        #expect(outcome == .notSuggested)
        #expect(!outcome.isAcceptable)
        #expect(outcome.acceptedAmount == nil)
    }

    // MARK: - Reject: income / transfer (mirror budgetableCategory)

    @Test("Income and transfer categories are never acceptable, even if flagged suggested")
    func rejectsExcludedCategories() {
        for excluded in CategoryBudgetPlanner.excludedCategories {
            let outcome = SuggestedBudgetAcceptance.evaluate(
                item: item(excluded, limit: 500, isSuggested: true),
                existingBudgets: [:]
            )
            #expect(outcome == .categoryNotBudgetable)
            #expect(!outcome.isAcceptable)
        }
    }

    @Test("Acceptance budgetability matches BudgetEditorInput.isBudgetable")
    func budgetabilityMatchesEditor() {
        for category in SpendingCategory.allCases {
            let outcome = SuggestedBudgetAcceptance.evaluate(
                item: item(category, limit: 300, isSuggested: true),
                existingBudgets: [:]
            )
            if BudgetEditorInput.isBudgetable(category) {
                #expect(outcome != .categoryNotBudgetable)
            } else {
                #expect(outcome == .categoryNotBudgetable)
            }
        }
    }

    // MARK: - Reject: non-positive / non-finite limit

    @Test("A non-positive suggested limit is not acceptable")
    func rejectsNonPositiveLimit() {
        #expect(
            SuggestedBudgetAcceptance.evaluate(
                item: item(.foodAndDrink, limit: 0, isSuggested: true),
                existingBudgets: [:]
            ) == .invalidLimit
        )
        #expect(
            SuggestedBudgetAcceptance.evaluate(
                item: item(.foodAndDrink, limit: -10, isSuggested: true),
                existingBudgets: [:]
            ) == .invalidLimit
        )
    }

    @Test("A non-finite suggested limit is not acceptable")
    func rejectsNonFiniteLimit() {
        #expect(
            SuggestedBudgetAcceptance.evaluate(
                item: item(.foodAndDrink, limit: .infinity, isSuggested: true),
                existingBudgets: [:]
            ) == .invalidLimit
        )
        #expect(
            SuggestedBudgetAcceptance.evaluate(
                item: item(.foodAndDrink, limit: .nan, isSuggested: true),
                existingBudgets: [:]
            ) == .invalidLimit
        )
    }

    // MARK: - Reject: already has an explicit budget

    @Test("A category that already has a saved budget is not re-accepted")
    func rejectsAlreadyBudgeted() {
        let outcome = SuggestedBudgetAcceptance.evaluate(
            item: item(.foodAndDrink, limit: 500, isSuggested: true),
            existingBudgets: [.foodAndDrink: 400]
        )
        #expect(outcome == .alreadyBudgeted)
        #expect(!outcome.isAcceptable)
    }

    @Test("A zero/negative existing limit does not block acceptance (treated as unset)")
    func zeroExistingDoesNotBlock() {
        let outcome = SuggestedBudgetAcceptance.evaluate(
            item: item(.foodAndDrink, limit: 500, isSuggested: true),
            existingBudgets: [.foodAndDrink: 0]
        )
        #expect(outcome == .accept(category: .foodAndDrink, amount: 500))
    }

    // MARK: - Convenience flag

    @Test("isAcceptable agrees with the accept case across outcomes")
    func isAcceptableFlag() {
        let accept = SuggestedBudgetAcceptance.evaluate(
            item: item(.shopping, limit: 100, isSuggested: true),
            existingBudgets: [:]
        )
        #expect(accept.isAcceptable)
        #expect(accept.acceptedAmount == 100)

        let reject = SuggestedBudgetAcceptance.evaluate(
            item: item(.shopping, limit: 100, isSuggested: false),
            existingBudgets: [:]
        )
        #expect(!reject.isAcceptable)
        #expect(reject.acceptedAmount == nil)
    }
}
