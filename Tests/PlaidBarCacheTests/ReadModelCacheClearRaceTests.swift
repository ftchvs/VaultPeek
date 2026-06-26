import Foundation
import Testing
@testable import PlaidBarCache
@testable import PlaidBarCore

/// Regression coverage for the cold-start clear-wins race (audit finding:
/// "Cold-start read-model cache can resurrect removed-institution balances").
///
/// When the user removes their last institution, `AppState` schedules a clear of
/// the disposable read-model cache. A persist of the *previous* (non-empty)
/// read-model may still be in flight. If that stale write lands after the clear,
/// the next cold start paints balances for an account the user removed.
///
/// The app-side fix (`ReadModelCacheClearGate` in `AppState+ReadModelCache.swift`)
/// guarantees a clear cannot be overwritten by a stale write via two mechanisms:
///   1. A scheduled write drops itself if a clear was requested after it was
///      scheduled (epoch recheck on the main actor).
///   2. Even if a stale write slips through, the clear's `clearAll()` is
///      serialized on the store actor *after* the clear is requested, so it wipes
///      the stale row.
///
/// These tests pin the store-level invariant the fix relies on: after the
/// remove-last sequence resolves with the clear winning, a cold-start `load`
/// returns nil — never the removed-institution balances. They also document the
/// raw hazard the gate exists to prevent.
@Suite("Read-model cache clear-wins race (cold-start resurrection)", .serialized)
struct ReadModelCacheClearRaceTests {

    private func nonEmptyModel(cacheKey: String = "sandbox|/x") -> DashboardReadModel {
        DashboardReadModelMapper.makeReadModel(
            cacheKey: cacheKey,
            accounts: [
                AccountDTO(
                    id: "chk", itemId: "i1", name: "Checking",
                    type: .depository, balances: BalanceDTO(available: 8200)
                ),
            ],
            transactions: [
                TransactionDTO(id: "t1", accountId: "chk", amount: 12.5, date: "2026-01-15", name: "Coffee"),
            ],
            generatedAt: Date(timeIntervalSince1970: 1_700_000)
        )
    }

    /// The hazard, made explicit: a stale write that commits *after* a clear
    /// leaves removed-institution balances in the cache for the next cold start.
    /// This is exactly the ordering the app-side gate prevents.
    @Test("stale write after clear resurrects removed balances (the bug the gate prevents)")
    func staleWriteAfterClearResurrects() async throws {
        let store = ReadModelCacheStore(inMemory: true)
        let key = "sandbox|/x"

        // Prior non-empty refresh persisted a row.
        try await store.save(nonEmptyModel(cacheKey: key))
        // User removes last institution → cache cleared.
        try await store.clearAll()
        // A stale in-flight persist of the prior model lands AFTER the clear.
        try await store.save(nonEmptyModel(cacheKey: key))

        // Next cold start would now resurrect the removed-institution balances.
        #expect(try await store.load(cacheKey: key) != nil)
    }

    /// The fix's guarantee: when the clear is sequenced after the (possibly
    /// stale) write — which `clearAll()` running on the store actor after the
    /// clear request ensures — the cold-start load is a clean miss.
    @Test("clear sequenced after a stale write wins; cold start sees no removed balances")
    func clearAfterStaleWriteWins() async throws {
        let store = ReadModelCacheStore(inMemory: true)
        let key = "sandbox|/x"

        try await store.save(nonEmptyModel(cacheKey: key))
        // Stale in-flight write slips through first...
        try await store.save(nonEmptyModel(cacheKey: key))
        // ...but the clear (serialized on the store actor after the clear request)
        // runs last and wipes it.
        try await store.clearAll()

        #expect(try await store.load(cacheKey: key) == nil)
    }

    // MARK: - Store-actor clear generation (AND-633: two-hop window)

    /// The two-hop residual the store-actor generation closes: with the *old*
    /// pattern, a persist that passed the main-actor epoch recheck could still
    /// commit after a clear that landed before its `save` reached the store actor.
    /// The atomic `save(_:ifNotClearedSince:)` re-validates the generation on the
    /// store actor, so a clear that bumped it since capture drops the write.
    @Test("save dropped when clear bumped the store generation after capture (AND-633)")
    func saveDroppedWhenClearRacedAfterGenerationCapture() async throws {
        let store = ReadModelCacheStore(inMemory: true)
        let key = "sandbox|/x"

        // Prior non-empty refresh seeded a row, then the user removed their last
        // institution. The persist captured the generation BEFORE the clear...
        try await store.save(nonEmptyModel(cacheKey: key))
        let capturedGeneration = await store.currentClearGeneration()

        // ...the clear lands in the two-hop window (bumping the store generation)...
        try await store.clearAll()

        // ...and the stale persist finally reaches the store actor. The atomic
        // re-check must observe the bumped generation and drop the write.
        let committed = try await store.save(
            nonEmptyModel(cacheKey: key),
            ifNotClearedSince: capturedGeneration
        )

        #expect(committed == false)
        #expect(try await store.load(cacheKey: key) == nil)
    }

    /// The happy path: when no clear intervenes between capturing the generation and
    /// committing, the clear-gated save behaves like a normal save.
    @Test("clear-gated save commits when no clear intervened (AND-633)")
    func clearGatedSaveCommitsWhenNoClearIntervened() async throws {
        let store = ReadModelCacheStore(inMemory: true)
        let key = "sandbox|/x"

        let capturedGeneration = await store.currentClearGeneration()
        let committed = try await store.save(
            nonEmptyModel(cacheKey: key),
            ifNotClearedSince: capturedGeneration
        )

        #expect(committed == true)
        #expect(try await store.load(cacheKey: key) != nil)
    }

    /// Concurrency stress: fan out clear-gated saves and clears that all capture the
    /// SAME starting generation, with a terminal clear. Whatever the interleaving,
    /// the atomic generation check guarantees the terminal clear is never overwritten
    /// — the cold-start load is always a clean miss.
    @Test("interleaved clear-gated saves never survive a terminal clear (AND-633)")
    func interleavedClearGatedSavesNeverSurviveTerminalClear() async throws {
        let store = ReadModelCacheStore(inMemory: true)
        let key = "sandbox|/x"
        let model = nonEmptyModel(cacheKey: key)

        await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<16 {
                group.addTask {
                    let captured = await store.currentClearGeneration()
                    _ = try await store.save(model, ifNotClearedSince: captured)
                }
            }
            while let _ = try? await group.next() {}
        }

        // Terminal clear bumps the generation; any concurrently captured save that
        // reaches the actor afterwards re-checks and drops itself.
        try await store.clearAll()
        // A late stale persist that captured an earlier generation must still drop.
        let staleGeneration: UInt64 = 0
        let committed = try await store.save(model, ifNotClearedSince: staleGeneration)

        #expect(committed == false)
        #expect(try await store.load(cacheKey: key) == nil)
    }

    /// Many interleaved persists followed by a terminal clear must always resolve
    /// to an empty cache — the clear is the last serialized store operation, so
    /// no in-flight write can survive it.
    @Test("terminal clear after concurrent persists always wins")
    func terminalClearWinsOverConcurrentPersists() async throws {
        let store = ReadModelCacheStore(inMemory: true)
        let key = "sandbox|/x"
        let model = nonEmptyModel(cacheKey: key)

        // Fan out several persists, then await them all so they are all committed.
        await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask { try await store.save(model) }
            }
            // Drain; ignore individual save failures (best-effort contract).
            while let _ = try? await group.next() {}
        }

        // The terminal clear is the last store operation, mirroring the
        // gate-enforced ordering where the empty-state clear wins.
        try await store.clearAll()

        #expect(try await store.load(cacheKey: key) == nil)
    }
}
