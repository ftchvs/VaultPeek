import Foundation
import PlaidBarCore

/// Outcome of a clear-gated `replaceAll`: either the rows were committed (carrying
/// the upsert plan so callers/tests can assert the blast radius) or the persist was
/// dropped because a `clearAll()` won the two-hop race (AND-633).
public enum ClearGatedWriteResult: Sendable {
    case committed(CachedTransactionUpsert.Plan)
    case dropped

    /// `true` when the write was dropped because a clear won.
    public var wasDropped: Bool {
        if case .dropped = self { return true }
        return false
    }
}

/// Actor-isolated store for the **disposable per-transaction** cache that feeds
/// the virtualized large-history list (AND-567).
///
/// ## Contract
/// - **Disposable cache, never authoritative.** Written after a successful
///   refresh/decode from the authoritative in-memory transactions, read back in
///   pages to paint a virtualized list. Deleting the store file is always safe:
///   it rebuilds on the next refresh.
/// - **Fallback-safe.** Every operation `throws`; callers wrap in `try?` so any
///   init/read/write failure degrades to exactly today's in-memory rendering.
///
/// ## Isolation / Privacy
/// Only `Sendable` ``TransactionDTO`` values cross the actor boundary. The
/// on-disk file lives only in `~/.vaultpeek/` (`0o700`/`0o600`), never the App
/// Group container or iCloud.
public actor TransactionCacheStore {
    /// Filename of the disposable per-transaction store. The `.store` suffix is
    /// preserved for compatibility with existing reset/privacy docs.
    public static let storeFilename = "transaction-cache-v1.store"

    private struct Snapshot: Codable, Sendable {
        var rowsByUniqueKey: [String: CachedTransaction]
    }

    /// Monotonic data generation, bumped by every write (`upsert`/`replaceAll`/
    /// `clearAll`). The cached ordering (``orderCache``) is keyed off this so a
    /// write invalidates the memoized sort without needing to clear it eagerly.
    private var dataGeneration: UInt64 = 0

    /// Monotonic **clear** generation, bumped only by `clearAll()`. Distinct from
    /// `dataGeneration` (which bumps on every write): a clear-gated persist must be
    /// dropped only when a *clear* — not an ordinary upsert — has landed since it
    /// captured its token. Lets a scheduled `replaceAll` re-validate, **on this
    /// actor**, that no clear raced in after it captured a token, closing the
    /// two-hop persist-after-clear window the main-actor `ReadModelCacheClearGate`
    /// epoch alone cannot (AND-633).
    private var clearGeneration: UInt64 = 0

    /// Memoized newest-first row ordering for one `cacheKey`, plus the generation
    /// it was built for. Reused across consecutive reads of the same key within one
    /// paging session so the `O(N log N)` filter+sort runs once per data
    /// generation, not per page.
    private var orderCache: (generation: UInt64, cacheKey: String, rows: [CachedTransaction])?

    private let storeURL: URL?
    private let fileManager: FileManager
    private var rowsByUniqueKey: [String: CachedTransaction]

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

    init(storeURL: URL?, fileManager: FileManager = .default) throws {
        self.storeURL = storeURL
        self.fileManager = fileManager
        if let storeURL, fileManager.fileExists(atPath: storeURL.path) {
            let data = try Data(contentsOf: storeURL)
            self.rowsByUniqueKey = try Self.decoder.decode(Snapshot.self, from: data).rowsByUniqueKey
        } else {
            self.rowsByUniqueKey = [:]
        }
    }

    // MARK: - Writes

    /// Upserts a batch of transactions for `cacheKey`. Re-syncing a transaction
    /// (same id) replaces its row in place — no duplicates. The dedup/insert-vs-
    /// update decision is the pure ``CachedTransactionUpsert`` (last-write-wins
    /// within the batch). Returns the plan so callers/tests can assert the blast
    /// radius. One persistence write at the end.
    @discardableResult
    public func upsert(cacheKey: String, transactions: [TransactionDTO]) throws -> CachedTransactionUpsert.Plan {
        let existingIds = existingTransactionIds(cacheKey: cacheKey)
        let plan = CachedTransactionUpsert.plan(incoming: transactions, existingIds: existingIds)
        guard !plan.rows.isEmpty else { return plan }

        for dto in plan.rows {
            let key = CachedTransaction.makeUniqueKey(cacheKey: cacheKey, transactionId: dto.id)
            let payload = try Self.encoder.encode(dto)
            rowsByUniqueKey[key] = CachedTransaction(
                uniqueKey: key,
                cacheKey: cacheKey,
                transactionId: dto.id,
                sortDate: dto.date,
                payload: payload
            )
        }
        try persist()
        invalidateOrderCache()
        return plan
    }

    /// Replaces the entire cached history for `cacheKey`: clears every row, then
    /// upserts the fresh set. Used when the authoritative array is reassigned
    /// wholesale (a full refresh or an environment switch) so removed transactions
    /// do not linger in the cache.
    @discardableResult
    public func replaceAll(cacheKey: String, transactions: [TransactionDTO]) throws -> CachedTransactionUpsert.Plan {
        rowsByUniqueKey.removeAll()
        try persist()
        invalidateOrderCache()
        return try upsert(cacheKey: cacheKey, transactions: transactions)
    }

    /// Removes every cached transaction (any environment). Used on local-data reset
    /// and before reseeding a different environment.
    ///
    /// Bumps `clearGeneration` so any persist that captured an earlier generation
    /// and reaches `replaceAll(cacheKey:transactions:ifNotClearedSince:)` afterwards
    /// on this actor drops itself rather than repopulating wiped rows (AND-633).
    public func clearAll() throws {
        clearGeneration &+= 1
        rowsByUniqueKey.removeAll()
        try persist()
        invalidateOrderCache()
    }

    /// The current clear generation. A scheduled persist captures this on the store
    /// actor when it is about to commit, then passes it to
    /// `replaceAll(cacheKey:transactions:ifNotClearedSince:)` so the persist drops
    /// itself if a `clearAll()` raced in between (AND-633).
    public func currentClearGeneration() -> UInt64 {
        clearGeneration
    }

    /// Atomic clear-gated `replaceAll`. Re-checks the clear generation **as the
    /// first action on this actor** and, if a `clearAll()` has run since
    /// `capturedGeneration` was taken, drops the persist entirely (returning a
    /// dropped result) rather than repopulating removed-institution transactions.
    /// Because the generation check and the row replace are one actor-isolated hop,
    /// no `clearAll()` can interleave between them — closing the two-hop window the
    /// main-actor epoch gate leaves open (AND-633).
    ///
    /// Returns `.committed(plan)` when the rows were replaced, `.dropped` when the
    /// persist was dropped because a clear won.
    @discardableResult
    public func replaceAll(
        cacheKey: String,
        transactions: [TransactionDTO],
        ifNotClearedSince capturedGeneration: UInt64
    ) throws -> ClearGatedWriteResult {
        guard capturedGeneration == clearGeneration else { return .dropped }
        return .committed(try replaceAll(cacheKey: cacheKey, transactions: transactions))
    }

    // MARK: - Reads

    /// Total cached transactions for `cacheKey`.
    ///
    /// Reuses the memoized newest-first ordering (rebuilt only when a write bumped
    /// the data generation), so a `count()` adjacent to `page()` calls in the same
    /// paging session shares one filter+sort rather than redoing it.
    public func count(cacheKey: String) throws -> Int {
        try orderedRows(cacheKey: cacheKey).count
    }

    /// Reads one newest-first page of transactions for `cacheKey`.
    public func page(cacheKey: String, window: TransactionPageWindow) throws -> [TransactionDTO] {
        guard window.limit > 0 else { return [] }
        let ordered = try orderedRows(cacheKey: cacheKey)
        let pageSlice = ordered.dropFirst(window.offset).prefix(window.limit)
        return try pageSlice.map { try Self.decoder.decode(TransactionDTO.self, from: $0.payload) }
    }

    /// Newest-first ordering over the stored scalar columns: `sortDate` descending
    /// (lexicographic order of `YYYY-MM-DD` equals chronological), `transactionId`
    /// descending as a stable tiebreak within a day.
    nonisolated private static func isNewerFirst(_ lhs: CachedTransaction, _ rhs: CachedTransaction) -> Bool {
        if lhs.sortDate != rhs.sortDate {
            return lhs.sortDate > rhs.sortDate
        }
        return lhs.transactionId > rhs.transactionId
    }

    // MARK: - Private

    /// The newest-first ordered rows for `cacheKey`, memoized per data generation.
    private func orderedRows(cacheKey: String) throws -> [CachedTransaction] {
        if let cached = orderCache, cached.generation == dataGeneration, cached.cacheKey == cacheKey {
            return cached.rows
        }
        let ordered = rowsByUniqueKey.values
            .filter { $0.cacheKey == cacheKey }
            .sorted(by: Self.isNewerFirst)
        orderCache = (dataGeneration, cacheKey, ordered)
        return ordered
    }

    /// Invalidates the memoized ordering by advancing the data generation. Called
    /// after every write so the next read rebuilds the sort.
    private func invalidateOrderCache() {
        dataGeneration &+= 1
        orderCache = nil
    }

    /// The transaction ids currently stored for `cacheKey`. Used inside `upsert`
    /// to decide insert-vs-update.
    private func existingTransactionIds(cacheKey: String) -> Set<String> {
        Set(rowsByUniqueKey.values.filter { $0.cacheKey == cacheKey }.map(\.transactionId))
    }

    private func persist() throws {
        guard let storeURL else { return }
        let data = try Self.encoder.encode(Snapshot(rowsByUniqueKey: rowsByUniqueKey))
        try fileManager.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try data.write(to: storeURL, options: [.atomic])
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storeURL.path)
    }
}
