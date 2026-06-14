import Foundation
import Hummingbird
import NIOCore
import PlaidBarCore

/// `/api/billing/subscription` — local subscription lifecycle metadata.
///
/// This endpoint receives already-normalized lifecycle state. It does not talk
/// to Stripe, verify webhooks, or store provider secrets/payloads.
struct BillingRoutes: Sendable {
    let billingStore: BillingSubscriptionStore

    func register(with group: RouterGroup<some RequestContext>) {
        group.group("billing")
            .get("subscription", use: getSubscription)
            .put("subscription", use: saveSubscription)
    }

    @Sendable
    func getSubscription(request: Request, context: some RequestContext) async throws -> Response {
        let subscription = try await billingStore.currentSubscription()
        return try Self.jsonResponse(subscription)
    }

    @Sendable
    func saveSubscription(request: Request, context: some RequestContext) async throws -> Response {
        let body = try await request.decode(as: SaveBillingSubscriptionRequest.self, context: context)
        let subscription = try await billingStore.save(body)
        return try Self.jsonResponse(subscription)
    }

    private static func jsonResponse(_ value: (some Encodable)?) throws -> Response {
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
