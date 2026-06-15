import Foundation
import FluentKit
import FluentSQLiteDriver
import Hummingbird
import HummingbirdFluent
import HTTPTypes
import Logging
import NIOCore
@testable import PlaidBarCore
@testable import PlaidBarServer
import Testing

/// Foundation tests for the consumer (Hosted Link) deployment seam. These prove
/// the seam is inert: `.local` is the default, the bridge holds no live
/// endpoints, and the entitlement middleware enforces nothing. They guard
/// against a future change accidentally flipping a user out of local mode or
/// gating BYO requests.
@Suite("Consumer foundation seam")
struct ConsumerFoundationTests {
    // MARK: - DeploymentMode

    @Test("Empty environment defaults to .local")
    func deploymentDefaultsToLocal() {
        #expect(DeploymentMode.resolved(from: [:]) == .local)
    }

    @Test("Unknown deployment value falls back to .local (fail-safe)")
    func deploymentUnknownFallsBackToLocal() {
        let env = [DeploymentMode.environmentVariable: "totally-bogus"]
        #expect(DeploymentMode.resolved(from: env) == .local)
    }

    @Test("Blank/whitespace deployment value falls back to .local")
    func deploymentBlankFallsBackToLocal() {
        let env = [DeploymentMode.environmentVariable: "   "]
        #expect(DeploymentMode.resolved(from: env) == .local)
    }

    @Test("Explicit values resolve to the named mode")
    func deploymentExplicitValues() {
        #expect(
            DeploymentMode.resolved(from: [DeploymentMode.environmentVariable: "local"]) == .local
        )
        #expect(
            DeploymentMode.resolved(
                from: [DeploymentMode.environmentVariable: "hosted-bridge"]
            ) == .hostedBridge
        )
    }

    // MARK: - RemoteBridgeConfig

    @Test("Bridge config is unconfigured and not provisioned by default")
    func bridgeDefaultsUnconfigured() {
        let bridge = RemoteBridgeConfig.resolved(from: [:])
        #expect(bridge == .unconfigured)
        #expect(bridge.isProvisioned == false)
        #expect(bridge.controlPlaneBaseURL == nil)
        #expect(bridge.dataPlaneProxyBaseURL == nil)
        #expect(bridge.entitlementPublicKeyBase64 == nil)
    }

    @Test("Bridge is provisioned only when both planes have URLs")
    func bridgeProvisionedRequiresBothPlanes() {
        let controlOnly = RemoteBridgeConfig.resolved(
            from: ["PLAIDBAR_BRIDGE_CONTROL_PLANE_URL": "https://example.test"]
        )
        #expect(controlOnly.isProvisioned == false)

        let both = RemoteBridgeConfig.resolved(from: [
            "PLAIDBAR_BRIDGE_CONTROL_PLANE_URL": "https://cp.example.test",
            "PLAIDBAR_BRIDGE_DATA_PLANE_URL": "https://dp.example.test"
        ])
        #expect(both.isProvisioned == true)
    }

    // MARK: - EntitlementMiddleware (enforces nothing)

    @Test("Entitlement evaluation always allows in .local mode")
    func entitlementAllowsLocal() {
        let decision = EntitlementMiddleware<TestRequestContext>.evaluate(
            deployment: .local,
            request: Self.makeRequest(path: "/api/accounts")
        )
        #expect(decision == .allow)
    }

    @Test("Entitlement evaluation allows even in .hostedBridge mode (inert)")
    func entitlementAllowsHostedBridge() {
        let decision = EntitlementMiddleware<TestRequestContext>.evaluate(
            deployment: .hostedBridge,
            request: Self.makeRequest(path: "/api/transactions/sync")
        )
        #expect(decision == .allow)
    }

    @Test("Entitlement middleware passes the request through unchanged")
    func entitlementMiddlewarePassesThrough() async throws {
        let middleware = EntitlementMiddleware<TestRequestContext>(deployment: .local)
        let request = Self.makeRequest(path: "/api/accounts")
        let context = TestRequestContext(source: TestRequestContextSource())

        let response = try await middleware.handle(request, context: context) { _, _ in
            Response(status: .ok)
        }
        #expect(response.status == .ok)
    }

    // MARK: - AccessTokenResolver seam

    @Test("Local deployment selects the Keychain-backed resolver")
    func resolverFactoryLocalIsTokenStoreBacked() async throws {
        try await withFluent { fluent in
            let tokenStore = TokenStore(fluent: fluent)
            let resolver = AccessTokenResolverFactory.make(
                deployment: .local,
                tokenStore: tokenStore
            )
            #expect(resolver is TokenStoreAccessTokenResolver)
        }
    }

    @Test("Hosted-bridge deployment selects the inert request-supplied stub")
    func resolverFactoryHostedBridgeIsStub() async throws {
        try await withFluent { fluent in
            let tokenStore = TokenStore(fluent: fluent)
            let resolver = AccessTokenResolverFactory.make(
                deployment: .hostedBridge,
                tokenStore: tokenStore
            )
            #expect(resolver is RequestSuppliedAccessTokenResolver)
        }
    }

    @Test("Request-supplied resolver stub fails closed (never weakens custody)")
    func requestSuppliedResolverFailsClosed() throws {
        let item = ItemModel(
            id: "item-foundation",
            accessToken: "keychain:item-foundation"
        )
        let resolver = RequestSuppliedAccessTokenResolver()
        #expect(throws: AccessTokenResolverError.self) {
            _ = try resolver.accessToken(
                for: item,
                request: Self.makeRequest(path: "/api/accounts")
            )
        }
    }

    // MARK: - Entitlement model

    @Test("Entitlement spare-capacity is pure arithmetic")
    func entitlementSpareCapacity() {
        let belowLimit = Entitlement(
            tier: .plus,
            institutionLimit: 8,
            itemsUsed: 3,
            subscriptionStatus: "active",
            expiresAt: nil
        )
        #expect(belowLimit.hasSpareCapacity == true)

        let atLimit = Entitlement(
            tier: .free,
            institutionLimit: 0,
            itemsUsed: 0,
            subscriptionStatus: "active",
            expiresAt: nil
        )
        #expect(atLimit.hasSpareCapacity == false)
    }

    @Test("Entitlement round-trips through Codable")
    func entitlementCodableRoundTrip() throws {
        let original = Entitlement(
            tier: .plus,
            institutionLimit: 8,
            itemsUsed: 2,
            subscriptionStatus: "active",
            expiresAt: Date(timeIntervalSince1970: 1_752_278_400)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Entitlement.self, from: data)
        #expect(decoded == original)
    }

    // MARK: - Billing lifecycle persistence

    @Test("Billing subscription status persists and can move through lifecycle states")
    func billingSubscriptionLifecyclePersists() async throws {
        try await withFluent { fluent in
            let store = BillingSubscriptionStore(fluent: fluent)

            #expect(try await store.currentSubscription() == nil)

            let trial = try await store.save(
                SaveBillingSubscriptionRequest(status: .trialing, plan: .free)
            )
            #expect(trial.status == .trialing)
            #expect(trial.plan == .free)

            let upgraded = try await store.save(
                SaveBillingSubscriptionRequest(status: .active, plan: .plus)
            )
            #expect(upgraded.status == .active)
            #expect(upgraded.plan == .plus)

            let failedPayment = try await store.save(
                SaveBillingSubscriptionRequest(status: .pastDue, plan: .plus)
            )
            #expect(failedPayment.status == .pastDue)

            let downgraded = try await store.save(
                SaveBillingSubscriptionRequest(status: .active, plan: .free)
            )
            #expect(downgraded.plan == .free)

            let canceled = try await store.save(
                SaveBillingSubscriptionRequest(status: .canceled, plan: .free)
            )
            #expect(canceled.status == .canceled)

            let expired = try await store.save(
                SaveBillingSubscriptionRequest(status: .expired, plan: .free)
            )
            #expect(expired.status == .expired)

            let reactivated = try await store.save(
                SaveBillingSubscriptionRequest(status: .active, plan: .free)
            )
            #expect(reactivated.status == .active)

            let loaded = try await store.currentSubscription()
            #expect(loaded?.status == .active)
            #expect(loaded?.plan == .free)
        }
    }

    @Test("Billing route receives normalized subscription status")
    func billingRouteReceivesSubscriptionStatus() async throws {
        try await withFluent { fluent in
            let store = BillingSubscriptionStore(fluent: fluent)
            let routes = BillingRoutes(billingStore: store)
            let context = TestRequestContext(source: TestRequestContextSource())
            let response = try await routes.saveSubscription(
                request: Self.makeJSONRequest(
                    method: .put,
                    path: "/api/billing/subscription",
                    body: SaveBillingSubscriptionRequest(status: .pastDue, plan: .plus)
                ),
                context: context
            )

            #expect(response.status == .ok)
            let loaded = try await store.currentSubscription()
            #expect(loaded?.status == .pastDue)
            #expect(loaded?.plan == .plus)
        }
    }

    @Test("Billing route accepts ISO-8601 trial and period-end dates from the app client")
    func billingRouteDecodesISO8601Dates() async throws {
        try await withFluent { fluent in
            let store = BillingSubscriptionStore(fluent: fluent)
            let routes = BillingRoutes(billingStore: store)
            let context = TestRequestContext(source: TestRequestContextSource())
            let trialEnd = Date(timeIntervalSince1970: 1_800_000_000)
            let periodEnd = Date(timeIntervalSince1970: 1_802_000_000)

            let response = try await routes.saveSubscription(
                request: Self.makeJSONRequest(
                    method: .put,
                    path: "/api/billing/subscription",
                    body: SaveBillingSubscriptionRequest(
                        status: .trialing,
                        plan: .plus,
                        currentPeriodEnd: periodEnd,
                        trialEndsAt: trialEnd
                    )
                ),
                context: context
            )

            #expect(response.status == .ok)
            let loaded = try await store.currentSubscription()
            #expect(loaded?.status == .trialing)
            #expect(loaded?.trialEndsAt == trialEnd)
            #expect(loaded?.currentPeriodEnd == periodEnd)
        }
    }

    // MARK: - Helpers

    private static func makeRequest(path: String) -> Request {
        Request(
            head: HTTPRequest(method: .get, scheme: nil, authority: nil, path: path),
            body: RequestBody(buffer: ByteBuffer())
        )
    }

    private static func makeJSONRequest(
        method: HTTPRequest.Method,
        path: String,
        body: some Encodable
    ) throws -> Request {
        // Mirror the real app client (ServerClient encodes with .iso8601), so
        // route tests exercise the same date wire format the server must accept.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(body)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Request(
            head: HTTPRequest(method: method, scheme: nil, authority: nil, path: path, headerFields: headers),
            body: RequestBody(buffer: ByteBuffer(data: data))
        )
    }

    /// In-memory SQLite Fluent for the resolver-factory type assertions. Always
    /// shuts Fluent down so the test holds no database handle.
    private func withFluent(_ body: (Fluent) async throws -> Void) async throws {
        let logger = Logger(label: "com.ftchvs.plaidbar-server-tests.consumer-foundation")
        let fluent = Fluent(logger: logger)
        fluent.databases.use(.sqlite(.memory), as: .sqlite)
        await fluent.migrations.add(CreateItems())
        await fluent.migrations.add(AddProviderToItems())
        await fluent.migrations.add(CreateSyncCursors())
        await fluent.migrations.add(CreateBillingSubscriptions())

        var bodyError: Error?
        do {
            try await fluent.migrate()
            try await body(fluent)
        } catch {
            bodyError = error
        }
        try await fluent.shutdown()
        if let bodyError {
            throw bodyError
        }
    }
}

// MARK: - Local request-context scaffolding

private struct TestRequestContextSource: RequestContextSource {
    let logger = Logger(label: "com.ftchvs.plaidbar-server-tests.consumer-foundation")
}

private struct TestRequestContext: RequestContext {
    typealias Source = TestRequestContextSource

    var coreContext: CoreRequestContextStorage

    init(source: TestRequestContextSource) {
        coreContext = CoreRequestContextStorage(source: source)
    }
}
