import Foundation
import Testing
@testable import PlaidBarCache
@testable import PlaidBarCore

// Serialized: each test exercises its own in-memory or temporary on-disk store;
// serial execution keeps cache-generation assertions deterministic.
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

    // MARK: - Bounded ordering cache + invalidation (Finding A)

    /// The newest-first ordering is memoized per data generation so a multi-page
    /// scroll sorts once. Repeated page reads with no intervening write must return
    /// stable, correct slices — the cache must not corrupt or stale the ordering.
    @Test("repeated page reads reuse the cached ordering and stay correct")
    func cachedOrderingStableAcrossPages() async throws {
        let store = try TransactionCacheStore(inMemory: true)
        let all = transactions(count: 30)
        try await store.upsert(cacheKey: key, transactions: all)
        let total = try await store.count(cacheKey: key)
        let expected = all.sorted { $0.date > $1.date }.map(\.id)

        let pageSize = 7
        // Read every page twice in interleaved order; the memoized order must give
        // identical, non-overlapping slices each time.
        for round in 0..<2 {
            var collected: [String] = []
            var window: TransactionPageWindow? = .make(pageIndex: 0, pageSize: pageSize, total: total)
            while let w = window {
                let page = try await store.page(cacheKey: key, window: w)
                collected.append(contentsOf: page.map(\.id))
                window = w.next(pageSize: pageSize, total: total)
            }
            #expect(collected == expected, "round \(round): cached ordering yields the full newest-first history")
        }
    }

    /// A write must bump the data generation and invalidate the memoized ordering,
    /// so a later read reflects the new rows rather than serving a stale sort. This
    /// is the cache-correctness guarantee behind the bounded paging path.
    @Test("a write invalidates the cached ordering so later reads see new rows")
    func writeInvalidatesCachedOrdering() async throws {
        let store = try TransactionCacheStore(inMemory: true)
        try await store.upsert(cacheKey: key, transactions: transactions(count: 5))

        // Prime the order cache with a read.
        #expect(try await store.count(cacheKey: key) == 5)
        let firstPage = try await store.page(
            cacheKey: key,
            window: .make(pageIndex: 0, pageSize: 50, total: 5)
        )
        #expect(firstPage.count == 5)

        // Grow the history (a concurrent re-sync). The generation must bump.
        try await store.upsert(cacheKey: key, transactions: transactions(count: 12))
        #expect(try await store.count(cacheKey: key) == 12, "count reflects the grown history, not the cached 5")

        let afterGrowth = try await store.page(
            cacheKey: key,
            window: .make(pageIndex: 0, pageSize: 50, total: 12)
        )
        #expect(afterGrowth.count == 12, "the page read sees the new rows after invalidation")
        let expected = transactions(count: 12).sorted { $0.date > $1.date }.map(\.id)
        #expect(afterGrowth.map(\.id) == expected, "ordering is rebuilt correctly, newest-first")
    }

    /// The memoized ordering is keyed by `cacheKey`, not just generation: reading
    /// two environments back-to-back within one generation must not serve the first
    /// key's ordering for the second key.
    @Test("the ordering cache does not bleed across cache keys within one generation")
    func cachedOrderingScopedPerKey() async throws {
        let store = try TransactionCacheStore(inMemory: true)
        try await store.upsert(cacheKey: "sandbox|/x", transactions: transactions(count: 4))
        try await store.upsert(cacheKey: "production|/x", transactions: transactions(count: 6))

        // Read sandbox first (primes the cache for the current generation), then
        // production in the same generation — production must not reuse sandbox's order.
        #expect(try await store.count(cacheKey: "sandbox|/x") == 4)
        #expect(try await store.count(cacheKey: "production|/x") == 6)
        // And back again, exercising the cache miss-on-key-change in both directions.
        #expect(try await store.count(cacheKey: "sandbox|/x") == 4)

        let prodPage = try await store.page(
            cacheKey: "production|/x",
            window: .make(pageIndex: 0, pageSize: 100, total: 6)
        )
        #expect(prodPage.count == 6, "production page reads its own rows, not sandbox's cached order")
    }

    /// An updated payload (same id) must be reflected by a subsequent page read —
    /// proving the cache is invalidated on update, not just on insert/delete, and
    /// that the page path faults in the fresh blob rather than a stale one.
    @Test("an in-place update is reflected after cache invalidation")
    func updateReflectedAfterInvalidation() async throws {
        let store = try TransactionCacheStore(inMemory: true)
        let original = TransactionDTO(id: "t1", accountId: "chk", amount: 10, date: "2026-01-10", name: "Old")
        try await store.upsert(cacheKey: key, transactions: [original])
        // Prime the cache.
        _ = try await store.page(cacheKey: key, window: .make(pageIndex: 0, pageSize: 10, total: 1))

        let updated = TransactionDTO(id: "t1", accountId: "chk", amount: 99, date: "2026-01-10", name: "New")
        try await store.upsert(cacheKey: key, transactions: [updated])

        let page = try await store.page(cacheKey: key, window: .make(pageIndex: 0, pageSize: 10, total: 1))
        #expect(page.first?.amount == 99, "the cached ordering did not serve the stale payload")
        #expect(page.first?.name == "New")
    }
}
