import Foundation

/// A point-in-time record of net balance for sparkline history
public struct BalanceSnapshot: Codable, Sendable, Equatable {
    public let date: Date
    public let balance: Double

    public init(date: Date, balance: Double) {
        self.date = date
        self.balance = balance
    }
}

public enum BalanceHistoryReducer {
    /// Appends a snapshot to history at one-per-day granularity: an existing
    /// snapshot from the same day is replaced (the background refresh runs many
    /// times a day), and entries older than the retention window are pruned.
    public static func appending(
        _ snapshot: BalanceSnapshot,
        to history: [BalanceSnapshot],
        retentionDays: Int = 90,
        calendar: Calendar = .current
    ) -> [BalanceSnapshot] {
        var updated = history.filter {
            !calendar.isDate($0.date, inSameDayAs: snapshot.date)
        }
        updated.append(snapshot)

        let cutoff = calendar.date(byAdding: .day, value: -retentionDays, to: snapshot.date) ?? snapshot.date
        // Strict < keeps a snapshot recorded exactly retentionDays ago, giving
        // an inclusive window; any "last N days" UI copy should match this.
        updated.removeAll { $0.date < cutoff }
        return updated.sorted { $0.date < $1.date }
    }
}
