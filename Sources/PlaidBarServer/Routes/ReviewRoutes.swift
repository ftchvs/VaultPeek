import Foundation
import Hummingbird
import NIOCore
import PlaidBarCore

/// `/api/review` — opt-in server-synced review state (AND-552, deferred epic
/// AND-524). Registered under the same `APITokenMiddleware`-guarded group as the
/// other API routes, so every call requires the bearer token.
///
/// ## Strictly opt-in
/// The route always exists, but it is only *exercised* by an app that has enabled
/// ``ServerSyncedReviewFeatureFlag`` (default OFF). A not-opted-in app never calls
/// it, so the synced tables stay empty and behavior is byte-identical to before
/// AND-552 — no review data leaves the device without explicit consent.
///
/// ## Endpoints
/// - `GET /api/review` — pull the stored snapshot (empty when never synced).
/// - `PUT /api/review` — upload a device snapshot; the server merges it into the
///   stored state with per-record last-writer-wins
///   (``ReviewStateConflictResolver``) and returns the merged union so the device
///   converges in one round-trip.
/// - `DELETE /api/review` — clear all synced review state (opt-out / reset).
///
/// ## Data surface
/// The stored snapshot holds **user category overrides, merchant renames, notes,
/// and categorization rules** — display-safe derived values, never a Plaid token.
/// This is the only place the server persists review state; the trust-boundary
/// change is documented in `SECURITY.md`.
struct ReviewRoutes: Sendable {
    let reviewStateStore: ReviewStateStore

    /// Reject uploads larger than this so a single `PUT` cannot balloon the local
    /// SQLite store. The synced state is small (overrides + rules), so 4 MiB is a
    /// generous ceiling that still fails closed on a malformed/huge body.
    static let maxUploadBytes = 4 * 1024 * 1024

    func register(with group: RouterGroup<some RequestContext>) {
        group.group("review")
            .get(use: getSnapshot)
            .put(use: putSnapshot)
            .delete(use: deleteSnapshot)
    }

    @Sendable
    func getSnapshot(request: Request, context: some RequestContext) async throws -> Response {
        let snapshot = try await reviewStateStore.snapshot()
        return try Self.jsonResponse(snapshot)
    }

    @Sendable
    func putSnapshot(request: Request, context: some RequestContext) async throws -> Response {
        let body = try await request.body.collect(upTo: Self.maxUploadBytes)
        let incoming = try Self.decodeSnapshot(body)
        let merged = try await reviewStateStore.merge(incoming: incoming)
        return try Self.jsonResponse(merged)
    }

    @Sendable
    func deleteSnapshot(request: Request, context: some RequestContext) async throws -> HTTPResponse.Status {
        try await reviewStateStore.clearAll()
        return .noContent
    }

    // MARK: - Validation (pure, testable without a request context)

    /// Decode and validate an uploaded snapshot. Rejects an unparseable body and a
    /// snapshot tagged with an unknown (newer) schema version — failing closed
    /// rather than silently persisting a shape this server cannot round-trip.
    static func decodeSnapshot(_ buffer: ByteBuffer) throws -> ReviewStateSnapshotDTO {
        var buffer = buffer
        let data = buffer.readData(length: buffer.readableBytes) ?? Data()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot: ReviewStateSnapshotDTO
        do {
            snapshot = try decoder.decode(ReviewStateSnapshotDTO.self, from: data)
        } catch {
            throw HTTPError(.badRequest, message: "Malformed review snapshot")
        }
        guard snapshot.schemaVersion <= ReviewStateSnapshotDTO.currentSchemaVersion else {
            throw HTTPError(
                .badRequest,
                message: "Unsupported review snapshot schema version \(snapshot.schemaVersion)"
            )
        }
        return snapshot
    }

    static func jsonResponse(_ value: some Encodable) throws -> Response {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: ByteBuffer(data: data))
        )
    }
}
