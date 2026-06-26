import Foundation
import PlaidBarCore

/// Actor-isolated store for the **opt-in, additive** budgeting-v2 schema snapshot
/// (AND-546 — deferred epic AND-524).
///
/// ## Contract
/// - **Additive and opt-in.** The store holds the persisted v2
///   ``BudgetingV2Schema`` (the seeded `Category`/`CategoryGroup`/`Budget(month,
///   rollover)` tables) for one Plaid environment. It is written *only* when a user
///   opts into budgeting v2; a v1, not-opted-in user never reads or writes it, so
///   v1 budgeting is byte-for-byte unchanged.
/// - **Reversible & safe.** The forward seed never mutates any v1 record. Opting
///   out clears the v2 snapshot (`clear`/`clearAll`), which restores v1 untouched;
///   v1 budgets are recoverable from the snapshot beforehand via
///   ``BudgetingV2Migration/reverseToV1Budgets(_:month:)``.
/// - **Disposable & self-healing.** A snapshot written by an older schema version
///   reads as a miss and is purged, so the store can reseed from the closed
///   ``SpendingCategory`` taxonomy at any time. Deleting the store file is always
///   safe.
/// - **Fallback-safe.** Every operation `throws`; callers wrap in `try?` so any
///   init/read/write failure degrades to v1 budgeting.
///
/// ## Isolation / Privacy
/// Only `Sendable` ``BudgetingV2Schema`` values cross the actor boundary. The
/// on-disk file lives only in the local private data dir (`~/.vaultpeek/`),
/// created `0o700`/`0o600` like the existing JSON/SQLite caches — never the App
/// Group container or iCloud.
public actor BudgetingV2Store {
    /// Filename of the v2 schema store inside the local data dir. The `.store`
    /// suffix matches the existing disposable caches' reset/privacy docs.
    public static let storeFilename = "budgeting-v2-schema-v1.store"

    private struct Snapshot: Codable, Sendable {
        var rowsByCacheKey: [String: BudgetingV2Schema]
    }

    private let storeURL: URL?
    private let fileManager: FileManager
    /// In-memory rows, lazily hydrated from disk on first access. `nil` means the
    /// store has not yet read its backing file — opening the actor performs **no**
    /// disk I/O (AND-670), so construction never blocks (or fails) before the v2
    /// snapshot is actually needed. The read+decode is deferred to ``loadedRows()``
    /// on the actor's own executor, mirroring ``ReadModelCacheStore`` (AND-656
    /// finding 3).
    private var rowsByCacheKey: [String: BudgetingV2Schema]?

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

    /// Opens the store **without** touching disk (AND-670). Construction is a pure
    /// handoff of the URL; the backing file is read lazily on the actor's executor
    /// (see ``loadedRows()``). The `throws` is retained for source compatibility
    /// with the existing factory/callers (which wrap construction in `try?`), even
    /// though opening no longer reads or decodes anything.
    init(storeURL: URL?, fileManager: FileManager = .default) throws {
        self.storeURL = storeURL
        self.fileManager = fileManager
        self.rowsByCacheKey = nil
    }

    // MARK: - Lazy load / self-heal

    /// The in-memory rows, hydrating from disk on first access.
    ///
    /// An **incompatible or corrupt backing file** is treated as a disposable miss,
    /// not a hard failure (AND-670): the unreadable file is discarded and the store
    /// starts empty so the next ``seedV2``/``save`` rebuilds it. The store never
    /// permanently disables itself and never loses real data — the authoritative v1
    /// budgeting records are untouched, and a not-opted-in user simply stays on v1.
    private func loadedRows() -> [String: BudgetingV2Schema] {
        if let rowsByCacheKey { return rowsByCacheKey }

        guard let storeURL, fileManager.fileExists(atPath: storeURL.path) else {
            rowsByCacheKey = [:]
            return [:]
        }

        do {
            let data = try Data(contentsOf: storeURL)
            let rows = try Self.decoder.decode(Snapshot.self, from: data).rowsByCacheKey
            rowsByCacheKey = rows
            return rows
        } catch {
            // Undecodable file (incompatible/corrupt): discard it so the store
            // self-heals into a clean miss instead of staying permanently broken.
            // `storeURL` is already unwrapped by the guard above.
            try? fileManager.removeItem(at: storeURL)
            rowsByCacheKey = [:]
            return [:]
        }
    }

    // MARK: - Opt-in (forward migration)

    /// Seed (or re-seed) the v2 schema for `cacheKey` from the closed v1 taxonomy,
    /// optionally carrying a user's existing v1 budgets into `month`, and persist
    /// the snapshot. This is the **forward migration**: it is additive (no v1 record
    /// is touched) and idempotent (re-seeding produces the same snapshot when the
    /// inputs match). Returns the seeded snapshot so callers/tests can assert it.
    @discardableResult
    public func seedV2(
        cacheKey: String,
        carryingForward v1Budgets: [CategoryBudgetDTO] = [],
        month: String? = nil
    ) throws -> BudgetingV2Schema {
        let schema = BudgetingV2Migration.seed(carryingForward: v1Budgets, month: month)
        var rows = loadedRows()
        rows[cacheKey] = schema
        rowsByCacheKey = rows
        try persist()
        return schema
    }

    /// Persist an already-built v2 schema for `cacheKey`, replacing any existing
    /// snapshot (a later epic's editor mutates the snapshot and saves it back). The
    /// store holds one snapshot per environment, so a save is an upsert.
    public func save(cacheKey: String, schema: BudgetingV2Schema) throws {
        var rows = loadedRows()
        rows[cacheKey] = schema
        rowsByCacheKey = rows
        try persist()
    }

    // MARK: - Reads

    /// Load the v2 schema for `cacheKey`. Returns `nil` on a miss **or** when the
    /// stored snapshot is from an older schema version — in which case the stale row
    /// is purged so the store self-heals (the caller reseeds). An incompatible or
    /// corrupt backing file reads as a miss via ``loadedRows()`` (AND-670) rather
    /// than throwing, so a not-opted-in user stays on v1.
    public func load(cacheKey: String) throws -> BudgetingV2Schema? {
        var rows = loadedRows()
        guard let schema = rows[cacheKey] else { return nil }
        guard !BudgetingV2Migration.needsMigration(schema) else {
            rows.removeValue(forKey: cacheKey)
            rowsByCacheKey = rows
            try? persist()
            return nil
        }
        return schema
    }

    /// Whether `cacheKey` has opted into v2 (a current-schema snapshot is stored).
    /// Mirrors `load(...) != nil` without returning the payload; drives the
    /// "v1 vs v2" branch a caller takes so a not-opted-in user stays on v1.
    public func isOptedIn(cacheKey: String) throws -> Bool {
        try load(cacheKey: cacheKey) != nil
    }

    // MARK: - Opt-out / reset (reverse-safe)

    /// Recover the v1 budgets for `month` from the stored v2 snapshot, then clear
    /// the snapshot for `cacheKey` — the **reverse migration** (opt-out). Returns
    /// the recovered v1 budgets so the caller can write them back to the v1
    /// `/api/budgets` store, guaranteeing the user's numbers survive the round-trip.
    /// Returns `[]` (and still clears) when nothing was stored.
    @discardableResult
    public func optOut(cacheKey: String, month: String) throws -> [CategoryBudgetDTO] {
        let recovered: [CategoryBudgetDTO]
        if let schema = try load(cacheKey: cacheKey) {
            recovered = BudgetingV2Migration.reverseToV1Budgets(schema, month: month)
        } else {
            recovered = []
        }
        try clear(cacheKey: cacheKey)
        return recovered
    }

    /// Remove the v2 snapshot for `cacheKey` (opt-out without recovery, or an
    /// environment switch). Safe to call when no snapshot exists. v1 budgeting is
    /// unaffected.
    public func clear(cacheKey: String) throws {
        var rows = loadedRows()
        rows.removeValue(forKey: cacheKey)
        rowsByCacheKey = rows
        try persist()
    }

    /// Remove every v2 snapshot (local-data reset). Used alongside the other
    /// disposable caches' `clearAll`. The store becomes empty regardless of any
    /// on-disk content, so this never needs to decode an incompatible file —
    /// a clear unconditionally wins and rewrites a fresh empty snapshot.
    public func clearAll() throws {
        rowsByCacheKey = [:]
        try persist()
    }

    // MARK: - Private

    private func persist() throws {
        guard let storeURL else { return }
        let data = try Self.encoder.encode(Snapshot(rowsByCacheKey: rowsByCacheKey ?? [:]))
        try fileManager.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try data.write(to: storeURL, options: [.atomic])
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storeURL.path)
    }
}
