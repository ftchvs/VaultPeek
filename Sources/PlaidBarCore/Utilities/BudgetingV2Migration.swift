import Foundation

/// Pure, deterministic seed + forward/reverse migration for the budgeting-v2
/// schema (AND-546).
///
/// All the *logic* of the v2 foundation lives here so it stays `Sendable`,
/// has no hidden `Date()` or I/O, and is fully unit-testable in `PlaidBarCore`.
/// `PlaidBarCache.BudgetingV2Store` is a thin persistence shell that calls into
/// this enum and writes the resulting ``BudgetingV2Schema`` snapshot to disk.
///
/// ## Forward migration (opt-in)
///
/// `seed(carryingForward:month:)` builds the v2 schema from the closed
/// ``SpendingCategory`` / ``CategoryGroup`` taxonomy, one row per case, keyed by
/// each case's stable `rawValue`. Optionally it carries a user's existing v1
/// ``CategoryBudgetDTO`` budgets forward into a chosen month. The result preserves
/// today's categorization exactly — no reclassification — because every id is the
/// same Plaid key v1 already uses.
///
/// ## Reversibility (safe, additive)
///
/// The migration is **additive and reversible**: it never mutates any v1 record.
/// `reverseToV1Budgets(_:)` recovers the v1 budget map from a v2 snapshot for a
/// chosen month, so opting *out* of v2 restores the v1 `/api/budgets` numbers
/// losslessly. The persisted v2 snapshot itself is disposable — deleting it leaves
/// v1 untouched and the table can be reseeded from the enum at any time.
public enum BudgetingV2Migration {
    /// The schema version this migration produces. Mirrors
    /// ``BudgetingV2Schema/currentSchemaVersion`` so the store and the migration
    /// agree on what "current" means.
    public static let producedSchemaVersion = BudgetingV2Schema.currentSchemaVersion

    // MARK: - Forward seed

    /// Seed the v2 category/group tables from the closed v1 taxonomy, optionally
    /// carrying a user's existing v1 budgets into `month`.
    ///
    /// - Parameters:
    ///   - v1Budgets: existing v1 ``CategoryBudgetDTO`` budgets to carry forward at
    ///     opt-in. Pass `[]` (the default) to seed only the taxonomy — the
    ///     foundation seeds *categories*, not budgets, unless the user already had
    ///     v1 budgets to preserve.
    ///   - month: the `YYYY-MM` month the carried-forward v1 limits are written to.
    ///     Ignored when `v1Budgets` is empty. The v1 limit is undated, so it lands
    ///     as that month's limit with rollover off.
    /// - Returns: a complete, current-version ``BudgetingV2Schema`` snapshot.
    public static func seed(
        carryingForward v1Budgets: [CategoryBudgetDTO] = [],
        month: String? = nil
    ) -> BudgetingV2Schema {
        // Groups in canonical display order so the persisted table is stable
        // (screenshots / QA matrix don't churn).
        let groups = CategoryGroup.displayOrder.map(BudgetCategoryGroupV2.init(seedingFrom:))

        // Categories ordered by (group display order, then category display name)
        // so the seeded leaf table is deterministic and reads naturally under each
        // group header.
        let categories = SpendingCategory.allCases
            .sorted { lhs, rhs in
                if lhs.group.sortIndex != rhs.group.sortIndex {
                    return lhs.group.sortIndex < rhs.group.sortIndex
                }
                return lhs.displayName < rhs.displayName
            }
            .map(BudgetCategoryV2.init(seedingFrom:))

        // Carry v1 budgets forward only when both a non-empty set AND a target
        // month are supplied. A budget for a category that somehow isn't in the
        // seeded table is dropped (can't happen for the closed enum, but keeps the
        // result internally consistent).
        let seededCategoryIds = Set(categories.map(\.id))
        let budgets: [MonthlyBudgetV2]
        if let month, !v1Budgets.isEmpty {
            budgets = v1Budgets
                .filter { seededCategoryIds.contains($0.category.rawValue) }
                .map { MonthlyBudgetV2(seedingFrom: $0, month: month) }
                // Stable order: by category id so the snapshot round-trips equal.
                .sorted { $0.categoryId < $1.categoryId }
        } else {
            budgets = []
        }

        return BudgetingV2Schema(
            schemaVersion: producedSchemaVersion,
            groups: groups,
            categories: categories,
            budgets: budgets
        )
    }

    // MARK: - Reverse (opt-out)

    /// Recover the v1 ``CategoryBudgetDTO`` budget set from a v2 snapshot for a
    /// chosen `month`, so opting out of v2 restores the v1 numbers losslessly.
    ///
    /// Only budgets for that month whose category seeded from a real
    /// ``SpendingCategory`` are recoverable (a future user-only category has no v1
    /// home and is intentionally dropped on the way back to v1). The result is the
    /// exact shape the v1 `/api/budgets` layer consumes.
    ///
    /// - Returns: the recovered budgets, ordered by category `rawValue` for a
    ///   deterministic result.
    public static func reverseToV1Budgets(
        _ schema: BudgetingV2Schema,
        month: String
    ) -> [CategoryBudgetDTO] {
        let categoriesById = Dictionary(
            schema.categories.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var recovered: [CategoryBudgetDTO] = []
        for budget in schema.budgets where budget.month == month {
            guard
                let category = categoriesById[budget.categoryId],
                let v1Category = category.seededFromCategory
            else { continue }
            recovered.append(
                CategoryBudgetDTO(category: v1Category, monthlyLimit: budget.monthlyLimit)
            )
        }
        return recovered.sorted { $0.category.rawValue < $1.category.rawValue }
    }

    // MARK: - Migration check

    /// Whether `schema` needs a forward re-seed: it is `nil` (never seeded) or was
    /// written by an older schema version. Drives the store's self-healing load —
    /// a stale snapshot reads as a miss and the caller reseeds, additively.
    public static func needsMigration(_ schema: BudgetingV2Schema?) -> Bool {
        guard let schema else { return true }
        return !schema.isCurrentSchema
    }
}
