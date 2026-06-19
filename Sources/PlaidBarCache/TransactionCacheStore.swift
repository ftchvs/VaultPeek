import Foundation
import PlaidBarCore
import SwiftData

/// Actor-isolated SwiftData store for the **disposable per-transaction** cache
/// that feeds the virtualized large-history list (AND-567).
///
/// ## Contract
/// - **Disposable cache, never authoritative.** Written after a successful
///   refresh/decode from the authoritative in-memory transactions, read back in
///   pages to paint a virtualized list. Deleting the store file is always safe:
///   it rebuilds on the next refresh.
/// - **Fallback-safe.** Every operation `throws`; callers wrap in `try?` so any
///   SwiftData init/read/write failure (or an unavailable store) degrades to
///   exactly today's in-memory rendering — no regression.
///
/// ## Why a second store
/// The dashboard read-model cache (``ReadModelCacheStore``) holds one bounded
/// row (the cold-start snapshot). This store holds the *full* transaction history
/// for on-demand paging, so it gets its own schema and file. Both are disposable
/// and live only in the local private data dir.
///
/// ## Paging
/// A page is the `TransactionPageWindow` slice (`offset`/`limit` from the pure
/// page-window math) of the newest-first ordering. Ordering and slicing run in
/// Swift over the lightweight stored scalar columns (`sortDate` then
/// `transactionId`, both descending), and **only the page's JSON payloads are
/// decoded** — so a multi-thousand-row history decodes just one page of
/// `TransactionDTO`s at a time. Both the sort and the cacheKey scope are done in
/// Swift rather than via `FetchDescriptor(sortBy:)`/`#Predicate`, because those
/// capture a non-`Sendable` `KeyPath` — an error under the project's Swift 6
/// strict-concurrency gate, the same constraint ``ReadModelCacheStore`` documents.
/// The store file is opened per data directory and the active environment is the
/// only one seeded into it (an environment switch calls
/// ``replaceAll(cacheKey:transactions:)`` which wipes first).
///
/// ## Isolation / Privacy
/// `@ModelActor` owns the non-`Sendable` `ModelContext`; only `Sendable`
/// ``TransactionDTO`` values cross the boundary. The on-disk file lives only in
/// `~/.vaultpeek/` (`0o700`/`0o600`), never the App Group container or iCloud.
@ModelActor
public actor TransactionCacheStore {
    /// Filename of the disposable per-transaction store. `v1` is namespaced so a
    /// future incompatible store can ship beside it and the old file be deleted.
    public static let storeFilename = "transaction-cache-v1.store"

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    // MARK: - Container factories

    public static func schema() -> Schema {
        Schema([CachedTransaction.self])
    }

    /// On-disk container under `directory` (the local private data dir), created
    /// with owner-only permissions and tightened to `0o600` after SwiftData
    /// materializes the file — matching the existing caches.
    public static func makeOnDiskContainer(
        in directory: URL,
        fileManager: FileManager = .default
    ) throws -> ModelContainer {
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let storeURL = directory.appendingPathComponent(storeFilename)
        let configuration = ModelConfiguration(
            "TransactionCache",
            schema: schema(),
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema(), configurations: configuration)
        #if os(macOS)
        for suffix in ["", "-wal", "-shm"] {
            let path = storeURL.path + suffix
            if fileManager.fileExists(atPath: path) {
                try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
            }
        }
        #endif
        return container
    }

    /// In-memory container for tests and a non-persisting fallback.
    public static func makeInMemoryContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema(), configurations: configuration)
    }

    // MARK: - Writes

    /// Upserts a batch of transactions for `cacheKey`. Re-syncing a transaction
    /// (same id) replaces its row in place via the `@Attribute(.unique)` key — no
    /// duplicates. The dedup/insert-vs-update decision is the pure
    /// ``CachedTransactionUpsert`` (last-write-wins within the batch). Returns the
    /// plan so callers/tests can assert the blast radius. One `save()` at the end.
    @discardableResult
    public func upsert(cacheKey: String, transactions: [TransactionDTO]) throws -> CachedTransactionUpsert.Plan {
        let existingIds = try existingTransactionIds(cacheKey: cacheKey)
        let plan = CachedTransactionUpsert.plan(incoming: transactions, existingIds: existingIds)
        guard !plan.rows.isEmpty else { return plan }

        // Index the existing rows we may need to overwrite so an update mutates the
        // stored row in place rather than inserting a duplicate (belt-and-braces on
        // top of the unique constraint, and avoids relying on insert-replaces-by-id
        // semantics for the payload columns).
        let updatedKeys = Set(plan.updatedIds.map {
            CachedTransaction.makeUniqueKey(cacheKey: cacheKey, transactionId: $0)
        })
        var rowsByKey: [String: CachedTransaction] = [:]
        if !updatedKeys.isEmpty {
            for row in try modelContext.fetch(FetchDescriptor<CachedTransaction>())
            where updatedKeys.contains(row.uniqueKey) {
                rowsByKey[row.uniqueKey] = row
            }
        }

        for dto in plan.rows {
            let key = CachedTransaction.makeUniqueKey(cacheKey: cacheKey, transactionId: dto.id)
            let payload = try Self.encoder.encode(dto)
            if let existing = rowsByKey[key] {
                existing.cacheKey = cacheKey
                existing.transactionId = dto.id
                existing.sortDate = dto.date
                existing.payload = payload
            } else {
                modelContext.insert(
                    CachedTransaction(
                        uniqueKey: key,
                        cacheKey: cacheKey,
                        transactionId: dto.id,
                        sortDate: dto.date,
                        payload: payload
                    )
                )
            }
        }
        try modelContext.save()
        return plan
    }

    /// Replaces the entire cached history for `cacheKey`: clears every row, then
    /// upserts the fresh set. Used when the authoritative array is reassigned
    /// wholesale (a full refresh or an environment switch) so removed transactions
    /// do not linger in the cache.
    @discardableResult
    public func replaceAll(cacheKey: String, transactions: [TransactionDTO]) throws -> CachedTransactionUpsert.Plan {
        try clearAll()
        return try upsert(cacheKey: cacheKey, transactions: transactions)
    }

    /// Removes every cached transaction (any environment). Used on local-data reset
    /// and before reseeding a different environment.
    public func clearAll() throws {
        try modelContext.delete(model: CachedTransaction.self)
        try modelContext.save()
    }

    // MARK: - Reads

    /// Total cached transactions for `cacheKey`.
    public func count(cacheKey: String) throws -> Int {
        try existingTransactionIds(cacheKey: cacheKey).count
    }

    /// Reads one newest-first page of transactions for `cacheKey`.
    ///
    /// The DB does the heavy lifting: a `FetchDescriptor` sorted by `sortDate`
    /// (then `transactionId`) descending with `fetchOffset`/`fetchLimit` taken from
    /// `window`, so only up to `window.limit` rows are materialized. The decoded
    /// DTOs are returned newest-first. A zero-limit window short-circuits to an
    /// empty page without touching the store.
    public func page(cacheKey: String, window: TransactionPageWindow) throws -> [TransactionDTO] {
        guard window.limit > 0 else { return [] }
        // Why not `FetchDescriptor(sortBy:)` + `fetchOffset/fetchLimit`: a SwiftData
        // `SortDescriptor(\.keyPath)` captures the model's `KeyPath`, which is
        // non-`Sendable` and an error under the project's Swift 6 strict-concurrency
        // gate — the same class of constraint AND-566 hit with `#Predicate`. So the
        // ordering is done in Swift over the stored scalar columns instead.
        //
        // The sort key is the lightweight `(sortDate, transactionId)` columns, not
        // the JSON blob, and crucially **only the requested page's payloads are
        // decoded** — so a multi-thousand-row history still decodes just one page of
        // `TransactionDTO`s, keeping per-page work bounded even though the row
        // *references* are sorted in memory.
        let rows = try modelContext.fetch(FetchDescriptor<CachedTransaction>())
        let ordered = rows
            .filter { $0.cacheKey == cacheKey }
            .sorted(by: Self.isNewerFirst)
        let pageSlice = ordered.dropFirst(window.offset).prefix(window.limit)
        return try pageSlice.map { try Self.decoder.decode(TransactionDTO.self, from: $0.payload) }
    }

    /// Newest-first ordering over the stored scalar columns: `sortDate` descending
    /// (lexicographic order of `YYYY-MM-DD` equals chronological), `transactionId`
    /// descending as a stable tiebreak within a day. Pure string comparison — no
    /// `KeyPath`, so it is strict-concurrency clean.
    nonisolated private static func isNewerFirst(_ lhs: CachedTransaction, _ rhs: CachedTransaction) -> Bool {
        if lhs.sortDate != rhs.sortDate {
            return lhs.sortDate > rhs.sortDate
        }
        return lhs.transactionId > rhs.transactionId
    }

    // MARK: - Private

    private func existingTransactionIds(cacheKey: String) throws -> Set<String> {
        let rows = try modelContext.fetch(FetchDescriptor<CachedTransaction>())
        return Set(rows.filter { $0.cacheKey == cacheKey }.map(\.transactionId))
    }
}
