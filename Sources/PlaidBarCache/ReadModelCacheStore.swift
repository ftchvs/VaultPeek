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

    /// In-memory rows, lazily hydrated from disk on first access. `nil` means the
    /// store has not yet read its backing file — opening the actor performs **no**
    /// disk I/O (AND-656 finding 3), so construction never blocks the MainActor
    /// caller with a full-history decode. The read+decode is deferred to
    /// ``loadedRows()`` on the actor's own executor.
    private var rowsByKey: [String: CachedDashboardReadModel]?

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
    /// pure, non-throwing handoff of the URL; the backing file is read lazily on the
    /// actor's executor (see ``loadedRows()``), so a MainActor caller never decodes
    /// the full history synchronously during open (AND-656 finding 3).
    init(storeURL: URL?, fileManager: FileManager = .default) {
        self.storeURL = storeURL
        self.fileManager = fileManager
        self.rowsByKey = nil
    }

    // MARK: - Lazy load / self-heal

    /// The in-memory rows, hydrating from disk on first access.
    ///
    /// An **incompatible or corrupt backing file** (e.g. a pre-JSON SwiftData
    /// `.store` that cannot decode as our `Snapshot`) is treated as a disposable
    /// cache *miss*, not a hard failure: the unreadable file is discarded and the
    /// store starts empty so the next refresh rebuilds it (AND-656 finding 2). This
    /// is why the disposable cache never permanently disables itself and never loses
    /// real data — the authoritative source is always the live in-memory data.
    private func loadedRows() -> [String: CachedDashboardReadModel] {
        if let rowsByKey { return rowsByKey }

        guard let storeURL, fileManager.fileExists(atPath: storeURL.path) else {
            rowsByKey = [:]
            return [:]
        }

        do {
            let data = try Data(contentsOf: storeURL)
            let rows = try Self.decoder.decode(Snapshot.self, from: data).rows
            rowsByKey = rows
            return rows
        } catch {
            // Undecodable file (incompatible/corrupt): discard it so the store
            // self-heals into a clean miss instead of staying permanently broken.
            discardIncompatibleStoreFile()
            rowsByKey = [:]
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

    // MARK: - Operations

    /// Persists the read-model, replacing any existing row for the same
    /// `cacheKey`. The cache holds a single row per environment, so a save is an
    /// upsert.
    public func save(_ model: DashboardReadModel) throws {
        var rows = loadedRows()
        let payload = try Self.encoder.encode(model)
        rows[model.cacheKey] = CachedDashboardReadModel(
            cacheKey: model.cacheKey,
            schemaVersion: model.schemaVersion,
            payload: payload
        )
        rowsByKey = rows
        try persist()
    }

    /// Reads the cached read-model for `cacheKey`. Returns `nil` on a miss or
    /// when the stored row is from an older schema (which is also purged so the
    /// store self-heals). A decode failure throws so the caller's `try?` can drop
    /// back to today's cold path.
    public func load(cacheKey: String) throws -> DashboardReadModel? {
        var rows = loadedRows()
        guard let row = rows[cacheKey] else { return nil }
        guard row.schemaVersion == DashboardReadModel.currentSchemaVersion else {
            rows.removeValue(forKey: cacheKey)
            rowsByKey = rows
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
        var rows = loadedRows()
        rows.removeValue(forKey: cacheKey)
        rowsByKey = rows
        try persist()
    }

    /// Removes every cached row. Used by the local-data reset path so the
    /// disposable cache is wiped alongside the JSON/SQLite caches.
    public func clearAll() throws {
        // The store becomes empty regardless of any on-disk content, so this never
        // needs to (and never triggers) a decode of an incompatible file: a clear
        // unconditionally wins and rewrites a fresh empty snapshot.
        rowsByKey = [:]
        try persist()
    }

    // MARK: - Private

    private func persist() throws {
        guard let storeURL else { return }
        let data = try Self.encoder.encode(Snapshot(rows: rowsByKey ?? [:]))
        try fileManager.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try data.write(to: storeURL, options: [.atomic])
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storeURL.path)
    }
}
