import FluentKit
import Foundation

final class BillingSubscriptionModel: Model, @unchecked Sendable {
    static let schema = "billing_subscriptions"

    @ID(custom: "id", generatedBy: .user)
    var id: String?

    @Field(key: "status")
    var status: String

    @Field(key: "plan")
    var plan: String

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    @OptionalField(key: "current_period_end")
    var currentPeriodEnd: Date?

    @OptionalField(key: "trial_ends_at")
    var trialEndsAt: Date?

    init() {}

    init(
        id: String,
        status: String,
        plan: String,
        currentPeriodEnd: Date? = nil,
        trialEndsAt: Date? = nil
    ) {
        self.id = id
        self.status = status
        self.plan = plan
        self.currentPeriodEnd = currentPeriodEnd
        self.trialEndsAt = trialEndsAt
    }
}

struct CreateBillingSubscriptions: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(BillingSubscriptionModel.schema)
            .field("id", .string, .identifier(auto: false))
            .field("status", .string, .required)
            .field("plan", .string, .required)
            .field("updated_at", .datetime)
            .field("current_period_end", .datetime)
            .field("trial_ends_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(BillingSubscriptionModel.schema).delete()
    }
}
