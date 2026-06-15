import Foundation

/// Plan tier for a consumer entitlement.
///
/// FOUNDATION ONLY. Mirrors `SubscriptionPlan` (the client-side preview type)
/// but lives on the entitlement wire/verification side. Kept as a distinct type
/// so the entitlement layer can evolve (e.g. add-ons, custom caps) without
/// coupling to the UI preview enum. Nothing issues or verifies real
/// entitlements yet — see `docs/strategy/subscription-entitlements.md`.
public enum EntitlementTier: String, Sendable, Codable, CaseIterable {
    case free
    case plus
    case managed
}

/// A signed consumer entitlement, as it will eventually arrive from the hosted
/// bridge's Stripe-backed signer.
///
/// FOUNDATION ONLY. This is the in-memory shape of the entitlement token
/// described in `subscription-entitlements.md` §4.2 (an Ed25519/PASETO-signed
/// document verified locally with an embedded public key). **Nothing produces,
/// signs, verifies, or enforces this today.** It exists so the entitlement
/// middleware shell and future verification have a stable `Sendable` model, and
/// so the wire contract is documented in one place. `.local` (BYO-keys) mode is
/// ungated and never constructs an `Entitlement` (entitlements doc D3: BYO stays
/// fully ungated).
public struct Entitlement: Sendable, Codable, Equatable {
    /// Plan tier this entitlement grants.
    public let tier: EntitlementTier

    /// Managed institutions this plan allows (the documented `institution_limit`
    /// claim). Display/enforcement uses this; nothing enforces it yet.
    public let institutionLimit: Int

    /// Managed institutions currently counted against the plan (`items_used`).
    public let itemsUsed: Int

    /// Subscription lifecycle as reported by the signer (`active`, `canceled`,
    /// …). Free-form here because the canonical set lives with the signer; the
    /// foundation only needs to carry it through.
    public let subscriptionStatus: String

    /// Token expiry (the 30-day TTL of the signed artifact, NOT the subscription
    /// end date — see entitlements doc §4.2 / §5).
    public let expiresAt: Date?

    public init(
        tier: EntitlementTier,
        institutionLimit: Int,
        itemsUsed: Int,
        subscriptionStatus: String,
        expiresAt: Date?
    ) {
        self.tier = tier
        self.institutionLimit = institutionLimit
        self.itemsUsed = itemsUsed
        self.subscriptionStatus = subscriptionStatus
        self.expiresAt = expiresAt
    }

    /// Whether the plan has spare managed-institution capacity. Pure display
    /// logic; not an enforcement point.
    public var hasSpareCapacity: Bool {
        itemsUsed < institutionLimit
    }
}

/// The outcome of evaluating entitlement for a request.
///
/// FOUNDATION ONLY. The middleware shell always returns `.allow` today (local /
/// BYO mode is ungated and the hosted path is not built). The non-`allow` cases
/// document the future shape so enforcement can be added behind a gate without
/// changing the decision type. The `retryAfter`/`reason` payloads map to the
/// `402 limit_reached` / entitlement-required responses described in
/// `managed-link-architecture.md` §6–§7.
public enum EntitlementDecision: Sendable, Equatable {
    /// Request proceeds. The only outcome today.
    case allow

    /// A valid entitlement is required but absent (future: missing/expired
    /// signed token on a managed-only route).
    case entitlementRequired(reason: String)

    /// The plan's managed-institution limit is reached (future: `402`).
    case limitReached(reason: String)
}
