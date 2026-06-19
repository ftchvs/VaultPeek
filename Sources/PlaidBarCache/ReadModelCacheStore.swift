import Foundation
import PlaidBarCore
import SwiftData

/// Actor-isolated SwiftData store for the **disposable** dashboard read-model
/// cache (AND-566).
///
/// ## Contract
/// - **Disposable cache, never authoritative.** It is written *after* a
///   successful refresh/decode from the authoritative in-memory data, and read
///   on cold start to paint frame 1 before the HTTP refresh returns. The live
///   refresh then overwrites it. Deleting the store file at any time is safe:
///   it rebuilds on the next refresh.
/// - **Fallback-safe.** Every operation is `throws`; callers wrap reads/writes
///   in `try?` so any SwiftData init/read/write failure (or an unavailable
///   store) degrades to exactly today's behavior — the empty/loading cold path
///   driven by the existing JSON/UserDefaults caches.
///
/// ## Isolation
/// `@ModelActor` makes this a `Sendable` actor that owns its non-`Sendable`
/// `ModelContext`. The `@Model` rows never escape the actor; only the `Sendable`
/// ``DashboardReadModel`` value is passed in and out, which keeps the
/// strict-concurrency build clean.
///
/// ## Privacy
/// The on-disk store lives only in the local private data dir (`~/.vaultpeek/`),
/// created with `0o700`/`0o600` like the existing SQLite/JSON caches — never the
/// App Group container or iCloud. See ``makeOnDiskContainer(in:)``.
@ModelActor
public actor ReadModelCacheStore {
    /// Filename of the disposable SwiftData store inside the local data dir.
    /// `v1` is namespaced so a future incompatible store can ship beside it and
    /// the old file can simply be deleted.
    public static let storeFilename = "dashboard-read-model-cache-v1.store"

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

    /// Builds the schema for the disposable cache. Single `@Model`, no
    /// relationships — intentionally trivial so the store stays rebuildable.
    public static func schema() -> Schema {
        Schema([CachedDashboardReadModel.self])
    }

    /// Builds an on-disk container for the disposable store under `directory`
    /// (the local private data dir). Creates the directory with owner-only
    /// permissions when missing, then tightens the store file to `0o600` after
    /// SwiftData materializes it — matching the existing JSON/SQLite caches so
    /// the financial payload never widens the on-disk privacy boundary.
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
            "DashboardReadModelCache",
            schema: schema(),
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema(), configurations: configuration)
        #if os(macOS)
        // SwiftData may create sidecar files (-wal/-shm); tighten whatever exists.
        for suffix in ["", "-wal", "-shm"] {
            let path = storeURL.path + suffix
            if fileManager.fileExists(atPath: path) {
                try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
            }
        }
        #endif
        return container
    }

    /// Builds an in-memory container for tests (and as a non-persisting fallback).
    /// Nothing touches disk.
    public static func makeInMemoryContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema(), configurations: configuration)
    }

    // MARK: - Operations

    /// Persists the read-model, replacing any existing row for the same
    /// `cacheKey`. The cache holds a single row per environment, so a save is an
    /// upsert: the prior row is deleted before the new one is inserted.
    public func save(_ model: DashboardReadModel) throws {
        let key = model.cacheKey
        try deleteRow(cacheKey: key)
        let payload = try Self.encoder.encode(model)
        let row = CachedDashboardReadModel(
            cacheKey: key,
            schemaVersion: model.schemaVersion,
            payload: payload
        )
        modelContext.insert(row)
        try modelContext.save()
    }

    /// Reads the cached read-model for `cacheKey`. Returns `nil` on a miss or
    /// when the stored row is from an older schema (which is also purged so the
    /// store self-heals). A decode failure throws so the caller's `try?` can
    /// drop back to today's cold path.
    public func load(cacheKey: String) throws -> DashboardReadModel? {
        guard let row = try fetchRow(cacheKey: cacheKey) else { return nil }
        guard row.schemaVersion == DashboardReadModel.currentSchemaVersion else {
            // Stale schema: discard so the next save writes a clean current row.
            modelContext.delete(row)
            try? modelContext.save()
            return nil
        }
        let model = try Self.decoder.decode(DashboardReadModel.self, from: row.payload)
        guard model.isCurrentSchema else { return nil }
        return model
    }

    /// Removes the row for `cacheKey` (e.g. after a local-data reset). Safe to
    /// call when no row exists.
    public func clear(cacheKey: String) throws {
        try deleteRow(cacheKey: cacheKey)
        try modelContext.save()
    }

    /// Removes every cached row. Used by the local-data reset path so the
    /// disposable cache is wiped alongside the JSON/SQLite caches.
    public func clearAll() throws {
        try modelContext.delete(model: CachedDashboardReadModel.self)
        try modelContext.save()
    }

    // MARK: - Private

    private func fetchRow(cacheKey: String) throws -> CachedDashboardReadModel? {
        // The cache holds at most one row per environment (a handful total), so
        // fetching all and matching in Swift is cheap. It also sidesteps the
        // `#Predicate` macro capturing a non-`Sendable` `KeyPath`, which is an
        // error under the project's Swift 6 strict-concurrency gate.
        let rows = try modelContext.fetch(FetchDescriptor<CachedDashboardReadModel>())
        return rows.first { $0.cacheKey == cacheKey }
    }

    private func deleteRow(cacheKey: String) throws {
        if let existing = try fetchRow(cacheKey: cacheKey) {
            modelContext.delete(existing)
        }
    }
}
