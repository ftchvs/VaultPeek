import Foundation

/// A single saved category budget — the persisted, user-set monthly limit for a
/// spending category. Shared across the server (storage + `/api/budgets`) and the
/// app (which scores it against transactions via `CategoryBudgetPlanner`).
public struct CategoryBudgetDTO: Codable, Sendable, Hashable, Identifiable {
    /// Stable identity is the category itself — at most one budget per category.
    public var id: String { category.rawValue }
    public let category: SpendingCategory
    public let monthlyLimit: Double

    public init(category: SpendingCategory, monthlyLimit: Double) {
        self.category = category
        self.monthlyLimit = monthlyLimit
    }
}

/// `GET /api/budgets` payload.
public struct CategoryBudgetsResponse: Codable, Sendable, Hashable {
    public let budgets: [CategoryBudgetDTO]

    public init(budgets: [CategoryBudgetDTO]) {
        self.budgets = budgets
    }

    /// Convenience map for scoring with `CategoryBudgetPlanner.presentation`.
    public var byCategory: [SpendingCategory: Double] {
        Dictionary(budgets.map { ($0.category, $0.monthlyLimit) }) { first, _ in first }
    }
}

/// `PUT /api/budgets/{category}` body — the category is taken from the path.
public struct SaveCategoryBudgetRequest: Codable, Sendable, Hashable {
    public let monthlyLimit: Double

    public init(monthlyLimit: Double) {
        self.monthlyLimit = monthlyLimit
    }
}
