import Foundation
import Testing
@testable import PlaidBarCore

@Suite("PlaidBar CLI helpers")
struct PlaidBarCLITests {
    @Test("CLI endpoints match local server API")
    func cliEndpointsMatchLocalServerAPI() {
        #expect(PlaidBarCLIEndpoint.status.path == "/api/status")
        #expect(PlaidBarCLIEndpoint.items.path == "/api/items")
        #expect(PlaidBarCLIEndpoint.balance.path == "/api/accounts/balances")
        #expect(PlaidBarCLIEndpoint.transactionsSync(itemId: nil).path == "/api/transactions/sync")
        #expect(PlaidBarCLIEndpoint.transactionsSync(itemId: "item 1").path == "/api/transactions/sync?item_id=item%201")
        #expect(PlaidBarCLIEndpoint.linkCreate.path == "/api/link/create")
        #expect(PlaidBarCLIEndpoint.linkUpdate(itemId: "item/1").path == "/api/link/update/item%2F1")
        #expect(PlaidBarCLIEndpoint.commitCursors.path == "/api/transactions/sync/cursors")
    }

    @Test("balance table includes account, current, available, currency, and item")
    func balanceTableIncludesExpectedColumns() {
        let accounts = [
            AccountDTO(
                id: "acc_1",
                itemId: "item_1",
                name: "Plaid Checking",
                type: .depository,
                subtype: "checking",
                mask: "0000",
                balances: BalanceDTO(available: 100, current: 110, isoCurrencyCode: "USD"),
                institutionName: "Plaid Bank"
            )
        ]

        let table = PlaidBarCLITableFormatter.balance(accounts)

        #expect(table.contains("ACCOUNT"))
        #expect(table.contains("Plaid Checking (0000)"))
        #expect(table.contains("100.00"))
        #expect(table.contains("110.00"))
        #expect(table.contains("USD"))
        #expect(table.contains("item_1"))
    }

    @Test("transactions table sorts newest first and limits count")
    func transactionsTableSortsNewestFirstAndLimitsCount() {
        let transactions = [
            TransactionDTO(id: "old", accountId: "acc", amount: 1, date: "2026-01-01", name: "Old"),
            TransactionDTO(id: "new", accountId: "acc", amount: 2, date: "2026-01-03", name: "New", merchantName: "Newest"),
            TransactionDTO(id: "middle", accountId: "acc", amount: 3, date: "2026-01-02", name: "Middle"),
        ]

        let table = PlaidBarCLITableFormatter.transactions(transactions, count: 2)
        let newestRange = table.range(of: "Newest")
        let middleRange = table.range(of: "Middle")

        #expect(newestRange != nil)
        #expect(middleRange != nil)
        #expect(table.contains("Old") == false)
        #expect(newestRange!.lowerBound < middleRange!.lowerBound)
    }

    @Test("status table keeps storage path display safe")
    func statusTableKeepsStoragePath() {
        let status = ServerStatus(
            version: "1.2.3",
            environment: .sandbox,
            itemCount: 2,
            credentialsConfigured: true,
            storagePath: "~/.plaidbar",
            syncReady: true,
            syncedItemCount: 1
        )

        let table = PlaidBarCLITableFormatter.status(status)

        #expect(table.contains("VERSION"))
        #expect(table.contains("1.2.3"))
        #expect(table.contains("sandbox"))
        #expect(table.contains("~/.plaidbar"))
        #expect(table.contains("yes"))
    }
}
