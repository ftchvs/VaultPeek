import Foundation
import Testing
@testable import PlaidBarCache
@testable import PlaidBarCore

// Serialized: each test spins up its own in-memory `ModelContainer`, and
// initializing several SwiftData containers for the same schema concurrently
// (the default parallel test run) crashes the SwiftData runtime — the same
// constraint `ReadModelCacheStoreTests` documents.
@Suite("Disposable per-transaction cache store (AND-567)", .serialized)
struct TransactionCacheStoreTests {

    private let key = "sandbox|/x"

    /// `count` transactions, newest id first by construction. Dates descend so the
    /// store's newest-first sort yields tx_0, tx_1, … in order.
    private func transactions(count: Int) -> [TransactionDTO] {
        (0..<count).map { i in
            // Higher index → older date, so newest-first paging returns tx_0 first.
            let day = max(1, 28 - (i % 28))
            let month = String(format: "%02d", 12 - min(11, i / 28))
            return TransactionDTO(
                id: "tx_\(String(format: "%04d", i))",
                accountId: "chk",
                amount: Double(i + 1),
                date: "2026-\(month)-\(String(format: "%02d", day))",
                name: "Merchant \(i)"
            )
        }
    }

    @Test("upsert then paged read returns the rows newest-first")
    func upsertThenPage() async throws {
        let store = try TransactionCacheStore(inMemory: true)
        let all = transactions(count: 10)
        try await store.upsert(cacheKey: key, transactions: all)

        let total = try await store.count(cacheKey: key)
        #expect(total == 10)

        let window = TransactionPageWindow.make(pageIndex: 0, pageSize: 4, total: total)
        let page = try await store.page(cacheKey: key, window: window)
        #expect(page.count == 4)
        // Sorted newest-first: tx_0000 has the newest date (Dec 28).
        let sortedExpectation = all.sorted { $0.date > $1.date }.prefix(4).map(\.id)
        #expect(page.map(\.id) == Array(sortedExpectation))
    }

    @Test("#Unique upsert replaces a re-synced transaction instead of duplicating")
    func uniqueUpsertReplaces() async throws {
        let store = try TransactionCacheStore(inMemory: true)
        let original = TransactionDTO(id: "t1", accountId: "chk", amount: 10, date: "2026-01-10", name: "Old")
        try await store.upsert(cacheKey: key, transactions: [original])

        // Re-sync the SAME id with a new payload.
        let updated = TransactionDTO(id: "t1", accountId: "chk", amount: 99, date: "2026-01-10", name: "New")
        let plan = try await store.upsert(cacheKey: key, transactions: [updated])

        #expect(plan.updatedIds == ["t1"], "same id is an update, not an insert")
        #expect(plan.insertedIds.isEmpty)

        let total = try await store.count(cacheKey: key)
        #expect(total == 1, "no duplicate row for the re-synced id")

        let page = try await store.page(
            cacheKey: key,
            window: TransactionPageWindow.make(pageIndex: 0, pageSize: 10, total: total)
        )
        #expect(page.count == 1)
        #expect(page.first?.amount == 99, "the row was updated in place to the latest payload")
        #expect(page.first?.name == "New")
    }

    @Test("paging walks the whole history with no overlap and no gaps")
    func pagingCoversHistory() async throws {
        let store = try TransactionCacheStore(inMemory: true)
        let all = transactions(count: 23)
        try await store.upsert(cacheKey: key, transactions: all)
        let total = try await store.count(cacheKey: key)
        #expect(total == 23)

        let pageSize = 5
        var collected: [String] = []
        var window: TransactionPageWindow? = TransactionPageWindow.make(pageIndex: 0, pageSize: pageSize, total: total)
        while let w = window {
            let page = try await store.page(cacheKey: key, window: w)
            collected.append(contentsOf: page.map(\.id))
            window = w.next(pageSize: pageSize, total: total)
        }

        let expected = all.sorted { $0.date > $1.date }.map(\.id)
        #expect(collected == expected, "every row appears exactly once, newest-first")
        #expect(Set(collected).count == 23, "no duplicates across pages")
    }

    @Test("an out-of-range page reads empty")
    func outOfRangePage() async throws {
        let store = try TransactionCacheStore(inMemory: true)
        try await store.upsert(cacheKey: key, transactions: transactions(count: 3))
        let total = try await store.count(cacheKey: key)
        let window = TransactionPageWindow.make(pageIndex: 5, pageSize: 10, total: total)
        let page = try await store.page(cacheKey: key, window: window)
        #expect(page.isEmpty)
    }

    @Test("replaceAll drops removed transactions")
    func replaceAllDropsRemoved() async throws {
        let store = try TransactionCacheStore(inMemory: true)
        try await store.upsert(cacheKey: key, transactions: transactions(count: 10))
        #expect(try await store.count(cacheKey: key) == 10)

        // A later refresh returns only 3 rows: the stale 7 must not linger.
        try await store.replaceAll(cacheKey: key, transactions: transactions(count: 3))
        #expect(try await store.count(cacheKey: key) == 3)
    }

    @Test("rows for a different environment key are not returned for this key")
    func cacheKeyScoping() async throws {
        let store = try TransactionCacheStore(inMemory: true)
        try await store.upsert(cacheKey: "sandbox|/x", transactions: transactions(count: 4))
        try await store.upsert(cacheKey: "production|/x", transactions: transactions(count: 6))

        #expect(try await store.count(cacheKey: "sandbox|/x") == 4)
        #expect(try await store.count(cacheKey: "production|/x") == 6)
    }

    @Test("clearAll empties the store")
    func clearAllEmpties() async throws {
        let store = try TransactionCacheStore(inMemory: true)
        try await store.upsert(cacheKey: key, transactions: transactions(count: 5))
        try await store.clearAll()
        #expect(try await store.count(cacheKey: key) == 0)
    }

    @Test("empty upsert is a no-op")
    func emptyUpsert() async throws {
        let store = try TransactionCacheStore(inMemory: true)
        let plan = try await store.upsert(cacheKey: key, transactions: [])
        #expect(plan.writeCount == 0)
        #expect(try await store.count(cacheKey: key) == 0)
    }
}
