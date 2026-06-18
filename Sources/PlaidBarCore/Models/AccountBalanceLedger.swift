import Foundation

/// Per-account "what the bank said" ledger (AND-490). Each refresh appends one
/// dated row per account capturing exactly the bank-reported numbers (current /
/// available / limit). Mirrors `BalanceHistoryReducer`: one entry per account
/// per day with same-day replacement and a retention window. Pure, Sendable,
/// app-side JSON persistence (no SQLite, no extra Plaid calls).
public struct AccountBalanceLedger: Codable, Sendable, Equatable {
    public struct LedgerEntry: Codable, Sendable, Equatable, Identifiable {
        public let accountId: String
        public let date: Date
        public let current: Double?
        public let available: Double?
        public let limit: Double?
        public let recordedAt: Date

        /// Stable per-account-per-day identity for deduplication and diffing.
        public var id: String { "\(accountId)|\(AccountBalanceLedger.dayKey(date))" }

        public init(
            accountId: String,
            date: Date,
            current: Double?,
            available: Double?,
            limit: Double?,
            recordedAt: Date
        ) {
            self.accountId = accountId
            self.date = date
            self.current = current
            self.available = available
            self.limit = limit
            self.recordedAt = recordedAt
        }
    }

    public let entries: [LedgerEntry]

    public init(entries: [LedgerEntry] = []) {
        self.entries = entries
    }

    /// Canonical day key (YYYY-MM-DD) used for same-day replacement and ids.
    static func dayKey(_ date: Date) -> String {
        Formatters.transactionDateString(date)
    }

    /// Appends one entry per account for `accounts` at `now`, replacing any
    /// existing same-account/same-day entry, pruning entries older than the
    /// retention window, and returning a stably-sorted ledger (by date, then
    /// accountId). Reuses the BalanceHistoryReducer pattern.
    public func appending(
        accounts: [AccountDTO],
        now: Date = Date(),
        retentionDays: Int = 90,
        calendar: Calendar = .current
    ) -> AccountBalanceLedger {
        var updated = entries

        for account in accounts {
            // Drop any prior entry for this account on the same day.
            updated.removeAll {
                $0.accountId == account.id && calendar.isDate($0.date, inSameDayAs: now)
            }
            updated.append(
                LedgerEntry(
                    accountId: account.id,
                    date: now,
                    current: account.balances.current,
                    available: account.balances.available,
                    limit: account.balances.limit,
                    recordedAt: now
                )
            )
        }

        let cutoff = calendar.date(byAdding: .day, value: -retentionDays, to: now) ?? now
        updated.removeAll { $0.date < cutoff }

        updated.sort {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.accountId < $1.accountId
        }
        return AccountBalanceLedger(entries: updated)
    }

    /// Most recent entry per account (one row per account), sorted by accountId.
    public func latestEntriesByAccount() -> [LedgerEntry] {
        var latest: [String: LedgerEntry] = [:]
        for entry in entries {
            if let existing = latest[entry.accountId] {
                if entry.date > existing.date { latest[entry.accountId] = entry }
            } else {
                latest[entry.accountId] = entry
            }
        }
        return latest.values.sorted { $0.accountId < $1.accountId }
    }
}
