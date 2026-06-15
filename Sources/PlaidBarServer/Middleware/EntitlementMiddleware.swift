import Foundation
import Hummingbird
import NIOCore
import PlaidBarCore

/// Store-free entitlement seam for the consumer (Hosted Link) track.
///
/// This middleware still enforces nothing directly: it evaluates to `.allow`
/// for every request and calls `next` unchanged. It stays in the `/api` chain
/// between `APITokenMiddleware` (authentication) and `SetupStateMiddleware`
/// (credential-readiness) so future request-signed entitlement checks have a
/// reviewed insertion point without re-threading the router.
///
/// AND-414's managed Link checks live in `LinkRoutes` instead of here because
/// they need `BillingSubscriptionStore` plus `TokenStore` counts. In `.local`
/// (BYO-keys) mode this middleware is wired but always allows; BYO/demo paths
/// remain ungated. There are **no Stripe calls, no token verification, and no
/// network access** here.
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
