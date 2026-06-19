import Foundation

/// Pure derivation of whether the last completed sync is "stale" and the
/// corresponding status-strip text. Extracted from `AppState` so the threshold
/// math and the boot/never-synced fall-throughs are unit-testable by both
/// processes without standing up the SwiftUI app state.
///
/// Staleness is a verdict about *completed* syncs: during the boot handshake the
/// first sync is still in flight, so stale warnings (menu-bar badge, row tints,
/// status strip) stay reserved for real staleness measured after the check
/// completes.
public enum SyncStaleness {
    /// Default fall-back floor used when the refresh policy imposes no minimum
    /// interval (manual-only): wait a full day before nagging about staleness.
    public static let manualOnlyFloor: TimeInterval = 24 * 60 * 60

    /// Slack added on top of the policy floor so a normally behaving install
    /// (refreshing at most ~twice a day) doesn't flag "stale" between refreshes.
    private static let policyFloorSlack: TimeInterval = 60 * 60

    /// The elapsed-time threshold after which a completed sync is considered
    /// stale. Aligns with the automatic-refresh floor so a normally behaving
    /// install doesn't flag "stale"/broken-connection between scheduled refreshes;
    /// manual-only has no floor, so it allows a full day.
    public static func staleThreshold(
        refreshInterval: TimeInterval,
        transactionSyncInterval: TimeInterval = PlaidBarConstants.transactionSyncInterval,
        refreshPolicy: AutomaticRefreshPolicy
    ) -> TimeInterval {
        let policyFloor = refreshPolicy.minimumInterval ?? manualOnlyFloor
        return max(
            refreshInterval * 2,
            transactionSyncInterval * 2,
            policyFloor + policyFloorSlack
        )
    }

    /// Whether the last completed sync is stale.
    ///
    /// - During the boot handshake (`isBootLoadInFlight`) the first sync is still
    ///   in flight, so this is always `false`.
    /// - A never-synced state (`lastSyncDate == nil`) past boot is treated as
    ///   stale, so the UI nudges the user to connect/refresh.
    public static func isStale(
        isBootLoadInFlight: Bool,
        lastSyncDate: Date?,
        refreshInterval: TimeInterval,
        transactionSyncInterval: TimeInterval = PlaidBarConstants.transactionSyncInterval,
        refreshPolicy: AutomaticRefreshPolicy,
        asOf now: Date
    ) -> Bool {
        if isBootLoadInFlight { return false }
        guard let lastSyncDate else { return true }
        let staleAfter = staleThreshold(
            refreshInterval: refreshInterval,
            transactionSyncInterval: transactionSyncInterval,
            refreshPolicy: refreshPolicy
        )
        return now.timeIntervalSince(lastSyncDate) > staleAfter
    }

    /// The status-strip sync text. `lastSyncRelative` is the human-readable
    /// relative timestamp of the last sync (e.g. "2h ago"), or `nil` if never
    /// synced.
    public static func statusText(
        isBootLoadInFlight: Bool,
        lastSyncRelative: String?,
        isStale: Bool
    ) -> String {
        if isBootLoadInFlight { return "Syncing" }
        guard let lastSyncRelative else { return "Never synced" }
        return isStale ? "Stale \(lastSyncRelative)" : "Synced \(lastSyncRelative)"
    }
}
