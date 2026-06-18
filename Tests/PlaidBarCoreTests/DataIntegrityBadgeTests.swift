import Foundation
@testable import PlaidBarCore
import Testing

@Suite("Data Integrity Badge Tests")
struct DataIntegrityBadgeTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("Fresh and all items synced -> nil")
    func freshAllSyncedIsNil() {
        let result = DataIntegrityBadge.evaluate(
            isSyncStale: false,
            isBootLoadInFlight: false,
            itemCount: 2,
            syncedItemCount: 2,
            degradedItemCount: 0,
            needsSyncItemCount: 0,
            lastSync: now,
            lastSyncRelative: "2 minutes ago",
            now: now
        )
        #expect(result == nil)
    }

    @Test("Boot load in flight -> nil even if counts look partial")
    func bootLoadIsNil() {
        let result = DataIntegrityBadge.evaluate(
            isSyncStale: true,
            isBootLoadInFlight: true,
            itemCount: 2,
            syncedItemCount: 1,
            degradedItemCount: 1,
            needsSyncItemCount: 1,
            lastSync: nil,
            lastSyncRelative: nil,
            now: now
        )
        #expect(result == nil)
    }

    @Test("Sync stale -> .stale with relative token and non-empty icon")
    func staleVerdict() {
        let result = DataIntegrityBadge.evaluate(
            isSyncStale: true,
            isBootLoadInFlight: false,
            itemCount: 2,
            syncedItemCount: 2,
            degradedItemCount: 0,
            needsSyncItemCount: 0,
            lastSync: now,
            lastSyncRelative: "3 days ago",
            now: now
        )
        #expect(result?.severity == .stale)
        #expect(result?.title.contains("3 days ago") == true)
        #expect(result?.iconName.isEmpty == false)
    }

    @Test("syncedItemCount < itemCount, not stale -> .partial 'may be incomplete'")
    func partialFromUnsyncedItems() {
        let result = DataIntegrityBadge.evaluate(
            isSyncStale: false,
            isBootLoadInFlight: false,
            itemCount: 2,
            syncedItemCount: 1,
            degradedItemCount: 0,
            needsSyncItemCount: 0,
            lastSync: now,
            lastSyncRelative: "5 minutes ago",
            now: now
        )
        #expect(result?.severity == .partial)
        #expect(result?.title.contains("may be incomplete since") == true)
    }

    @Test("degradedItemCount > 0 while counts equal -> .partial")
    func partialFromDegradedItems() {
        let result = DataIntegrityBadge.evaluate(
            isSyncStale: false,
            isBootLoadInFlight: false,
            itemCount: 2,
            syncedItemCount: 2,
            degradedItemCount: 1,
            needsSyncItemCount: 0,
            lastSync: now,
            lastSyncRelative: "5 minutes ago",
            now: now
        )
        #expect(result?.severity == .partial)
    }

    @Test("needsSyncItemCount > 0 -> .partial")
    func partialFromNeedsSync() {
        let result = DataIntegrityBadge.evaluate(
            isSyncStale: false,
            isBootLoadInFlight: false,
            itemCount: 2,
            syncedItemCount: 2,
            degradedItemCount: 0,
            needsSyncItemCount: 1,
            lastSync: now,
            lastSyncRelative: "5 minutes ago",
            now: now
        )
        #expect(result?.severity == .partial)
    }

    @Test("lastSync nil and not boot -> .stale Never")
    func neverSyncedIsStale() {
        let result = DataIntegrityBadge.evaluate(
            isSyncStale: true,
            isBootLoadInFlight: false,
            itemCount: 1,
            syncedItemCount: 0,
            degradedItemCount: 0,
            needsSyncItemCount: 0,
            lastSync: nil,
            lastSyncRelative: nil,
            now: now
        )
        #expect(result?.severity == .stale)
        #expect(result?.title.contains("Never") == true)
    }

    @Test("Stale takes precedence over partial when both true")
    func stalePrecedence() {
        let result = DataIntegrityBadge.evaluate(
            isSyncStale: true,
            isBootLoadInFlight: false,
            itemCount: 2,
            syncedItemCount: 1,
            degradedItemCount: 1,
            needsSyncItemCount: 1,
            lastSync: now,
            lastSyncRelative: "4 days ago",
            now: now
        )
        #expect(result?.severity == .stale)
    }

    @Test("accessibilityLabel carries the date/relative token, not color")
    func accessibilityLabelCarriesToken() {
        let result = DataIntegrityBadge.evaluate(
            isSyncStale: true,
            isBootLoadInFlight: false,
            itemCount: 1,
            syncedItemCount: 1,
            degradedItemCount: 0,
            needsSyncItemCount: 0,
            lastSync: now,
            lastSyncRelative: "3 days ago",
            now: now
        )
        #expect(result?.accessibilityLabel.isEmpty == false)
        #expect(result?.accessibilityLabel.contains("3 days ago") == true)
    }

    @Test("Result is Equatable for clean @Observable reads")
    func resultIsEquatable() {
        let a = DataIntegrityBadge.Result(
            severity: .partial, title: "t", detail: "d", iconName: "i", accessibilityLabel: "a"
        )
        let b = DataIntegrityBadge.Result(
            severity: .partial, title: "t", detail: "d", iconName: "i", accessibilityLabel: "a"
        )
        #expect(a == b)
    }
}
