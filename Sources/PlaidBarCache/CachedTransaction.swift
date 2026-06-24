import Foundation

/// Row backing the disposable **per-transaction** cache used for large-history
/// paging (AND-567).
///
/// Like ``CachedDashboardReadModel``, this is a disposable read-model row, never a
/// source of truth: it is written *after* a successful decode from the
/// authoritative DTOs and read back in pages to feed a virtualized list. The file
/// can be deleted at any time and rebuilt from the next refresh.
struct CachedTransaction: Codable, Equatable, Sendable {
    /// `"<cacheKey>|<transactionId>"`. Unique so a re-synced transaction replaces
    /// its row in place (upsert) instead of duplicating.
    var uniqueKey: String
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
