import Foundation
import Hummingbird
import NIOCore
import PlaidBarCore

/// `/api/billing/*` — subscription lifecycle, Stripe-shaped session seams, and
/// the secret-free entitlement summary used by managed linking.
///
/// These endpoints receive/return normalized metadata only. They do not store
/// Stripe secrets, raw webhook payloads, payment-method details, invoices, Plaid
/// tokens, account identifiers, balances, or transactions.
struct BillingRoutes: Sendable {
    let billingStore: BillingSubscriptionStore
    let tokenStore: TokenStore?
    let deployment: DeploymentMode
    let webhookEvents: StripeBillingEventStore

    init(
        billingStore: BillingSubscriptionStore,
        tokenStore: TokenStore? = nil,
        deployment: DeploymentMode = .local,
        webhookEvents: StripeBillingEventStore = StripeBillingEventStore()
    ) {
        self.billingStore = billingStore
        self.tokenStore = tokenStore
        self.deployment = deployment
        self.webhookEvents = webhookEvents
    }

    func register(with group: RouterGroup<some RequestContext>) {
        let billing = group.group("billing")
        billing.get("subscription", use: getSubscription)
        billing.put("subscription", use: saveSubscription)
        billing.get("entitlement", use: getEntitlement)
        billing.post("checkout", use: createCheckoutSession)
        billing.post("portal", use: createPortalSession)
        billing.post("webhook", use: handleStripeWebhook)
    }

    @Sendable
    func getSubscription(request: Request, context: some RequestContext) async throws -> Response {
        let subscription = try await billingStore.currentSubscription()
        return try Self.jsonResponse(subscription)
    }

    @Sendable
    func saveSubscription(request: Request, context: some RequestContext) async throws -> Response {
        let body: SaveBillingSubscriptionRequest = try await Self.decodeBody(
            request,
            errorMessage: "Invalid billing subscription payload"
        )
        let subscription = try await billingStore.save(body)
        return try Self.jsonResponse(subscription)
    }

    @Sendable
    func getEntitlement(request: Request, context: some RequestContext) async throws -> Response {
        let summary = try await billingEntitlementSummary()
        return try Self.jsonResponse(summary)
    }

    @Sendable
    func createCheckoutSession(request: Request, context: some RequestContext) async throws -> Response {
        let body: BillingCheckoutSessionRequest = try await Self.decodeBody(
            request,
            errorMessage: "Invalid billing checkout payload"
        )
        guard body.plan != .free else {
            throw HTTPError(.badRequest, message: "Stripe Checkout is only available for paid managed plans")
        }
        let encodedPlan = body.plan.rawValue.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? body.plan.rawValue
        let encodedSuccess = body.successURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? body.successURL
        let encodedCancel = body.cancelURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? body.cancelURL
        return try Self.jsonResponse(BillingCheckoutSessionResponse(
            checkoutURL: "https://billing.stripe.local/checkout?plan=\(encodedPlan)&success_url=\(encodedSuccess)&cancel_url=\(encodedCancel)",
            plan: body.plan
        ))
    }

    @Sendable
    func createPortalSession(request: Request, context: some RequestContext) async throws -> Response {
        let body: BillingPortalSessionRequest = try await Self.decodeBody(
            request,
            errorMessage: "Invalid billing portal payload"
        )
        let encodedReturn = body.returnURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? body.returnURL
        return try Self.jsonResponse(BillingPortalSessionResponse(
            portalURL: "https://billing.stripe.local/portal?return_url=\(encodedReturn)"
        ))
    }

    @Sendable
    func handleStripeWebhook(request: Request, context: some RequestContext) async throws -> Response {
        let event: StripeBillingWebhookEvent = try await Self.decodeBody(
            request,
            errorMessage: "Invalid Stripe billing webhook payload"
        )
        let inserted = await webhookEvents.recordIfNew(event.id)
        if inserted {
            _ = try await billingStore.save(SaveBillingSubscriptionRequest(
                status: event.status,
                plan: event.plan,
                currentPeriodEnd: event.currentPeriodEnd,
                trialEndsAt: event.trialEndsAt
            ))
        }
        return try Self.jsonResponse(["status": inserted ? "processed" : "duplicate"])
    }

    private func billingEntitlementSummary() async throws -> BillingEntitlementSummary {
        let subscription = try await billingStore.currentSubscription()
        let managedSummary: ManagedLinkEntitlementSummary
        if let tokenStore {
            managedSummary = try await ManagedLinkEntitlementService(
                deployment: deployment,
                billingStore: billingStore,
                tokenStore: tokenStore
            ).summary()
        } else {
            managedSummary = ManagedLinkEntitlementService.summary(
                deployment: deployment,
                subscription: subscription,
                activeInstitutionCount: 0
            )
        }
        return BillingEntitlementSummary(
            plan: managedSummary.plan,
            status: managedSummary.status,
            institutionLimit: managedSummary.institutionLimit,
            activeInstitutionCount: managedSummary.activeInstitutionCount,
            trialEndsAt: subscription?.trialEndsAt,
            features: Self.allowedPremiumFeatures(subscription: subscription),
            managedLink: managedSummary
        )
    }

    private static func allowedPremiumFeatures(subscription: BillingSubscription?) -> [String] {
        guard let subscription, subscription.status.allowsPaidFeatures else { return [] }
        switch subscription.plan {
        case .free:
            return []
        case .plus:
            return ["managed_linking", "managed_institution_limit_8"]
        }
    }

    private static func decodeBody<T: Decodable>(_ request: Request, errorMessage: String) async throws -> T {
        let buffer = try await request.body.collect(upTo: Self.maxBodyBytes)
        let data = Data(buffer: buffer)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw HTTPError(.badRequest, message: errorMessage)
        }
    }

    /// Upper bound for the small JSON billing payload.
    private static let maxBodyBytes = 64 * 1024

    private static func jsonResponse(_ value: some Encodable) throws -> Response {
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

actor StripeBillingEventStore {
    private var processedEventIDs: Set<String> = []

    func recordIfNew(_ eventID: String) -> Bool {
        processedEventIDs.insert(eventID).inserted
    }
}
