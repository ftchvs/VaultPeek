import CryptoKit
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

private let consumerTestsKeychainAvailable: Bool = {
    let itemId = "consumer_keychain_probe_\(UUID().uuidString)"
    do {
        let storedToken = try PlaidTokenVault.store(accessToken: "probe-token", itemId: itemId)
        try PlaidTokenVault.delete(storedToken: storedToken, fallbackItemId: itemId)
        return true
    } catch {
        return false
    }
}()

/// Accepting verifier for tests that exercise webhook *application* logic; the
/// fail-closed default is asserted separately.
private struct AcceptingStripeWebhookVerifier: StripeWebhookVerifier {
    func verify(payload: Data, signatureHeader: String?, now: Date) async throws {}
}

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

    // MARK: - Managed Link Broker

    @Test("Allowed managed link session returns only hosted URL and entitlement summary")
    func allowedManagedLinkSessionOmitsProviderSecrets() async throws {
        try await withFluent { fluent in
            let tokenStore = TokenStore(fluent: fluent)
            let billingStore = BillingSubscriptionStore(fluent: fluent)
            _ = try await billingStore.save(SaveBillingSubscriptionRequest(status: .active, plan: .plus))
            let plaidClient = ManagedLinkStubPlaidClient()
            let routes = LinkRoutes(
                plaidClient: plaidClient,
                tokenStore: tokenStore,
                pendingLinkSessions: PendingLinkSessionStore(),
                billingStore: billingStore,
                config: try Self.hostedBridgeConfig()
            )

            let response = try await routes.createManagedLinkSession(
                request: Self.makeRequest(path: "/api/link/managed/create"),
                context: TestRequestContext(source: TestRequestContextSource())
            )
            let body = try await Self.responseString(response)
            let decoded = try JSONDecoder().decode(ManagedLinkSessionResponse.self, from: Data(body.utf8))
            let calls = await plaidClient.recordedCreateCompletionRedirectURIs()

            #expect(response.status == .ok)
            #expect(decoded.linkUrl == "https://link.example.test/session")
            #expect(decoded.entitlement.plan == .plus)
            #expect(decoded.entitlement.status == .active)
            #expect(decoded.entitlement.institutionLimit == 8)
            #expect(decoded.entitlement.activeInstitutionCount == 0)
            #expect(decoded.entitlement.canCreateManagedLink)
            #expect(calls.count == 1)
            #expect(calls.first?.contains("/oauth/callback?state=") == true)
            #expect(!body.contains("linkToken"))
            #expect(!body.contains("link-token-server-only"))
            #expect(!body.localizedCaseInsensitiveContains("secret"))
            #expect(!body.localizedCaseInsensitiveContains("access"))
            #expect(!body.localizedCaseInsensitiveContains("public"))
        }
    }

    @Test(".local mode always blocks managed link creation regardless of plan or subscription")
    func localModeAlwaysBlocksManagedLinkCreation() {
        // The entire safety case for shipping this gated broker in the default
        // local-first beta rests on `.local` NEVER allowing a managed link. Lock it
        // as a pure-function invariant: even a fully-paid, active Plus subscription
        // with spare capacity is blocked with `.managedBridgeUnavailable` (the
        // route at LinkRoutes gates on exactly this `canCreateManagedLink`).
        let updatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let subscriptions: [BillingSubscription?] = [
            nil,
            BillingSubscription(status: .active, plan: .plus, updatedAt: updatedAt),
            BillingSubscription(status: .trialing, plan: .plus, updatedAt: updatedAt),
        ]
        for subscription in subscriptions {
            let summary = ManagedLinkEntitlementService.summary(
                deployment: .local,
                subscription: subscription,
                activeInstitutionCount: 0
            )
            #expect(summary.canCreateManagedLink == false)
            #expect(summary.blockReason == .managedBridgeUnavailable)
        }
    }

    @Test("Over-limit managed link creation is blocked before Plaid is called")
    func overLimitManagedLinkIsBlocked() async throws {
        try await withFluent { fluent in
            let tokenStore = TokenStore(fluent: fluent)
            let billingStore = BillingSubscriptionStore(fluent: fluent)
            _ = try await billingStore.save(SaveBillingSubscriptionRequest(status: .active, plan: .plus))
            for index in 0 ..< SubscriptionPlan.plus.institutionLimit {
                try await ItemModel(
                    id: "managed-item-\(index)",
                    accessToken: "keychain:managed-item-\(index)",
                    institutionId: "ins_managed_\(index)",
                    origin: .managed
                ).save(on: fluent.db())
            }
            let plaidClient = ManagedLinkStubPlaidClient()
            let routes = LinkRoutes(
                plaidClient: plaidClient,
                tokenStore: tokenStore,
                pendingLinkSessions: PendingLinkSessionStore(),
                billingStore: billingStore,
                config: try Self.hostedBridgeConfig()
            )

            let response = try await routes.createManagedLinkSession(
                request: Self.makeRequest(path: "/api/link/managed/create"),
                context: TestRequestContext(source: TestRequestContextSource())
            )
            let body = try await Self.responseString(response)
            let decoded = try JSONDecoder().decode(ManagedLinkErrorResponse.self, from: Data(body.utf8))
            let calls = await plaidClient.recordedCreateCompletionRedirectURIs()

            #expect(response.status == ManagedLinkEntitlementService.paymentRequired)
            #expect(decoded.entitlement.blockReason == .institutionLimitReached)
            #expect(decoded.entitlement.activeInstitutionCount == 8)
            #expect(decoded.entitlement.canCreateManagedLink == false)
            #expect(decoded.error.contains("limit"))
            #expect(calls.isEmpty)
            #expect(!body.contains("link-token-server-only"))
            #expect(!body.localizedCaseInsensitiveContains("secret"))
        }
    }

    @Test("Disconnect removes managed item from active entitlement count without counting BYO")
    func disconnectUpdatesManagedInstitutionCount() async throws {
        try await withFluent { fluent in
            let tokenStore = TokenStore(fluent: fluent)
            let billingStore = BillingSubscriptionStore(fluent: fluent)
            _ = try await billingStore.save(SaveBillingSubscriptionRequest(status: .active, plan: .plus))
            try await ItemModel(
                id: "managed-item-disconnect",
                accessToken: "keychain:managed-item-disconnect",
                institutionId: "ins_managed_disconnect",
                origin: .managed
            ).save(on: fluent.db())
            try await ItemModel(
                id: "byo-item-ignored",
                accessToken: "keychain:byo-item-ignored",
                institutionId: "ins_byo_ignored",
                origin: .bringYourOwn
            ).save(on: fluent.db())
            let service = ManagedLinkEntitlementService(
                deployment: .hostedBridge,
                billingStore: billingStore,
                tokenStore: tokenStore
            )

            let before = try await service.summary()
            try await tokenStore.deleteItem(id: "managed-item-disconnect")
            let after = try await service.summary()

            #expect(before.activeInstitutionCount == 1)
            #expect(before.canCreateManagedLink)
            #expect(after.activeInstitutionCount == 0)
            #expect(after.canCreateManagedLink)
            #expect(try await tokenStore.getItem(id: "byo-item-ignored") != nil)
        }
    }

    @Test("Degraded entitlement blocks managed link creation without deleting local data")
    func degradedEntitlementBlocksManagedLinkCreation() async throws {
        try await withFluent { fluent in
            let tokenStore = TokenStore(fluent: fluent)
            let billingStore = BillingSubscriptionStore(fluent: fluent)
            _ = try await billingStore.save(SaveBillingSubscriptionRequest(status: .pastDue, plan: .plus))
            try await ItemModel(
                id: "managed-item-kept",
                accessToken: "keychain:managed-item-kept",
                institutionId: "ins_managed_kept",
                origin: .managed
            ).save(on: fluent.db())
            let plaidClient = ManagedLinkStubPlaidClient()
            let routes = LinkRoutes(
                plaidClient: plaidClient,
                tokenStore: tokenStore,
                pendingLinkSessions: PendingLinkSessionStore(),
                billingStore: billingStore,
                config: try Self.hostedBridgeConfig()
            )

            let response = try await routes.createManagedLinkSession(
                request: Self.makeRequest(path: "/api/link/managed/create"),
                context: TestRequestContext(source: TestRequestContextSource())
            )
            let body = try await Self.responseString(response)
            let decoded = try JSONDecoder().decode(ManagedLinkErrorResponse.self, from: Data(body.utf8))
            let calls = await plaidClient.recordedCreateCompletionRedirectURIs()

            #expect(response.status == ManagedLinkEntitlementService.paymentRequired)
            #expect(decoded.entitlement.blockReason == .subscriptionDegraded)
            #expect(decoded.entitlement.status == .pastDue)
            #expect(decoded.entitlement.activeInstitutionCount == 1)
            #expect(calls.isEmpty)
            #expect(try await tokenStore.getItem(id: "managed-item-kept") != nil)
        }
    }

    @Test("Managed OAuth callback enforces limit before public-token exchange")
    func managedCallbackBlocksWhenLimitReachedBeforeExchange() async throws {
        try await withFluent { fluent in
            let tokenStore = TokenStore(fluent: fluent)
            let billingStore = BillingSubscriptionStore(fluent: fluent)
            _ = try await billingStore.save(SaveBillingSubscriptionRequest(status: .active, plan: .plus))
            for index in 0 ..< SubscriptionPlan.plus.institutionLimit {
                try await ItemModel(
                    id: "managed-callback-item-\(index)",
                    accessToken: "keychain:managed-callback-item-\(index)",
                    institutionId: "ins_managed_callback_\(index)",
                    origin: .managed
                ).save(on: fluent.db())
            }
            let linkToken = "managed-callback-link-token"
            let plaidClient = ManagedLinkStubPlaidClient(
                linkTokenGetResponse: PlaidLinkTokenGetResponse(
                    linkToken: linkToken,
                    linkSessions: [
                        PlaidLinkSession(
                            linkSessionId: "managed-callback-session",
                            results: PlaidLinkResults(
                                itemAddResults: [
                                    PlaidLinkItemAddResult(
                                        publicToken: "managed-callback-public-token",
                                        institution: PlaidLinkInstitution(
                                            name: "Example Bank",
                                            institutionId: "ins_new_blocked"
                                        )
                                    ),
                                ]
                            )
                        ),
                    ],
                    onSuccess: nil,
                    results: nil
                )
            )
            let pendingLinkSessions = PendingLinkSessionStore()
            let state = await pendingLinkSessions.issueState()
            await pendingLinkSessions.save(
                state: state,
                linkToken: linkToken,
                origin: .managed
            )
            let route = OAuthCallbackRoute(
                plaidClient: plaidClient,
                tokenStore: tokenStore,
                pendingLinkSessions: pendingLinkSessions,
                entitlementService: ManagedLinkEntitlementService(
                    deployment: .hostedBridge,
                    billingStore: billingStore,
                    tokenStore: tokenStore
                )
            )

            let response = try await route.handleCallback(
                request: Self.makeRequest(path: "/oauth/callback?state=\(state)"),
                context: TestRequestContext(source: TestRequestContextSource())
            )
            let body = try await Self.responseString(response)
            let calls = await plaidClient.recordedCalls()

            #expect(response.status == .internalServerError)
            #expect(body.contains("institution limit"))
            #expect(calls.linkTokens == [linkToken])
            #expect(calls.publicTokens.isEmpty)
            #expect(try await tokenStore.activeInstitutionCount(origin: .managed) == 8)
        }
    }

    // MARK: - Stripe Entitlements

    @Test("Checkout and portal endpoints return Stripe-shaped session URLs without secrets")
    func checkoutAndPortalSessionEndpointsAreSecretFree() async throws {
        try await withFluent { fluent in
            let billingStore = BillingSubscriptionStore(fluent: fluent)
            let routes = BillingRoutes(billingStore: billingStore)
            let checkout = try await routes.createCheckoutSession(
                request: try Self.makeJSONRequest(
                    method: .post,
                    path: "/api/billing/checkout",
                    body: BillingCheckoutSessionRequest(
                        plan: .plus,
                        successURL: "vaultpeek://billing/success",
                        cancelURL: "vaultpeek://billing/cancel"
                    )
                ),
                context: TestRequestContext(source: TestRequestContextSource())
            )
            let portal = try await routes.createPortalSession(
                request: try Self.makeJSONRequest(
                    method: .post,
                    path: "/api/billing/portal",
                    body: BillingPortalSessionRequest(returnURL: "vaultpeek://billing/return")
                ),
                context: TestRequestContext(source: TestRequestContextSource())
            )
            let checkoutBody = try await Self.responseString(checkout)
            let portalBody = try await Self.responseString(portal)
            let decodedCheckout = try JSONDecoder().decode(BillingCheckoutSessionResponse.self, from: Data(checkoutBody.utf8))
            let decodedPortal = try JSONDecoder().decode(BillingPortalSessionResponse.self, from: Data(portalBody.utf8))

            #expect(checkout.status == .ok)
            #expect(decodedCheckout.plan == .plus)
            #expect(decodedCheckout.checkoutURL.contains("billing.stripe.local/checkout"))
            #expect(decodedPortal.portalURL.contains("billing.stripe.local/portal"))
            #expect(!checkoutBody.localizedCaseInsensitiveContains("secret"))
            #expect(!portalBody.localizedCaseInsensitiveContains("secret"))
        }
    }

    @Test("Stripe webhook metadata updates billing and entitlement summary")
    func stripeWebhookUpdatesBillingEntitlementSummary() async throws {
        try await withFluent { fluent in
            let tokenStore = TokenStore(fluent: fluent)
            let billingStore = BillingSubscriptionStore(fluent: fluent)
            let routes = BillingRoutes(
                billingStore: billingStore,
                tokenStore: tokenStore,
                deployment: .hostedBridge,
                verifier: AcceptingStripeWebhookVerifier()
            )
            let trialEnd = Date(timeIntervalSince1970: 1_800_000_000)
            let webhook = StripeBillingWebhookEvent(
                id: "evt_test_subscription_updated",
                type: "customer.subscription.updated",
                status: .trialing,
                plan: .plus,
                trialEndsAt: trialEnd
            )

            let first = try await routes.handleStripeWebhook(
                request: try Self.makeJSONRequest(method: .post, path: "/api/billing/webhook", body: webhook),
                context: TestRequestContext(source: TestRequestContextSource())
            )
            let duplicate = try await routes.handleStripeWebhook(
                request: try Self.makeJSONRequest(method: .post, path: "/api/billing/webhook", body: webhook),
                context: TestRequestContext(source: TestRequestContextSource())
            )
            let entitlement = try await routes.getEntitlement(
                request: Self.makeRequest(path: "/api/billing/entitlement"),
                context: TestRequestContext(source: TestRequestContextSource())
            )
            let entitlementBody = try await Self.responseString(entitlement)
            let entitlementDecoder = JSONDecoder()
            entitlementDecoder.dateDecodingStrategy = .iso8601
            let decoded = try entitlementDecoder.decode(BillingEntitlementSummary.self, from: Data(entitlementBody.utf8))

            #expect(first.status == .ok)
            #expect(try await Self.responseString(duplicate).contains("duplicate"))
            #expect(decoded.plan == .plus)
            #expect(decoded.status == .trialing)
            #expect(decoded.institutionLimit == 8)
            #expect(decoded.activeInstitutionCount == 0)
            #expect(decoded.trialEndsAt == trialEnd)
            #expect(decoded.features.contains("managed_linking"))
            #expect(decoded.managedLink.canCreateManagedLink)
            #expect(!entitlementBody.localizedCaseInsensitiveContains("secret"))
        }
    }

    @Test("Canceled Stripe entitlement blocks future managed linking without deleting data")
    func canceledStripeEntitlementBlocksManagedLinking() async throws {
        try await withFluent { fluent in
            let tokenStore = TokenStore(fluent: fluent)
            let billingStore = BillingSubscriptionStore(fluent: fluent)
            let routes = BillingRoutes(
                billingStore: billingStore,
                tokenStore: tokenStore,
                deployment: .hostedBridge,
                verifier: AcceptingStripeWebhookVerifier()
            )
            try await ItemModel(
                id: "managed-kept-after-cancel",
                accessToken: "keychain:managed-kept-after-cancel",
                institutionId: "ins_cancel_kept",
                origin: .managed
            ).save(on: fluent.db())
            _ = try await routes.handleStripeWebhook(
                request: try Self.makeJSONRequest(
                    method: .post,
                    path: "/api/billing/webhook",
                    body: StripeBillingWebhookEvent(
                        id: "evt_test_subscription_deleted",
                        type: "customer.subscription.deleted",
                        status: .canceled,
                        plan: .plus
                    )
                ),
                context: TestRequestContext(source: TestRequestContextSource())
            )

            let entitlement = try await routes.getEntitlement(
                request: Self.makeRequest(path: "/api/billing/entitlement"),
                context: TestRequestContext(source: TestRequestContextSource())
            )
            let decoded = try JSONDecoder().decode(
                BillingEntitlementSummary.self,
                from: Data(try await Self.responseString(entitlement).utf8)
            )

            #expect(decoded.managedLink.canCreateManagedLink == false)
            #expect(decoded.managedLink.blockReason == .subscriptionDegraded)
            #expect(decoded.features.isEmpty)
            #expect(try await tokenStore.getItem(id: "managed-kept-after-cancel") != nil)
        }
    }

    @Test("Stripe webhook fails closed by default: an unverified event mutates no billing state")
    func stripeWebhookFailsClosedByDefault() async throws {
        try await withFluent { fluent in
            let billingStore = BillingSubscriptionStore(fluent: fluent)
            // Default verifier is UnconfiguredStripeWebhookVerifier (fail-closed).
            let routes = BillingRoutes(billingStore: billingStore, deployment: .hostedBridge)
            await #expect(throws: StripeWebhookVerificationError.signatureVerificationUnavailable) {
                _ = try await routes.handleStripeWebhook(
                    request: try Self.makeJSONRequest(
                        method: .post,
                        path: "/api/billing/webhook",
                        body: StripeBillingWebhookEvent(
                            id: "evt_forged_active",
                            type: "customer.subscription.updated",
                            status: .active,
                            plan: .plus
                        )
                    ),
                    context: TestRequestContext(source: TestRequestContextSource())
                )
            }
            // A forged event granted nothing.
            let granted = try await billingStore.currentSubscription()
            #expect(granted == nil)
        }
    }

    @Test("Unconfigured Stripe verifier rejects every event")
    func unconfiguredStripeVerifierRejects() async {
        await #expect(throws: StripeWebhookVerificationError.signatureVerificationUnavailable) {
            try await UnconfiguredStripeWebhookVerifier().verify(
                payload: Data("{}".utf8),
                signatureHeader: "t=1,v1=abc",
                now: Date(timeIntervalSince1970: 1)
            )
        }
    }

    @Test("HMAC Stripe verifier accepts a correctly signed payload and rejects tampering")
    func hmacStripeVerifierAcceptsValidRejectsInvalid() async throws {
        let secret = "whsec_test_secret"
        let verifier = StripeSignatureWebhookVerifier(signingSecret: secret)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let payload = Data(#"{"id":"evt_1","type":"customer.subscription.updated"}"#.utf8)
        let timestamp = String(Int(now.timeIntervalSince1970))
        var signed = Data(timestamp.utf8)
        signed.append(0x2e)
        signed.append(payload)
        let mac = HMAC<SHA256>.authenticationCode(for: signed, using: SymmetricKey(data: Data(secret.utf8)))
        let signature = mac.map { String(format: "%02x", $0) }.joined()

        // Correctly signed payload passes.
        try await verifier.verify(payload: payload, signatureHeader: "t=\(timestamp),v1=\(signature)", now: now)
        // Wrong signature rejected.
        await #expect(throws: StripeWebhookVerificationError.signatureMismatch) {
            try await verifier.verify(payload: payload, signatureHeader: "t=\(timestamp),v1=deadbeef", now: now)
        }
        // Missing header rejected.
        await #expect(throws: StripeWebhookVerificationError.missingSignatureHeader) {
            try await verifier.verify(payload: payload, signatureHeader: nil, now: now)
        }
        // Stale timestamp (replay) rejected.
        await #expect(throws: StripeWebhookVerificationError.timestampOutOfTolerance) {
            try await verifier.verify(
                payload: payload,
                signatureHeader: "t=\(timestamp),v1=\(signature)",
                now: now.addingTimeInterval(3600)
            )
        }
    }

    @Test(
        "Concurrent managed inserts never exceed the institution limit",
        .enabled(if: consumerTestsKeychainAvailable, "macOS Keychain accepts test writes")
    )
    func concurrentManagedInsertsRespectLimit() async throws {
        try await withFluent { fluent in
            let tokenStore = TokenStore(fluent: fluent)
            let limit = SubscriptionPlan.plus.institutionLimit
            // Seed limit-1 managed institutions, leaving exactly one open slot.
            for index in 0 ..< (limit - 1) {
                try await ItemModel(
                    id: "seed-managed-\(index)",
                    accessToken: "keychain:seed-managed-\(index)",
                    institutionId: "ins_seed_\(index)",
                    origin: .managed
                ).save(on: fluent.db())
            }
            // Drive `limit` concurrent inserts, each a distinct new institution. Only
            // one may win the last slot; without atomic enforcement they would all
            // observe count == limit-1 and overshoot.
            let successes = await withTaskGroup(of: Bool.self) { group -> Int in
                for index in 0 ..< limit {
                    group.addTask {
                        do {
                            try await tokenStore.saveManagedItemEnforcingLimit(
                                id: "race-item-\(index)",
                                accessToken: "race-access-\(index)",
                                institutionId: "ins_race_\(index)",
                                institutionName: "Race Bank \(index)",
                                institutionLimit: limit
                            )
                            return true
                        } catch {
                            return false
                        }
                    }
                }
                var count = 0
                for await stored in group where stored { count += 1 }
                return count
            }

            let finalCount = try await tokenStore.activeInstitutionCount(origin: .managed)
            #expect(successes == 1)
            #expect(finalCount == limit)
        }
    }

    @Test(
        "Concurrent managed same-institution inserts are allowed at the institution cap",
        .enabled(if: consumerTestsKeychainAvailable, "macOS Keychain accepts test writes")
    )
    func concurrentManagedSameInstitutionInsertsDoNotSpendExtraSlots() async throws {
        try await withFluent { fluent in
            let tokenStore = TokenStore(fluent: fluent)
            let limit = SubscriptionPlan.plus.institutionLimit
            // Seed limit-1 unique managed institutions, leaving one open slot.
            for index in 0 ..< (limit - 1) {
                try await ItemModel(
                    id: "same-seed-managed-\(index)",
                    accessToken: "keychain:same-seed-managed-\(index)",
                    institutionId: "ins_same_seed_\(index)",
                    origin: .managed
                ).save(on: fluent.db())
            }

            let sharedInstitutionId = "ins_shared_race"
            let successes = await withTaskGroup(of: Bool.self) { group -> Int in
                for index in 0 ..< 2 {
                    group.addTask {
                        do {
                            try await tokenStore.saveManagedItemEnforcingLimit(
                                id: "same-race-item-\(index)",
                                accessToken: "same-race-access-\(index)",
                                institutionId: sharedInstitutionId,
                                institutionName: "Shared Race Bank",
                                institutionLimit: limit
                            )
                            return true
                        } catch {
                            return false
                        }
                    }
                }
                var count = 0
                for await stored in group where stored { count += 1 }
                return count
            }

            let finalCount = try await tokenStore.activeInstitutionCount(origin: .managed)
            let storedItems = try await tokenStore.getAllItems(providerID: .plaid)
                .filter { $0.origin == ItemOrigin.managed.rawValue && $0.institutionId == sharedInstitutionId }
            #expect(successes == 2)
            #expect(finalCount == limit)
            #expect(storedItems.count == 2)
        }
    }

    // MARK: - Helpers

    private static func makeRequest(path: String) -> Request {
        Request(
            head: HTTPRequest(method: .get, scheme: nil, authority: nil, path: path),
            body: RequestBody(buffer: ByteBuffer())
        )
    }

    private static func responseString(_ response: Response) async throws -> String {
        let collector = ResponseBodyCollector()
        let writer = CollectingResponseBodyWriter(collector: collector)
        try await response.body.write(writer)
        var buffer = await collector.collectedBuffer()
        return buffer.readString(length: buffer.readableBytes) ?? ""
    }

    private static func hostedBridgeConfig() throws -> ServerConfig {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-managed-link-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configURL = directory.appendingPathComponent("server.conf")
        let dataDirectory = directory.appendingPathComponent("data", isDirectory: true)
        try """
        PLAID_CLIENT_ID=test-client-id
        PLAID_SECRET=test-secret-placeholder
        PLAID_ENV=sandbox
        PLAIDBAR_DEPLOYMENT=hosted-bridge
        PLAID_LINK_WEBHOOK_URL=https://vaultpeek.example.test/webhooks/plaid/hosted-link
        PLAIDBAR_OAUTH_REDIRECT_URI=https://link.vaultpeek.example.test/oauth/callback
        PLAIDBAR_DATA_DIR=\(dataDirectory.path)
        """.write(to: configURL, atomically: true, encoding: .utf8)
        return try ServerConfig.load(from: configURL.path)
    }

    private actor ResponseBodyCollector {
        private var buffer = ByteBuffer()

        func append(_ chunk: ByteBuffer) {
            var copy = chunk
            buffer.writeBuffer(&copy)
        }

        func collectedBuffer() -> ByteBuffer {
            buffer
        }
    }

    private struct CollectingResponseBodyWriter: ResponseBodyWriter {
        let collector: ResponseBodyCollector

        mutating func write(_ buffer: ByteBuffer) async throws {
            await collector.append(buffer)
        }

        consuming func finish(_ trailingHeaders: HTTPFields?) async throws {}
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
        await fluent.migrations.add(AddOriginToItems())
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

private actor ManagedLinkStubPlaidClient: PlaidClientProtocol {
    private let linkTokenGetResponse: PlaidLinkTokenGetResponse
    private var createCompletionRedirectURIs: [String] = []
    private var requestedLinkTokens: [String] = []
    private var exchangedPublicTokens: [String] = []

    init(
        linkTokenGetResponse: PlaidLinkTokenGetResponse = PlaidLinkTokenGetResponse(
            linkToken: nil,
            linkSessions: nil,
            onSuccess: nil,
            results: nil
        )
    ) {
        self.linkTokenGetResponse = linkTokenGetResponse
    }

    func createLinkToken(
        clientUserId _: String,
        completionRedirectUri: String
    ) async throws -> PlaidLinkTokenResponse {
        createCompletionRedirectURIs.append(completionRedirectUri)
        return PlaidLinkTokenResponse(
            linkToken: "link-token-server-only",
            expiration: nil,
            requestId: nil,
            hostedLinkUrl: "https://link.example.test/session"
        )
    }

    func createUpdateLinkToken(
        clientUserId _: String,
        accessToken _: String,
        completionRedirectUri _: String
    ) async throws -> PlaidLinkTokenResponse {
        throw PlaidError.invalidResponse
    }

    func getLinkToken(_ linkToken: String) async throws -> PlaidLinkTokenGetResponse {
        requestedLinkTokens.append(linkToken)
        return linkTokenGetResponse
    }

    func exchangePublicToken(_ publicToken: String) async throws -> PlaidTokenExchangeResponse {
        exchangedPublicTokens.append(publicToken)
        throw PlaidError.invalidResponse
    }

    func getAccounts(accessToken _: String) async throws -> PlaidAccountsResponse {
        throw PlaidError.invalidResponse
    }

    func getBalances(accessToken _: String) async throws -> PlaidAccountsResponse {
        throw PlaidError.invalidResponse
    }

    func syncTransactions(
        accessToken _: String,
        cursor _: String?
    ) async throws -> PlaidTransactionsSyncResponse {
        throw PlaidError.invalidResponse
    }

    func removeItem(accessToken _: String) async throws {
        throw PlaidError.invalidResponse
    }

    func recordedCreateCompletionRedirectURIs() -> [String] {
        createCompletionRedirectURIs
    }

    func recordedCalls() -> (linkTokens: [String], publicTokens: [String]) {
        (requestedLinkTokens, exchangedPublicTokens)
    }
}
