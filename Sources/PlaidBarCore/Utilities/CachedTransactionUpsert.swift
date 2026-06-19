import Foundation

/// Pure, testable upsert/dedup decision for the disposable per-transaction cache
/// (AND-567).
///
/// The SwiftData `CachedTransaction` row is keyed `@Attribute(.unique)` on the
/// stable Plaid `transaction_id`, so re-syncing a transaction must *replace* the
/// existing row rather than duplicate it. This type decides — given the ids
/// already in the store and the freshly decoded authoritative DTOs — which ids are
/// inserts and which are updates, and collapses duplicate ids *within* the
/// incoming batch (a sync page can re-list the same id; the newest occurrence
/// wins). Keeping the decision out of the `@ModelActor` lets the boundary
/// conditions be unit-tested without SwiftData.
public enum CachedTransactionUpsert {
    /// The classification of an incoming batch against the store's existing ids.
    public struct Plan: Sendable, Equatable {
        /// Ids present in the batch but not yet in the store (fresh inserts).
        public let insertedIds: [String]
        /// Ids present in both the batch and the store (updated in place).
        public let updatedIds: [String]
        /// The deduplicated rows to write, in input order, last-write-wins per id.
        public let rows: [TransactionDTO]

        public init(insertedIds: [String], updatedIds: [String], rows: [TransactionDTO]) {
            self.insertedIds = insertedIds
            self.updatedIds = updatedIds
            self.rows = rows
        }

        /// Total rows that will be written (inserts + updates), after batch dedup.
        public var writeCount: Int { rows.count }
    }

    /// Builds the upsert plan for `incoming` against the ids already persisted
    /// (`existingIds`).
    ///
    /// Dedup rule: when the same id appears more than once in `incoming`, the
    /// **last** occurrence wins (matching Plaid's "a later sync page supersedes an
    /// earlier one" semantics) and the row keeps the position of its first
    /// appearance so output order is stable. An id already in `existingIds` is an
    /// update; a brand-new id is an insert. Classification reflects the
    /// deduplicated set, so a batch listing the same new id twice counts as one
    /// insert, not two.
    public static func plan(
        incoming: [TransactionDTO],
        existingIds: Set<String>
    ) -> Plan {
        var order: [String] = []
        var latestById: [String: TransactionDTO] = [:]
        for tx in incoming {
            if latestById[tx.id] == nil {
                order.append(tx.id)
            }
            latestById[tx.id] = tx // last write wins
        }

        var inserted: [String] = []
        var updated: [String] = []
        var rows: [TransactionDTO] = []
        rows.reserveCapacity(order.count)
        for id in order {
            guard let row = latestById[id] else { continue }
            rows.append(row)
            if existingIds.contains(id) {
                updated.append(id)
            } else {
                inserted.append(id)
            }
        }
        return Plan(insertedIds: inserted, updatedIds: updated, rows: rows)
    }

    /// Convenience: classify a single id as an update (already stored) or insert.
    public static func isUpdate(id: String, existingIds: Set<String>) -> Bool {
        existingIds.contains(id)
    }
}
