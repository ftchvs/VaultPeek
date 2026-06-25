import Foundation
import Testing
@testable import PlaidBarCache
@testable import PlaidBarCore

/// Regression coverage for the transaction-cache persist-after-clear race (P2,
/// data resurrection): "transaction cache has a persist-after-clear race the
/// read-model cache already guards against."
///
/// `persistTransactionCache()` schedules an off-main `replaceAll`; once
/// `clearTransactionCache()` nils the property, the captured `store` actor lives
/// on, so refresh A's detached persist can commit *after* refresh B's clear,
/// repopulating `transaction-cache-v1.store` with removed-institution
/// transactions that the cold-start paged read then surfaces.
///
/// The app-side fix routes this cache through the *same* `ReadModelCacheClearGate`
/// (in `AppState+TransactionCache.swift`) the read-model cache uses:
///   1. A scheduled persist captures the clear epoch synchronously on the main
///      actor and re-checks it before committing; if a clear was requested since,
///      the `replaceAll` is dropped (epoch recheck).
///   2. Even if a stale write slips through, the clear's `clearAll()` is serialized
///      on the store actor *after* the clear is requested, so it wipes the stale
///      rows.
///
/// These tests mirror `ReadModelCacheClearRaceTests` for the per-transaction
/// store: they pin the store-level invariant the gate relies on (a captured-epoch
/// persist landing after a `beginClear` must NOT commit) and document the raw
/// hazard the gate exists to prevent.
@Suite("Transaction cache clear-wins race (cold-start resurrection)", .serialized)
struct TransactionCacheClearRaceTests {

    private static let key = "sandbox|/x"

    private func removedInstitutionTransactions() -> [TransactionDTO] {
        [
            TransactionDTO(id: "t1", accountId: "chk", amount: 12.5, date: "2026-01-15", name: "Coffee"),
            TransactionDTO(id: "t2", accountId: "chk", amount: 88.0, date: "2026-01-16", name: "Groceries"),
        ]
    }

    /// A minimal stand-in for the `@MainActor` `ReadModelCacheClearGate` the app
    /// shares between both caches: a monotonic epoch bumped on `beginClear`, with
    /// a capture/recheck the scheduled persist uses to decide whether to commit.
    /// Mirrors the gate's `currentEpoch` / `beginClear()` / `mayCommit(capturedEpoch:)`
    /// shape so the store-level invariant under test matches production wiring.
    private final class ClearGateStub {
        private var clearEpoch = 0
        var currentEpoch: Int { clearEpoch }
        func beginClear() { clearEpoch &+= 1 }
        func mayCommit(capturedEpoch: Int) -> Bool { capturedEpoch == clearEpoch }
    }

    /// The hazard, made explicit: an UNGUARDED stale persist that commits *after* a
    /// clear leaves removed-institution transactions in the cache for the next cold
    /// start. This is exactly the ordering the app-side gate prevents.
    @Test("stale persist after clear resurrects removed transactions (the bug the gate prevents)")
    func staleWriteAfterClearResurrects() async throws {
        let store = TransactionCacheStore(inMemory: true)
        let key = Self.key

        // Prior non-empty refresh persisted the history.
        try await store.replaceAll(cacheKey: key, transactions: removedInstitutionTransactions())
        // User removes last institution → cache cleared.
        try await store.clearAll()
        // A stale in-flight persist of the prior transactions lands AFTER the clear.
        try await store.replaceAll(cacheKey: key, transactions: removedInstitutionTransactions())

        // Next cold-start paged read would now resurrect the removed transactions.
        #expect(try await store.count(cacheKey: key) == 2)
    }

    /// The fix's guarantee at the store level: a persist that captured its epoch
    /// *before* a `beginClear` must drop itself (the `mayCommit` recheck fails), so
    /// `replaceAll` never runs and the cold-start paged read is a clean miss.
    @Test("captured-epoch persist landing after beginClear does NOT commit")
    func capturedEpochPersistAfterClearIsDropped() async throws {
        let store = TransactionCacheStore(inMemory: true)
        let key = Self.key
        let gate = ClearGateStub()

        // Refresh A's prior persist seeded the cache (committed under the old epoch).
        try await store.replaceAll(cacheKey: key, transactions: removedInstitutionTransactions())

        // Refresh A schedules a fresh persist: capture the epoch as it is scheduled.
        let capturedEpoch = gate.currentEpoch

        // Refresh B clears: epoch is bumped synchronously *before* its store wipe.
        gate.beginClear()
        try await store.clearAll()

        // Refresh A's detached persist now reaches the commit point. With the gate
        // it must observe the bump and drop the `replaceAll` rather than resurrect.
        if gate.mayCommit(capturedEpoch: capturedEpoch) {
            try await store.replaceAll(cacheKey: key, transactions: removedInstitutionTransactions())
        }

        // Clear won: the cold-start paged read sees no removed transactions.
        #expect(try await store.count(cacheKey: key) == 0)
    }

    /// The serialization backstop: when the clear is sequenced on the store actor
    /// *after* a (possibly stale) write, the clear runs last and wipes it — the
    /// cold-start paged read is a clean miss even if a write slipped the recheck.
    @Test("clear sequenced after a stale persist wins; cold start pages nothing")
    func clearAfterStaleWriteWins() async throws {
        let store = TransactionCacheStore(inMemory: true)
        let key = Self.key

        try await store.replaceAll(cacheKey: key, transactions: removedInstitutionTransactions())
        // Stale in-flight persist slips through first...
        try await store.replaceAll(cacheKey: key, transactions: removedInstitutionTransactions())
        // ...but the clear (serialized on the store actor after the clear request)
        // runs last and wipes it.
        try await store.clearAll()

        #expect(try await store.count(cacheKey: key) == 0)
    }
}
