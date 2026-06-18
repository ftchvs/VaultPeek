import Foundation
@testable import PlaidBarCore
import Testing

@Suite("Liability presentation (Payments Due)")
struct LiabilityPresentationTests {
    private static let card = AccountDTO(
        id: "cc-1", itemId: "item-1", name: "Test Card",
        type: .credit, subtype: "credit card",
        balances: BalanceDTO(current: -1_200, limit: 5_000)
    )

    @Test("No liability keeps the honest utilization-only placeholder")
    func noLiabilityKeepsPlaceholder() {
        #expect(AccountPresentation.creditDueMetadataText(for: Self.card, liability: nil) == "due not synced")
    }

    @Test("Real liability shows the next due date and purchase APR")
    func realLiabilityShowsDueAndApr() {
        let liability = LiabilityDTO(
            accountId: "cc-1",
            purchaseAprPercentage: 24.99,
            nextPaymentDueDate: "2026-06-30"
        )
        let text = AccountPresentation.creditDueMetadataText(for: Self.card, liability: liability)
        #expect(text.contains("APR"))
        #expect(text.contains("Due"))
        #expect(!text.contains("due not synced"))
    }

    @Test("Overdue is communicated by the word, not color alone")
    func overdueSaysOverdue() {
        let liability = LiabilityDTO(
            accountId: "cc-1",
            nextPaymentDueDate: "2026-06-01",
            isOverdue: true
        )
        let text = AccountPresentation.creditDueMetadataText(for: Self.card, liability: liability)
        #expect(text.contains("Overdue"))
    }

    @Test("A liability with no APR and no due date falls back to the placeholder")
    func emptyLiabilityFallsBack() {
        let liability = LiabilityDTO(accountId: "cc-1")
        #expect(AccountPresentation.creditDueMetadataText(for: Self.card, liability: liability) == "due not synced")
    }

    @Test("Non-credit accounts never render liability text")
    func nonCreditReturnsEmpty() {
        let checking = AccountDTO(
            id: "chk", itemId: "item-1", name: "Checking",
            type: .depository, balances: BalanceDTO(current: 500)
        )
        let liability = LiabilityDTO(accountId: "chk", purchaseAprPercentage: 10)
        #expect(AccountPresentation.creditDueMetadataText(for: checking, liability: liability) == "")
    }

    @Test("Demo fixtures provide liabilities for the demo credit cards")
    func demoFixturesCoverDemoCards() {
        let ids = Set(DemoFixtures.liabilities().map(\.accountId))
        #expect(ids.contains("demo_amex"))
        #expect(ids.contains("demo_visa"))
        // Every demo liability points at an existing demo credit account.
        let creditIds = Set(DemoFixtures.accounts.filter { $0.type == .credit }.map(\.id))
        #expect(ids.isSubset(of: creditIds))
    }
}
