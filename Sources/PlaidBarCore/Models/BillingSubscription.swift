import Foundation

/// Stripe subscription lifecycle as persisted by the local companion server.
///
/// This is display and gating metadata only. Do not add Stripe secrets, Plaid
/// tokens, account IDs, balances, transactions, or raw webhook/provider payloads
/// to this model.
public enum BillingSubscriptionStatus: String, Codable, Sendable, CaseIterable {
    case active
    case trialing
    case pastDue = "past_due"
    case canceled
    case expired

    public var allowsPaidFeatures: Bool {
        switch self {
        case .active, .trialing:
            true
        case .pastDue, .canceled, .expired:
            false
        }
    }

    public var displayName: String {
        switch self {
        case .active:
            "Active"
        case .trialing:
            "Trial"
        case .pastDue:
            "Payment failed"
        case .canceled:
            "Canceled"
        case .expired:
            "Expired"
        }
    }

    public var recoveryAction: String {
        switch self {
        case .active:
            "Continue using VaultPeek."
        case .trialing:
            "Add billing before the trial ends to keep this feature."
        case .pastDue:
            "Update your payment method to restore access."
        case .canceled:
            "Restart your subscription to unlock this feature."
        case .expired:
            "Choose a plan to unlock this feature again."
        }
    }
}

public struct BillingSubscription: Codable, Sendable, Equatable {
    public let status: BillingSubscriptionStatus
    public let plan: SubscriptionPlan
    public let updatedAt: Date
    public let currentPeriodEnd: Date?
    public let trialEndsAt: Date?

    public init(
        status: BillingSubscriptionStatus,
        plan: SubscriptionPlan,
        updatedAt: Date,
        currentPeriodEnd: Date? = nil,
        trialEndsAt: Date? = nil
    ) {
        self.status = status
        self.plan = plan
        self.updatedAt = updatedAt
        self.currentPeriodEnd = currentPeriodEnd
        self.trialEndsAt = trialEndsAt
    }
}

public struct SaveBillingSubscriptionRequest: Codable, Sendable, Equatable {
    public let status: BillingSubscriptionStatus
    public let plan: SubscriptionPlan
    public let currentPeriodEnd: Date?
    public let trialEndsAt: Date?

    public init(
        status: BillingSubscriptionStatus,
        plan: SubscriptionPlan,
        currentPeriodEnd: Date? = nil,
        trialEndsAt: Date? = nil
    ) {
        self.status = status
        self.plan = plan
        self.currentPeriodEnd = currentPeriodEnd
        self.trialEndsAt = trialEndsAt
    }
}

public struct BillingCheckoutSessionRequest: Codable, Sendable, Equatable {
    public let plan: SubscriptionPlan
    public let successURL: String
    public let cancelURL: String

    public init(plan: SubscriptionPlan, successURL: String, cancelURL: String) {
        self.plan = plan
        self.successURL = successURL
        self.cancelURL = cancelURL
    }
}

public struct BillingCheckoutSessionResponse: Codable, Sendable, Equatable {
    public let checkoutURL: String
    public let plan: SubscriptionPlan
    public let mode: String

    public init(checkoutURL: String, plan: SubscriptionPlan, mode: String = "subscription") {
        self.checkoutURL = checkoutURL
        self.plan = plan
        self.mode = mode
    }
}

public struct BillingPortalSessionRequest: Codable, Sendable, Equatable {
    public let returnURL: String

    public init(returnURL: String) {
        self.returnURL = returnURL
    }
}

public struct BillingPortalSessionResponse: Codable, Sendable, Equatable {
    public let portalURL: String

    public init(portalURL: String) {
        self.portalURL = portalURL
    }
}

/// Safe Stripe webhook projection. It intentionally carries only normalized
/// subscription metadata; never raw Stripe payloads, signatures, customer email,
/// payment-method details, invoices, or secrets.
public struct StripeBillingWebhookEvent: Codable, Sendable, Equatable {
    public let id: String
    public let type: String
    public let status: BillingSubscriptionStatus
    public let plan: SubscriptionPlan
    public let currentPeriodEnd: Date?
    public let trialEndsAt: Date?

    public init(
        id: String,
        type: String,
        status: BillingSubscriptionStatus,
        plan: SubscriptionPlan,
        currentPeriodEnd: Date? = nil,
        trialEndsAt: Date? = nil
    ) {
        self.id = id
        self.type = type
        self.status = status
        self.plan = plan
        self.currentPeriodEnd = currentPeriodEnd
        self.trialEndsAt = trialEndsAt
    }
}

public struct BillingEntitlementSummary: Codable, Sendable, Equatable {
    public let plan: SubscriptionPlan
    public let status: BillingSubscriptionStatus?
    public let institutionLimit: Int
    public let activeInstitutionCount: Int
    public let trialEndsAt: Date?
    public let features: [String]
    public let managedLink: ManagedLinkEntitlementSummary

    public init(
        plan: SubscriptionPlan,
        status: BillingSubscriptionStatus?,
        institutionLimit: Int,
        activeInstitutionCount: Int,
        trialEndsAt: Date?,
        features: [String],
        managedLink: ManagedLinkEntitlementSummary
    ) {
        self.plan = plan
        self.status = status
        self.institutionLimit = institutionLimit
        self.activeInstitutionCount = activeInstitutionCount
        self.trialEndsAt = trialEndsAt
        self.features = features
        self.managedLink = managedLink
    }
}

public struct BillingFeatureLock: Sendable, Equatable {
    public let title: String
    public let message: String
    public let recoveryAction: String
}

public enum BillingFeatureGateResult: Sendable, Equatable {
    case available
    case locked(BillingFeatureLock)

    public var isLocked: Bool {
        switch self {
        case .available:
            false
        case .locked:
            true
        }
    }
}

public enum BillingFeatureGate {
    public static func evaluate(
        featureName: String,
        subscription: BillingSubscription?
    ) -> BillingFeatureGateResult {
        guard let subscription else {
            return .available
        }
        guard !subscription.status.allowsPaidFeatures else {
            return .available
        }
        return .locked(
            BillingFeatureLock(
                title: "\(featureName) is locked",
                message: "Your \(subscription.status.displayName.lowercased()) subscription cannot use \(featureName). Local financial data stays on this Mac and is not deleted.",
                recoveryAction: subscription.status.recoveryAction
            )
        )
    }
}

public struct BillingPlanTransition: Sendable, Equatable {
    public let from: SubscriptionPlan
    public let to: SubscriptionPlan

    public init(from: SubscriptionPlan, to: SubscriptionPlan) {
        self.from = from
        self.to = to
    }

    public var isDowngrade: Bool {
        to.institutionLimit < from.institutionLimit
    }

    public var preservesLocalFinancialData: Bool {
        true
    }

    public var explanation: String {
        if isDowngrade {
            return "Downgrading changes future plan limits only. VaultPeek does not delete local accounts, transactions, balances, or budgets."
        }
        return "Changing plans updates feature access only. VaultPeek keeps local financial data intact."
    }
}
