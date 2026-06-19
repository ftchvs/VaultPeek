import Foundation
import SwiftData

/// SwiftData row backing the disposable dashboard read-model cache (AND-566).
///
/// The structured, authoritative payload is the pure ``DashboardReadModel``
/// value type in `PlaidBarCore`; this `@Model` stores that value as a single
/// JSON `payload` blob alongside two queryable scalar columns (`cacheKey`,
/// `schemaVersion`). Keeping the SwiftData schema to three flat, primitive
/// properties is deliberate:
///
/// - The store is **disposable**: with no relationships and no per-field schema
///   to migrate, a shape change is handled by bumping
///   ``DashboardReadModel/currentSchemaVersion`` and treating mismatched rows as
///   a cache miss — the file can always be deleted and rebuilt from the
///   authoritative refresh.
/// - The Codable round-trip is already proven by `DashboardReadModelMapper`
///   tests, so the on-disk format inherits that guarantee instead of forking a
///   second SwiftData-specific mapping.
///
/// `@Model` classes are reference types and are **not** `Sendable`; instances of
/// this type never leave ``ReadModelCacheStore``'s actor isolation. Only the
/// `Sendable` ``DashboardReadModel`` value crosses the boundary.
@Model
final class CachedDashboardReadModel {
    /// Environment + data-dir scoped key. Unique so the cache holds exactly one
    /// row per environment (the last-known dashboard).
    @Attribute(.unique) var cacheKey: String
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
