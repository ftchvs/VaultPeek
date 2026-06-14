import Foundation
import Hummingbird
import NIOCore
import PlaidBarCore

/// Entitlement enforcement seam for the consumer (Hosted Link) track.
///
/// FOUNDATION ONLY — **this middleware enforces nothing.** It is inserted into
/// the `/api` chain between `APITokenMiddleware` (authentication) and
/// `SetupStateMiddleware` (credential-readiness) so the gated managed-consumer
/// work has a fixed, reviewed place to add Stripe-backed entitlement checks
/// later, without re-threading the router.
///
/// Today it evaluates to `.allow` for every request and calls `next` unchanged,
/// so the request path is byte-for-byte identical to before it existed. In
/// `.local` (BYO-keys) mode it is wired but always allows; entitlements doc D3
/// keeps BYO fully ungated, so even when enforcement is built it must stay a
/// no-op in `.local` mode. There are **no Stripe calls, no token verification,
/// and no network access** here.
///
/// When the gated work lands, `evaluate` gains: parse the device-signed
/// entitlement, verify the embedded Ed25519 signature
/// (`RemoteBridgeConfig.entitlementPublicKeyBase64`), check TTL/grace, and map
/// managed-only routes to `.entitlementRequired` / `.limitReached`. The decision
/// type (`EntitlementDecision`) already models those outcomes.
struct EntitlementMiddleware<Context: RequestContext>: RouterMiddleware {
    let deployment: DeploymentMode

    func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        switch Self.evaluate(deployment: deployment, request: request) {
        case .allow:
            return try await next(request, context)
        case .entitlementRequired(let reason):
            // Unreachable today (`evaluate` only returns `.allow`). Wired so the
            // gated implementation has the correct response shape ready.
            return try Self.errorResponse(status: Self.paymentRequired, message: reason)
        case .limitReached(let reason):
            return try Self.errorResponse(status: Self.paymentRequired, message: reason)
        }
    }

    /// HTTP 402 — `swift-http-types` does not ship a named member for it, so the
    /// future `.entitlementRequired` / `.limitReached` paths construct it here.
    /// Matches the `402 limit_reached` response in `managed-link-architecture.md`.
    private static var paymentRequired: HTTPResponse.Status {
        HTTPResponse.Status(code: 402, reasonPhrase: "Payment Required")
    }

    /// Pure decision function — no I/O, fully testable. Always `.allow` today.
    /// `.local` mode short-circuits to `.allow` so BYO can never be gated even
    /// after enforcement is added (entitlements doc D3).
    static func evaluate(
        deployment: DeploymentMode,
        request: Request
    ) -> EntitlementDecision {
        switch deployment {
        case .local:
            return .allow
        case .hostedBridge:
            // FOUNDATION: the hosted path is not built. Allow unconditionally so
            // selecting `.hostedBridge` today changes no behavior. Real checks
            // are gated (consumer-production-checklist.md).
            return .allow
        }
    }

    /// Flat `{"error": ...}` body — the shape `ServerClient` extracts a
    /// user-facing message from (matches `SetupStateMiddleware`).
    private static func errorResponse(
        status: HTTPResponse.Status,
        message: String
    ) throws -> Response {
        let body = try JSONEncoder().encode(["error": message])
        return Response(
            status: status,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: ByteBuffer(data: body))
        )
    }
}
