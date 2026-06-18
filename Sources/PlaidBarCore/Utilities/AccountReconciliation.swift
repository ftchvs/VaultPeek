import Foundation

/// Pure reconciliation rules deciding which accounts survive a refresh or a boot
/// cache load. Extracted from `AppState` so the "deleted accounts must not
/// resurrect" decisions are `Sendable` and unit-testable (GH #507, #508).
///
/// The problem both rules guard against: a server-side `removeItem` deletes the
/// item authoritatively, but its accounts can still sit in memory or in the
/// on-disk JSON cache. Naively re-attaching every cached account "missing from
/// the latest server response" resurrects exactly those just-deleted accounts.
public enum AccountReconciliation {
    /// Resolves the account list after a balances/accounts refresh.
    ///
    /// - When `itemStatusesAvailable` is `true`, the server's item list is known,
    ///   so only accounts belonging to a *known-degraded* item that the partial
    ///   refresh omitted are preserved from cache (a degraded item — e.g.
    ///   login-required or a provider outage — legitimately drops out of the
    ///   balances response without being deleted).
    /// - When `itemStatusesAvailable` is `false`, the item list could not be
    ///   fetched, so the app cannot tell "intentionally deleted" from
    ///   "temporarily degraded". In that case the refreshed (server) account list
    ///   is treated as the source of truth and stale cache is **not** merged back
    ///   in — otherwise a successfully-deleted account reappears (GH #507).
    ///
    /// - Parameters:
    ///   - refreshedAccounts: accounts returned by the latest server refresh.
    ///   - currentAccounts: accounts currently held in memory / loaded from cache.
    ///   - itemStatusesAvailable: whether the `/api/items` fetch succeeded.
    ///   - itemStatuses: the (possibly empty) item statuses backing the refresh.
    /// - Returns: the reconciled account list to render and persist.
    public static func accountsAfterRefresh(
        refreshedAccounts: [AccountDTO],
        currentAccounts: [AccountDTO],
        itemStatusesAvailable: Bool,
        itemStatuses: [ItemStatus]
    ) -> [AccountDTO] {
        // Item statuses unavailable: cannot distinguish a deleted item from a
        // degraded one, so trust the server response. Merging cached accounts here
        // is what resurrected server-deleted accounts (GH #507).
        guard itemStatusesAvailable else { return refreshedAccounts }

        return accountsPreservingDegradedItems(
            refreshedAccounts: refreshedAccounts,
            currentAccounts: currentAccounts,
            itemStatuses: itemStatuses
        )
    }

    /// Preserves cached accounts only for items the server reports as degraded but
    /// that the partial refresh omitted. Mirrors the prior
    /// `accountsPreservingUnavailableItems` behavior, now pure and testable.
    public static func accountsPreservingDegradedItems(
        refreshedAccounts: [AccountDTO],
        currentAccounts: [AccountDTO],
        itemStatuses: [ItemStatus]
    ) -> [AccountDTO] {
        guard !currentAccounts.isEmpty, !itemStatuses.isEmpty else { return refreshedAccounts }

        let refreshedAccountIds = Set(refreshedAccounts.map(\.id))
        let refreshedItemIds = Set(refreshedAccounts.map(\.itemId))
        let unavailableItemIds = Set(itemStatuses.compactMap { item -> String? in
            guard item.status != .connected, !refreshedItemIds.contains(item.id) else { return nil }
            return item.id
        })
        guard !unavailableItemIds.isEmpty else { return refreshedAccounts }

        let preservedAccounts = currentAccounts.filter { account in
            unavailableItemIds.contains(account.itemId) && !refreshedAccountIds.contains(account.id)
        }
        return refreshedAccounts + preservedAccounts
    }

    /// Reconciles cached accounts against the authoritative set of server item ids
    /// (from `/api/items`) at boot, before rendering.
    ///
    /// Accounts whose item is no longer present server-side are dropped, even when
    /// a time-based auto-refresh is not due. This closes the window where a
    /// removal's cache write failed (so the stale JSON still lists the account)
    /// and manual-only / recently-synced state skips `refreshAccounts`, leaving a
    /// deleted account visible after the next launch (GH #508).
    ///
    /// - Parameters:
    ///   - cachedAccounts: accounts just loaded from the on-disk cache.
    ///   - serverItemIds: item ids the server currently reports as connected.
    /// - Returns: cached accounts filtered to items the server still knows about.
    public static func cachedAccountsReconciledAgainstServerItems(
        cachedAccounts: [AccountDTO],
        serverItemIds: [String]
    ) -> [AccountDTO] {
        guard !cachedAccounts.isEmpty else { return cachedAccounts }
        let liveItemIds = Set(serverItemIds)
        return cachedAccounts.filter { liveItemIds.contains($0.itemId) }
    }
}
