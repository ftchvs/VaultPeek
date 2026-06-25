import Foundation
import OSLog
import PlaidBarCache
import PlaidBarCore

/// AppState wiring for the disposable per-transaction cache that backs
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
///
/// ## Persist/clear ordering (clear-wins)
/// `persistTransactionCache()` schedules its `replaceAll` off the main actor so it
/// never delays the render. `clearTransactionCache()` wipes the same store on local
/// reset / last-institution removal. Those two land on the store actor in an
/// undefined order, so without a guard an in-flight persist of the *previous*
/// (non-empty) transactions could commit *after* the clear — repopulating
/// `transaction-cache-v1.store` with removed-institution rows that the cold-start
/// paged read then surfaces.
///
/// This cache routes through the *same* ``ReadModelCacheClearGate`` the read-model
/// cache uses (see `AppState+ReadModelCache.swift`), so both caches clear/persist
/// from the same two seams in the same program order under one monotonic epoch.
/// `persistTransactionCache()` captures `currentEpoch` synchronously on the main
/// actor as it schedules, and re-checks `mayCommit(capturedEpoch:)` (still on the
/// main actor) immediately before committing; `clearTransactionCache()` calls
/// `beginClear()` unconditionally as its first line (even when no store is open).
/// Because the epoch bump and the capture/recheck both run synchronously on the
/// main actor, a clear requested after a persist in program order is always
/// observed by that persist.
///
/// ## Two-hop residual closed at the store actor (AND-633)
/// As with the read-model cache, the main-actor epoch recheck and the store
/// `replaceAll` are separate awaits, leaving a narrow window where a clear could
/// land in between. ``TransactionCacheStore`` closes it the same way: it owns a
/// monotonic clear generation (bumped by `clearAll()`), and the persist captures
/// `currentClearGeneration()` and passes it to
/// `replaceAll(cacheKey:transactions:ifNotClearedSince:)`, which re-validates the
/// generation **as its first action on the store actor** (FIFO-ordered against
/// `clearAll()`). The check and the row replace are one atomic actor hop, so a
/// clear always wins. The main-actor epoch is retained as a cheap fast-drop.
extension AppState {
    nonisolated static let transactionCacheLogger = Logger(
        subsystem: "com.ftchvs.PlaidBar",
        category: "TransactionCache"
    )

    /// Lazily opens (or re-opens) the on-disk per-transaction store for the active
    /// data directory. Returns `nil` — and stays disabled for this call — when the
    /// cache is feature-disabled, in demo mode, or when the file-backed store fails
    /// to open. Reopens when the active storage directory changes so the store always
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
        // Capture the clear epoch synchronously on the main actor as this write is
        // scheduled. The replace below only commits if no clear has been requested
        // since — so a clear (local reset / last institution removed) can never be
        // overwritten by this in-flight write. Shared with the read-model cache via
        // `ReadModelCacheClearGate`.
        let gate = ReadModelCacheClearGate.shared
        let capturedEpoch = gate.currentEpoch
        Task.detached {
            do {
                // First line of defense: a cheap main-actor epoch recheck drops the
                // wide race where a clear was requested after this persist was
                // scheduled.
                guard await gate.mayCommit(capturedEpoch: capturedEpoch) else { return }
                // Second line of defense (AND-633): capture the store's clear
                // generation and pass it INTO the atomic, clear-gated replaceAll.
                // The check and the row replace are one store-actor hop, FIFO-ordered
                // against `clearAll()`, so a clear that lands in the gap between the
                // epoch recheck above and this commit still wins — closing the
                // two-hop persist-after-clear window the main-actor epoch alone
                // cannot.
                let capturedGeneration = await store.currentClearGeneration()
                try await store.replaceAll(
                    cacheKey: cacheKey,
                    transactions: snapshot,
                    ifNotClearedSince: capturedGeneration
                )
            } catch {
                AppState.transactionCacheLogger.error(
                    "Transaction cache write failed: \(String(describing: error), privacy: .public)"
                )
            }
        }
    }

    /// Builds a data source for the virtualized transaction list. When the cache is
    /// available it pages from the file-backed store; otherwise (disabled / unavailable / no
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
    ///
    /// Bumps the shared clear epoch synchronously *first* (via the same
    /// ``ReadModelCacheClearGate`` the read-model cache uses) so any persist already
    /// scheduled in program order observes the clear and drops its `replaceAll` —
    /// the clear must win over an in-flight persist of the prior (non-empty)
    /// transactions. The epoch is bumped unconditionally (even when no store is
    /// open) so a clear requested while the store is briefly absent still
    /// invalidates a concurrently scheduled write. Mirrors `clearReadModelCache()`.
    func clearTransactionCache() async {
        ReadModelCacheClearGate.shared.beginClear()
        guard let store = transactionCacheStore else { return }
        try? await store.clearAll()
        transactionCacheStore = nil
        transactionCacheStoreDirectoryPath = nil
    }
}
