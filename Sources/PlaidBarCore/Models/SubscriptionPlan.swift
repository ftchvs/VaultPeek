import Foundation

/// Client-side shape for the proposed managed consumer plans.
///
/// FOUNDATION ONLY. These types describe plan limits and connection origin so
/// the UI can render restrained, honest plan-selection and usage shells. They
/// do **not** enforce anything: there is no Stripe billing, no entitlement
/// token, no managed broker, and no server-side limit check behind them yet.
/// The managed cloud backend remains gated by `docs/strategy/approval-gates.md`
/// (decisions D1-D10 in `docs/strategy/subscription-entitlements.md` are
/// unresolved as of 2026-06-12). Until those gates pass, every plan is a
/// preview and demo / bring-your-own-keys mode stays fully free and ungated.
public enum SubscriptionPlan: String, CaseIterable, Sendable, Codable, Identifiable {
    case personal
    case plus

    /// `@AppStorage` key for the locally-remembered plan preference. This is a
    /// UI preference only — it carries no entitlement and grants no access.
    public static let storageKey = "subscription.selectedPlan"

    /// Default plan when nothing has been chosen yet.
    public static let defaultPlan = SubscriptionPlan.personal

    public var id: String { rawValue }

    /// Human-facing plan name for pickers and labels.
    public var displayName: String {
        switch self {
        case .personal:
            "Personal"
        case .plus:
            "Plus"
        }
    }

    /// Managed-institution cap proposed for each tier.
    ///
    /// Values come from `docs/strategy/subscription-entitlements.md` §D2
    /// (Personal = 3, Plus = 8). These are design proposals, not commitments,
    /// and are surfaced here for the usage shell only — nothing enforces them.
    public var institutionLimit: Int {
        switch self {
        case .personal:
            3
        case .plus:
            8
        }
    }

    /// Short forward-looking tagline. Deliberately framed as a preview so copy
    /// never implies billing or a managed backend exists today.
    public var priceDescription: String {
        switch self {
        case .personal:
            "Preview · up to 3 institutions"
        case .plus:
            "Preview · up to 8 institutions"
        }
    }
}

/// Forward-looking marker for how a linked item was created.
///
/// `managed` = brokered through a future hosted VaultPeek bridge; `bringYourOwn`
/// = the user's own Plaid keys on their local server (today's only real path).
/// Defined now so DTOs and storage can adopt it later **without a breaking
/// change**. It is intentionally not wired into any existing DTO decoding here;
/// if a DTO ever carries it, the field must be optional with a default so
/// existing server JSON keeps decoding.
public enum ItemOrigin: String, Sendable, Codable {
    case managed
    case bringYourOwn
}

/// Pure, testable description of "how many institutions are connected versus the
/// plan's limit." Drives the usage widget and upgrade CTA. Performs no network
/// calls and enforces nothing — it only produces display state.
public struct InstitutionUsage: Sendable, Equatable {
    /// Institutions currently connected.
    public let connectedCount: Int

    /// Plan cap, or `nil` when the concept of a limit does not apply (e.g.
    /// demo / BYO mode, where everything stays free and ungated).
    public let limit: Int?

    public init(connectedCount: Int, limit: Int?) {
        self.connectedCount = connectedCount
        self.limit = limit
    }

    /// Derive the limit from a plan. Used on the managed/production path.
    public init(connectedCount: Int, plan: SubscriptionPlan) {
        self.init(connectedCount: connectedCount, limit: plan.institutionLimit)
    }

    /// `true` only when a finite limit exists and is met or exceeded. A `nil`
    /// limit (ungated) is never at limit.
    public var isAtLimit: Bool {
        guard let limit else { return false }
        return connectedCount >= limit
    }

    /// Human-readable summary, e.g. "2 of 3 institutions connected". When there
    /// is no limit, reports the count alone without implying a cap.
    public var summaryText: String {
        let institutionWord = connectedCount == 1 ? "institution" : "institutions"
        if let limit {
            return "\(connectedCount) of \(limit) institutions connected"
        }
        return "\(connectedCount) \(institutionWord) connected"
    }
}
