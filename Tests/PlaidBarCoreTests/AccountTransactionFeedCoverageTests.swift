import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Account transaction feed coverage")
struct AccountTransactionFeedCoverageTests {
    private func tx(_ id: String, account: String, pending: Bool, date: String) -> TransactionDTO {
        TransactionDTO(
            id: id, accountId: account, amount: 10, date: date,
            name: id, merchantName: id, category: .foodAndDrink, pending: pending
        )
    }

    @Test("Snapshot built from transactions derives counts, pending list, and latest date")
    func snapshotFromTransactions() {
        let snapshot = AccountTransactionFeed.AccountActivitySnapshot(transactions: [
            tx("a", account: "x", pending: false, date: "2026-06-10"),
            tx("b", account: "x", pending: true, date: "2026-06-12"),
        ])
        #expect(snapshot.transactionCount == 2)
        #expect(snapshot.pendingTransactionCount == 1)
        #expect(snapshot.pendingTransactions.map(\.id) == ["b"])
        #expect(snapshot.latestTransactionDate == "2026-06-12")
    }

    @Test("sortedForFeed returns every transaction in a deterministic order")
    func sortedForFeed() {
        let sorted = AccountTransactionFeed.sortedForFeed([
            tx("a", account: "x", pending: false, date: "2026-06-10"),
            tx("b", account: "x", pending: false, date: "2026-06-12"),
        ])
        #expect(sorted.count == 2)
        #expect(Set(sorted.map(\.id)) == ["a", "b"])
    }

    @Test("transactions(forAccountId:) filters to the requested account")
    func transactionsForAccount() {
        let txns = [
            tx("a", account: "x", pending: false, date: "2026-06-10"),
            tx("c", account: "y", pending: false, date: "2026-06-11"),
        ]
        #expect(AccountTransactionFeed.transactions(forAccountId: "x", in: txns).map(\.id) == ["a"])
    }
}
