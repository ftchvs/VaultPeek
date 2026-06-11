import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Dashboard Change Receipt Tests")
struct DashboardChangeReceiptTests {
    @Test("Receipt reports local net and transaction changes without identifiers")
    func receiptReportsLocalChanges() throws {
        let previous = try #require(Formatters.parseTransactionDate("2026-06-10"))
        let now = try #require(Formatters.parseTransactionDate("2026-06-11"))

        let receipt = try #require(DashboardChangeReceipt.evaluate(
            history: [
                BalanceSnapshot(date: previous, balance: 10_000),
                BalanceSnapshot(date: now, balance: 10_240),
            ],
            transactions: [
                TransactionDTO(id: "tx_recent", accountId: "acct_hidden", amount: 42, date: "2026-06-11", name: "SHOULD NOT LEAK"),
                TransactionDTO(id: "tx_old", accountId: "acct_hidden", amount: 12, date: "2026-06-10", name: "OLD"),
            ],
            itemStatuses: [ItemStatus(id: "item_secret", institutionName: "Bank", status: .connected)],
            now: now
        ))

        #expect(receipt.title == "Latest local changes")
        #expect(receipt.summary.contains("net up"))
        #expect(receipt.summary.contains("1 new tx"))
        #expect(receipt.rows.map(\.id) == ["net-worth", "transactions"])
        #expect(!receipt.accessibilitySummary.contains("acct_hidden"))
        #expect(!receipt.accessibilitySummary.contains("item_secret"))
        #expect(!receipt.accessibilitySummary.contains("SHOULD NOT LEAK"))
    }

    @Test("Receipt handles first local snapshot as a baseline")
    func receiptHandlesFirstLocalSnapshot() throws {
        let now = try #require(Formatters.parseTransactionDate("2026-06-11"))

        let receipt = try #require(DashboardChangeReceipt.evaluate(
            history: [BalanceSnapshot(date: now, balance: 8_400)],
            transactions: [],
            itemStatuses: [],
            now: now
        ))

        #expect(receipt.summary == "First local snapshot saved")
        #expect(receipt.rows.map(\.id) == ["baseline"])
        #expect(receipt.accessibilitySummary.contains("First local snapshot saved"))
    }

    @Test("Receipt exposes degraded item count without raw item IDs")
    func receiptExposesDegradedItemCount() throws {
        let previous = try #require(Formatters.parseTransactionDate("2026-06-10"))
        let now = try #require(Formatters.parseTransactionDate("2026-06-11"))

        let receipt = try #require(DashboardChangeReceipt.evaluate(
            history: [
                BalanceSnapshot(date: previous, balance: 10_000),
                BalanceSnapshot(date: now, balance: 10_000),
            ],
            transactions: [],
            itemStatuses: [
                ItemStatus(id: "item_login_secret", institutionName: "Bank", status: .loginRequired),
                ItemStatus(id: "item_error_secret", institutionName: "Brokerage", status: .error),
            ],
            now: now
        ))

        #expect(receipt.summary.contains("2 items need attention"))
        #expect(receipt.rows.map(\.id).contains("attention"))
        #expect(!receipt.accessibilitySummary.contains("item_login_secret"))
        #expect(!receipt.accessibilitySummary.contains("item_error_secret"))
    }

    @Test("Receipt bounds transactions to the compared snapshot window")
    func receiptBoundsTransactionsToSnapshotWindow() throws {
        let previous = try #require(Formatters.parseTransactionDate("2026-06-10"))
        let latest = try #require(Formatters.parseTransactionDate("2026-06-11"))
        let now = try #require(Formatters.parseTransactionDate("2026-06-12"))

        let receipt = try #require(DashboardChangeReceipt.evaluate(
            history: [
                BalanceSnapshot(date: previous, balance: 10_000),
                BalanceSnapshot(date: latest, balance: 10_100),
            ],
            transactions: [
                TransactionDTO(id: "inside", accountId: "hidden", amount: 10, date: "2026-06-11", name: "IN WINDOW"),
                TransactionDTO(id: "after", accountId: "hidden", amount: 20, date: "2026-06-12", name: "AFTER SNAPSHOT"),
            ],
            itemStatuses: [],
            now: now
        ))

        #expect(receipt.summary.contains("1 new tx"))
    }
}
