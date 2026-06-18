import Foundation
import PlaidBarCore
import Testing

@Suite("Account reconciliation against server item authority")
struct AccountReconciliationTests {
    // MARK: Fixtures

    private func account(_ id: String, item: String) -> AccountDTO {
        AccountDTO(
            id: id,
            itemId: item,
            name: "Account \(id)",
            type: .depository,
            balances: BalanceDTO(available: 100, current: 100, isoCurrencyCode: "USD")
        )
    }

    private func status(_ id: String, _ connection: ItemConnectionStatus) -> ItemStatus {
        ItemStatus(id: id, status: connection)
    }

    // MARK: GH #507 — item statuses unavailable must not resurrect deleted accounts

    @Test("Item-statuses-unavailable refresh trusts the server list and does NOT resurrect a deleted account")
    func unavailableStatusesDoNotResurrect() {
        // chase_item was deleted server-side; its account is intentionally absent
        // from the refresh but still lingers in the in-memory / cached list.
        let cached = [account("a_chase", item: "chase_item"), account("a_amex", item: "amex_item")]
        let serverResponse = [account("a_amex", item: "amex_item")]

        let result = AccountReconciliation.accountsAfterRefresh(
            refreshedAccounts: serverResponse,
            currentAccounts: cached,
            itemStatusesAvailable: false,
            itemStatuses: []
        )

        #expect(result.map(\.id) == ["a_amex"])
        #expect(!result.contains { $0.itemId == "chase_item" })
    }

    @Test("Item-statuses-unavailable refresh still returns the full server list when nothing was deleted")
    func unavailableStatusesPreserveServerTruth() {
        let cached = [account("a_amex", item: "amex_item")]
        let serverResponse = [
            account("a_amex", item: "amex_item"),
            account("a_chase", item: "chase_item"),
        ]

        let result = AccountReconciliation.accountsAfterRefresh(
            refreshedAccounts: serverResponse,
            currentAccounts: cached,
            itemStatusesAvailable: false,
            itemStatuses: []
        )

        #expect(Set(result.map(\.id)) == ["a_amex", "a_chase"])
    }

    // MARK: Item statuses available — degraded items preserved, deleted ones dropped

    @Test("Item statuses available preserves cached accounts only for known-degraded omitted items")
    func availableStatusesPreserveDegradedItem() {
        // amex is degraded (login_required) and dropped from the partial refresh —
        // its cached account must survive. chase is connected and present.
        let cached = [
            account("a_chase", item: "chase_item"),
            account("a_amex", item: "amex_item"),
        ]
        let serverResponse = [account("a_chase", item: "chase_item")]
        let statuses = [
            status("chase_item", .connected),
            status("amex_item", .loginRequired),
        ]

        let result = AccountReconciliation.accountsAfterRefresh(
            refreshedAccounts: serverResponse,
            currentAccounts: cached,
            itemStatusesAvailable: true,
            itemStatuses: statuses
        )

        #expect(Set(result.map(\.id)) == ["a_chase", "a_amex"])
    }

    @Test("Item statuses available does NOT preserve a cached account whose item is simply gone (deleted)")
    func availableStatusesDropDeletedItem() {
        // amex_item is no longer in the server item list at all (deleted). It is
        // not in itemStatuses, so it is neither connected nor degraded — drop it.
        let cached = [
            account("a_chase", item: "chase_item"),
            account("a_amex", item: "amex_item"),
        ]
        let serverResponse = [account("a_chase", item: "chase_item")]
        let statuses = [status("chase_item", .connected)]

        let result = AccountReconciliation.accountsAfterRefresh(
            refreshedAccounts: serverResponse,
            currentAccounts: cached,
            itemStatusesAvailable: true,
            itemStatuses: statuses
        )

        #expect(result.map(\.id) == ["a_chase"])
        #expect(!result.contains { $0.itemId == "amex_item" })
    }

    // MARK: GH #508 — boot reconciliation against authoritative /api/items

    @Test("Boot reconciliation drops cached accounts whose item the server no longer reports (failed post-delete save)")
    func bootReconciliationDropsStaleRemovedAccount() {
        // removeAccount deleted chase_item server-side but the cache write failed,
        // so the stale JSON still lists its account. On boot the server item list
        // is authoritative and the stale account must not render.
        let cached = [
            account("a_chase", item: "chase_item"),
            account("a_amex", item: "amex_item"),
        ]
        let serverItemIds = ["amex_item"]

        let result = AccountReconciliation.cachedAccountsReconciledAgainstServerItems(
            cachedAccounts: cached,
            serverItemIds: serverItemIds
        )

        #expect(result.map(\.id) == ["a_amex"])
        #expect(!result.contains { $0.itemId == "chase_item" })
    }

    @Test("Boot reconciliation keeps every cached account when all items are still present server-side")
    func bootReconciliationKeepsLiveAccounts() {
        let cached = [
            account("a_chase", item: "chase_item"),
            account("a_amex", item: "amex_item"),
        ]
        let serverItemIds = ["chase_item", "amex_item"]

        let result = AccountReconciliation.cachedAccountsReconciledAgainstServerItems(
            cachedAccounts: cached,
            serverItemIds: serverItemIds
        )

        #expect(Set(result.map(\.id)) == ["a_chase", "a_amex"])
    }

    @Test("Boot reconciliation on empty cache returns empty without consulting server ids")
    func bootReconciliationEmptyCache() {
        let result = AccountReconciliation.cachedAccountsReconciledAgainstServerItems(
            cachedAccounts: [],
            serverItemIds: ["chase_item"]
        )
        #expect(result.isEmpty)
    }
}
