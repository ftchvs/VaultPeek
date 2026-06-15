import Foundation
import Hummingbird
import NIOCore
import PlaidBarCore

struct ManagedLinkEntitlementService: Sendable {
    let deployment: DeploymentMode
    let billingStore: BillingSubscriptionStore
    let tokenStore: TokenStore

    func summary() async throws -> ManagedLinkEntitlementSummary {
        let subscription = try await billingStore.currentSubscription()
        let activeInstitutionCount = try await tokenStore.activeInstitutionCount(origin: .managed)
        return Self.summary(
            deployment: deployment,
            subscription: subscription,
            activeInstitutionCount: activeInstitutionCount
        )
    }

    static func summary(
        deployment: DeploymentMode,
        subscription: BillingSubscription?,
        activeInstitutionCount: Int
    ) -> ManagedLinkEntitlementSummary {
        let plan = subscription?.plan ?? .free
        let status = subscription?.status
        let institutionLimit = plan.institutionLimit
        let blockReason: ManagedLinkBlockReason?

        switch deployment {
        case .local:
            blockReason = .managedBridgeUnavailable
        case .hostedBridge:
            if let status, !status.allowsPaidFeatures {
                blockReason = .subscriptionDegraded
            } else if subscription == nil {
                blockReason = .subscriptionRequired
            } else if activeInstitutionCount >= institutionLimit {
                blockReason = .institutionLimitReached
            } else {
                blockReason = nil
            }
        }

        return ManagedLinkEntitlementSummary(
            plan: plan,
            status: status,
            institutionLimit: institutionLimit,
            activeInstitutionCount: activeInstitutionCount,
            canCreateManagedLink: blockReason == nil,
            blockReason: blockReason
        )
    }

    static var paymentRequired: HTTPResponse.Status {
        HTTPResponse.Status(code: 402, reasonPhrase: "Payment Required")
    }

    static func blockedResponse(summary: ManagedLinkEntitlementSummary) throws -> Response {
        let message = summary.message ?? "Managed bank linking is unavailable."
        let body = try JSONEncoder().encode(
            ManagedLinkErrorResponse(error: message, entitlement: summary)
        )
        return Response(
            status: paymentRequired,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: ByteBuffer(data: body))
        )
    }
}
