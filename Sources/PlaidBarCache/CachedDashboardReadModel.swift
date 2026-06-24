import Foundation

/// Row backing the disposable dashboard read-model cache (AND-566).
///
/// The authoritative payload is the pure ``DashboardReadModel`` value type in
/// `PlaidBarCore`; this row stores that value as a JSON `payload` blob alongside
/// two queryable scalar columns (`cacheKey`, `schemaVersion`). The store is
/// deliberately disposable: a schema mismatch is a cache miss and the file can be
/// deleted and rebuilt from the authoritative refresh at any time.
struct CachedDashboardReadModel: Codable, Equatable, Sendable {
    /// Environment + data-dir scoped key. Unique so the cache holds exactly one
    /// row per environment (the last-known dashboard).
    var cacheKey: String
    /// The schema version the payload was written with, mirrored out of the blob
    /// so a version sweep can run without decoding every row.
    var schemaVersion: Int
    /// JSON-encoded ``DashboardReadModel``.
    var payload: Data

    init(cacheKey: String, schemaVersion: Int, payload: Data) {
        self.cacheKey = cacheKey
        self.schemaVersion = schemaVersion
        self.payload = payload
    }
}
