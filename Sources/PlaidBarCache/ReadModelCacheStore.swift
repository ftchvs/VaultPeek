import Foundation
import PlaidBarCore

/// Actor-isolated store for the **disposable** dashboard read-model cache
/// (AND-566).
///
/// ## Contract
/// - **Disposable cache, never authoritative.** It is written *after* a
///   successful refresh/decode from the authoritative in-memory data, and read on
///   cold start to paint frame 1 before the HTTP refresh returns. Deleting the
///   store file at any time is safe: it rebuilds on the next refresh.
/// - **Fallback-safe.** Every operation is `throws`; callers wrap reads/writes in
///   `try?` so any init/read/write failure degrades to exactly today's behavior —
///   the empty/loading cold path driven by the existing JSON/UserDefaults caches.
///
/// ## Privacy
/// The on-disk store lives only in the local private data dir (`~/.vaultpeek/`),
/// created with `0o700`/`0o600` like the existing SQLite/JSON caches — never the
/// App Group container or iCloud.
public actor ReadModelCacheStore {
    /// Filename of the disposable store inside the local data dir. The `.store`
    /// suffix is preserved for compatibility with existing reset/privacy docs.
    public static let storeFilename = "dashboard-read-model-cache-v1.store"

    private struct Snapshot: Codable, Sendable {
        var rows: [String: CachedDashboardReadModel]
    }

    private let storeURL: URL?
    private let fileManager: FileManager
    private var rowsByKey: [String: CachedDashboardReadModel]

    /// Monotonic clear generation, bumped by `clearAll()`. Lets a scheduled write
    /// re-validate, **on this actor**, that no clear has landed since it captured a
    /// generation token — closing the two-hop persist-after-clear window the
    /// main-actor `ReadModelCacheClearGate` epoch alone cannot (AND-633). Because
    /// `clearGeneration()`, `clearAll()`, and `save(_:ifNotClearedSince:)` are all
    /// FIFO-serialized on this actor, a clear that is enqueued after a write's
    /// capture always bumps the counter before that write commits, so the clear
    /// wins.
    private var clearGeneration: UInt64 = 0

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
            self.rowsByKey = try Self.decoder.decode(Snapshot.self, from: data).rows
        } else {
            self.rowsByKey = [:]
        }
    }

    // MARK: - Operations

    /// Persists the read-model, replacing any existing row for the same
    /// `cacheKey`. The cache holds a single row per environment, so a save is an
    /// upsert.
    public func save(_ model: DashboardReadModel) throws {
        let payload = try Self.encoder.encode(model)
        rowsByKey[model.cacheKey] = CachedDashboardReadModel(
            cacheKey: model.cacheKey,
            schemaVersion: model.schemaVersion,
            payload: payload
        )
        try persist()
    }

    /// The current clear generation. A scheduled write captures this on the store
    /// actor when it is about to commit, then passes it to
    /// `save(_:ifNotClearedSince:)` so the write drops itself if a `clearAll()`
    /// raced in between (AND-633).
    public func currentClearGeneration() -> UInt64 {
        clearGeneration
    }

    /// Atomic clear-gated save. Re-checks the clear generation **as the first
    /// action on this actor** and, if a `clearAll()` has run since `capturedGeneration`
    /// was taken, drops the write entirely (returning `false`) rather than
    /// resurrecting removed-institution balances. Because the generation check and
    /// the row write are one actor-isolated hop, no `clearAll()` can interleave
    /// between them — closing the two-hop window the main-actor epoch gate leaves
    /// open (AND-633).
    ///
    /// Returns `true` when the row was committed, `false` when it was dropped
    /// because a clear won.
    @discardableResult
    public func save(_ model: DashboardReadModel, ifNotClearedSince capturedGeneration: UInt64) throws -> Bool {
        guard capturedGeneration == clearGeneration else { return false }
        try save(model)
        return true
    }

    /// Reads the cached read-model for `cacheKey`. Returns `nil` on a miss or
    /// when the stored row is from an older schema (which is also purged so the
    /// store self-heals). A decode failure throws so the caller's `try?` can drop
    /// back to today's cold path.
    public func load(cacheKey: String) throws -> DashboardReadModel? {
        guard let row = rowsByKey[cacheKey] else { return nil }
        guard row.schemaVersion == DashboardReadModel.currentSchemaVersion else {
            rowsByKey.removeValue(forKey: cacheKey)
            try? persist()
            return nil
        }
        let model = try Self.decoder.decode(DashboardReadModel.self, from: row.payload)
        guard model.isCurrentSchema else { return nil }
        return model
    }

    /// Removes the row for `cacheKey` (e.g. after a local-data reset). Safe to
    /// call when no row exists.
    public func clear(cacheKey: String) throws {
        rowsByKey.removeValue(forKey: cacheKey)
        try persist()
    }

    /// Removes every cached row. Used by the local-data reset path so the
    /// disposable cache is wiped alongside the JSON/SQLite caches.
    ///
    /// Bumps `clearGeneration` so any write that captured an earlier generation and
    /// reaches `save(_:ifNotClearedSince:)` afterwards on this actor drops itself
    /// rather than resurrecting wiped rows (AND-633).
    public func clearAll() throws {
        clearGeneration &+= 1
        rowsByKey.removeAll()
        try persist()
    }

    // MARK: - Private

    private func persist() throws {
        guard let storeURL else { return }
        let data = try Self.encoder.encode(Snapshot(rows: rowsByKey))
        try fileManager.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try data.write(to: storeURL, options: [.atomic])
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storeURL.path)
    }
}
