import Foundation

/// How often VaultPeek refreshes financial data from Plaid *automatically*
/// (on popover open and via the background loop). Manual refreshes — the
/// refresh button and recovery actions — always run regardless of this policy.
///
/// The product default is twice a day: opening the popover should show cached
/// data instantly and only hit Plaid when the data is actually stale, rather
/// than syncing on every open.
public enum AutomaticRefreshPolicy: String, Codable, Sendable, CaseIterable, Equatable, Hashable {
    /// Auto-refresh at most once every 12 hours (≈ twice a day).
    case twiceDaily
    /// Never auto-refresh; only the user's manual refresh updates data.
    case manualOnly

    public static let storageKey = "data.automaticRefreshPolicy"
    public static let defaultValue = AutomaticRefreshPolicy.twiceDaily

    public var displayName: String {
        switch self {
        case .twiceDaily: "Twice a day"
        case .manualOnly: "Manual only"
        }
    }

    /// Minimum elapsed time since the last successful sync before another
    /// automatic refresh is allowed. `nil` means automatic refresh is disabled
    /// (manual only).
    public var minimumInterval: TimeInterval? {
        switch self {
        case .twiceDaily: 12 * 60 * 60
        case .manualOnly: nil
        }
    }

    /// Whether an automatic (non-user-triggered) refresh should run now, given
    /// the last successful sync time. A never-synced state (`lastSync == nil`)
    /// always refreshes once under a time-based policy so first data loads;
    /// `.manualOnly` never auto-refreshes.
    public func shouldAutoRefresh(lastSync: Date?, now: Date) -> Bool {
        guard let minimumInterval else { return false }
        guard let lastSync else { return true }
        return now.timeIntervalSince(lastSync) >= minimumInterval
    }

    /// Whether an automatic refresh should run when the app has detected a
    /// correctness-critical immediate need, such as linked items with no cached
    /// accounts yet or an item explicitly marked as needing sync. Immediate needs
    /// bypass the time floor for time-based policies, but they must not override
    /// the user's explicit Manual only choice.
    public func shouldAutoRefresh(lastSync: Date?, now: Date, hasImmediateNeed: Bool) -> Bool {
        guard minimumInterval != nil else { return false }
        if hasImmediateNeed { return true }
        return shouldAutoRefresh(lastSync: lastSync, now: now)
    }
}
