import Foundation
import Hummingbird
import PlaidBarCore

/// Resolves the Plaid access token a read route needs for a given linked item.
///
/// FOUNDATION ONLY — a seam, not a behavior change. Today every route resolves
/// the token the same way: `TokenStore.accessToken(for:)` reads it from the
/// macOS Keychain (local custody). The consumer Hosted Link track needs a
/// second posture — the *device* holds the token and supplies it on the request,
/// while a stateless hosted proxy injects the org secret and never stores the
/// token (`docs/strategy/managed-link-architecture.md` §5.4, Variant 1 device
/// custody). This protocol is the single point both postures share so routes can
/// adopt it without caring which one is active.
///
/// `.local` mode uses `TokenStoreAccessTokenResolver`, which delegates verbatim
/// to today's code path — so wiring this in is behavior-preserving. The
/// request-supplied resolver is an inert stub: it is never constructed in
/// `.local` mode and throws `unsupportedInLocalMode` if reached, so it cannot
/// accidentally weaken local custody.
protocol AccessTokenResolver: Sendable {
    /// Resolve the access token for a stored item, given the inbound request
    /// (which a hosted-stateless resolver reads a device-supplied token from).
    /// Local custody ignores the request entirely.
    func accessToken(
        for item: ItemModel,
        request: Request
    ) throws -> String
}

/// Local-custody resolver: the only resolver wired today. Delegates straight to
/// `TokenStore.accessToken(for:)` (Keychain-backed), so routes that adopt the
/// seam behave exactly as they do now in `.local` mode.
struct TokenStoreAccessTokenResolver: AccessTokenResolver {
    let tokenStore: TokenStore

    func accessToken(for item: ItemModel, request: Request) throws -> String {
        // `request` is intentionally unused: local custody never trusts a
        // client-supplied token. The token lives in the Keychain.
        try tokenStore.accessToken(for: item)
    }
}

/// Hosted-stateless resolver STUB for the future `.hostedBridge` posture, where
/// the device holds the access token and supplies it per request and the hosted
/// blind proxy injects the org secret without ever persisting the token.
///
/// FOUNDATION ONLY. This is not wired anywhere and is never constructed in
/// `.local` mode. It documents the intended contract (read a verified,
/// item-bound device token off the request) and fails closed until the gated
/// bridge work lands — it must never silently fall back to an empty or
/// unverified token. The eventual implementation must verify the token is bound
/// to the named managed item before returning it (architecture doc §5.4
/// "Managed Item binding"); this stub does no such verification and therefore
/// refuses to run.
struct RequestSuppliedAccessTokenResolver: AccessTokenResolver {
    /// Header the device uses to supply its custodied access token in the future
    /// hosted-stateless posture. Defined now so the contract is documented in
    /// one place; nothing reads it yet.
    static let deviceTokenHeader = "X-VaultPeek-Device-Token"

    func accessToken(for item: ItemModel, request: Request) throws -> String {
        throw AccessTokenResolverError.unsupportedInLocalMode
    }
}

/// Selects the resolver for a deployment posture. Today this always returns the
/// local-custody resolver; `.hostedBridge` returns the inert stub. Centralizing
/// the choice here keeps route construction posture-agnostic and gives the gated
/// work one place to swap in the real device-token resolver.
enum AccessTokenResolverFactory {
    static func make(
        deployment: DeploymentMode,
        tokenStore: TokenStore
    ) -> any AccessTokenResolver {
        switch deployment {
        case .local:
            TokenStoreAccessTokenResolver(tokenStore: tokenStore)
        case .hostedBridge:
            // Inert today: `.hostedBridge` is foundation-only and the stub
            // fails closed. When the gated bridge lands, this returns the real
            // device-token resolver bound to `RemoteBridgeConfig`.
            RequestSuppliedAccessTokenResolver()
        }
    }
}

enum AccessTokenResolverError: Error, LocalizedError, Sendable {
    /// The request-supplied (hosted-stateless) resolver was reached, but that
    /// posture is not implemented. Foundation guard: never weaken local custody.
    case unsupportedInLocalMode

    var errorDescription: String? {
        switch self {
        case .unsupportedInLocalMode:
            "Request-supplied access token resolution is not available yet; "
                + "this build only supports local (Keychain) token custody."
        }
    }
}
