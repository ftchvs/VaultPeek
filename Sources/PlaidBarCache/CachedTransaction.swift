import Foundation
import SwiftData

/// SwiftData row backing the disposable **per-transaction** cache used for
/// large-history paging (AND-567).
///
/// Like ``CachedDashboardReadModel``, this is a disposable read-model row, never a
/// source of truth: it is written *after* a successful decode from the
/// authoritative DTOs and read back in pages to feed a virtualized list. The file
/// can be deleted at any time and rebuilt from the next refresh.
///
/// ## Shape
/// The authoritative ``TransactionDTO`` is stored as a single JSON `payload` blob
/// alongside flat, queryable scalar columns:
/// - `uniqueKey` — `@Attribute(.unique)`, `"<cacheKey>|<transactionId>"`. Making
///   the key composite means a re-sync of the same transaction **upserts** (the
///   unique constraint replaces the row) while two Plaid environments sharing one
///   store file can never collide on a bare transaction id.
/// - `cacheKey` — environment + data-dir scope, so a page read filters to the
///   active environment.
/// - `sortDate` — the `YYYY-MM-DD` string (lexicographically sortable), used as the
///   primary newest-first sort key; `transactionId` breaks ties for a stable order.
///
/// Keeping the schema to flat primitives + one blob mirrors the AND-566 cache: a
/// shape change is handled by bumping the disposable store filename and deleting
/// the old file, not by a SwiftData migration.
///
/// `@Model` classes are reference types and are **not** `Sendable`; instances of
/// this type never leave ``TransactionCacheStore``'s actor isolation. Only the
/// `Sendable` ``TransactionDTO`` value crosses the boundary.
@Model
final class CachedTransaction {
    /// `"<cacheKey>|<transactionId>"`. Unique so a re-synced transaction replaces
    /// its row in place (upsert) instead of duplicating.
    @Attribute(.unique) var uniqueKey: String
    /// Environment + data-dir scope key (matches the dashboard cache's key space).
    var cacheKey: String
    /// Plaid `transaction_id`, mirrored out of the blob for tie-breaking the sort.
    var transactionId: String
    /// `YYYY-MM-DD`; lexicographic order equals chronological order, so a plain
    /// descending string sort yields newest-first paging without parsing dates.
    var sortDate: String
    /// JSON-encoded ``TransactionDTO``.
    var payload: Data

    init(uniqueKey: String, cacheKey: String, transactionId: String, sortDate: String, payload: Data) {
        self.uniqueKey = uniqueKey
        self.cacheKey = cacheKey
        self.transactionId = transactionId
        self.sortDate = sortDate
        self.payload = payload
    }

    /// Builds the composite unique key for a (cacheKey, transactionId) pair.
    static func makeUniqueKey(cacheKey: String, transactionId: String) -> String {
        "\(cacheKey)|\(transactionId)"
    }
}
