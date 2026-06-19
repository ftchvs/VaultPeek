import Foundation
import OSLog
import PlaidBarCache
import PlaidBarCore

/// AppState wiring for the disposable SwiftData read-model cache (AND-566).
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
extension AppState {
    nonisolated static let readModelCacheLogger = Logger(
        subsystem: "com.ftchvs.PlaidBar",
        category: "ReadModelCache"
    )

    /// Lazily opens (or re-opens) the on-disk disposable store for the active
    /// data directory. Returns `nil` — and stays disabled for this call — when
    /// the cache is feature-disabled, when in demo mode (demo data is never
    /// cached), or when SwiftData fails to open the store. Reopens when the
    /// active storage directory changes (e.g. sandbox↔production switch) so the
    /// store always matches the environment whose key it is asked about.
    func readModelCacheStoreIfAvailable() -> ReadModelCacheStore? {
        guard readModelCacheEnabled, !isDemoMode else { return nil }

        let directory = activeStorageDirectoryURL
        let directoryPath = directory.standardizedFileURL.path

        if let existing = readModelCacheStore,
           readModelCacheStoreDirectoryPath == directoryPath {
            return existing
        }

        do {
            let store = try ReadModelCacheStore(onDiskIn: directory)
            readModelCacheStore = store
            readModelCacheStoreDirectoryPath = directoryPath
            return store
        } catch {
            // SwiftData unavailable / store unopenable: behave exactly as before
            // the cache existed. Logged without any financial material.
            AppState.readModelCacheLogger.error(
                "Read-model cache unavailable: \(String(describing: error), privacy: .public)"
            )
            readModelCacheStore = nil
            readModelCacheStoreDirectoryPath = nil
            return nil
        }
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
        Task.detached {
            do {
                try await store.save(model)
            } catch {
                AppState.readModelCacheLogger.error(
                    "Read-model cache write failed: \(String(describing: error), privacy: .public)"
                )
            }
        }
    }

    /// Wipes the disposable cache alongside the JSON/SQLite caches on local reset.
    func clearReadModelCache() async {
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
