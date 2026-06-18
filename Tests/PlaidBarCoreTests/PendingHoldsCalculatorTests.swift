import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Pending holds calculator (AND-499)")
struct PendingHoldsCalculatorTests {
    private static let checking = AccountDTO(
        id: "checking", itemId: "item", name: "Checking",
        type: .depository, balances: BalanceDTO(available: 1_000, current: 1_050)
    )
    private static let savings = AccountDTO(
        id: "savings", itemId: "item", name: "Savings",
        type: .depository, balances: BalanceDTO(available: 5_000, current: 5_000)
    )
    private static let credit = AccountDTO(
        id: "card", itemId: "item", name: "Card",
        type: .credit, balances: BalanceDTO(current: -300, limit: 2_000)
    )
    private static let loan = AccountDTO(
        id: "loan", itemId: "item", name: "Loan",
        type: .loan, balances: BalanceDTO(current: -5_000)
    )

    @Test("Sums absolute amounts of pending outflows on included cash accounts only")
    func sumsPendingCashOutflows() {
        let transactions = [
            tx(id: "a", account: "checking", amount: 80, pending: true),
            tx(id: "b", account: "savings", amount: 20, pending: true),
        ]
        let total = PendingHoldsCalculator.pendingHolds(
            from: transactions,
            accounts: [Self.checking, Self.savings]
        )
        #expect(abs(total - 100) < 0.001)
    }

    @Test("Excludes pending transactions on credit/loan accounts")
    func excludesNonCashAccounts() {
        let transactions = [
            tx(id: "a", account: "card", amount: 650, pending: true),
            tx(id: "b", account: "loan", amount: 200, pending: true),
        ]
        let total = PendingHoldsCalculator.pendingHolds(
            from: transactions,
            accounts: [Self.checking, Self.credit, Self.loan]
        )
        #expect(total == 0)
    }

    @Test("Excludes pending income and own-account transfers")
    func excludesInflowsAndTransfers() {
        let transactions = [
            // Income: negative amount AND income category — never a hold.
            tx(id: "a", account: "checking", amount: -500, pending: true, category: .income),
            // Positive amount but transfer-out category — own-account move.
            tx(id: "b", account: "checking", amount: 300, pending: true, category: .transferOut),
            tx(id: "c", account: "checking", amount: 200, pending: true, category: .transfer),
        ]
        let total = PendingHoldsCalculator.pendingHolds(
            from: transactions,
            accounts: [Self.checking]
        )
        #expect(total == 0)
    }

    @Test("Posted (non-pending) transactions contribute zero")
    func postedContributeZero() {
        let transactions = [
            tx(id: "a", account: "checking", amount: 80, pending: false),
            tx(id: "b", account: "checking", amount: 40, pending: true),
        ]
        let total = PendingHoldsCalculator.pendingHolds(
            from: transactions,
            accounts: [Self.checking]
        )
        #expect(abs(total - 40) < 0.001)
    }

    @Test("Empty input returns zero")
    func emptyReturnsZero() {
        #expect(PendingHoldsCalculator.pendingHolds(from: [], accounts: []) == 0)
        #expect(PendingHoldsCalculator.pendingHolds(from: [], accounts: [Self.checking]) == 0)
    }

    @Test("Demo fixtures expose a non-zero cash pending hold")
    func demoHasCashHold() {
        let now = Date()
        let calendar = Calendar(identifier: .gregorian)
        let total = PendingHoldsCalculator.pendingHolds(
            from: DemoFixtures.transactions(now: now, calendar: calendar),
            accounts: DemoFixtures.accounts
        )
        #expect(total > 0)
    }

    private func tx(
        id: String,
        account: String,
        amount: Double,
        pending: Bool,
        category: SpendingCategory = .foodAndDrink
    ) -> TransactionDTO {
        TransactionDTO(
            id: id,
            accountId: account,
            amount: amount,
            date: "2026-06-13",
            name: "Synthetic",
            merchantName: "Synthetic",
            category: category,
            pending: pending
        )
    }
}
