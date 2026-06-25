import Foundation
import OSLog
import PlaidBarCache
import PlaidBarCore

/// AppState wiring for the disposable read-model cache (AND-566).
///
/// Two seams only:
///   1. **Cold-start hydrate** — `hydrateFromReadModelCache()` runs inside
///      `preloadCachedDataBeforeFirstConnect()` to paint the first frame before
///      the HTTP refresh returns.
///   2. **Post-refresh persist** — `persistReadModelCache()` runs from
///      `writeGlanceSnapshot()`, the single seam already hit after every
///      refresh/sync/mutation, so the cache always trails the authoritative
///      in-memory data.
///
/// Everything is best-effort: any failure leaves the app on its existing
/// JSON/UserDefaults cold path. The cache is never read as a source of truth and
/// never blocks a render.
///
/// ## Persist/clear ordering (clear-wins)
/// `persistReadModelCache()` schedules its write off the main actor so it never
/// delays the render, and the empty-accounts path schedules a clear of the same
/// store. Those two land on the store actor in an undefined order, so without a
/// guard an in-flight persist of the *previous* (non-empty) read-model could
/// commit *after* the clear that fires when the user removes their last
/// institution — resurrecting removed-account balances on the next cold start.
///
/// `ReadModelCacheClearGate` closes that race: a monotonic clear epoch is bumped
/// synchronously on the main actor the instant a clear is requested, *before* the
/// clear's own off-main work begins. Every scheduled write captures the epoch it
/// was scheduled under and re-checks it (still on the main actor) immediately
/// before committing; if a clear has been requested since, the write is dropped.
/// Because both the epoch bump and the capture/recheck run synchronously on the
/// main actor, a clear that is *requested after* a persist in program order is
/// always observed by that persist — so a clear can never be overwritten by a
/// stale write.
@MainActor
final class ReadModelCacheClearGate {
    static let shared = ReadModelCacheClearGate()

    private var clearEpoch = 0

    /// The epoch a write should capture when it is scheduled.
    var currentEpoch: Int { clearEpoch }

    /// Marks that a clear has been requested. Call synchronously on the main
    /// actor *before* the clear's off-main work so any persist scheduled earlier
    /// in program order observes the bump and drops itself.
    func beginClear() {
        clearEpoch &+= 1
    }

    /// Whether a write scheduled under `capturedEpoch` may still commit. Returns
    /// `false` once any clear has been requested since the write was scheduled.
    func mayCommit(capturedEpoch: Int) -> Bool {
        capturedEpoch == clearEpoch
    }
}

extension AppState {
    nonisolated static let readModelCacheLogger = Logger(
        subsystem: "com.ftchvs.PlaidBar",
        category: "ReadModelCache"
    )

    /// Lazily opens (or re-opens) the on-disk disposable store for the active
    /// data directory. Returns `nil` — and stays disabled for this call — when
    /// the cache is feature-disabled or when in demo mode (demo data is never
    /// cached). Reopens when the active storage directory changes (e.g.
    /// sandbox↔production switch) so the store always matches the environment whose
    /// key it is asked about.
    ///
    /// Opening does **no** disk I/O and cannot fail: the backing file is read and
    /// decoded lazily on the store actor's executor, so this never blocks the
    /// MainActor with a full decode (AND-656 finding 3). An incompatible/corrupt
    /// file (e.g. a pre-JSON SwiftData `.store`) is self-healed into a disposable
    /// miss on that first off-main read rather than disabling the cache (AND-656
    /// finding 2).
    func readModelCacheStoreIfAvailable() -> ReadModelCacheStore? {
        guard readModelCacheEnabled, !isDemoMode else { return nil }

        let directory = activeStorageDirectoryURL
        let directoryPath = directory.standardizedFileURL.path

        if let existing = readModelCacheStore,
           readModelCacheStoreDirectoryPath == directoryPath {
            return existing
        }

        let store = ReadModelCacheStore(onDiskIn: directory)
        readModelCacheStore = store
        readModelCacheStoreDirectoryPath = directoryPath
        return store
    }

    /// The environment+directory-scoped key for the active context, or `nil`
    /// when no server context is known yet (in which case there is nothing to
    /// read or write).
    func readModelCacheKey() -> String? {
        guard let context = currentReadModelCacheContext() else { return nil }
        return DashboardReadModelMapper.cacheKey(
            environment: context.environment,
            storagePath: context.storagePath
        )
    }

    /// Best-effort cold-start hydration. Seeds `accounts`/`transactions` from the
    /// cached read-model only when both are still empty, so it never overwrites
    /// data the JSON warm path (or a fast refresh) already loaded. Any failure is
    /// swallowed — the cold path then proceeds exactly as before.
    func hydrateFromReadModelCache() async {
        guard accounts.isEmpty, transactions.isEmpty,
              let store = readModelCacheStoreIfAvailable(),
              let cacheKey = readModelCacheKey()
        else { return }

        let model = try? await store.load(cacheKey: cacheKey)
        guard let model,
              let hydration = DashboardReadModelMapper.hydrate(from: model, expectedCacheKey: cacheKey)
        else { return }

        // Re-check the empty guard: an awaited refresh could have populated these
        // between the guard above and now. The authoritative data must win.
        guard accounts.isEmpty, transactions.isEmpty else { return }
        accounts = hydration.accounts
        transactions = hydration.recentTransactions
    }

    /// Best-effort persist of the current authoritative dashboard data into the
    /// disposable cache. Called from `writeGlanceSnapshot()` after every refresh.
    /// Skips when there is nothing to cache or no context yet. Detached so it
    /// never delays the render; failures are swallowed.
    func persistReadModelCache() {
        guard readModelCacheEnabled, !isDemoMode,
              !accounts.isEmpty,
              let store = readModelCacheStoreIfAvailable(),
              let cacheKey = readModelCacheKey()
        else { return }

        let model = DashboardReadModelMapper.makeReadModel(
            cacheKey: cacheKey,
            accounts: accounts,
            transactions: transactions,
            generatedAt: Date()
        )
        // Capture the clear epoch synchronously on the main actor as this write is
        // scheduled. The save below only commits if no clear has been requested
        // since — so an empty-state clear (last institution removed) can never be
        // overwritten by this in-flight write. See `ReadModelCacheClearGate`.
        let gate = ReadModelCacheClearGate.shared
        let capturedEpoch = gate.currentEpoch
        Task.detached {
            do {
                // Re-check on the main actor right before committing: if a clear
                // raced ahead, drop this stale write rather than resurrect rows.
                guard await gate.mayCommit(capturedEpoch: capturedEpoch) else { return }
                try await store.save(model)
            } catch {
                AppState.readModelCacheLogger.error(
                    "Read-model cache write failed: \(String(describing: error), privacy: .public)"
                )
            }
        }
    }

    /// Wipes **only the read-model store** alongside the JSON/SQLite caches on local
    /// reset and on the empty-accounts path (last institution removed). The
    /// per-transaction store is wiped separately by ``clearTransactionCache()``
    /// (AND-657) — both route through the same ``ReadModelCacheClearGate`` epoch so
    /// they clear in the same program order.
    ///
    /// Bumps the clear epoch synchronously *first* so any persist already
    /// scheduled in program order observes the clear and drops its write — the
    /// empty-state clear must win over an in-flight persist of the prior
    /// (non-empty) read-model. The epoch is bumped unconditionally (even when no
    /// store is open) so a clear requested while the store is briefly absent still
    /// invalidates a concurrently scheduled write.
    func clearReadModelCache() async {
        ReadModelCacheClearGate.shared.beginClear()
        guard let store = readModelCacheStore else { return }
        try? await store.clearAll()
        readModelCacheStore = nil
        readModelCacheStoreDirectoryPath = nil
    }

    /// The active environment + storage path, sourced from the live server
    /// context when known and otherwise from the same preconnect hint the JSON
    /// warm path uses — so a cold start (before the first status check) can still
    /// read the row written under the last-known context.
    private func currentReadModelCacheContext() -> TransactionCacheContext? {
        if let live = liveTransactionCacheContext {
            return live
        }
        return preconnectReadModelCacheContextHint()
    }
}
