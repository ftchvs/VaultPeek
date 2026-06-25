import Foundation

/// A disposable, rebuildable snapshot of just enough decoded data to paint the
/// dashboard popover's first frame instantly on a cold start — before the HTTP
/// refresh returns (AND-566).
///
/// This is a **read-model cache**, never a source of truth. The authoritative
/// data path stays the in-memory DTOs + JSON ledger + UserDefaults caches the
/// app already keeps. This struct is the serialized shape the disposable
/// file-backed store persists after a successful refresh/decode and reads back
/// on the next launch. If it is missing, stale, or fails to decode, the app
/// falls back to exactly its prior behavior (empty/loading → HTTP refresh).
///
/// It carries the same `Sendable` DTOs the dashboard already renders
/// (``AccountDTO`` / ``TransactionDTO``) plus a small derived summary so the
/// menu-bar headline can render without recomputation. It is a pure value type
/// so it can be unit-tested and mapped without touching the cache store.
///
/// ## Privacy
/// This read-model holds financial values and Plaid identifiers (account/item
/// ids), so — like the existing `accounts.json` / `transactions.json` caches —
/// it must only ever be written into the local private data dir
/// (`~/.vaultpeek/`, `0o700`/`0o600`), never the world-readable App Group
/// container or iCloud. The redaction boundary that governs the App Group glance
/// snapshot is unchanged and unaffected by this cache.
public struct DashboardReadModel: Codable, Sendable, Equatable {
    /// Bumped whenever the persisted shape changes in a way that should
    /// invalidate older cached rows. A decoded model whose version differs from
    /// ``currentSchemaVersion`` is treated as a cache miss (rebuild from the
    /// authoritative refresh), which keeps the store disposable across upgrades.
    public static let currentSchemaVersion = 1

    /// Stable identifier for the single cached row. The cache holds exactly one
    /// read-model at a time (the last-known dashboard), keyed by the per-install
    /// data dir + Plaid environment so a sandbox/production switch never reads a
    /// foreign environment's row.
    public let cacheKey: String
    /// The schema version this row was written with.
    public let schemaVersion: Int
    /// Last-known accounts, in the dashboard's display order.
    public let accounts: [AccountDTO]
    /// Recent transactions, newest-first, already capped to the dashboard window.
    public let recentTransactions: [TransactionDTO]
    /// Pre-derived headline numbers so frame 1 needs no recomputation.
    public let summary: Summary
    /// When the authoritative data this row was built from was captured.
    public let generatedAt: Date

    /// Small derived rollup mirroring the menu-bar/overview headline so the cold
    /// frame can show real totals without re-running the aggregators. Recomputed
    /// authoritatively once the live refresh lands; values here are only a head
    /// start, never the source of truth.
    public struct Summary: Codable, Sendable, Equatable {
        /// Net cash across spendable (depository/investment) accounts minus loans.
        public let netCash: Double
        /// Total credit-card debt (positive number).
        public let totalDebt: Double
        /// Number of accounts represented.
        public let accountCount: Int

        public init(netCash: Double, totalDebt: Double, accountCount: Int) {
            self.netCash = netCash
            self.totalDebt = totalDebt
            self.accountCount = accountCount
        }
    }

    public init(
        cacheKey: String,
        schemaVersion: Int = DashboardReadModel.currentSchemaVersion,
        accounts: [AccountDTO],
        recentTransactions: [TransactionDTO],
        summary: Summary,
        generatedAt: Date
    ) {
        self.cacheKey = cacheKey
        self.schemaVersion = schemaVersion
        self.accounts = accounts
        self.recentTransactions = recentTransactions
        self.summary = summary
        self.generatedAt = generatedAt
    }

    /// True when this row was written by the current schema version. A
    /// version-mismatched row is a deliberate cache miss (rebuild), not a crash.
    public var isCurrentSchema: Bool {
        schemaVersion == DashboardReadModel.currentSchemaVersion
    }

    /// True when the row carries nothing worth rendering early. Treated as "no
    /// usable cache" so the cold path stays on today's empty/loading behavior.
    public var isEmpty: Bool {
        accounts.isEmpty && recentTransactions.isEmpty
    }
}
