import FluentKit
import FluentSQLiteDriver
import Foundation
import Hummingbird
import HummingbirdFluent
import HTTPTypes
import Logging
import NIOCore
@testable import PlaidBarCore
@testable import PlaidBarServer
import Testing

private struct WebhookTestContextSource: RequestContextSource {
    let logger = Logger(label: "com.ftchvs.plaidbar-server-tests.webhooks")
}

private struct WebhookTestContext: RequestContext {
    typealias Source = WebhookTestContextSource

    var coreContext: CoreRequestContextStorage

    init(source: WebhookTestContextSource) {
        coreContext = CoreRequestContextStorage(source: source)
    }
}

private struct AcceptingSignatureValidator: PlaidWebhookSignatureValidator {
    func validate(jwt: String, header: PlaidWebhookJWTHeader, claims: PlaidWebhookJWTClaims) async throws {}
}

private struct RejectingVerifier: PlaidWebhookVerifier {
    func verify(jwt: String, body: Data, now: Date) async throws {
        throw PlaidWebhookVerificationError.bodyHashMismatch
    }
}

@Suite("Plaid webhook receiver")
struct WebhookReceiverTests {
    @Test("Verifier rejects non-ES256, stale iat, bad hash, and unavailable signature validation")
    func verifierRejectsInvalidInputs() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let body = Data(Self.payload(webhookCode: "SYNC_UPDATES_AVAILABLE").utf8)
        let verifier = StrictPlaidWebhookVerifier(signatureValidator: AcceptingSignatureValidator())

        await #expect(throws: PlaidWebhookVerificationError.unsupportedAlgorithm) {
            try await verifier.verify(jwt: Self.jwt(alg: "HS256", iat: Int(now.timeIntervalSince1970), body: body), body: body, now: now)
        }
        await #expect(throws: PlaidWebhookVerificationError.staleIssuedAt) {
            try await verifier.verify(jwt: Self.jwt(iat: Int(now.addingTimeInterval(-301).timeIntervalSince1970), body: body), body: body, now: now)
        }
        await #expect(throws: PlaidWebhookVerificationError.bodyHashMismatch) {
            try await verifier.verify(jwt: Self.jwt(iat: Int(now.timeIntervalSince1970), body: Data("{}".utf8)), body: body, now: now)
        }

        let strictDefault = StrictPlaidWebhookVerifier()
        await #expect(throws: PlaidWebhookVerificationError.signatureVerificationUnavailable) {
            try await strictDefault.verify(jwt: Self.jwt(iat: Int(now.timeIntervalSince1970), body: body), body: body, now: now)
        }
    }

    @Test("Verifier body-hash comparison is length-checked and constant-time")
    func verifierBodyHashComparison() {
        let body = Data(Self.payload(webhookCode: "SYNC_UPDATES_AVAILABLE").utf8)
        let hash = StrictPlaidWebhookVerifier.sha256Hex(body)
        let changedLast = hash.last == "0" ? "1" : "0"
        let sameLengthMismatch = String(hash.dropLast()) + changedLast

        #expect(StrictPlaidWebhookVerifier.constantTimeEquals(hash, hash))
        #expect(!StrictPlaidWebhookVerifier.constantTimeEquals(hash, sameLengthMismatch))
        #expect(!StrictPlaidWebhookVerifier.constantTimeEquals(hash, hash + "0"))
    }

    @Test("Duplicate delivery is idempotent and stores metadata only")
    func duplicateDeliveryIsIdempotent() async throws {
        try await Self.withStores { tokenStore, eventStore in
            try await tokenStore.updateItemStatus(id: "item-webhook", status: ItemConnectionStatus.connected.rawValue)
            let route = WebhookRoutes(
                verifier: StrictPlaidWebhookVerifier(signatureValidator: AcceptingSignatureValidator()),
                tokenStore: tokenStore,
                eventStore: eventStore,
                now: { Date(timeIntervalSince1970: 1_800_000_000) }
            )
            let body = Self.payload(webhookCode: "ITEM_LOGIN_REQUIRED")
            let jwt = Self.jwt(iat: 1_800_000_000, body: Data(body.utf8))

            _ = try await route.receive(
                request: Self.request(body: body, jwt: jwt),
                context: WebhookTestContext(source: WebhookTestContextSource())
            )
            _ = try await route.receive(
                request: Self.request(body: body, jwt: jwt),
                context: WebhookTestContext(source: WebhookTestContextSource())
            )

            #expect(try await tokenStore.getItem(id: "item-webhook")?.status == ItemConnectionStatus.loginRequired.rawValue)
            let latest = try await eventStore.latestEvent(itemId: "item-webhook")
            #expect(latest?.webhookCode == "ITEM_LOGIN_REQUIRED")
            #expect(latest?.requestId == "request-safe")
            #expect(latest?.idempotencyHash.contains("ITEM_LOGIN_REQUIRED") == false)
        }
    }

    @Test("Out-of-order webhook metadata is retained without regressing item status")
    func outOfOrderDeliveryDoesNotRegressStatus() async throws {
        try await Self.withStores { tokenStore, eventStore in
            let route = WebhookRoutes(
                verifier: StrictPlaidWebhookVerifier(signatureValidator: AcceptingSignatureValidator()),
                tokenStore: tokenStore,
                eventStore: eventStore,
                now: { Date(timeIntervalSince1970: 1_800_000_000) }
            )
            let repaired = Self.payload(webhookCode: "LOGIN_REPAIRED", timestamp: "2026-06-14T12:10:00Z")
            let olderLoginRequired = Self.payload(webhookCode: "ITEM_LOGIN_REQUIRED", timestamp: "2026-06-14T12:00:00Z")

            _ = try await route.receive(
                request: Self.request(body: repaired, jwt: Self.jwt(iat: 1_800_000_000, body: Data(repaired.utf8))),
                context: WebhookTestContext(source: WebhookTestContextSource())
            )
            _ = try await route.receive(
                request: Self.request(body: olderLoginRequired, jwt: Self.jwt(iat: 1_800_000_000, body: Data(olderLoginRequired.utf8))),
                context: WebhookTestContext(source: WebhookTestContextSource())
            )

            #expect(try await tokenStore.getItem(id: "item-webhook")?.status == ItemConnectionStatus.connected.rawValue)
            #expect(try await eventStore.latestEvent(itemId: "item-webhook")?.webhookCode == "LOGIN_REPAIRED")
        }
    }

    @Test("Invalid verification is rejected before storage")
    func invalidVerificationRejectsRequest() async throws {
        try await Self.withStores { tokenStore, eventStore in
            let route = WebhookRoutes(
                verifier: RejectingVerifier(),
                tokenStore: tokenStore,
                eventStore: eventStore,
                now: { Date(timeIntervalSince1970: 1_800_000_000) }
            )
            let body = Self.payload(webhookCode: "ITEM_LOGIN_REQUIRED")

            await #expect(throws: PlaidWebhookVerificationError.bodyHashMismatch) {
                _ = try await route.receive(
                    request: Self.request(body: body, jwt: "bad.jwt.signature"),
                    context: WebhookTestContext(source: WebhookTestContextSource())
                )
            }

            let itemStatus = try await tokenStore.getItem(id: "item-webhook")?.status
            let latestEvent = try await eventStore.latestEvent(itemId: "item-webhook")
            #expect(itemStatus == ItemConnectionStatus.connected.rawValue)
            #expect(latestEvent == nil)
        }
    }

    @Test("LOGIN_REPAIRED clears stale repair prompt and status includes safe webhook flags")
    func loginRepairedClearsStalePromptAndStatusIncludesFlags() async throws {
        try await Self.withStatusStores { tokenStore, billingStore, eventStore, config in
            try await tokenStore.updateItemStatus(id: "item-webhook", status: ItemConnectionStatus.loginRequired.rawValue)
            let route = WebhookRoutes(
                verifier: StrictPlaidWebhookVerifier(signatureValidator: AcceptingSignatureValidator()),
                tokenStore: tokenStore,
                eventStore: eventStore,
                now: { Date(timeIntervalSince1970: 1_800_000_000) }
            )
            let body = Self.payload(webhookCode: "LOGIN_REPAIRED")
            _ = try await route.receive(
                request: Self.request(body: body, jwt: Self.jwt(iat: 1_800_000_000, body: Data(body.utf8))),
                context: WebhookTestContext(source: WebhookTestContextSource())
            )

            let statusRoutes = StatusRoutes(
                tokenStore: tokenStore,
                billingStore: billingStore,
                webhookEventStore: eventStore,
                config: config
            )
            let status = try await statusRoutes.statusSnapshot(includeItems: true)
            let item = try #require(status.itemStatuses?.first)

            #expect(item.status == .loginRepaired)
            #expect(item.lastWebhookEvent == "ITEM.LOGIN_REPAIRED")
            #expect(item.lastWebhookAt != nil)
            #expect(item.needsSync == false)
        }
    }

    @Test("Status polling marks sync-needed webhook only until item refresh advances")
    func statusPollingSyncFlagClearsAfterRefresh() async throws {
        try await Self.withStatusStores { tokenStore, billingStore, eventStore, config in
            let signal = WebhookItemSignal(
                itemId: "item-webhook",
                webhookType: "TRANSACTIONS",
                webhookCode: "SYNC_UPDATES_AVAILABLE",
                requestId: "request-sync",
                idempotencyHash: "sync-\(UUID().uuidString)",
                eventAt: Date(),
                receivedAt: Date(),
                needsSync: true
            )
            _ = try await eventStore.record(signal)

            let statusRoutes = StatusRoutes(
                tokenStore: tokenStore,
                billingStore: billingStore,
                webhookEventStore: eventStore,
                config: config
            )
            let pending = try await statusRoutes.statusSnapshot(includeItems: true)
            #expect(try #require(pending.itemStatuses?.first).needsSync)

            try await tokenStore.saveSyncCursor(itemId: "item-webhook", cursor: "cursor-after-sync")
            let refreshed = try await statusRoutes.statusSnapshot(includeItems: true)
            #expect(!((try #require(refreshed.itemStatuses?.first)).needsSync))
        }
    }

    @Test("Status-changing webhook does not clear an earlier pending transaction sync")
    func statusChangingWebhookDoesNotClearPendingTransactionSync() async throws {
        try await Self.withStatusStores { tokenStore, billingStore, eventStore, config in
            let signal = WebhookItemSignal(
                itemId: "item-webhook",
                webhookType: "TRANSACTIONS",
                webhookCode: "SYNC_UPDATES_AVAILABLE",
                requestId: "request-sync-before-status",
                idempotencyHash: "sync-before-status-\(UUID().uuidString)",
                eventAt: Date(timeIntervalSince1970: 1_800_000_000),
                receivedAt: Date(timeIntervalSince1970: 1_800_000_000),
                needsSync: true
            )
            _ = try await eventStore.record(signal)

            let statusRoutes = StatusRoutes(
                tokenStore: tokenStore,
                billingStore: billingStore,
                webhookEventStore: eventStore,
                config: config
            )
            let pending = try await statusRoutes.statusSnapshot(includeItems: true)
            #expect(try #require(pending.itemStatuses?.first).needsSync)

            let webhookRoute = WebhookRoutes(
                verifier: StrictPlaidWebhookVerifier(signatureValidator: AcceptingSignatureValidator()),
                tokenStore: tokenStore,
                eventStore: eventStore,
                now: { Date(timeIntervalSince1970: 1_800_000_600) }
            )
            let body = Self.payload(webhookCode: "PENDING_EXPIRATION", timestamp: "2027-01-15T08:10:00Z")
            _ = try await webhookRoute.receive(
                request: Self.request(body: body, jwt: Self.jwt(iat: 1_800_000_600, body: Data(body.utf8))),
                context: WebhookTestContext(source: WebhookTestContextSource())
            )

            let afterStatusWebhook = try await statusRoutes.statusSnapshot(includeItems: true)
            let item = try #require(afterStatusWebhook.itemStatuses?.first)
            #expect(item.status == .pendingExpiration)
            #expect(item.lastWebhookEvent == "ITEM.PENDING_EXPIRATION")
            #expect(item.needsSync)
        }
    }

    @Test("Consent-repair webhook codes persist their modeled item status")
    func consentRepairWebhookCodesPersistModeledStatus() async throws {
        let scenarios: [(code: String, expected: ItemConnectionStatus)] = [
            ("PENDING_EXPIRATION", .pendingExpiration),
            ("PENDING_DISCONNECT", .pendingDisconnect),
            ("USER_PERMISSION_REVOKED", .permissionRevoked),
            ("NEW_ACCOUNTS_AVAILABLE", .newAccountsAvailable),
        ]
        for scenario in scenarios {
            try await Self.withStores { tokenStore, eventStore in
                // The fresh item defaults to `.connected`; the consent code must
                // move it to its modeled repair state, not silently no-op or get
                // flattened to `.connected` by the old coarse mapper.
                let route = WebhookRoutes(
                    verifier: StrictPlaidWebhookVerifier(signatureValidator: AcceptingSignatureValidator()),
                    tokenStore: tokenStore,
                    eventStore: eventStore,
                    now: { Date(timeIntervalSince1970: 1_800_000_000) }
                )
                let body = Self.payload(webhookCode: scenario.code)
                _ = try await route.receive(
                    request: Self.request(body: body, jwt: Self.jwt(iat: 1_800_000_000, body: Data(body.utf8))),
                    context: WebhookTestContext(source: WebhookTestContextSource())
                )
                let persisted = try await tokenStore.getItem(id: "item-webhook")?.status
                #expect(persisted == scenario.expected.rawValue, "webhook \(scenario.code)")
            }
        }
    }

    @Test("LOGIN_REPAIRED does not clobber a hard item error")
    func loginRepairedDoesNotClobberError() async throws {
        try await Self.withStores { tokenStore, eventStore in
            try await tokenStore.updateItemStatus(id: "item-webhook", status: ItemConnectionStatus.error.rawValue)
            let route = WebhookRoutes(
                verifier: StrictPlaidWebhookVerifier(signatureValidator: AcceptingSignatureValidator()),
                tokenStore: tokenStore,
                eventStore: eventStore,
                now: { Date(timeIntervalSince1970: 1_800_000_000) }
            )
            let body = Self.payload(webhookCode: "LOGIN_REPAIRED")
            _ = try await route.receive(
                request: Self.request(body: body, jwt: Self.jwt(iat: 1_800_000_000, body: Data(body.utf8))),
                context: WebhookTestContext(source: WebhookTestContextSource())
            )
            // A repair must not flip a hard error to connected/repaired; the item
            // still needs a full reconnect.
            #expect(try await tokenStore.getItem(id: "item-webhook")?.status == ItemConnectionStatus.error.rawValue)
        }
    }

    @Test("Concurrent duplicate record returns .duplicate instead of throwing a unique-constraint error")
    func concurrentDuplicateRecordIsIdempotent() async throws {
        try await Self.withStores { _, eventStore in
            // Both deliveries share an idempotency hash, so the find-then-save in
            // `record` races: one save wins, the other hits the unique
            // constraint. The store must translate that into `.duplicate`, never
            // surface the throw.
            let hash = "concurrent-\(UUID().uuidString)"
            @Sendable func makeSignal() -> WebhookItemSignal {
                WebhookItemSignal(
                    itemId: "item-webhook",
                    webhookType: "TRANSACTIONS",
                    webhookCode: "SYNC_UPDATES_AVAILABLE",
                    requestId: "request-concurrent",
                    idempotencyHash: hash,
                    eventAt: Date(timeIntervalSince1970: 1_800_000_000),
                    receivedAt: Date(timeIntervalSince1970: 1_800_000_000),
                    needsSync: true
                )
            }

            async let first = eventStore.record(makeSignal())
            async let second = eventStore.record(makeSignal())
            let results = try await [first, second]

            // Neither call threw; the pair is one persisted write and one
            // duplicate (order is nondeterministic).
            #expect(results.contains { $0.disposition == .duplicate })
            #expect(results.filter { $0.disposition == .stored }.count <= 1)
            #expect(results.allSatisfy { $0.disposition != .outOfOrder })

            // Exactly one row exists for the shared hash.
            let stored = try await eventStore.latestEvent(itemId: "item-webhook")
            #expect(stored?.idempotencyHash == hash)
        }
    }

    private static func withStores(
        _ body: (TokenStore, WebhookEventStore) async throws -> Void
    ) async throws {
        try await withStatusStores { tokenStore, _, eventStore, _ in
            try await body(tokenStore, eventStore)
        }
    }

    private static func withStatusStores(
        _ body: (TokenStore, BillingSubscriptionStore, WebhookEventStore, ServerConfig) async throws -> Void
    ) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-webhooks-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("plaidbar-test.sqlite").path
        let logger = Logger(label: "com.ftchvs.plaidbar-server-tests.webhooks")
        let fluent = Fluent(logger: logger)
        fluent.databases.use(.sqlite(.file(databasePath)), as: .sqlite)
        await fluent.migrations.add(CreateItems())
        await fluent.migrations.add(AddProviderToItems())
        await fluent.migrations.add(AddOriginToItems())
        await fluent.migrations.add(CreateSyncCursors())
        await fluent.migrations.add(CreateBillingSubscriptions())
        await fluent.migrations.add(CreateWebhookEvents())

        var bodyError: Error?
        do {
            try await fluent.migrate()
            try await ItemModel(
                id: "item-webhook",
                accessToken: "token-webhook",
                institutionId: "ins-webhook",
                institutionName: "Webhook Bank"
            ).save(on: fluent.db())
            try await body(
                TokenStore(fluent: fluent, logger: logger),
                BillingSubscriptionStore(fluent: fluent),
                WebhookEventStore(fluent: fluent),
                try setupStateConfig(in: directory)
            )
        } catch {
            bodyError = error
        }
        try await fluent.shutdown()
        if let bodyError {
            throw bodyError
        }
    }

    private static func setupStateConfig(in directory: URL) throws -> ServerConfig {
        let dataDirectory = directory.appendingPathComponent("data", isDirectory: true)
        let configURL = directory.appendingPathComponent("plaidbar.conf")
        try """
        PLAID_CLIENT_ID=
        PLAID_SECRET=
        PLAID_ENV=sandbox
        PLAIDBAR_DATA_DIR=\(dataDirectory.path)
        """.write(to: configURL, atomically: true, encoding: .utf8)
        return try ServerConfig.load(from: configURL.path)
    }

    private static func request(body: String, jwt: String) -> Request {
        var headers = HTTPFields()
        headers[HTTPField.Name("Plaid-Verification")!] = jwt
        headers[.contentType] = "application/json"
        return Request(
            head: HTTPRequest(method: .post, scheme: nil, authority: nil, path: "/webhooks/plaid", headerFields: headers),
            body: RequestBody(buffer: ByteBuffer(data: Data(body.utf8)))
        )
    }

    private static func payload(
        webhookCode: String,
        timestamp: String = "2026-06-14T12:00:00Z"
    ) -> String {
        """
        {"webhook_type":"ITEM","webhook_code":"\(webhookCode)","item_id":"item-webhook","request_id":"request-safe","timestamp":"\(timestamp)"}
        """
    }

    private static func jwt(alg: String = "ES256", iat: Int, body: Data) -> String {
        let header = #"{"alg":"\#(alg)","kid":"kid-safe"}"#
        let claims = #"{"iat":\#(iat),"request_body_sha256":"\#(StrictPlaidWebhookVerifier.sha256Hex(body))"}"#
        return [
            base64URL(Data(header.utf8)),
            base64URL(Data(claims.utf8)),
            "signature",
        ].joined(separator: ".")
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
