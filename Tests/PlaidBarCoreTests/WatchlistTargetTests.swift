import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Watchlist target value type (AND-501)")
struct WatchlistTargetTests {
    @Test("Kind exposes a display name for every case")
    func kindDisplayNames() {
        #expect(WatchlistTarget.Kind.merchant.displayName == "Merchant")
        #expect(WatchlistTarget.Kind.category.displayName == "Category")
        #expect(WatchlistTarget.Kind.allCases.count == 2)
    }

    @Test("Merchant keys are normalized and negative thresholds clamp to zero")
    func initNormalizesAndClamps() {
        let target = WatchlistTarget(kind: .merchant, key: "  Whole Foods  ", monthlyThreshold: -10, label: "Whole Foods")
        #expect(target.key == "whole foods")
        #expect(target.monthlyThreshold == 0)
    }

    @Test("Category keys are stored verbatim")
    func categoryKeyVerbatim() {
        let target = WatchlistTarget(kind: .category, key: "FOOD_AND_DRINK", monthlyThreshold: 50, label: "Food & Drink")
        #expect(target.key == "FOOD_AND_DRINK")
    }

    @Test("Merchant factory trims the name and falls back to a generic label when blank")
    func merchantFactory() {
        let named = WatchlistTarget.merchant("  Starbucks  ", threshold: 25)
        #expect(named.kind == .merchant)
        #expect(named.key == "starbucks")
        #expect(named.label == "Starbucks")

        let blank = WatchlistTarget.merchant("   ", threshold: 25)
        #expect(blank.label == "Merchant")
        #expect(blank.key.isEmpty)
    }

    @Test("Category factory derives key and label from the category")
    func categoryFactory() {
        let target = WatchlistTarget.category(.shopping, threshold: 100)
        #expect(target.kind == .category)
        #expect(target.key == SpendingCategory.shopping.rawValue)
        #expect(target.label == SpendingCategory.shopping.displayName)
    }

    @Test("category resolves only for category targets")
    func categoryAccessor() {
        #expect(WatchlistTarget.category(.travel, threshold: 1).category == .travel)
        #expect(WatchlistTarget.merchant("Acme", threshold: 1).category == nil)
    }

    @Test("normalizeMerchant lowercases and trims")
    func normalizeMerchant() {
        #expect(WatchlistTarget.normalizeMerchant("  Whole Foods ") == "whole foods")
    }
}
