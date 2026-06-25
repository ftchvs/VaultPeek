import Foundation
import FluentKit
import FluentSQLiteDriver
import Hummingbird
import HummingbirdFluent
import HummingbirdTesting
import Logging
@testable import PlaidBarCore
@testable import PlaidBarServer
import Testing

/// Opt-in server-synced review state — store + `/api/review` route (AND-552).
@Suite("Server-synced review state persistence (AND-552)")
struct ReviewStateStoreTests {
    private let apiToken = "local-review-token"
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Fixtures

    private func metadataRecord(
        id: String,
        category: SpendingCategory?,
        updatedAt: Date
    ) -> ReviewMetadataRecordDTO {
        ReviewMetadataRecordDTO(
            metadata: TransactionReviewMetadata(id: id, status: .reviewed, userCategory: category),
            updatedAt: updatedAt
        )
    }

    private func ruleRecord(
        id: UUID,
        merchantContains: String,
        category: SpendingCategory?,
        updatedAt: Date
    ) -> ReviewRuleRecordDTO {
        ReviewRuleRecordDTO(
            rule: TransactionRule(
                id: id,
                matchMerchantContains: merchantContains,
                category: category,
                createdAt: epoch
            ),
            updatedAt: updatedAt
        )
    }

    // MARK: - Harnesses (mirror CategoryBudgetStoreTests)

    private func withReviewStore(_ body: (ReviewStateStore) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-review-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("review.sqlite").path
        let logger = Logger(label: "com.ftchvs.plaidbar-server-tests.review")
        let fluent = Fluent(logger: logger)
        fluent.databases.use(.sqlite(.file(databasePath)), as: .sqlite)
        await fluent.migrations.add(CreateReviewState())

        var bodyError: Error?
        do {
            try await fluent.migrate()
            try await body(ReviewStateStore(fluent: fluent))
        } catch {
            bodyError = error
        }
        try await fluent.shutdown()
        if let bodyError { throw bodyError }
    }

    private func withReviewAPI(_ body: @Sendable (any TestClientProtocol) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-review-api-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("review.sqlite").path
        let logger = Logger(label: "com.ftchvs.plaidbar-server-tests.review-api")
        let fluent = Fluent(logger: logger)
        fluent.databases.use(.sqlite(.file(databasePath)), as: .sqlite)
        await fluent.migrations.add(CreateReviewState())

        var bodyError: Error?
        do {
            try await fluent.migrate()

            let router = Router()
            let api = router.group("api")
            api.add(middleware: APITokenMiddleware(authToken: apiToken))
            ReviewRoutes(reviewStateStore: ReviewStateStore(fluent: fluent))
                .register(with: api)

            let app = Application(router: router, logger: logger)
            try await app.test(.router) { client in
                try await body(client)
            }
        } catch {
            bodyError = error
        }
        try await fluent.shutdown()
        if let bodyError { throw bodyError }
    }

    private var authorizedJSONHeaders: HTTPFields {
        var headers = HTTPFields()
        headers[.authorization] = "Bearer \(apiToken)"
        headers[.contentType] = "application/json"
        return headers
    }

    private func encode(_ snapshot: ReviewStateSnapshotDTO) throws -> ByteBuffer {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return ByteBuffer(data: try encoder.encode(snapshot))
    }

    private func decode<T: Decodable>(_ type: T.Type, from response: TestResponse) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var body = response.body
        let data = body.readData(length: body.readableBytes) ?? Data()
        return try decoder.decode(T.self, from: data)
    }

    // MARK: - Store

    @Test("An empty store returns an empty snapshot")
    func emptyStore() async throws {
        try await withReviewStore { store in
            let snapshot = try await store.snapshot()
            #expect(snapshot.metadata.isEmpty)
            #expect(snapshot.rules.isEmpty)
        }
    }

    @Test("Merge persists records and round-trips them sorted")
    func mergeRoundTrips() async throws {
        try await withReviewStore { store in
            let ruleId = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
            let uploaded = ReviewStateSnapshotDTO(
                metadata: [
                    metadataRecord(id: "tx-b", category: .shopping, updatedAt: epoch),
                    metadataRecord(id: "tx-a", category: .foodAndDrink, updatedAt: epoch),
                ],
                rules: [ruleRecord(id: ruleId, merchantContains: "Coffee", category: .foodAndDrink, updatedAt: epoch)]
            )
            let merged = try await store.merge(incoming: uploaded)
            #expect(merged.metadata.map(\.id) == ["tx-a", "tx-b"])

            let reloaded = try await store.snapshot()
            #expect(reloaded.metadata.map(\.id) == ["tx-a", "tx-b"])
            #expect(reloaded.rules.map(\.id) == [ruleId])
            #expect(reloaded.metadata.first?.metadata.userCategory == .foodAndDrink)
        }
    }

    @Test("Merge applies last-writer-wins on a conflicting transaction id")
    func mergeLastWriterWins() async throws {
        try await withReviewStore { store in
            try await store.merge(incoming: ReviewStateSnapshotDTO(
                metadata: [metadataRecord(id: "tx-1", category: .foodAndDrink, updatedAt: epoch)],
                rules: []
            ))
            // A newer write to the same id replaces it.
            try await store.merge(incoming: ReviewStateSnapshotDTO(
                metadata: [metadataRecord(id: "tx-1", category: .shopping, updatedAt: epoch.addingTimeInterval(60))],
                rules: []
            ))
            let snapshot = try await store.snapshot()
            #expect(snapshot.metadata.count == 1)
            #expect(snapshot.metadata.first?.metadata.userCategory == .shopping)

            // An older write to the same id does NOT clobber the newer stored one.
            try await store.merge(incoming: ReviewStateSnapshotDTO(
                metadata: [metadataRecord(id: "tx-1", category: .travel, updatedAt: epoch)],
                rules: []
            ))
            let afterStale = try await store.snapshot()
            #expect(afterStale.metadata.first?.metadata.userCategory == .shopping)
        }
    }

    @Test("clearAll removes all synced review state (opt-out)")
    func clearAllRemovesEverything() async throws {
        try await withReviewStore { store in
            try await store.merge(incoming: ReviewStateSnapshotDTO(
                metadata: [metadataRecord(id: "tx-1", category: .foodAndDrink, updatedAt: epoch)],
                rules: [ruleRecord(
                    id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
                    merchantContains: "X",
                    category: .shopping,
                    updatedAt: epoch
                )]
            ))
            try await store.clearAll()
            let snapshot = try await store.snapshot()
            #expect(snapshot.metadata.isEmpty)
            #expect(snapshot.rules.isEmpty)
            // Idempotent: clearing an empty store does not throw.
            try await store.clearAll()
        }
    }

    // MARK: - Route contract

    @Test("GET /api/review starts empty after the migration")
    func apiGetStartsEmpty() async throws {
        try await withReviewAPI { client in
            let response = try await client.execute(uri: "/api/review", method: .get, headers: authorizedJSONHeaders)
            #expect(response.status == .ok)
            let snapshot = try decode(ReviewStateSnapshotDTO.self, from: response)
            #expect(snapshot.metadata.isEmpty)
            #expect(snapshot.rules.isEmpty)
        }
    }

    @Test("PUT/GET/DELETE /api/review round-trips and merges via the wired route")
    func apiRoundTripContract() async throws {
        try await withReviewAPI { client in
            let upload = ReviewStateSnapshotDTO(
                metadata: [metadataRecord(id: "tx-1", category: .foodAndDrink, updatedAt: epoch)],
                rules: []
            )
            let put = try await client.execute(
                uri: "/api/review",
                method: .put,
                headers: authorizedJSONHeaders,
                body: try encode(upload)
            )
            #expect(put.status == .ok)
            let merged = try decode(ReviewStateSnapshotDTO.self, from: put)
            #expect(merged.metadata.first?.metadata.userCategory == .foodAndDrink)

            // A second device PUT with a newer write to the same id wins via LWW.
            let upload2 = ReviewStateSnapshotDTO(
                metadata: [metadataRecord(id: "tx-1", category: .shopping, updatedAt: epoch.addingTimeInterval(120))],
                rules: []
            )
            let put2 = try await client.execute(
                uri: "/api/review",
                method: .put,
                headers: authorizedJSONHeaders,
                body: try encode(upload2)
            )
            let merged2 = try decode(ReviewStateSnapshotDTO.self, from: put2)
            #expect(merged2.metadata.first?.metadata.userCategory == .shopping)

            let get = try await client.execute(uri: "/api/review", method: .get, headers: authorizedJSONHeaders)
            let persisted = try decode(ReviewStateSnapshotDTO.self, from: get)
            #expect(persisted.metadata.first?.metadata.userCategory == .shopping)

            let delete = try await client.execute(uri: "/api/review", method: .delete, headers: authorizedJSONHeaders)
            #expect(delete.status == .noContent)

            let getAfter = try await client.execute(uri: "/api/review", method: .get, headers: authorizedJSONHeaders)
            let cleared = try decode(ReviewStateSnapshotDTO.self, from: getAfter)
            #expect(cleared.metadata.isEmpty)
        }
    }

    @Test("/api/review requires the bearer token")
    func apiRequiresAuth() async throws {
        try await withReviewAPI { client in
            let response = try await client.execute(uri: "/api/review", method: .get)
            #expect(response.status == .unauthorized)
        }
    }

    @Test("PUT /api/review rejects a malformed body")
    func apiRejectsMalformedBody() async throws {
        try await withReviewAPI { client in
            let response = try await client.execute(
                uri: "/api/review",
                method: .put,
                headers: authorizedJSONHeaders,
                body: ByteBuffer(string: "{ not valid json")
            )
            #expect(response.status == .badRequest)
        }
    }

    // MARK: - Pure decode validation

    @Test("decodeSnapshot rejects an unsupported (newer) schema version")
    func decodeRejectsFutureSchema() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let future = ReviewStateSnapshotDTO(
            schemaVersion: ReviewStateSnapshotDTO.currentSchemaVersion + 1,
            metadata: [],
            rules: []
        )
        let buffer = ByteBuffer(data: try encoder.encode(future))
        #expect(throws: (any Error).self) { try ReviewRoutes.decodeSnapshot(buffer) }
    }
}
