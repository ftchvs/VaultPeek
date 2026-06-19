import Foundation
import OSLog
import PlaidBarCache
import PlaidBarCore

/// AppState wiring for the disposable per-transaction SwiftData cache that backs
/// the virtualized large-history list (AND-567).
///
/// Built on the AND-566 seams: it reuses ``readModelCacheKey()`` for environment
/// scoping and the same lazy, per-directory store-open pattern. Two seams only:
///   1. **Post-refresh persist** — `persistTransactionCache()` runs from the same
///      `writeGlanceSnapshot()` seam as the read-model cache, mirroring the live
///      transactions into the cache (upsert, no duplicates) so the paged list is
///      ready on the next open.
///   2. **List data source** — `makePagedTransactionSource(fallback:)` hands the
///      virtualized list a ``PagedTransactionSource`` over the cache, falling back
///      to the supplied in-memory array when the cache is unavailable/disabled.
///
/// Everything is best-effort and fallback-safe: any failure leaves the list on
/// today's in-memory rendering (no regression).
extension AppState {
    nonisolated static let transactionCacheLogger = Logger(
        subsystem: "com.ftchvs.PlaidBar",
        category: "TransactionCache"
    )

    /// Lazily opens (or re-opens) the on-disk per-transaction store for the active
    /// data directory. Returns `nil` — and stays disabled for this call — when the
    /// cache is feature-disabled, in demo mode, or when SwiftData fails to open the
    /// store. Reopens when the active storage directory changes so the store always
    /// matches the environment whose key it is asked about.
    func transactionCacheStoreIfAvailable() -> TransactionCacheStore? {
        guard readModelCacheEnabled, !isDemoMode else { return nil }

        let directory = activeStorageDirectoryURL
        let directoryPath = directory.standardizedFileURL.path

        if let existing = transactionCacheStore,
           transactionCacheStoreDirectoryPath == directoryPath {
            return existing
        }

        do {
            let store = try TransactionCacheStore(onDiskIn: directory)
            transactionCacheStore = store
            transactionCacheStoreDirectoryPath = directoryPath
            return store
        } catch {
            AppState.transactionCacheLogger.error(
                "Transaction cache unavailable: \(String(describing: error), privacy: .public)"
            )
            transactionCacheStore = nil
            transactionCacheStoreDirectoryPath = nil
            return nil
        }
    }

    /// Best-effort persist of the current authoritative transactions into the
    /// disposable per-transaction cache. Called from `writeGlanceSnapshot()` after
    /// every refresh. `replaceAll` so a refresh that *removed* transactions does not
    /// leave stale rows behind. Detached so it never delays the render; failures are
    /// swallowed (the list still renders the in-memory array).
    func persistTransactionCache() {
        guard readModelCacheEnabled, !isDemoMode,
              !transactions.isEmpty,
              let store = transactionCacheStoreIfAvailable(),
              let cacheKey = readModelCacheKey()
        else { return }

        let snapshot = transactions
        Task.detached {
            do {
                try await store.replaceAll(cacheKey: cacheKey, transactions: snapshot)
            } catch {
                AppState.transactionCacheLogger.error(
                    "Transaction cache write failed: \(String(describing: error), privacy: .public)"
                )
            }
        }
    }

    /// Builds a data source for the virtualized transaction list. When the cache is
    /// available it pages from SwiftData; otherwise (disabled / unavailable / no
    /// context yet) the source stays on `fallback` and the list renders exactly the
    /// in-memory rows it does today — no regression.
    func makePagedTransactionSource(fallback: [TransactionDTO]) -> PagedTransactionSource {
        PagedTransactionSource(
            fallbackTransactions: fallback,
            store: transactionCacheStoreIfAvailable(),
            cacheKey: readModelCacheKey()
        )
    }

    /// Wipes the disposable per-transaction cache alongside the other caches on
    /// local reset, so a post-reset list never pages pre-reset transactions.
    func clearTransactionCache() async {
        guard let store = transactionCacheStore else { return }
        try? await store.clearAll()
        transactionCacheStore = nil
        transactionCacheStoreDirectoryPath = nil
    }
}
