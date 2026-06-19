import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Local AI insights model accessors")
struct LocalAIInsightsModelTests {
    @Test("Insight window ids mirror their raw values")
    func windowIds() {
        for window in LocalAIInsightWindow.allCases {
            #expect(window.id == window.rawValue)
        }
    }

    @Test("Category resolution source has a distinct display name per case")
    func resolutionSourceDisplayNames() {
        #expect(LocalAICategoryResolutionSource.localAISuggestion.displayName == "Local AI")
        #expect(LocalAICategoryResolutionSource.appleNaturalLanguage.displayName == "Suggested")
        #expect(LocalAICategoryResolutionSource.plaidCategory.displayName == "Plaid")
        #expect(LocalAICategoryResolutionSource.fallbackOther.displayName == "Other")
    }

    @Test("DTO identities derive from their key fields")
    func dtoIdentities() {
        let total = LocalAICategoryTotal(
            category: .foodAndDrink, totalAmount: 100, transactionCount: 3,
            transactionIds: ["t1"], evidence: []
        )
        #expect(total.id == "FOOD_AND_DRINK")

        let item = LocalAITransactionInsightItem(
            transactionId: "t1", accountId: "a1", date: "2026-06-14", displayName: "Coffee",
            amount: 5, effectiveCategory: .foodAndDrink, plaidCategory: nil,
            categorySource: .appleNaturalLanguage, pending: false, evidence: []
        )
        #expect(item.id == "t1")

        let suggestion = LocalAICategorySuggestion(
            transactionId: "t1", suggestedCategory: .shopping, confidence: 0.9, evidence: []
        )
        #expect(suggestion.id == "t1-GENERAL_MERCHANDISE")
    }
}
