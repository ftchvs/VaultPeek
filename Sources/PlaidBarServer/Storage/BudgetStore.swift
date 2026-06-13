import FluentKit
import Foundation
import HummingbirdFluent
import PlaidBarCore

/// Local persistence for user-set category budgets (AND-402).
///
/// Mirrors `TokenStore`: an `actor` over the same Fluent/SQLite store, so writes
/// are serialized and the database stays single-writer. Budgets are display-safe
/// numbers (no Plaid tokens or account data), so unlike `TokenStore` there is no
/// Keychain indirection — the value lives directly in SQLite.
actor BudgetStore {
    private let fluent: Fluent

    init(fluent: Fluent) {
        self.fluent = fluent
    }

    /// All saved budgets, ordered by category display name for a stable list.
    /// Rows whose stored category no longer maps to a known `SpendingCategory`
    /// (e.g. a taxonomy change) are skipped rather than surfaced as garbage.
    func allBudgets() async throws -> [CategoryBudgetDTO] {
        let rows = try await CategoryBudgetModel.query(on: fluent.db()).all()
        return rows
            .compactMap { row -> CategoryBudgetDTO? in
                guard let key = row.id, let category = SpendingCategory(rawValue: key) else {
                    return nil
                }
                return CategoryBudgetDTO(category: category, monthlyLimit: row.monthlyLimit)
            }
            .sorted { $0.category.displayName < $1.category.displayName }
    }

    /// Upsert the monthly limit for a category (one budget per category).
    func saveBudget(category: SpendingCategory, monthlyLimit: Double) async throws {
        let key = category.rawValue
        if let existing = try await CategoryBudgetModel.find(key, on: fluent.db()) {
            existing.monthlyLimit = monthlyLimit
            try await existing.save(on: fluent.db())
        } else {
            try await CategoryBudgetModel(category: key, monthlyLimit: monthlyLimit)
                .save(on: fluent.db())
        }
    }

    /// Remove a category's budget. A no-op if none is saved.
    func deleteBudget(category: SpendingCategory) async throws {
        guard let existing = try await CategoryBudgetModel.find(category.rawValue, on: fluent.db())
        else { return }
        try await existing.delete(on: fluent.db())
    }
}
