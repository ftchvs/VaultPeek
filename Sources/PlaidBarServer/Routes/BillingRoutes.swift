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
        // The app client encodes billing dates with `.iso8601`
        // (ServerClient.encoder), but Hummingbird's default request decoder
        // expects numeric `Date`s, so a non-nil trial/period-end date would fail
        // to decode. Decode the raw body with a matching ISO-8601 decoder.
        let buffer = try await request.body.collect(upTo: Self.maxBodyBytes)
        let data = Data(buffer: buffer)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let body: SaveBillingSubscriptionRequest
        do {
            body = try decoder.decode(SaveBillingSubscriptionRequest.self, from: data)
        } catch {
            throw HTTPError(.badRequest, message: "Invalid billing subscription payload")
        }
        let subscription = try await billingStore.save(body)
        return try Self.jsonResponse(subscription)
    }

    /// Upper bound for the small JSON billing payload.
    private static let maxBodyBytes = 64 * 1024

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
