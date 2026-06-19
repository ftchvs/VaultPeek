import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Category budget DTO")
struct CategoryBudgetDTOTests {
    @Test("Identity is the category raw value")
    func identity() {
        let dto = CategoryBudgetDTO(category: .foodAndDrink, monthlyLimit: 300)
        #expect(dto.id == "FOOD_AND_DRINK")
        #expect(dto.monthlyLimit == 300)
    }

    @Test("Response byCategory maps each budget to its limit")
    func byCategory() {
        let response = CategoryBudgetsResponse(budgets: [
            CategoryBudgetDTO(category: .foodAndDrink, monthlyLimit: 300),
            CategoryBudgetDTO(category: .shopping, monthlyLimit: 150),
        ])
        #expect(response.byCategory[.foodAndDrink] == 300)
        #expect(response.byCategory[.shopping] == 150)
        #expect(response.byCategory.count == 2)
    }

    @Test("Save request carries the monthly limit")
    func saveRequest() {
        #expect(SaveCategoryBudgetRequest(monthlyLimit: 99).monthlyLimit == 99)
    }
}
