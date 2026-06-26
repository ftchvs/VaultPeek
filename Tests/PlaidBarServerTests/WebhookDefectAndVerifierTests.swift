import CryptoKit
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

/// AND-634 (dormant ordering/state defect fixes) + AND-646 (gated real ES256
/// signature verifier). The three AND-634 cases are regressions: each fails on
/// the pre-fix code and passes after.
@Suite("Webhook ordering/state defects and gated verifier")
struct WebhookDefectAndVerifierTests {
    // MARK: - AND-634 #1: clock-mixing out-of-order key

    @Test("Out-of-order is decided only when both events carry an eventAt")
    func outOfOrderOnlyWhenBothHaveEventAt() async throws {
        try await Self.withStore { eventStore in
            // First delivery: NO eventAt, only receivedAt (far in the future).
            let first = Self.signal(
                hash: "h1",
                eventAt: nil,
                receivedAt: Date(timeIntervalSince1970: 2_000_000_000),
                code: "DEFAULT_UPDATE"
            )
            let firstResult = try await eventStore.record(first)
            #expect(firstResult.disposition == .stored)

            // Second delivery: HAS an eventAt that is *earlier* than the stored
            // receivedAt. The pre-fix code compared stored receivedAt
            // (2_000_000_000) against the new eventAt and spuriously flagged
            // out-of-order. With the fix, ordering is undecidable (the stored
            // event has no eventAt) so it is treated as in-order (.stored).
            let second = Self.signal(
                hash: "h2",
                eventAt: Date(timeIntervalSince1970: 1_000_000_000),
                receivedAt: Date(timeIntervalSince1970: 2_000_000_001),
                code: "DEFAULT_UPDATE"
            )
            let secondResult = try await eventStore.record(second)
            #expect(secondResult.disposition == .stored)
        }
    }

    @Test("Out-of-order still fires when both events carry an eventAt")
    func outOfOrderFiresWhenBothHaveEventAt() async throws {
        try await Self.withStore { eventStore in
            let newer = Self.signal(
                hash: "n1",
                eventAt: Date(timeIntervalSince1970: 1_000_000_200),
                receivedAt: Date(timeIntervalSince1970: 1_000_000_200),
                code: "DEFAULT_UPDATE"
            )
            _ = try await eventStore.record(newer)

            let older = Self.signal(
                hash: "n2",
                eventAt: Date(timeIntervalSince1970: 1_000_000_100),
                receivedAt: Date(timeIntervalSince1970: 1_000_000_300),
                code: "DEFAULT_UPDATE"
            )
            let result = try await eventStore.record(older)
            #expect(result.disposition == .outOfOrder)
        }
    }

    // MARK: - AND-634 #2: needsPollingSync masked by a later non-sync webhook

    @Test("A later non-sync webhook does not mask an earlier pending sync signal")
    func laterNonSyncDoesNotMaskPendingSync() async throws {
        try await Self.withStatusStores { tokenStore, billingStore, eventStore, config in
            // Both events are dated *after* the item's creation `updatedAt` so the
            // sync is genuinely pending (the item has not refreshed past it).
            let base = Date().addingTimeInterval(60)
            // Earlier: SYNC_UPDATES_AVAILABLE (needsSync) at T0.
            _ = try await eventStore.record(Self.signal(
                hash: "sync-1",
                eventAt: base,
                receivedAt: base,
                code: "SYNC_UPDATES_AVAILABLE"
            ))
            // Later: PENDING_EXPIRATION (NOT needsSync) at T1 > T0. Pre-fix this
            // collapsed the per-item state to the max-effectiveDate event and
            // hid the still-pending sync signal.
            _ = try await eventStore.record(Self.signal(
                hash: "pending-1",
                eventAt: base.addingTimeInterval(60),
                receivedAt: base.addingTimeInterval(60),
                code: "PENDING_EXPIRATION"
            ))

            let statusRoutes = StatusRoutes(
                tokenStore: tokenStore,
                billingStore: billingStore,
                webhookEventStore: eventStore,
                config: config
            )
            let status = try await statusRoutes.statusSnapshot(includeItems: true)
            let item = try #require(status.itemStatuses?.first)
            // Sync remains needed despite the later non-sync delivery.
            #expect(item.needsSync)
            // Display still reflects the latest-overall event.
            #expect(item.lastWebhookEvent == "ITEM.PENDING_EXPIRATION")
        }
    }

    @Test("Sticky sync signal clears once the committed cursor advances past it")
    func stickySyncClearsAfterCursorCommit() async throws {
        try await Self.withStatusStores { tokenStore, billingStore, eventStore, config in
            // Events dated "now" sit after the item's creation `updatedAt`, so the
            // sync is pending until a transaction-sync cursor commit advances past
            // them.
            let syncAt = Date()
            _ = try await eventStore.record(Self.signal(
                hash: "sync-2",
                eventAt: syncAt,
                receivedAt: syncAt,
                code: "SYNC_UPDATES_AVAILABLE"
            ))
            // A later non-sync delivery must not clear the still-pending sync.
            _ = try await eventStore.record(Self.signal(
                hash: "pending-2",
                eventAt: syncAt.addingTimeInterval(1),
                receivedAt: syncAt.addingTimeInterval(1),
                code: "PENDING_EXPIRATION"
            ))

            let statusRoutes = StatusRoutes(
                tokenStore: tokenStore,
                billingStore: billingStore,
                webhookEventStore: eventStore,
                config: config
            )
            #expect(try #require(try await statusRoutes.statusSnapshot(includeItems: true).itemStatuses?.first).needsSync)

            // A status-only write bumps `items.updated_at`, but per #685 the sync
            // signal is driven by the committed *cursor* time, not the item row —
            // so a non-sync status change alone must NOT clear a pending sync.
            try await tokenStore.updateItemStatus(id: "item-webhook", status: ItemConnectionStatus.connected.rawValue)
            #expect(try #require(try await statusRoutes.statusSnapshot(includeItems: true).itemStatuses?.first).needsSync)

            // Committing a transaction-sync cursor whose observation time is past
            // the sync event is what clears the sticky signal (the cursor-commit
            // boundary owns the clear, AND-667 / #685).
            try await tokenStore.saveSyncCursorIfItemExists(
                itemId: "item-webhook",
                cursor: "cursor-after-sync",
                updatedAt: syncAt.addingTimeInterval(2)
            )
            let refreshed = try await statusRoutes.statusSnapshot(includeItems: true)
            #expect(!(try #require(refreshed.itemStatuses?.first).needsSync))
        }
    }

    // MARK: - AND-634 #3: concurrent-delivery race serialized per item

    @Test("Concurrent distinct-hash deliveries for one item are serialized and both apply in order")
    func concurrentDistinctDeliveriesAreSerialized() async throws {
        try await Self.withStores { tokenStore, eventStore in
            try await tokenStore.updateItemStatus(id: "item-webhook", status: ItemConnectionStatus.connected.rawValue)
            let route = WebhookRoutes(
                verifier: Self.acceptingVerifier,
                tokenStore: tokenStore,
                eventStore: eventStore,
                now: { Date(timeIntervalSince1970: 1_800_000_000) }
            )
            // Two distinct webhooks (different codes -> different hashes) for the
            // SAME item, delivered concurrently. Pre-fix, both could resolve
            // .stored and interleave their status read-modify-writes. The
            // per-item lock serializes record+apply, so both are stored and the
            // store ends with exactly two rows for the item.
            let loginRequired = Self.payload(code: "ITEM_LOGIN_REQUIRED", timestamp: "2026-06-14T12:00:00Z")
            let pendingExpiration = Self.payload(code: "PENDING_EXPIRATION", timestamp: "2026-06-14T12:05:00Z")

            @Sendable func deliver(_ body: String) async throws {
                _ = try await route.receive(
                    request: Self.request(body: body, jwt: "header.payload.sig"),
                    context: WebhookDefectTestContext(source: WebhookDefectTestContextSource())
                )
            }

            async let a: Void = deliver(loginRequired)
            async let b: Void = deliver(pendingExpiration)
            _ = try await (a, b)

            // Both rows persisted (no lost write under the lock).
            let rows = try await eventStore.allEventCountForTest(itemId: "item-webhook")
            #expect(rows == 2)
            // Final status is a valid one of the two applied codes — never a
            // torn/interleaved value. (Both map deterministically off .connected.)
            let status = try await tokenStore.getItem(id: "item-webhook")?.status
            #expect(
                status == ItemConnectionStatus.loginRequired.rawValue
                    || status == ItemConnectionStatus.pendingExpiration.rawValue
            )
        }
    }

    @Test("Distinct items are not blocked by each other's lock")
    func distinctItemsDoNotBlock() async throws {
        try await Self.withStore { eventStore in
            // Two locks on different ids can be held concurrently without
            // deadlock; both bodies run and return.
            async let a = eventStore.withItemLock(itemId: "item-a") { "a" }
            async let b = eventStore.withItemLock(itemId: "item-b") { "b" }
            let results = await Set([a, b])
            #expect(results == ["a", "b"])
        }
    }

    // MARK: - AND-646: real ES256 signature verifier (synthetic keypair)

    @Test("ES256 validator accepts a correctly signed JWT and rejects tampering")
    func es256ValidatorAcceptsAndRejects() async throws {
        let privateKey = P256.Signing.PrivateKey()
        let kid = "test-kid"
        let keySource = StaticPlaidWebhookKeySource(keysByID: [kid: privateKey.publicKey])
        let validator = ES256PlaidWebhookSignatureValidator(keySource: keySource)

        let headerJSON = #"{"alg":"ES256","kid":"\#(kid)"}"#
        let claimsJSON = #"{"iat":1800000000,"request_body_sha256":"abc"}"#
        let signingInput = "\(Self.base64URL(Data(headerJSON.utf8))).\(Self.base64URL(Data(claimsJSON.utf8)))"
        let signature = try privateKey.signature(for: SHA256.hash(data: Data(signingInput.utf8)))
        let validJWT = "\(signingInput).\(Self.base64URL(signature.rawRepresentation))"

        let header = PlaidWebhookJWTHeader(alg: "ES256", kid: kid)
        let claims = PlaidWebhookJWTClaims(iat: 1_800_000_000, requestBodySHA256: "abc", bodySHA256: nil)

        // Correct signature passes.
        try await validator.validate(jwt: validJWT, header: header, claims: claims)

        // Tampered payload -> signature mismatch.
        let tamperedJWT = "\(Self.base64URL(Data(headerJSON.utf8))).\(Self.base64URL(Data(#"{"iat":1}"#.utf8))).\(Self.base64URL(signature.rawRepresentation))"
        await #expect(throws: PlaidWebhookSignatureError.signatureMismatch) {
            try await validator.validate(jwt: tamperedJWT, header: header, claims: claims)
        }

        // Unknown kid -> rejected before any crypto.
        let unknownHeader = PlaidWebhookJWTHeader(alg: "ES256", kid: "other-kid")
        await #expect(throws: PlaidWebhookSignatureError.unknownKeyID) {
            try await validator.validate(jwt: validJWT, header: unknownHeader, claims: claims)
        }

        // Missing kid -> rejected.
        let noKidHeader = PlaidWebhookJWTHeader(alg: "ES256", kid: nil)
        await #expect(throws: PlaidWebhookSignatureError.missingKeyID) {
            try await validator.validate(jwt: validJWT, header: noKidHeader, claims: claims)
        }
    }

    @Test("JWK round-trips to a usable P-256 public key")
    func jwkParsesToPublicKey() throws {
        let privateKey = P256.Signing.PrivateKey()
        let x963 = privateKey.publicKey.x963Representation
        // x963 layout: 0x04 || x(32) || y(32).
        let x = x963.subdata(in: 1..<33)
        let y = x963.subdata(in: 33..<65)
        let jwkJSON = """
        {"kty":"EC","crv":"P-256","x":"\(Self.base64URL(x))","y":"\(Self.base64URL(y))","kid":"k1"}
        """
        let jwk = try JSONDecoder().decode(PlaidWebhookJWK.self, from: Data(jwkJSON.utf8))
        let rebuilt = try jwk.publicKey()
        #expect(rebuilt.x963Representation == privateKey.publicKey.x963Representation)

        // Non-EC key type is rejected.
        let rsaJWK = PlaidWebhookJWK(kty: "RSA", crv: "P-256", x: "AA", y: "AA", kid: "k2")
        #expect(throws: PlaidWebhookSignatureError.unsupportedKeyType) {
            try rsaJWK.publicKey()
        }
    }

    @Test("StrictPlaidWebhookVerifier end-to-end with the real ES256 validator")
    func strictVerifierEndToEndWithES256() async throws {
        let privateKey = P256.Signing.PrivateKey()
        let kid = "e2e-kid"
        let keySource = StaticPlaidWebhookKeySource(keysByID: [kid: privateKey.publicKey])
        let verifier = StrictPlaidWebhookVerifier(
            signatureValidator: ES256PlaidWebhookSignatureValidator(keySource: keySource)
        )
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let body = Data(#"{"webhook_type":"ITEM","webhook_code":"LOGIN_REPAIRED","item_id":"x"}"#.utf8)
        let headerJSON = #"{"alg":"ES256","kid":"\#(kid)"}"#
        let claimsJSON = #"{"iat":1800000000,"request_body_sha256":"\#(StrictPlaidWebhookVerifier.sha256Hex(body))"}"#
        let signingInput = "\(Self.base64URL(Data(headerJSON.utf8))).\(Self.base64URL(Data(claimsJSON.utf8)))"
        let signature = try privateKey.signature(for: SHA256.hash(data: Data(signingInput.utf8)))
        let jwt = "\(signingInput).\(Self.base64URL(signature.rawRepresentation))"

        // Full structural + claims + body-hash + signature path passes.
        try await verifier.verify(jwt: jwt, body: body, now: now)

        // A signature made over a *different* body fails the body-hash gate
        // before crypto even runs.
        await #expect(throws: PlaidWebhookVerificationError.bodyHashMismatch) {
            try await verifier.verify(jwt: jwt, body: Data("{}".utf8), now: now)
        }
    }

    // MARK: - AND-646 gating: default config ships dormant

    @Test("Webhook verification config defaults to disabled and only opts in explicitly")
    func webhookVerificationConfigGating() throws {
        #expect(PlaidWebhookVerificationConfig.resolved(from: [:]) == .disabled)
        #expect(PlaidWebhookVerificationConfig.resolved(from: ["PLAIDBAR_WEBHOOK_VERIFICATION": ""]) == .disabled)
        #expect(PlaidWebhookVerificationConfig.resolved(from: ["PLAIDBAR_WEBHOOK_VERIFICATION": "nonsense"]) == .disabled)

        let enabled = PlaidWebhookVerificationConfig.resolved(from: ["PLAIDBAR_WEBHOOK_VERIFICATION": "on"])
        #expect(enabled.enabled)
        #expect(enabled.signingKeyJWKJSON == nil)

        let withKey = PlaidWebhookVerificationConfig.resolved(from: [
            "PLAIDBAR_WEBHOOK_VERIFICATION": "true",
            "PLAIDBAR_WEBHOOK_SIGNING_JWK": #"{"kty":"EC"}"#,
        ])
        #expect(withKey.enabled)
        #expect(withKey.signingKeyJWKJSON == #"{"kty":"EC"}"#)
    }

    @Test("Default-config verifier keeps the dormant unconfigured signature validator")
    func defaultVerifierStaysDormant() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-webhook-cfg-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configURL = directory.appendingPathComponent("plaidbar.conf")
        try """
        PLAID_CLIENT_ID=
        PLAID_SECRET=
        PLAID_ENV=sandbox
        PLAIDBAR_DATA_DIR=\(directory.appendingPathComponent("data").path)
        """.write(to: configURL, atomically: true, encoding: .utf8)
        let config = try ServerConfig.load(from: configURL.path)
        #expect(config.webhookVerification == .disabled)

        let logger = Logger(label: "test.webhook.gating")
        let verifier = PlaidBarServer.webhookVerifier(config: config, logger: logger)
        // The default-config verifier rejects with the unavailable signal,
        // proving the dormant `UnconfiguredPlaidWebhookSignatureValidator` is
        // still wired (receiver never activates).
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let body = Data(#"{"webhook_type":"ITEM","webhook_code":"LOGIN_REPAIRED","item_id":"x"}"#.utf8)
        let headerJSON = #"{"alg":"ES256","kid":"k"}"#
        let claimsJSON = #"{"iat":1800000000,"request_body_sha256":"\#(StrictPlaidWebhookVerifier.sha256Hex(body))"}"#
        let jwt = "\(Self.base64URL(Data(headerJSON.utf8))).\(Self.base64URL(Data(claimsJSON.utf8))).sig"
        await #expect(throws: PlaidWebhookVerificationError.signatureVerificationUnavailable) {
            try await verifier.verify(jwt: jwt, body: body, now: now)
        }
    }

    // MARK: - Helpers

    private static let acceptingVerifier = NoopDefectVerifier()

    private static func signal(
        hash: String,
        eventAt: Date?,
        receivedAt: Date,
        code: String,
        itemId: String = "item-webhook"
    ) -> WebhookItemSignal {
        WebhookItemSignal(
            itemId: itemId,
            webhookType: "ITEM",
            webhookCode: code,
            requestId: "req-\(hash)",
            idempotencyHash: hash,
            eventAt: eventAt,
            receivedAt: receivedAt,
            needsSync: PlaidWebhookEvent.needsSync(webhookCode: code)
        )
    }

    private static func payload(code: String, timestamp: String) -> String {
        """
        {"webhook_type":"ITEM","webhook_code":"\(code)","item_id":"item-webhook","request_id":"request-safe","timestamp":"\(timestamp)"}
        """
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

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func withStore(
        _ body: (WebhookEventStore) async throws -> Void
    ) async throws {
        try await withStores { _, eventStore in
            try await body(eventStore)
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
            .appendingPathComponent("plaidbar-webhook-defect-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("plaidbar-test.sqlite").path
        let logger = Logger(label: "com.ftchvs.plaidbar-server-tests.webhook-defects")
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
}

/// Bypasses all JWT verification so the concurrency test exercises only the
/// record-and-apply path under the per-item lock.
private struct NoopDefectVerifier: PlaidWebhookVerifier {
    func verify(jwt: String, body: Data, now: Date) async throws {}
}

private struct WebhookDefectTestContextSource: RequestContextSource {
    let logger = Logger(label: "com.ftchvs.plaidbar-server-tests.webhook-defects")
}

private struct WebhookDefectTestContext: RequestContext {
    typealias Source = WebhookDefectTestContextSource

    var coreContext: CoreRequestContextStorage

    init(source: WebhookDefectTestContextSource) {
        coreContext = CoreRequestContextStorage(source: source)
    }
}
