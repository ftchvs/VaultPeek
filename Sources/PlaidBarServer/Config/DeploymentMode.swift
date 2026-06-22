import Foundation

/// Where this `PlaidBarServer` process runs and which Plaid-credential posture
/// it uses.
///
/// FOUNDATION ONLY. This seam exists so the consumer (Hosted Link) track can be
/// built incrementally without forking the server. **`.local` is the default and
/// is byte-for-byte today's behavior**: the server holds the user's own Plaid
/// `client_id`/`secret` (BYO-keys) and proxies Plaid directly. `.hostedBridge`
/// is a placeholder for the future stateless bridge; nothing reads a live bridge
/// endpoint yet, and selecting it changes no runtime path until the gated work
/// lands.
///
/// Parsed from `PLAIDBAR_DEPLOYMENT` (env or `server.conf`). Unknown/blank
/// values fall back to `.local` so a malformed config can never silently flip a
/// user into a non-existent hosted path.
enum DeploymentMode: String, Sendable, Equatable, CaseIterable {
    /// Today's only real path: local-first, server holds the user's own Plaid
    /// credentials and talks to Plaid directly. The default.
    case local

    /// Future consumer path: end users supply no Plaid credentials; a hosted
    /// VaultPeek bridge mints link tokens and a stateless blind proxy injects the
    /// org secret. Access tokens + financial data stay on the device. Inert
    /// today — see `RemoteBridgeConfig` and the gated checklist.
    case hostedBridge = "hosted-bridge"

    static let environmentVariable = "PLAIDBAR_DEPLOYMENT"

    /// Resolve from a config/env dictionary. Defaults to `.local`; an
    /// unrecognized value also resolves to `.local` (fail-safe, never throws) so
    /// the existing BYO path can never be broken by a typo.
    static func resolved(from environment: [String: String]) -> DeploymentMode {
        guard let raw = environment[environmentVariable]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty,
            let mode = DeploymentMode(rawValue: raw)
        else {
            return .local
        }
        return mode
    }
}

/// Placeholder configuration for the future hosted VaultPeek bridge.
///
/// FOUNDATION ONLY. Holds **no** live endpoints, secrets, or keys. It records
/// the *shape* of what `.hostedBridge` mode will eventually need — a control-plane
/// base URL (link/exchange/remove + entitlement), a blind-proxy base URL
/// (data-plane relay), and the base64 Ed25519 public key the server verifies
/// signed entitlements against. Every field is optional and defaults to `nil`;
/// `.local` mode never constructs a non-nil value, and no code dials these URLs
/// yet. Registering real endpoints, the org secret, and the entitlement public
/// key is owner-gated.
struct RemoteBridgeConfig: Sendable, Equatable {
    /// Control-plane base URL (link-token mint, public-token exchange, item
    /// removal, entitlement ping). `nil` until the bridge is provisioned.
    let controlPlaneBaseURL: String?

    /// Blind-proxy (data-plane) base URL — the stateless relay that injects the
    /// org secret for `/transactions/sync`, `/accounts/get`, etc. `nil` until
    /// provisioned.
    let dataPlaneProxyBaseURL: String?

    /// Base64-encoded Ed25519 public key used to verify signed entitlement
    /// tokens locally. `nil` until the signer exists. Never a private key.
    let entitlementPublicKeyBase64: String?

    /// The inert placeholder used in `.local` mode and as the default in
    /// `.hostedBridge` mode until real values are registered.
    static let unconfigured = RemoteBridgeConfig(
        controlPlaneBaseURL: nil,
        dataPlaneProxyBaseURL: nil,
        entitlementPublicKeyBase64: nil
    )

    /// `true` only when both control-plane and data-plane URLs are present.
    /// Today this is always `false`; it is the future guard that gates any code
    /// path from attempting a remote call.
    var isProvisioned: Bool {
        controlPlaneBaseURL?.isEmpty == false
            && dataPlaneProxyBaseURL?.isEmpty == false
    }

    /// Resolve placeholder values from a config/env dictionary. Returns
    /// `.unconfigured` unless explicit non-empty values are present; this lets a
    /// future "provision the bridge" step populate config without any code
    /// change, while keeping today's behavior untouched (nothing reads the
    /// result in `.local` mode).
    static func resolved(from environment: [String: String]) -> RemoteBridgeConfig {
        func value(_ key: String) -> String? {
            guard let raw = environment[key]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !raw.isEmpty
            else {
                return nil
            }
            return raw
        }
        return RemoteBridgeConfig(
            controlPlaneBaseURL: value("PLAIDBAR_BRIDGE_CONTROL_PLANE_URL"),
            dataPlaneProxyBaseURL: value("PLAIDBAR_BRIDGE_DATA_PLANE_URL"),
            entitlementPublicKeyBase64: value("PLAIDBAR_ENTITLEMENT_PUBLIC_KEY")
        )
    }
}
