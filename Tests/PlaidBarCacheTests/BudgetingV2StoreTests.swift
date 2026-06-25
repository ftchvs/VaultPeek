import Foundation
import Testing
@testable import PlaidBarCache
@testable import PlaidBarCore

// Serialized: each test exercises its own in-memory or temporary on-disk store,
// mirroring the other disposable cache-store suites.
@Suite("Budgeting v2 schema store (AND-546)", .serialized)
struct BudgetingV2StoreTests {

    private func v1Budgets() -> [CategoryBudgetDTO] {
        [
            CategoryBudgetDTO(category: .foodAndDrink, monthlyLimit: 500),
            CategoryBudgetDTO(category: .transportation, monthlyLimit: 120),
        ]
    }

    // MARK: - Opt-in / seed

    @Test("seedV2 persists a current-schema snapshot that loads back equal")
    func seedRoundTrips() async throws {
        let store = try BudgetingV2Store(inMemory: true)
        let seeded = try await store.seedV2(cacheKey: "sandbox|/x")

        let loaded = try await store.load(cacheKey: "sandbox|/x")
        #expect(loaded == seeded)
        #expect(loaded?.categories.count == SpendingCategory.allCases.count)
        #expect(loaded?.isCurrentSchema == true)
    }

    @Test("seedV2 carries v1 budgets forward into the chosen month")
    func seedCarriesV1Forward() async throws {
        let store = try BudgetingV2Store(inMemory: true)
        try await store.seedV2(cacheKey: "sandbox|/x", carryingForward: v1Budgets(), month: "2026-06")

        let loaded = try #require(try await store.load(cacheKey: "sandbox|/x"))
        #expect(loaded.budgets.count == 2)
        let food = loaded.budgets.first { $0.categoryId == "FOOD_AND_DRINK" }
        #expect(food?.month == "2026-06")
        #expect(food?.monthlyLimit == 500)
    }

    // MARK: - Opt-in gate

    @Test("A fresh store is NOT opted in — load is a clean miss (v1 stays in effect)")
    func notOptedInByDefault() async throws {
        let store = try BudgetingV2Store(inMemory: true)
        #expect(try await store.load(cacheKey: "sandbox|/x") == nil)
        #expect(try await store.isOptedIn(cacheKey: "sandbox|/x") == false)
    }

    @Test("After seeding, isOptedIn is true for that environment only (no cross-env bleed)")
    func optInIsPerEnvironment() async throws {
        let store = try BudgetingV2Store(inMemory: true)
        try await store.seedV2(cacheKey: "sandbox|/x")

        #expect(try await store.isOptedIn(cacheKey: "sandbox|/x") == true)
        // A different environment did NOT opt in.
        #expect(try await store.isOptedIn(cacheKey: "production|/x") == false)
        #expect(try await store.load(cacheKey: "production|/x") == nil)
    }

    // MARK: - Reversibility (opt-out)

    @Test("optOut recovers the exact v1 budgets and clears the v2 snapshot")
    func optOutIsReversible() async throws {
        let store = try BudgetingV2Store(inMemory: true)
        try await store.seedV2(cacheKey: "sandbox|/x", carryingForward: v1Budgets(), month: "2026-06")

        let recovered = try await store.optOut(cacheKey: "sandbox|/x", month: "2026-06")

        // The v1 numbers survive the round-trip...
        let expected = v1Budgets().sorted { $0.category.rawValue < $1.category.rawValue }
        #expect(recovered == expected)
        // ...and v2 is gone, so the user is back on v1.
        #expect(try await store.load(cacheKey: "sandbox|/x") == nil)
        #expect(try await store.isOptedIn(cacheKey: "sandbox|/x") == false)
    }

    @Test("optOut on a never-seeded key recovers nothing and stays a no-op")
    func optOutWithoutSeedIsSafe() async throws {
        let store = try BudgetingV2Store(inMemory: true)
        let recovered = try await store.optOut(cacheKey: "sandbox|/x", month: "2026-06")
        #expect(recovered.isEmpty)
        #expect(try await store.load(cacheKey: "sandbox|/x") == nil)
    }

    // MARK: - Self-healing / disposable

    @Test("A stale-schema snapshot reads as a miss and is purged (self-healing)")
    func staleSchemaPurged() async throws {
        let store = try BudgetingV2Store(inMemory: true)
        let key = "sandbox|/x"
        let current = BudgetingV2Migration.seed()
        let stale = BudgetingV2Schema(
            schemaVersion: BudgetingV2Schema.currentSchemaVersion - 1,
            groups: current.groups,
            categories: current.categories,
            budgets: current.budgets
        )
        try await store.save(cacheKey: key, schema: stale)

        // First load: stale → nil, and the row is purged.
        #expect(try await store.load(cacheKey: key) == nil)
        // Confirms the purge — still nil, nothing lingering.
        #expect(try await store.load(cacheKey: key) == nil)
    }

    @Test("clear removes one key; clearAll empties the store")
    func clearing() async throws {
        let store = try BudgetingV2Store(inMemory: true)
        try await store.seedV2(cacheKey: "a|/x")
        try await store.seedV2(cacheKey: "b|/x")

        try await store.clear(cacheKey: "a|/x")
        #expect(try await store.load(cacheKey: "a|/x") == nil)
        #expect(try await store.load(cacheKey: "b|/x") != nil)

        try await store.clearAll()
        #expect(try await store.load(cacheKey: "b|/x") == nil)
    }

    // MARK: - On-disk persistence + privacy

    @Test("on-disk store round-trips and writes the file owner-only (0o600)")
    func onDiskRoundTripAndPrivacy() async throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("vaultpeek-budgetv2-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: directory) }

        let store = try BudgetingV2Store(onDiskIn: directory)
        let seeded = try await store.seedV2(cacheKey: "sandbox|/x", carryingForward: v1Budgets(), month: "2026-06")
        #expect(try await store.load(cacheKey: "sandbox|/x") == seeded)

        let storeURL = directory.appendingPathComponent(BudgetingV2Store.storeFilename)
        #expect(fileManager.fileExists(atPath: storeURL.path))

        let attrs = try fileManager.attributesOfItem(atPath: storeURL.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue
        #expect(perms == 0o600)
    }

    @Test("A reopened store on the same directory reads the seeded snapshot (survives restart)")
    func reopenSameDirectoryReads() async throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("vaultpeek-budgetv2-reopen-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: directory) }

        let seeded: BudgetingV2Schema
        do {
            let store = try BudgetingV2Store(onDiskIn: directory)
            seeded = try await store.seedV2(cacheKey: "sandbox|/x", carryingForward: v1Budgets(), month: "2026-06")
        }
        let reopened = try BudgetingV2Store(onDiskIn: directory)
        #expect(try await reopened.load(cacheKey: "sandbox|/x") == seeded)
    }
}
