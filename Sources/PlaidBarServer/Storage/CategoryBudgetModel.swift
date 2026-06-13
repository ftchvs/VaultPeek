import FluentKit
import Foundation

// MARK: - Category Budget Model (Fluent)

/// One saved monthly limit per spending category (AND-402). The row id is the
/// `SpendingCategory.rawValue`, so a category has at most one budget and upserts
/// are a primary-key lookup. Holds only a display-safe number — no Plaid data.
final class CategoryBudgetModel: Model, @unchecked Sendable {
    static let schema = "category_budgets"

    @ID(custom: "category", generatedBy: .user)
    var id: String?

    @Field(key: "monthly_limit")
    var monthlyLimit: Double

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(category: String, monthlyLimit: Double) {
        self.id = category
        self.monthlyLimit = monthlyLimit
    }
}

// MARK: - Migration

struct CreateCategoryBudgets: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("category_budgets")
            .field("category", .string, .identifier(auto: false))
            .field("monthly_limit", .double, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("category_budgets").delete()
    }
}
