import Foundation
import PlaidBarCore

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

    /// Memoized newest-first row ordering for one `cacheKey`, plus the generation
    /// it was built for. Reused across consecutive reads of the same key within one
    /// paging session so the `O(N log N)` filter+sort runs once per data
    /// generation, not per page.
    private var orderCache: (generation: UInt64, cacheKey: String, rows: [CachedTransaction])?

    private let storeURL: URL?
    private let fileManager: FileManager

    /// In-memory rows, lazily hydrated from disk on first access. `nil` means the
    /// store has not yet read its backing file — opening the actor performs **no**
    /// disk I/O (AND-656 finding 3), so construction never blocks the MainActor
    /// caller with a full-history JSON decode. The potentially large read+decode is
    /// deferred to ``loadedRows()`` on the actor's own executor, off any UI path.
    private var rowsByUniqueKey: [String: CachedTransaction]?

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

    /// Opens the store **without** touching disk. Constructing the actor is now a
    /// pure, non-throwing handoff of the URL; the (potentially large) backing file
    /// is read lazily on the actor's executor (see ``loadedRows()``), so a MainActor
    /// caller never decodes the full transaction history synchronously during open
    /// (AND-656 finding 3) — opening stays cheap and paging stays the bounded path.
    init(storeURL: URL?, fileManager: FileManager = .default) {
        self.storeURL = storeURL
        self.fileManager = fileManager
        self.rowsByUniqueKey = nil
    }

    // MARK: - Lazy load / self-heal

    /// The in-memory rows, hydrating from disk on first access.
    ///
    /// An **incompatible or corrupt backing file** (e.g. a pre-JSON SwiftData
    /// `.store` that cannot decode as our `Snapshot`) is treated as a disposable
    /// cache *miss*, not a hard failure: the unreadable file is discarded and the
    /// store starts empty so the next refresh rebuilds it (AND-656 finding 2). The
    /// disposable cache therefore never permanently disables itself and never loses
    /// real data — the authoritative source is always the live in-memory data.
    private func loadedRows() -> [String: CachedTransaction] {
        if let rowsByUniqueKey { return rowsByUniqueKey }

        guard let storeURL, fileManager.fileExists(atPath: storeURL.path) else {
            rowsByUniqueKey = [:]
            return [:]
        }

        do {
            let data = try Data(contentsOf: storeURL)
            let rows = try Self.decoder.decode(Snapshot.self, from: data).rowsByUniqueKey
            rowsByUniqueKey = rows
            return rows
        } catch {
            // Undecodable file (incompatible/corrupt): discard it so the store
            // self-heals into a clean miss instead of staying permanently broken.
            discardIncompatibleStoreFile()
            rowsByUniqueKey = [:]
            return [:]
        }
    }

    /// Removes the unreadable backing file so a subsequent ``persist()`` writes a
    /// fresh, decodable snapshot. Best-effort: a failure to delete leaves the empty
    /// in-memory state, and the next atomic write overwrites the file anyway.
    private func discardIncompatibleStoreFile() {
        guard let storeURL else { return }
        try? fileManager.removeItem(at: storeURL)
    }

    // MARK: - Writes

    /// Upserts a batch of transactions for `cacheKey`. Re-syncing a transaction
    /// (same id) replaces its row in place — no duplicates. The dedup/insert-vs-
    /// update decision is the pure ``CachedTransactionUpsert`` (last-write-wins
    /// within the batch). Returns the plan so callers/tests can assert the blast
    /// radius. One persistence write at the end.
    @discardableResult
    public func upsert(cacheKey: String, transactions: [TransactionDTO]) throws -> CachedTransactionUpsert.Plan {
        var rows = loadedRows()
        let existingIds = existingTransactionIds(in: rows, cacheKey: cacheKey)
        let plan = CachedTransactionUpsert.plan(incoming: transactions, existingIds: existingIds)
        guard !plan.rows.isEmpty else { return plan }

        for dto in plan.rows {
            let key = CachedTransaction.makeUniqueKey(cacheKey: cacheKey, transactionId: dto.id)
            let payload = try Self.encoder.encode(dto)
            rows[key] = CachedTransaction(
                uniqueKey: key,
                cacheKey: cacheKey,
                transactionId: dto.id,
                sortDate: dto.date,
                payload: payload
            )
        }
        rowsByUniqueKey = rows
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
        // Replacing the whole history starts from empty regardless of any on-disk
        // content, so this never needs to (and never triggers) a decode of an
        // incompatible file before the subsequent `upsert` rebuilds it.
        rowsByUniqueKey = [:]
        try persist()
        invalidateOrderCache()
        return try upsert(cacheKey: cacheKey, transactions: transactions)
    }

    /// Removes every cached transaction (any environment). Used on local-data reset
    /// and before reseeding a different environment.
    public func clearAll() throws {
        // The store becomes empty regardless of any on-disk content, so a clear
        // unconditionally wins and rewrites a fresh empty snapshot without first
        // decoding a (possibly incompatible) file.
        rowsByUniqueKey = [:]
        try persist()
        invalidateOrderCache()
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
        let ordered = loadedRows().values
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

    /// The transaction ids in `rows` for `cacheKey`. Used inside `upsert` to decide
    /// insert-vs-update over the already-loaded snapshot (avoids re-reading disk).
    nonisolated private func existingTransactionIds(
        in rows: [String: CachedTransaction],
        cacheKey: String
    ) -> Set<String> {
        Set(rows.values.filter { $0.cacheKey == cacheKey }.map(\.transactionId))
    }

    private func persist() throws {
        guard let storeURL else { return }
        let data = try Self.encoder.encode(Snapshot(rowsByUniqueKey: rowsByUniqueKey ?? [:]))
        try fileManager.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try data.write(to: storeURL, options: [.atomic])
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storeURL.path)
    }
}
