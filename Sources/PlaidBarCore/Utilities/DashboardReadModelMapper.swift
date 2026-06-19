import Foundation

/// Pure, testable mapping between the authoritative in-memory DTOs and the
/// disposable ``DashboardReadModel`` cache payload (AND-566).
///
/// Kept free of SwiftData and of any I/O so the DTO↔read-model transform can be
/// unit-tested in isolation. The SwiftData persistence layer (app target) calls
/// into this to build the row it stores and to read a hydrated model back; it
/// never re-derives these numbers itself.
public enum DashboardReadModelMapper {
    /// Builds the cache key for a given environment + storage directory. Scoping
    /// the single cached row by environment + data dir guarantees a
    /// sandbox/production switch (or a relocated data dir) reads as a cache miss
    /// rather than surfacing a foreign environment's balances.
    public static func cacheKey(environment: PlaidEnvironment, storagePath: String) -> String {
        let normalizedPath = URL(
            fileURLWithPath: NSString(string: storagePath).expandingTildeInPath,
            isDirectory: true
        ).standardizedFileURL.path
        return "\(environment.rawValue)|\(normalizedPath)"
    }

    /// Builds a disposable read-model from the current authoritative dashboard
    /// data. Recent transactions are sorted newest-first and capped to the
    /// dashboard window so the cached row is bounded and matches what the popover
    /// renders. The summary reuses the same `MenuBarSummary` aggregators the live
    /// dashboard uses, so the cold frame's headline equals the warm one.
    public static func makeReadModel(
        cacheKey: String,
        accounts: [AccountDTO],
        transactions: [TransactionDTO],
        maxRecentTransactions: Int = PlaidBarConstants.maxRecentTransactions,
        generatedAt: Date
    ) -> DashboardReadModel {
        let recent = Array(
            transactions
                .sorted { $0.date > $1.date }
                .prefix(max(0, maxRecentTransactions))
        )
        let summary = DashboardReadModel.Summary(
            netCash: MenuBarSummary.netCash(from: accounts),
            totalDebt: MenuBarSummary.totalDebt(from: accounts.filter { $0.type == .credit }),
            accountCount: accounts.count
        )
        return DashboardReadModel(
            cacheKey: cacheKey,
            accounts: accounts,
            recentTransactions: recent,
            summary: summary,
            generatedAt: generatedAt
        )
    }

    /// Decoded DTOs ready to seed the cold-start render. Returns `nil` when the
    /// row is from an older schema, is empty, or its key does not match the
    /// active environment — every one of which must fall back to today's
    /// empty/loading path rather than render mismatched data.
    public static func hydrate(
        from model: DashboardReadModel,
        expectedCacheKey: String
    ) -> Hydration? {
        guard model.isCurrentSchema,
              model.cacheKey == expectedCacheKey,
              !model.isEmpty
        else { return nil }
        return Hydration(
            accounts: model.accounts,
            recentTransactions: model.recentTransactions
        )
    }

    /// The DTO payload pulled back out of a cached read-model for first-frame
    /// hydration. Mirrors the two authoritative arrays AppState seeds on a warm
    /// start, nothing more.
    public struct Hydration: Sendable, Equatable {
        public let accounts: [AccountDTO]
        public let recentTransactions: [TransactionDTO]

        public init(accounts: [AccountDTO], recentTransactions: [TransactionDTO]) {
            self.accounts = accounts
            self.recentTransactions = recentTransactions
        }
    }
}
