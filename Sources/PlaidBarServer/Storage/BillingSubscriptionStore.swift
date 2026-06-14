import FluentKit
import Foundation
import HummingbirdFluent
import PlaidBarCore

/// Local persistence for subscription lifecycle metadata.
///
/// The row contains status/plan/dates only. Stripe customer IDs, payment method
/// details, webhook payloads, and Plaid data must stay out of this store.
actor BillingSubscriptionStore {
    private static let singletonID = "current"

    private let fluent: Fluent

    init(fluent: Fluent) {
        self.fluent = fluent
    }

    func currentSubscription() async throws -> BillingSubscription? {
        guard let row = try await BillingSubscriptionModel.find(Self.singletonID, on: fluent.db()),
              let status = BillingSubscriptionStatus(rawValue: row.status),
              let plan = SubscriptionPlan(rawValue: row.plan)
        else {
            return nil
        }

        return BillingSubscription(
            status: status,
            plan: plan,
            updatedAt: row.updatedAt ?? Date(timeIntervalSince1970: 0),
            currentPeriodEnd: row.currentPeriodEnd,
            trialEndsAt: row.trialEndsAt
        )
    }

    func save(_ request: SaveBillingSubscriptionRequest) async throws -> BillingSubscription {
        let row: BillingSubscriptionModel
        if let existing = try await BillingSubscriptionModel.find(Self.singletonID, on: fluent.db()) {
            row = existing
            row.status = request.status.rawValue
            row.plan = request.plan.rawValue
            row.currentPeriodEnd = request.currentPeriodEnd
            row.trialEndsAt = request.trialEndsAt
        } else {
            row = BillingSubscriptionModel(
                id: Self.singletonID,
                status: request.status.rawValue,
                plan: request.plan.rawValue,
                currentPeriodEnd: request.currentPeriodEnd,
                trialEndsAt: request.trialEndsAt
            )
        }

        try await row.save(on: fluent.db())
        return BillingSubscription(
            status: request.status,
            plan: request.plan,
            updatedAt: row.updatedAt ?? Date(),
            currentPeriodEnd: request.currentPeriodEnd,
            trialEndsAt: request.trialEndsAt
        )
    }
}
