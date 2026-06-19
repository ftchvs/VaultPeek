import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Cached transaction upsert/dedup decision (AND-567)")
struct CachedTransactionUpsertTests {

    private func tx(_ id: String, amount: Double = 10, date: String = "2026-01-10", name: String = "M") -> TransactionDTO {
        TransactionDTO(id: id, accountId: "chk", amount: amount, date: date, name: name)
    }

    @Test("all-new ids are inserts")
    func allInserts() {
        let plan = CachedTransactionUpsert.plan(
            incoming: [tx("a"), tx("b"), tx("c")],
            existingIds: []
        )
        #expect(plan.insertedIds == ["a", "b", "c"])
        #expect(plan.updatedIds.isEmpty)
        #expect(plan.writeCount == 3)
    }

    @Test("ids already in the store are updates, not duplicate inserts")
    func updatesReplace() {
        let plan = CachedTransactionUpsert.plan(
            incoming: [tx("a"), tx("b"), tx("c")],
            existingIds: ["b"]
        )
        #expect(plan.insertedIds == ["a", "c"])
        #expect(plan.updatedIds == ["b"], "a re-synced id updates in place")
    }

    @Test("same id re-synced uses the latest payload (last write wins)")
    func lastWriteWins() {
        let plan = CachedTransactionUpsert.plan(
            incoming: [tx("a", amount: 10, name: "Old"), tx("a", amount: 25, name: "New")],
            existingIds: []
        )
        #expect(plan.rows.count == 1, "duplicate id collapses to one row")
        #expect(plan.rows.first?.amount == 25)
        #expect(plan.rows.first?.name == "New")
        #expect(plan.insertedIds == ["a"], "a duplicated new id is a single insert")
    }

    @Test("dedup keeps the position of the first appearance for stable order")
    func stableOrder() {
        let plan = CachedTransactionUpsert.plan(
            incoming: [tx("a"), tx("b"), tx("a", amount: 99)],
            existingIds: []
        )
        #expect(plan.rows.map(\.id) == ["a", "b"], "order follows first appearance")
        #expect(plan.rows.first?.amount == 99, "but the value is the latest")
    }

    @Test("empty batch yields an empty plan")
    func emptyBatch() {
        let plan = CachedTransactionUpsert.plan(incoming: [], existingIds: ["x"])
        #expect(plan.rows.isEmpty)
        #expect(plan.insertedIds.isEmpty)
        #expect(plan.updatedIds.isEmpty)
        #expect(plan.writeCount == 0)
    }

    @Test("a pending charge re-listed under the same id never duplicates")
    func pendingThenPosted() {
        // First seen pending, then the posted version arrives under the SAME id in
        // a later page; it must replace, not duplicate.
        let pending = TransactionDTO(id: "t1", accountId: "chk", amount: 12, date: "2026-01-10", name: "Cafe", pending: true)
        let posted = TransactionDTO(id: "t1", accountId: "chk", amount: 12, date: "2026-01-11", name: "Cafe", pending: false)
        let plan = CachedTransactionUpsert.plan(incoming: [pending, posted], existingIds: ["t1"])
        #expect(plan.rows.count == 1)
        #expect(plan.rows.first?.pending == false, "posted version wins")
        #expect(plan.updatedIds == ["t1"])
    }

    @Test("isUpdate classifies a single id")
    func isUpdate() {
        #expect(CachedTransactionUpsert.isUpdate(id: "a", existingIds: ["a", "b"]))
        #expect(!CachedTransactionUpsert.isUpdate(id: "z", existingIds: ["a", "b"]))
    }
}
