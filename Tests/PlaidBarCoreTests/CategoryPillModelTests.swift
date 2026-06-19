import Foundation
import Testing
@testable import PlaidBarCore

@Suite("CategoryPillModel — colored icon+text pill (AND-530)")
struct CategoryPillModelTests {
    @Test("a real category yields its name, glyph, and accent")
    func realCategoryMapping() {
        let pill = CategoryPillModel.make(category: .foodAndDrink)
        #expect(pill.category == .foodAndDrink)
        #expect(pill.title == SpendingCategory.foodAndDrink.displayName)
        #expect(pill.glyph == SpendingCategory.foodAndDrink.iconName)
        #expect(pill.accentColorHex == SpendingCategory.foodAndDrink.colorHex)
    }

    @Test("nil category yields the neutral uncategorized pill")
    func uncategorizedMapping() {
        let pill = CategoryPillModel.make(category: nil)
        #expect(pill.category == nil)
        #expect(pill.title == CategoryPillModel.uncategorizedTitle)
        #expect(pill.title == "Uncategorized")
        #expect(pill.glyph == CategoryPillModel.uncategorizedGlyph)
        #expect(pill.accentColorHex == CategoryPillModel.uncategorizedAccentHex)
    }

    @Test("every category produces a non-empty title and glyph (no color-only meaning)")
    func everyCategoryHasTextAndGlyph() {
        // The pill must always carry its meaning in text + glyph so it never relies on
        // color alone (ACCESSIBILITY.md). Assert that for the uncategorized case too.
        let pills = SpendingCategory.allCases.map { CategoryPillModel.make(category: $0) }
            + [CategoryPillModel.make(category: nil)]
        for pill in pills {
            #expect(!pill.title.isEmpty)
            #expect(!pill.glyph.isEmpty)
            #expect(!pill.accentColorHex.isEmpty)
        }
    }

    @Test("title and glyph match the source SpendingCategory for every case")
    func mappingStaysInSyncWithCategory() {
        // Pin the pill to the canonical category contract so a future rename of a
        // category's display name / icon flows through without the pill drifting.
        for category in SpendingCategory.allCases {
            let pill = CategoryPillModel.make(category: category)
            #expect(pill.title == category.displayName)
            #expect(pill.glyph == category.iconName)
            #expect(pill.accentColorHex == category.colorHex)
        }
    }

    @Test("distinct categories produce distinct pill models")
    func categoriesProduceDistinctPills() {
        let foodPill = CategoryPillModel.make(category: .foodAndDrink)
        let travelPill = CategoryPillModel.make(category: .travel)
        #expect(foodPill != travelPill)
        // Hashable conformance keeps the model usable as a dictionary key / set member.
        #expect(Set([foodPill, travelPill, foodPill]).count == 2)
    }
}
