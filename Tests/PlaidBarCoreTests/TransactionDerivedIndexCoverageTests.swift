import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Transaction derived index coverage")
struct TransactionDerivedIndexCoverageTests {
    private func tx(_ id: String, date: String, account: String = "x") -> TransactionDTO {
        TransactionDTO(
            id: id, accountId: account, amount: 10, date: date,
            name: id, merchantName: id, category: .foodAndDrink, pending: false
        )
    }

    @Test("recentEntries filters to the inclusive date window and drops unparseable dates")
    func recentEntriesWindow() throws {
        let index = TransactionDerivedIndex(transactions: [
            tx("a", date: "2026-06-01"),
            tx("b", date: "2026-06-15"),
            tx("c", date: "2026-06-30"),
            tx("bad", date: "not-a-date"),
        ])
        let start = try #require(Formatters.parseTransactionDate("2026-06-10"))
        let end = try #require(Formatters.parseTransactionDate("2026-06-20"))
        #expect(index.recentEntries(from: start, through: end).map(\.transaction.id) == ["b"])
    }

    @Test("entries(in:from:through:) filters an arbitrary entry source")
    func entriesInSource() throws {
        let index = TransactionDerivedIndex(transactions: [
            tx("a", date: "2026-06-01"),
            tx("b", date: "2026-06-15"),
        ])
        let start = try #require(Formatters.parseTransactionDate("2026-06-14"))
        let end = try #require(Formatters.parseTransactionDate("2026-06-16"))
        #expect(index.entries(in: index.entries, from: start, through: end).map(\.transaction.id) == ["b"])
    }

    @Test("FinanceDerivedSnapshot builds an account lookup and a transaction index")
    func financeDerivedSnapshot() {
        let snapshot = FinanceDerivedSnapshot(
            accounts: [
                AccountDTO(id: "x", itemId: "i", name: "Checking", type: .depository, balances: BalanceDTO(current: 100)),
                AccountDTO(id: "y", itemId: "i", name: "Savings", type: .depository, balances: BalanceDTO(current: 200)),
            ],
            transactions: [tx("a", date: "2026-06-01", account: "x")]
        )
        #expect(snapshot.accounts.count == 2)
        #expect(snapshot.accountsById["x"]?.name == "Checking")
        #expect(snapshot.accountsById["y"]?.name == "Savings")
        #expect(snapshot.transactionIndex.entries.count == 1)
    }
}
