import FluentKit
import Foundation

// MARK: - Review state models (Fluent) — opt-in server-synced review (AND-552)

/// One synced **review-metadata** record: the per-transaction override the user
/// set in the Review Inbox (category, merchant rename, transfer flag, budget
/// exclusion, note, status), persisted only when the user opts into server-synced
/// review (AND-552 — deferred epic AND-524).
///
/// The row id is the transaction id, so a transaction has at most one synced
/// review record and an upsert is a primary-key lookup. The metadata itself is
/// stored as a JSON blob (`payload`) of the `Sendable` `ReviewMetadataRecordDTO`
/// so the schema does not have to mirror every override field as a column — the
/// shared `PlaidBarCore` DTO is the contract. `updated_at` is the explicit
/// last-writer-wins clock the conflict resolver orders on (distinct from any
/// Fluent auto-timestamp).
///
/// ## Trust boundary
/// This row holds **user category overrides and merchant renames** — display-safe
/// derived state, never a Plaid token or access secret — and exists only after an
/// explicit opt-in. The expanded server data surface is documented in
/// `SECURITY.md`.
final class ReviewMetadataModel: Model, @unchecked Sendable {
    static let schema = "review_metadata"

    @ID(custom: "transaction_id", generatedBy: .user)
    var id: String?

    /// JSON-encoded `ReviewMetadataRecordDTO` (the override payload + its clock).
    @Field(key: "payload")
    var payload: String

    /// Last-writer-wins clock, mirrored out of the payload into a column so the
    /// store can order/query without decoding every row.
    @Field(key: "updated_at")
    var updatedAt: Date

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(transactionId: String, payload: String, updatedAt: Date) {
        self.id = transactionId
        self.payload = payload
        self.updatedAt = updatedAt
    }
}

/// One synced **categorization rule** record (AND-552). The row id is the rule's
/// UUID string; the full `ReviewRuleRecordDTO` is stored as a JSON `payload`, with
/// `updated_at` mirrored out as the LWW clock. Same opt-in / trust-boundary
/// contract as ``ReviewMetadataModel``.
final class ReviewRuleModel: Model, @unchecked Sendable {
    static let schema = "review_rules"

    @ID(custom: "rule_id", generatedBy: .user)
    var id: String?

    /// JSON-encoded `ReviewRuleRecordDTO`.
    @Field(key: "payload")
    var payload: String

    @Field(key: "updated_at")
    var updatedAt: Date

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(ruleId: String, payload: String, updatedAt: Date) {
        self.id = ruleId
        self.payload = payload
        self.updatedAt = updatedAt
    }
}

// MARK: - Migration

/// Creates the two opt-in review-sync tables (AND-552). Additive: the migration
/// only creates new tables, never touching `items`, `category_budgets`, or any
/// existing schema, so an installed server that never receives an opted-in `PUT`
/// keeps these tables empty and behaves exactly as before.
struct CreateReviewState: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("review_metadata")
            .field("transaction_id", .string, .identifier(auto: false))
            .field("payload", .string, .required)
            .field("updated_at", .datetime, .required)
            .field("created_at", .datetime)
            .create()

        try await database.schema("review_rules")
            .field("rule_id", .string, .identifier(auto: false))
            .field("payload", .string, .required)
            .field("updated_at", .datetime, .required)
            .field("created_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("review_rules").delete()
        try await database.schema("review_metadata").delete()
    }
}
