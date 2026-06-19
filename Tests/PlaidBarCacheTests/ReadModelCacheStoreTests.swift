import Foundation
import Testing
@testable import PlaidBarCache
@testable import PlaidBarCore

// Serialized: each test spins up its own in-memory `ModelContainer`, and
// initializing several SwiftData containers for the same schema concurrently
// (the default parallel test run) crashes the SwiftData runtime. The suite is
// tiny and fast, so serial execution costs nothing.
@Suite("Disposable SwiftData read-model cache store (AND-566)", .serialized)
struct ReadModelCacheStoreTests {

    private func accounts() -> [AccountDTO] {
        [
            AccountDTO(id: "chk", itemId: "i1", name: "Checking", type: .depository, balances: BalanceDTO(available: 8200)),
            AccountDTO(id: "amex", itemId: "i2", name: "Amex", type: .credit, balances: BalanceDTO(current: -850, limit: 10000)),
        ]
    }

    private func transactions() -> [TransactionDTO] {
        [
            TransactionDTO(id: "t1", accountId: "chk", amount: 12.5, date: "2026-01-15", name: "Coffee"),
            TransactionDTO(id: "t2", accountId: "chk", amount: 80, date: "2026-01-14", name: "Groceries"),
        ]
    }

    private func sampleModel(cacheKey: String = "sandbox|/x") -> DashboardReadModel {
        DashboardReadModelMapper.makeReadModel(
            cacheKey: cacheKey,
            accounts: accounts(),
            transactions: transactions(),
            generatedAt: Date(timeIntervalSince1970: 1_700_000)
        )
    }

    @Test("write then read returns an equal read-model (round-trip)")
    func roundTrip() async throws {
        let store = try ReadModelCacheStore(inMemory: true)
        let model = sampleModel()

        try await store.save(model)
        let loaded = try await store.load(cacheKey: model.cacheKey)

        #expect(loaded == model)
    }

    @Test("load returns nil for an unknown key (cold miss)")
    func missReturnsNil() async throws {
        let store = try ReadModelCacheStore(inMemory: true)
        let loaded = try await store.load(cacheKey: "never|written")
        #expect(loaded == nil)
    }

    @Test("save upserts: a second save replaces the row for the same key")
    func upsert() async throws {
        let store = try ReadModelCacheStore(inMemory: true)
        let key = "sandbox|/x"

        try await store.save(sampleModel(cacheKey: key))
        let updated = DashboardReadModelMapper.makeReadModel(
            cacheKey: key,
            accounts: accounts(),
            transactions: [TransactionDTO(id: "t9", accountId: "chk", amount: 5, date: "2026-02-01", name: "New")],
            generatedAt: Date(timeIntervalSince1970: 1_800_000)
        )
        try await store.save(updated)

        let loaded = try await store.load(cacheKey: key)
        #expect(loaded == updated)
        #expect(loaded?.recentTransactions.count == 1)
    }

    @Test("two environments keep independent rows (no cross-environment bleed)")
    func environmentScoping() async throws {
        let store = try ReadModelCacheStore(inMemory: true)
        let sandbox = sampleModel(cacheKey: "sandbox|/x")
        let production = DashboardReadModelMapper.makeReadModel(
            cacheKey: "production|/x",
            accounts: [AccountDTO(id: "p", itemId: "ip", name: "Prod", type: .depository, balances: BalanceDTO(available: 1))],
            transactions: [],
            generatedAt: Date(timeIntervalSince1970: 1)
        )

        try await store.save(sandbox)
        try await store.save(production)

        #expect(try await store.load(cacheKey: "sandbox|/x") == sandbox)
        #expect(try await store.load(cacheKey: "production|/x") == production)
    }

    @Test("a stale-schema row reads as a miss and is purged (disposable upgrade)")
    func staleSchemaPurged() async throws {
        let store = try ReadModelCacheStore(inMemory: true)
        let key = "sandbox|/x"
        // Persist a row tagged with an older schema version directly through the
        // store so we exercise the version sweep on load.
        let stale = DashboardReadModel(
            cacheKey: key,
            schemaVersion: DashboardReadModel.currentSchemaVersion - 1,
            accounts: accounts(),
            recentTransactions: transactions(),
            summary: .init(netCash: 0, totalDebt: 0, accountCount: 2),
            generatedAt: Date()
        )
        try await store.save(stale)

        // First load: stale → nil, and the row is removed.
        #expect(try await store.load(cacheKey: key) == nil)
        // Second load confirms the purge (still nil, nothing lingering).
        #expect(try await store.load(cacheKey: key) == nil)
    }

    @Test("clear removes a key; clearAll empties the store")
    func clearing() async throws {
        let store = try ReadModelCacheStore(inMemory: true)
        try await store.save(sampleModel(cacheKey: "a|/x"))
        try await store.save(sampleModel(cacheKey: "b|/x"))

        try await store.clear(cacheKey: "a|/x")
        #expect(try await store.load(cacheKey: "a|/x") == nil)
        #expect(try await store.load(cacheKey: "b|/x") != nil)

        try await store.clearAll()
        #expect(try await store.load(cacheKey: "b|/x") == nil)
    }

    /// Regression guard for the fallback contract: when the cache is empty (the
    /// disabled / first-launch / failed-open case), the cold-start hydration
    /// inputs resolve to "nothing to seed", so a caller keeps exactly its
    /// pre-cache behavior (the empty/loading → HTTP-refresh path). This models
    /// what `AppState.hydrateFromReadModelCache()` sees when the store is empty
    /// or unavailable: `load` → nil, and even a present-but-empty row → no
    /// hydration.
    @Test("empty/disabled cache produces no hydration (no cold-start regression)")
    func emptyCacheIsANoOp() async throws {
        let store = try ReadModelCacheStore(inMemory: true)

        // Empty store: a load is a clean miss.
        let loaded = try await store.load(cacheKey: "sandbox|/x")
        #expect(loaded == nil)

        // A would-be hydration from "no model" is nil — caller falls through.
        let hydrationFromMiss = loaded.flatMap {
            DashboardReadModelMapper.hydrate(from: $0, expectedCacheKey: "sandbox|/x")
        }
        #expect(hydrationFromMiss == nil)

        // Saving an empty read-model never yields a usable hydration either, so a
        // no-account state can't paint stale data on the next cold start.
        let emptyModel = DashboardReadModelMapper.makeReadModel(
            cacheKey: "sandbox|/x",
            accounts: [],
            transactions: [],
            generatedAt: Date()
        )
        try await store.save(emptyModel)
        let reloaded = try #require(try await store.load(cacheKey: "sandbox|/x"))
        #expect(DashboardReadModelMapper.hydrate(from: reloaded, expectedCacheKey: "sandbox|/x") == nil)
    }

    @Test("hydrate from a loaded row yields the dashboard DTOs")
    func hydrateFromLoaded() async throws {
        let store = try ReadModelCacheStore(inMemory: true)
        let model = sampleModel()
        try await store.save(model)

        let loaded = try #require(try await store.load(cacheKey: model.cacheKey))
        let hydration = DashboardReadModelMapper.hydrate(from: loaded, expectedCacheKey: model.cacheKey)
        #expect(hydration?.accounts == accounts())
        #expect(hydration?.recentTransactions.count == 2)
    }

    @Test("on-disk store round-trips and writes the store file private (0o600)")
    func onDiskRoundTripAndPrivacy() async throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("vaultpeek-readmodel-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: directory) }

        let store = try ReadModelCacheStore(onDiskIn: directory)
        let model = sampleModel()
        try await store.save(model)
        #expect(try await store.load(cacheKey: model.cacheKey) == model)

        // The store file lands inside the supplied private directory...
        let storeURL = directory.appendingPathComponent(ReadModelCacheStore.storeFilename)
        #expect(fileManager.fileExists(atPath: storeURL.path))

        // ...with owner-only permissions, matching the existing JSON/SQLite caches.
        let attrs = try fileManager.attributesOfItem(atPath: storeURL.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue
        #expect(perms == 0o600)
    }

    @Test("a fresh store reopened on the same directory rebuilds and reads (disposable)")
    func reopenSameDirectoryReads() async throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("vaultpeek-readmodel-reopen-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: directory) }

        let model = sampleModel()
        do {
            let store = try ReadModelCacheStore(onDiskIn: directory)
            try await store.save(model)
        }
        // A brand-new store actor over the same on-disk file still reads the row,
        // proving persistence survives an AppState/process restart.
        let reopened = try ReadModelCacheStore(onDiskIn: directory)
        #expect(try await reopened.load(cacheKey: model.cacheKey) == model)
    }
}
