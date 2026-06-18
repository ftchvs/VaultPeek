import Foundation

/// Pure, Sendable decider for the per-number "data may be incomplete / stale"
/// badge (AND-489). Maps completeness inputs to an optional badge whose verdict
/// is carried by text + an SF Symbol — never color alone. Distinguishes "stale"
/// (last sync too old, all items) from "partial/incomplete" (some items not yet
/// synced, or a degraded item omitted from the totals).
public enum DataIntegrityBadge {
    public enum Severity: String, Sendable, Equatable {
        case stale
        case partial
    }

    public struct Result: Sendable, Equatable {
        public let severity: Severity
        public let title: String
        public let detail: String
        public let iconName: String
        public let accessibilityLabel: String

        public init(
            severity: Severity,
            title: String,
            detail: String,
            iconName: String,
            accessibilityLabel: String
        ) {
            self.severity = severity
            self.title = title
            self.detail = detail
            self.iconName = iconName
            self.accessibilityLabel = accessibilityLabel
        }
    }

    /// Returns nil when data is complete and fresh.
    ///
    /// Precedence:
    /// 1. boot-in-flight -> nil (first sync still running, no verdict yet)
    /// 2. stale -> `.stale` ("since <relative>", or "Never" when never synced)
    /// 3. some items unsynced OR degraded/needs-sync items exist -> `.partial`
    /// 4. otherwise -> nil
    public static func evaluate(
        isSyncStale: Bool,
        isBootLoadInFlight: Bool,
        itemCount: Int,
        syncedItemCount: Int,
        degradedItemCount: Int,
        needsSyncItemCount: Int,
        lastSync: Date?,
        lastSyncRelative: String?,
        now: Date = Date()
    ) -> Result? {
        if isBootLoadInFlight {
            return nil
        }

        if isSyncStale {
            let token = lastSync == nil ? "Never" : (lastSyncRelative ?? "recently")
            let title = lastSync == nil ? "Never synced" : "As of \(token) — sync stale"
            let detail = lastSync == nil
                ? "These numbers have not synced yet."
                : "These numbers may be out of date. Last synced \(token)."
            return Result(
                severity: .stale,
                title: title,
                detail: detail,
                iconName: "clock.badge.exclamationmark",
                accessibilityLabel: "\(title). \(detail)"
            )
        }

        let hasUnsyncedItems = syncedItemCount < itemCount
        let hasIncompleteItems = degradedItemCount > 0 || needsSyncItemCount > 0
        if hasUnsyncedItems || hasIncompleteItems {
            let token = lastSyncRelative ?? "the last sync"
            let title = "Data may be incomplete since \(token)"
            let detail: String
            if hasUnsyncedItems {
                detail = "\(syncedItemCount) of \(itemCount) connections are included; the rest are still catching up."
            } else {
                detail = "Some connections need attention, so these totals may be missing accounts."
            }
            return Result(
                severity: .partial,
                title: title,
                detail: detail,
                iconName: "exclamationmark.triangle",
                accessibilityLabel: "\(title). \(detail)"
            )
        }

        return nil
    }
}
