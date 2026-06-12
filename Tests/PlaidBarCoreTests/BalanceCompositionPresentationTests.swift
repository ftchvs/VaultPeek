import Testing
@testable import PlaidBarCore

@Suite("Balance composition presentation")
struct BalanceCompositionPresentationTests {
    @Test("Computes active balance-mix segments in one reusable pass")
    func computesActiveSegments() {
        let accounts = [
            AccountDTO(id: "checking", itemId: "item", name: "Checking", type: .depository, balances: BalanceDTO(available: 800, current: 900)),
            AccountDTO(id: "brokerage", itemId: "item", name: "Brokerage", type: .investment, balances: BalanceDTO(current: 1_200)),
            AccountDTO(id: "card", itemId: "item", name: "Card", type: .credit, balances: BalanceDTO(current: -300, limit: 2_000)),
            AccountDTO(id: "loan", itemId: "item", name: "Loan", type: .loan, balances: BalanceDTO(current: -700)),
        ]

        let presentation = BalanceCompositionPresentation(accounts: accounts)

        #expect(presentation.accountCount == 4)
        #expect(presentation.total == 3_000)
        #expect(presentation.segments.map(\.id) == ["cash", "investments", "credit", "loans"])
        #expect(presentation.segments.map(\.title) == ["Cash", "Investments", "Credit", "Loans"])
        #expect(presentation.segments.map(\.value) == [800, 1_200, 300, 700])
        #expect(presentation.segments.map { Int(($0.share * 100).rounded()) } == [27, 40, 10, 23])
    }

    @Test("Suppresses zero and negative asset segments")
    func suppressesInactiveSegments() {
        let accounts = [
            AccountDTO(id: "checking", itemId: "item", name: "Checking", type: .depository, balances: BalanceDTO(current: -50)),
            AccountDTO(id: "card", itemId: "item", name: "Card", type: .credit, balances: BalanceDTO(current: -125)),
        ]

        let presentation = BalanceCompositionPresentation(accounts: accounts)

        #expect(presentation.total == 125)
        #expect(presentation.segments.map(\.id) == ["credit"])
        #expect(presentation.segments.first?.share == 1)
    }
}
