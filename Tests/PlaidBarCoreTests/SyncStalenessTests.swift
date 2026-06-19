import Foundation
@testable import PlaidBarCore
import Testing

@Suite("SyncStaleness Tests")
struct SyncStalenessTests {
    private let oneHour: TimeInterval = 60 * 60
    private let twelveHours: TimeInterval = 12 * 60 * 60

    // MARK: - staleThreshold

    @Test("threshold: twiceDaily floor (policyFloor + 1h) wins for a short refresh interval")
    func thresholdTwiceDailyPolicyFloorWins() {
        // refreshInterval*2 = 7200, transactionSyncInterval*2 = 3600,
        // policyFloor (12h) + 1h slack = 46800 → max is 46800.
        let threshold = SyncStaleness.staleThreshold(
            refreshInterval: oneHour,
            refreshPolicy: .twiceDaily
        )
        #expect(threshold == twelveHours + oneHour)
    }

    @Test("threshold: a long refresh interval dominates the floor")
    func thresholdRefreshIntervalWins() {
        // refreshInterval*2 = 120000 > 46800.
        let threshold = SyncStaleness.staleThreshold(
            refreshInterval: 60_000,
            refreshPolicy: .twiceDaily
        )
        #expect(threshold == 120_000)
    }

    @Test("threshold: manualOnly uses the 24h fallback floor + 1h slack")
    func thresholdManualOnlyFallbackFloor() {
        // minimumInterval is nil → manualOnlyFloor (86400) + 3600 = 90000,
        // which beats refreshInterval*2 (7200) and transactionSyncInterval*2 (3600).
        let threshold = SyncStaleness.staleThreshold(
            refreshInterval: oneHour,
            refreshPolicy: .manualOnly
        )
        #expect(threshold == SyncStaleness.manualOnlyFloor + oneHour)
        #expect(threshold == 90_000)
    }

    @Test("threshold: transactionSyncInterval*2 can win for a tiny refresh interval")
    func thresholdTransactionSyncWins() {
        // refreshInterval*2 = 100, transactionSyncInterval*2 = 3600,
        // policyFloor: pass a tiny override via manualOnly with explicit txn interval.
        // Use a degenerate refresh interval and a manual policy with a small slice:
        // here transactionSyncInterval is overridden large to dominate.
        let threshold = SyncStaleness.staleThreshold(
            refreshInterval: 1,
            transactionSyncInterval: 100_000,
            refreshPolicy: .twiceDaily
        )
        #expect(threshold == 200_000)
    }

    // MARK: - isStale

    @Test("isStale: boot load in flight is never stale, even with no prior sync")
    func isStaleBootSuppressed() {
        #expect(SyncStaleness.isStale(
            isBootLoadInFlight: true,
            lastSyncDate: nil,
            refreshInterval: oneHour,
            refreshPolicy: .twiceDaily,
            asOf: Date()
        ) == false)
    }

    @Test("isStale: never synced past boot is stale")
    func isStaleNeverSynced() {
        #expect(SyncStaleness.isStale(
            isBootLoadInFlight: false,
            lastSyncDate: nil,
            refreshInterval: oneHour,
            refreshPolicy: .twiceDaily,
            asOf: Date()
        ) == true)
    }

    @Test("isStale: just past the threshold is stale; just under is fresh")
    func isStaleThresholdBoundary() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let threshold = SyncStaleness.staleThreshold(
            refreshInterval: oneHour,
            refreshPolicy: .twiceDaily
        ) // 46800
        let staleSync = now.addingTimeInterval(-(threshold + 1))
        let freshSync = now.addingTimeInterval(-(threshold - 1))
        // Exactly at the threshold is NOT stale (strict greater-than).
        let exactSync = now.addingTimeInterval(-threshold)

        #expect(SyncStaleness.isStale(
            isBootLoadInFlight: false, lastSyncDate: staleSync,
            refreshInterval: oneHour, refreshPolicy: .twiceDaily, asOf: now
        ) == true)
        #expect(SyncStaleness.isStale(
            isBootLoadInFlight: false, lastSyncDate: freshSync,
            refreshInterval: oneHour, refreshPolicy: .twiceDaily, asOf: now
        ) == false)
        #expect(SyncStaleness.isStale(
            isBootLoadInFlight: false, lastSyncDate: exactSync,
            refreshInterval: oneHour, refreshPolicy: .twiceDaily, asOf: now
        ) == false)
    }

    // MARK: - statusText

    @Test("statusText: boot load shows Syncing")
    func statusTextBoot() {
        #expect(SyncStaleness.statusText(
            isBootLoadInFlight: true, lastSyncRelative: "2h ago", isStale: true
        ) == "Syncing")
    }

    @Test("statusText: no relative timestamp shows Never synced")
    func statusTextNeverSynced() {
        #expect(SyncStaleness.statusText(
            isBootLoadInFlight: false, lastSyncRelative: nil, isStale: false
        ) == "Never synced")
    }

    @Test("statusText: stale and fresh prefix the relative timestamp")
    func statusTextStaleFresh() {
        #expect(SyncStaleness.statusText(
            isBootLoadInFlight: false, lastSyncRelative: "2h ago", isStale: true
        ) == "Stale 2h ago")
        #expect(SyncStaleness.statusText(
            isBootLoadInFlight: false, lastSyncRelative: "2h ago", isStale: false
        ) == "Synced 2h ago")
    }
}
